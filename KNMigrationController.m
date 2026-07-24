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

NSString *KNNotationalVelocityBundleIdentifier = @"net.notational.velocity";
NSString *KNNotationalVelocityDefaultDirectoryName = @"Notational Data";

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

@end
