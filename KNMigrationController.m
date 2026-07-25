//
//  KNMigrationController.m
//  Kinetic Notes
//
//  First-run import of a Notational Velocity notes directory.

/*Copyright (c) 2026, the Kinetic Notes authors.
    This file is part of Kinetic Notes, a fork of Notational Velocity.

    Kinetic Notes is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    Kinetic Notes is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with Kinetic Notes.  If not, see <http://www.gnu.org/licenses/>. */

#import "KNMigrationController.h"
#import "NotationController.h"
#import "NotationFileManager.h"
#import "NSFileManager_NV.h"
#import "NSData_transformations.h"
#import "FrozenNotation.h"
#import "KNSecureArchiving.h"
#import "NotationPrefs.h"

NSString *KNNotationalVelocityBundleIdentifier = @"net.notational.velocity";
NSString *KNNotationalVelocityDefaultDirectoryName = @"Notational Data";
NSString *KNMigrationErrorDomain = @"KNMigrationErrorDomain";

//the key under which NV records the notes directory it last used, in its own defaults domain
static NSString *KNNotationalVelocityDirectoryAliasKey = @"DirectoryAlias";

//WALController writes its journal under this name; see the filename in -[WALStorageController initWithParentFSRep:].
//NV unlinks it on a clean quit, so finding one means NV is running or was killed at some point.
//Deliberately NOT a reason to refuse an import: a journal left by a crash years ago would block
//migration forever. It is copied with everything else and replayed by the normal recovery path in
//-[NotationController initializeJournaling], which is exactly what NV itself would do next launch.
//Only NV actually running blocks an import, because then the database is being written underneath us.
static NSString *KNWriteAheadLogFileName = @"Interim Note-Changes";

//where a copy is assembled before being moved into place
static NSString *KNStagedImportDirectoryName = @"Kinetic Notes (importing)";

@implementation KNMigrationController

+ (NSString*)applicationSupportDirectory {

	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
	return [paths count] ? [paths objectAtIndex:0] : nil;
}

+ (NSString*)kineticNotesDirectory {

	//must match the directory +[NotationController getDefaultNotesDirectoryRef:] creates
	return [[self applicationSupportDirectory] stringByAppendingPathComponent:@"Kinetic Notes"];
}

+ (NSString*)stagedImportDirectory {

	NSString *staged = [[self applicationSupportDirectory] stringByAppendingPathComponent:KNStagedImportDirectoryName];
	BOOL isDirectory = NO;
	if ([[NSFileManager defaultManager] fileExistsAtPath:staged isDirectory:&isDirectory] && isDirectory)
		return staged;

	return nil;
}

//a directory counts as a real notes store only if it holds a database with something in it
+ (BOOL)directoryHoldsNotesDatabase:(NSString*)directory {

	if (![directory length]) return NO;

	NSString *database = [directory stringByAppendingPathComponent:NotesDatabaseFileName];
	NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:database error:NULL];

	return attributes && [[attributes objectForKey:NSFileSize] unsignedLongLongValue] > 0;
}

+ (BOOL)isFirstRun {

	//the presence of our own defaults means we have run before even if the directory was since moved
	if ([[NSUserDefaults standardUserDefaults] objectForKey:@"DirectoryAlias"]) return NO;

	return ![self directoryHoldsNotesDatabase:[self kineticNotesDirectory]];
}

+ (BOOL)isNotationalVelocityRunning {

	NSArray *running = [[NSWorkspace sharedWorkspace] runningApplications];
	NSUInteger i = 0;
	for (i = 0; i < [running count]; i++) {
		if ([[[running objectAtIndex:i] bundleIdentifier] isEqualToString:KNNotationalVelocityBundleIdentifier])
			return YES;
	}

	return NO;
}

//NV stores its notes directory as Alias Manager data, not as an NSURL bookmark. FSCopyAliasInfo is
//unreliable for this (NV's own code says as much), so resolve to an FSRef and take the path from
//that, which is the chain AppController uses when reporting the location of a database it can't open.
+ (NSString*)directoryFromNotationalVelocityAliasData:(NSData*)aliasData {

	if (![aliasData length]) return nil;

	FSRef directoryRef;
	if (![aliasData fsRefAsAlias:&directoryRef]) return nil;

	return [[NSFileManager defaultManager] pathWithFSRef:&directoryRef];
}

+ (NSString*)detectedNotationalVelocityDirectory {

	//first choice: wherever NV was last pointed, which may not be the default location
	NSData *aliasData = (NSData *)CFPreferencesCopyAppValue((CFStringRef)KNNotationalVelocityDirectoryAliasKey,
														   (CFStringRef)KNNotationalVelocityBundleIdentifier);
	if (aliasData) {
		NSString *recorded = nil;
		if ([aliasData isKindOfClass:[NSData class]])
			recorded = [self directoryFromNotationalVelocityAliasData:aliasData];

		CFRelease((CFDataRef)aliasData);

		if ([self directoryHoldsNotesDatabase:recorded]) return recorded;
	}

	//second choice: the location NV creates on a clean install
	NSString *defaultDirectory = [[self applicationSupportDirectory]
								  stringByAppendingPathComponent:KNNotationalVelocityDefaultDirectoryName];
	if ([self directoryHoldsNotesDatabase:defaultDirectory]) return defaultDirectory;

	return nil;
}

+ (BOOL)directoryHasUnflushedJournal:(NSString*)directory {

	return [[NSFileManager defaultManager] fileExistsAtPath:
			[directory stringByAppendingPathComponent:KNWriteAheadLogFileName]];
}


#pragma mark - Staging and committing the copy

+ (NSError*)errorWithCode:(KNMigrationError)code description:(NSString*)description underlying:(NSError*)underlying {

	NSMutableDictionary *info = [NSMutableDictionary dictionary];
	if (description) [info setObject:description forKey:NSLocalizedDescriptionKey];
	if (underlying) [info setObject:underlying forKey:NSUnderlyingErrorKey];
	return [NSError errorWithDomain:KNMigrationErrorDomain code:code userInfo:info];
}

//total bytes occupied by everything under a directory, following the tree but not symlinks out of it
+ (unsigned long long)sizeOfDirectory:(NSString*)directory {

	NSFileManager *fm = [NSFileManager defaultManager];
	NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:directory];
	unsigned long long total = 0;
	NSString *relative = nil;
	while ((relative = [enumerator nextObject])) {
		NSDictionary *attributes = [enumerator fileAttributes];
		if ([[attributes fileType] isEqualToString:NSFileTypeRegular])
			total += [attributes fileSize];
	}
	return total;
}

+ (unsigned long long)availableCapacityAtPath:(NSString*)path {

	NSURL *url = [NSURL fileURLWithPath:path];
	NSNumber *available = nil;
	if ([url getResourceValue:&available forKey:NSURLVolumeAvailableCapacityKey error:NULL] && available)
		return [available unsignedLongLongValue];

	return 0;
}

+ (NSString*)stageImportFromDirectory:(NSString*)sourceDirectory error:(NSError**)outError {

	NSFileManager *fm = [NSFileManager defaultManager];

	if (![self directoryHoldsNotesDatabase:sourceDirectory]) {
		if (outError) *outError = [self errorWithCode:KNMigrationErrorSourceUnreadable
										  description:NSLocalizedString(@"The Notational Velocity notes folder could not be read.", nil)
										   underlying:nil];
		return nil;
	}

	NSString *applicationSupport = [self applicationSupportDirectory];
	if (![fm isWritableFileAtPath:applicationSupport]) {
		if (outError) *outError = [self errorWithCode:KNMigrationErrorDestinationNotWritable
										  description:NSLocalizedString(@"Kinetic Notes cannot write to its Application Support folder.", nil)
										   underlying:nil];
		return nil;
	}

	//require noticeably more free space than the source occupies, so the copy can't fill the volume
	unsigned long long needed = [self sizeOfDirectory:sourceDirectory];
	unsigned long long available = [self availableCapacityAtPath:applicationSupport];
	if (available && needed && available < needed + needed / 5) {
		if (outError) *outError = [self errorWithCode:KNMigrationErrorInsufficientSpace
										  description:NSLocalizedString(@"There is not enough free disk space to import your notes.", nil)
										   underlying:nil];
		return nil;
	}

	NSString *staged = [applicationSupport stringByAppendingPathComponent:KNStagedImportDirectoryName];

	//clear any staged directory left by an interrupted earlier attempt; it is ours, never the source
	if ([fm fileExistsAtPath:staged])
		[fm removeItemAtPath:staged error:NULL];

	//copyItemAtPath: opens the source read-only. It never modifies, moves, or deletes the source.
	NSError *copyError = nil;
	if (![fm copyItemAtPath:sourceDirectory toPath:staged error:&copyError]) {
		//leave whatever landed for inspection rather than deleting it
		if (outError) *outError = [self errorWithCode:KNMigrationErrorCopyFailed
										  description:NSLocalizedString(@"Your notes could not be copied.", nil)
										   underlying:copyError];
		return nil;
	}

	return staged;
}

+ (NSInteger)noteCountInDirectory:(NSString*)directory {

	NSString *databasePath = [directory stringByAppendingPathComponent:NotesDatabaseFileName];
	NSData *archived = [NSData dataWithContentsOfFile:databasePath];
	if (![archived length]) return -1;

	@try {
		FrozenNotation *frozen = KNUnarchiveObjectOfClass([FrozenNotation class], archived);
		if (![frozen isKindOfClass:[FrozenNotation class]]) return -1;

		//can't count an encrypted database without the passphrase, which is asked for later, on open
		if ([[frozen notationPrefs] doesEncryption]) return -1;

		OSStatus err = noErr;
		NSArray *notes = [frozen unpackedNotesWithPrefs:[frozen notationPrefs] returningError:&err];
		if (err != noErr || !notes) return -1;

		return (NSInteger)[notes count];
	} @catch (NSException *exception) {
		return -1;
	}
}

+ (BOOL)verifyDatabaseInDirectory:(NSString*)directory isEncrypted:(BOOL*)isEncrypted error:(NSError**)outError {

	NSString *databasePath = [directory stringByAppendingPathComponent:NotesDatabaseFileName];
	NSData *archived = [NSData dataWithContentsOfFile:databasePath];
	if (![archived length]) {
		if (outError) *outError = [self errorWithCode:KNMigrationErrorDatabaseUnreadable
										  description:NSLocalizedString(@"The copied notes database could not be read.", nil)
										   underlying:nil];
		return NO;
	}

	FrozenNotation *frozen = nil;
	@try {
		frozen = KNUnarchiveObjectOfClass([FrozenNotation class], archived);
	} @catch (NSException *exception) {
		frozen = nil;
	}

	if (![frozen isKindOfClass:[FrozenNotation class]] || ![frozen hasEncodedNotesData]) {
		if (outError) *outError = [self errorWithCode:KNMigrationErrorDatabaseUnreadable
										  description:NSLocalizedString(@"The copied notes database is not in a form Kinetic Notes recognizes.", nil)
										   underlying:nil];
		return NO;
	}

	if (isEncrypted) *isEncrypted = [[frozen notationPrefs] doesEncryption];
	return YES;
}

+ (NSString*)commitStagedImport:(NSString*)stagedDirectory error:(NSError**)outError {

	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *destination = [self kineticNotesDirectory];

	NSURL *stagedURL = [NSURL fileURLWithPath:stagedDirectory];
	NSURL *destinationURL = [NSURL fileURLWithPath:destination];
	NSError *moveError = nil;

	if ([fm fileExistsAtPath:destination]) {
		//there is an existing (presumably empty first-run) directory; swap it atomically on the same volume
		NSURL *resultingURL = nil;
		if (![fm replaceItemAtURL:destinationURL withItemAtURL:stagedURL backupItemName:nil
						  options:0 resultingItemURL:&resultingURL error:&moveError]) {
			if (outError) *outError = [self errorWithCode:KNMigrationErrorCommitFailed
											  description:NSLocalizedString(@"The imported notes could not be put into place.", nil)
											   underlying:moveError];
			return nil;
		}
		return resultingURL ? [resultingURL path] : destination;
	}

	//no existing directory: a plain move is already atomic on one volume
	if (![fm moveItemAtURL:stagedURL toURL:destinationURL error:&moveError]) {
		if (outError) *outError = [self errorWithCode:KNMigrationErrorCommitFailed
										  description:NSLocalizedString(@"The imported notes could not be put into place.", nil)
										   underlying:moveError];
		return nil;
	}

	return destination;
}

@end
