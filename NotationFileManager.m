//
//  NotationFileManager.m
//  Notation
//
//  Created by Zachary Schneirov on 4/9/06.

/*Copyright (c) 2010, Zachary Schneirov. All rights reserved.
    This file is part of Notational Velocity.

    Notational Velocity is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    Notational Velocity is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with Notational Velocity.  If not, see <http://www.gnu.org/licenses/>. */


#import "NotationFileManager.h"
#import "KNAlert.h"
#import "NotationPrefs.h"
#import "NSString_NV.h"
#import "NSFileManager_NV.h"
#import "NoteObject.h"
#import "GlobalPrefs.h"
#import "NSData_transformations.h"
#include <sys/param.h>
#include <sys/mount.h>
#include <sys/attr.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <errno.h>
#include <CommonCrypto/CommonDigest.h>

//Errors still travel through this program as OSStatus, so an NSError has to be brought back to one.
static OSStatus OSStatusFromError(NSError *error) {
	if (!error) return noErr;
	if ([[error domain] isEqualToString:NSPOSIXErrorDomain]) return KNOSStatusFromErrno((int)[error code]);

	NSError *underlying = [[error userInfo] objectForKey:NSUnderlyingErrorKey];
	return underlying ? OSStatusFromError(underlying) : ioErr;
}

NSString *NotesDatabaseFileName = @"Notes & Settings";

//CreateTemporaryFileInDirectory names its scratch files ".<digits>-<digits>-<digits>" (see
//CreateRandomizedFileName in BufferUtils.c). Recognizing exactly that shape lets the sweep below remove
//leftover temp files without touching the database, note files, or anything else in the directory.
static BOOL IsOrphanedTemporaryFileName(NSString *name) {
	const char *s = [name UTF8String];
	if (!s || s[0] != '.') return NO;

	int i = 1, groups = 0, digitsInGroup = 0;
	while (s[i]) {
		if (s[i] >= '0' && s[i] <= '9') {
			digitsInGroup++;
		} else if (s[i] == '-') {
			if (digitsInGroup == 0) return NO;   //no empty groups, e.g. leading or doubled '-'
			groups++;
			digitsInGroup = 0;
		} else {
			return NO;                            //anything else (".DS_Store", a note title, ...) is not ours
		}
		i++;
	}
	if (digitsInGroup == 0) return NO;            //must not end on a '-'
	groups++;                                     //count the final digit group

	return groups == 3;
}

@implementation NotationController (NotationFileManager)

static struct statfs *StatFSVolumeInfo(NotationController *controller);

//Creates a scratch file in the notes directory, opened for writing, with a name that
//-removeOrphanedTemporaryFiles will recognize should the save be interrupted before it is renamed
//into place. Returns the descriptor, or -1 with errno set; *outPath is where it was created.
static int CreateTemporaryFileInDirectory(NSString *directory, NSString **outPath) {
	unsigned int attempt = 0;

	for (attempt = 0; attempt < 1000; attempt++) {
		NSString *name = [(NSString*)CreateRandomizedFileName() autorelease];
		NSString *path = [directory stringByAppendingPathComponent:name];

		int fd = open([path fileSystemRepresentation], O_WRONLY | O_CREAT | O_EXCL, 0644);
		if (fd >= 0) {
			if (outPath) *outPath = path;
			return fd;
		}
		if (EEXIST != errno) return -1;
	}

	errno = EEXIST;
	return -1;
}


/*
 Read the UUID from a mounted volume, by calling getattrlist().
 Assumes the path is the mount point of an HFS volume.
 */
static BOOL GetVolumeUUIDAttr(const char *path, VolumeUUID *volumeUUIDPtr) {
	struct attrlist alist;
	struct FinderAttrBuf {
		u_int32_t info_length;
		u_int32_t finderinfo[8];
	} volFinderInfo;
	
	int result = -1;
	
	/* Set up the attrlist structure to get the volume's Finder Info */
	alist.bitmapcount = 5;
	alist.reserved = 0;
	alist.commonattr = ATTR_CMN_FNDRINFO;
	alist.volattr = ATTR_VOL_INFO;
	alist.dirattr = 0;
	alist.fileattr = 0;
	alist.forkattr = 0;
	
	/* Get the Finder Info */
	if ((result = getattrlist(path, &alist, &volFinderInfo, sizeof(volFinderInfo), 0))) {
		NSLog(@"GetVolumeUUIDAttr error: %d", result);
		return NO;
	}
	
	/* Copy the UUID from the Finder Into to caller's buffer */
	VolumeUUID *finderInfoUUIDPtr = (VolumeUUID *)(&volFinderInfo.finderinfo[6]);
	volumeUUIDPtr->v.high = CFSwapInt32BigToHost(finderInfoUUIDPtr->v.high);
	volumeUUIDPtr->v.low = CFSwapInt32BigToHost(finderInfoUUIDPtr->v.low);
	
	return YES;
}


// Create a version 3 UUID; derived using "name" via MD5 checksum.
static void uuid_create_md5_from_name(unsigned char result_uuid[16], const void *name, int namelen) {
	
	static unsigned char FSUUIDNamespaceSHA1[16] = { 
		0xB3, 0xE2, 0x0F, 0x39, 0xF2, 0x92, 0x11, 0xD6, 
		0x97, 0xA4, 0x00, 0x30, 0x65, 0x43, 0xEC, 0xAC
	};
	
	//MD5 is required here by the version-3 UUID definition -- this identifies a volume, it is not a security check.
	//CommonCrypto deprecates these for that reason; the deprecation is suppressed rather than the algorithm changed,
	//because the resulting UUIDs are matched against ones already recorded in existing databases.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    CC_MD5_CTX c;

    CC_MD5_Init(&c);
    CC_MD5_Update(&c, FSUUIDNamespaceSHA1, (CC_LONG)sizeof(FSUUIDNamespaceSHA1));
    CC_MD5_Update(&c, name, (CC_LONG)namelen);
    CC_MD5_Final(result_uuid, &c);
#pragma clang diagnostic pop

    result_uuid[6] = (result_uuid[6] & 0x0F) | 0x30;
    result_uuid[8] = (result_uuid[8] & 0x3F) | 0x80;
}


CFUUIDRef CopyHFSVolumeUUIDForMount(const char *mntonname) {
	VolumeUUID targetVolumeUUID;
	
	unsigned char rawUUID[8];
	
	if (!GetVolumeUUIDAttr(mntonname, &targetVolumeUUID))
		return NULL;
	
	((uint32_t *)rawUUID)[0] = CFSwapInt32HostToBig(targetVolumeUUID.v.high);
	((uint32_t *)rawUUID)[1] = CFSwapInt32HostToBig(targetVolumeUUID.v.low);
	
	CFUUIDBytes uuidBytes;
	uuid_create_md5_from_name((void*)&uuidBytes, rawUUID, sizeof(rawUUID));
	
	return CFUUIDCreateFromUUIDBytes(NULL, uuidBytes);
}

//A volume's creation date, as a last resort for identifying a disk that has neither HFS Finder info
//nor an FSEvents UUID -- which an external APFS drive really can be, so this is reachable and the UUID
//it produces has to keep matching the one an existing database already recorded.
//
//That is why this is the one place the File Manager is still called. Measured against every volume
//mounted on this machine, getattrlist(ATTR_CMN_CRTIME) and FSGetVolumeInfo agree exactly on HFS+ but
//disagree on APFS: they read the sub-second fraction from different places at different precisions,
//and on the system volume they do not even report the same second. Reading the date any other way
//would therefore change the UUID, which changes the per-disk table index, which makes every note in
//an existing database look externally modified once. Only the path plumbing is retired here; the read
//itself stays byte-for-byte what it was.
CFUUIDRef CopySyntheticUUIDForVolumeCreationDate(const char *path) {
	FSRef fsRef;

	if (!path || FSPathMakeRef((const UInt8 *)path, &fsRef, NULL) != noErr)
		return NULL;

	FSCatalogInfo fileInfo;
	if (FSGetCatalogInfo(&fsRef, kFSCatInfoVolume, &fileInfo, NULL, NULL, NULL) == noErr) {

		FSVolumeInfo volInfo;
		OSStatus err = FSGetVolumeInfo(fileInfo.volume, 0, NULL, kFSVolInfoCreateDate, &volInfo, NULL, NULL);
		if (err == noErr) {
			volInfo.createDate.highSeconds = CFSwapInt16HostToBig(volInfo.createDate.highSeconds);
			volInfo.createDate.lowSeconds = CFSwapInt32HostToBig(volInfo.createDate.lowSeconds);
			volInfo.createDate.fraction = CFSwapInt16HostToBig(volInfo.createDate.fraction);

			CFUUIDBytes uuidBytes;
			uuid_create_md5_from_name((void*)&uuidBytes, (void*)&volInfo.createDate, sizeof(UTCDateTime));

			return CFUUIDCreateFromUUIDBytes(NULL, uuidBytes);
		} else {
			NSLog(@"can't even get the volume creation date -- what are you trying to do to me?");
		}
	}
	return NULL;
}

- (void)purgeOldPerDiskInfoFromNotes {
	//here's where notes' PerDiskInfo arrays would have older times removed, depending on -[DiskUUIDEntry lastAccessed]
	//each note will use RemovePerDiskInfoWithTableIndex
}

- (void)initializeDiskUUIDIfNecessary {
	//create a CFUUIDRef that identifies the volume this database sits on
	
	//don't bother unless we will be reading notes as separate files; otherwise there's no need to track the source of the attr mod dates
	//maybe disk UUIDs will be used in the future for something else; at that point this check should be altered
	
	if (!diskUUID && [self currentNoteStorageFormat] != SingleDatabaseFormat) {
		
		struct statfs * sfsb = StatFSVolumeInfo(self);
		//if this is not an hfs+ disk, then get the FSEvents UUID
		//if this is not Leopard or the FSEvents UUID is null, 
		//then take MD5 sum of creation date + some other info?

		if (!strcmp(sfsb->f_fstypename, "hfs")) {
			//if this is an HFS volume, then use getattrlist to get finderinfo from the volume
			diskUUID = CopyHFSVolumeUUIDForMount(sfsb->f_mntonname);
		}

		//ah but what happens when a non-hfs disk is first mounted on leopard+, and then moves to a tiger machine?
		//or vise-versa; that calls for tracking how the UUIDs were generated, and grouping them together when others are found;
		//this is probably unnecessary for now
		if (!diskUUID) {
			//this is not an hfs disk; use FSEvents to identify the volume
			diskUUID = FSEventsCopyUUIDForDevice(sfsb->f_fsid.val[0]);
		}
		
		if (!diskUUID) {
			//all other checks failed; just use the volume's creation date
			diskUUID = CopySyntheticUUIDForVolumeCreationDate([noteDirectoryPath fileSystemRepresentation]);
		}
		diskUUIDIndex = [notationPrefs tableIndexOfDiskUUID:diskUUID];
	}
}

static struct statfs *StatFSVolumeInfo(NotationController *controller) {
	if (!controller->statfsInfo) {
		NSString *directory = controller->noteDirectoryPath;

		if ([directory length]) {
			controller->statfsInfo = calloc(1, sizeof(struct statfs));

			if (statfs([directory fileSystemRepresentation], controller->statfsInfo))
				NSLog(@"statfs: error %d\n", errno);
		} else
			NSLog(@"the notes directory has no path\n");
	}
	return controller->statfsInfo;
}

UInt32 diskUUIDIndexForNotation(NotationController *controller) {
	return controller->diskUUIDIndex;
}

long BlockSizeForNotation(NotationController *controller) {
    if (!controller->blockSize) {
		long iosize = 0;

		struct statfs * sfsb = StatFSVolumeInfo(controller);
		if (sfsb) iosize = sfsb->f_iosize;
		
		controller->blockSize = MAX(iosize, 16 * 1024);
    }
    
    return controller->blockSize;
}

- (NSString*)noteDirectoryPath {
	return noteDirectoryPath;
}

- (NSString*)pathInNotesDirectoryForFilename:(NSString*)filename {
	if (![noteDirectoryPath length] || ![filename length]) return nil;
	return [noteDirectoryPath stringByAppendingPathComponent:filename];
}

+ (NSURL*)trashDirectoryURLForItemAtURL:(NSURL*)itemURL {
	//each volume keeps its own trash, so ask for the one that would receive this particular item
	return [[NSFileManager defaultManager] URLForDirectory:NSTrashDirectory inDomain:NSUserDomainMask
										appropriateForURL:itemURL create:NO error:NULL];
}

- (BOOL)notesDirectoryIsTrashed {
	if (![noteDirectoryPath length]) return NO;

	NSURL *directoryURL = [[NSURL fileURLWithPath:noteDirectoryPath isDirectory:YES] URLByStandardizingPath];
	NSURL *trashURL = [[NotationController trashDirectoryURLForItemAtURL:directoryURL] URLByStandardizingPath];
	if (!trashURL) return NO;

	return [[directoryURL path] hasPrefix:[[trashURL path] stringByAppendingString:@"/"]];
}

- (BOOL)notesDirectoryContainsFile:(NSString*)filename {
	NSString *path = [self pathInNotesDirectoryForFilename:filename];
	if (!path) return NO;

	return access([path fileSystemRepresentation], F_OK) == 0;
}

- (OSStatus)renameAndForgetNoteDatabaseFile:(NSString*)newfilename {
	//this method does not move the note database file; for now it is used in cases of upgrading incompatible files

	NSString *oldPath = [self pathInNotesDirectoryForFilename:NotesDatabaseFileName];
	NSString *newPath = [self pathInNotesDirectoryForFilename:newfilename];
	if (!oldPath || !newPath) return paramErr;

	if (rename([oldPath fileSystemRepresentation], [newPath fileSystemRepresentation]) != 0) {
		NSLog(@"Error renaming notes database file to %@: %d", newfilename, errno);
		return KNOSStatusFromErrno(errno);
	}
	return noErr;
}

- (BOOL)removeSpuriousDatabaseFileNotes {
	//remove any notes that might have been made out of the database or write-ahead-log files by accident
	//but leave the files intact; ensure only that they are also remotely unsynced
	//returns true if at least one note was removed, in which case allNotes should probably be refiltered
	
	NSUInteger i = 0;
	NoteObject *dbNote = nil, *walNote = nil;
	
	for (i=0; i<[allNotes count]; i++) {
		NoteObject *obj = [allNotes objectAtIndex:i];
		
		if (!dbNote && [filenameOfNote(obj) isEqualToString:NotesDatabaseFileName])
			dbNote = [[obj retain] autorelease];
		if (!walNote && [filenameOfNote(obj) isEqualToString:@"Interim Note-Changes"])
			walNote = [[obj retain] autorelease];
	}
	if (dbNote) {
		[allNotes removeObjectIdenticalTo:dbNote];
		[self _addDeletedNote:dbNote];
	}
	if (walNote) {
		[allNotes removeObjectIdenticalTo:walNote];
		[self _addDeletedNote:walNote];
	}
	return walNote || dbNote;
}

- (void)relocateNotesDirectory {
	
	while (1) {
		NSOpenPanel *openPanel = [NSOpenPanel openPanel];
		[openPanel setCanCreateDirectories:YES];
		[openPanel setCanChooseFiles:NO];
		[openPanel setCanChooseDirectories:YES];
		[openPanel setResolvesAliases:YES];
		[openPanel setAllowsMultipleSelection:NO];
		[openPanel setTreatsFilePackagesAsDirectories:NO];
		[openPanel setTitle:NSLocalizedString(@"Select a folder",nil)];
		[openPanel setPrompt:NSLocalizedString(@"Select",nil)];
		[openPanel setMessage:NSLocalizedString(@"Select a new location for your Notational Velocity notes.",nil)];
		
		if ([openPanel runModal] == NSModalResponseOK) {
			NSString *chosenParent = [openPanel filename];
			if (chosenParent) {

				NSString *oldPath = [[noteDirectoryPath copy] autorelease];
				NSString *newPath = [chosenParent stringByAppendingPathComponent:[oldPath lastPathComponent]];

				//record what the directory is, so that after the move we can tell whether it is still
				//the same object -- in which case the alias recorded for it still resolves
				struct stat before;
				BOOL identityKnown = (stat([oldPath fileSystemRepresentation], &before) == 0);

				NSError *moveError = nil;
				if (![[NSFileManager defaultManager] moveItemAtPath:oldPath toPath:newPath error:&moveError]) {
					KNRunAlert([NSString stringWithFormat:NSLocalizedString(@"Couldn't move notes into the chosen folder because %@",nil),
						[moveError localizedDescription]], NSLocalizedString(@"Your notes were not moved.",nil), NSLocalizedString(@"OK",nil), NULL, NULL);
					continue;
				}

				[noteDirectoryPath autorelease];
				noteDirectoryPath = [newPath copy];
				free(statfsInfo);
				statfsInfo = NULL;
				blockSize = 0;

				struct stat after;
				BOOL stillTheSameDirectory = identityKnown && stat([newPath fileSystemRepresentation], &after) == 0 &&
											 after.st_dev == before.st_dev && after.st_ino == before.st_ino;
				if (!stillTheSameDirectory) {
					//the notes crossed volumes, so what was recorded for them no longer names them
					[self setBookmarkNeedsUpdating:YES];
					NSData *bookmark = [self bookmarkDataForNoteDirectory];
					if (bookmark) [[GlobalPrefs defaultPrefs] setBookmarkDataForDefaultDirectory:bookmark sender:self];
					//we must quit now, as notes will very likely be re-initialized in the same place
					goto terminate;
				}

				//directory move successful! //show the user where new notes are
				[[NSWorkspace sharedWorkspace] selectFile:newPath inFileViewerRootedAtPath:nil];

				break;
			} else {
				goto terminate;
			}
		} else {
terminate:
			[NSApp terminate:nil];
			break;
		}
	}
}

+ (NSString*)defaultNotesDirectoryPathReturningError:(OSStatus*)outErr {
	NSFileManager *fileMan = [NSFileManager defaultManager];
	NSError *error = nil;

	if (outErr) *outErr = noErr;

	NSURL *appSupport = [fileMan URLForDirectory:NSApplicationSupportDirectory inDomain:NSUserDomainMask
							   appropriateForURL:nil create:YES error:&error];
	if (!appSupport) {
		NSLog(@"Unable to locate or create an Application Support directory: %@", error);
		if (outErr) *outErr = fnfErr;
		return nil;
	}

	//Kinetic Notes keeps its own directory rather than sharing "Notational Data" with Notational Velocity,
	//so that both apps can be installed at once and NV's database is never written to by this one
	NSString *notesDir = [[appSupport path] stringByAppendingPathComponent:@"Kinetic Notes"];

	if (![fileMan createDirectoryAtPath:notesDir withIntermediateDirectories:YES attributes:nil error:&error]) {
		NSLog(@"Unable to create the notes directory at %@: %@", notesDir, error);
		if (outErr) *outErr = OSStatusFromError(error);
		return nil;
	}

	return notesDir;
}

//whenever a note uses this method to change its filename, we will have to re-establish all the links to it
- (NSString*)uniqueFilenameForTitle:(NSString*)title fromNote:(NoteObject*)note {
    //generate a unique filename based on title, varying numbers
    BOOL isUnique = YES;
    NSString *uniqueFilename = title;
	
	//remove illegal characters
	NSMutableString *sanitizedName = [[[uniqueFilename stringByReplacingOccurrencesOfString:@":" withString:@"-"] mutableCopy] autorelease];
	if ([sanitizedName characterAtIndex:0] == (unichar)'.')	[sanitizedName replaceCharactersInRange:NSMakeRange(0, 1) withString:@"_"];
	uniqueFilename = [[sanitizedName copy] autorelease];
	
	//use the note's current format if the current default format is for a database; get the "ideal" extension for that format
	int noteFormat = [notationPrefs notesStorageFormat] || !note ? [notationPrefs notesStorageFormat] : storageFormatOfNote(note);
	NSString *extension = [notationPrefs chosenPathExtensionForFormat:noteFormat];
	
	//if the note's current extension is compatible with the storage format above, then use the existing extension instead
	if (note && filenameOfNote(note) && [notationPrefs pathExtensionAllowed:[filenameOfNote(note) pathExtension] forFormat:noteFormat])
		extension = [filenameOfNote(note) pathExtension];
	
	//assume that we won't have more than 999 notes with the exact same name and of more than 247 chars
	uniqueFilename = [uniqueFilename filenameExpectingAdditionalCharCount:3 + [extension length] + 2];
	
    unsigned int iteration = 0;
    do {
		isUnique = YES;
		unsigned int i;
		
		//this ought to just use an nsset, but then we'd have to maintain a parallel data structure for marginal benefit
		//also, it won't quite work right for filenames with no (real) extensions and periods in their names
		for (i=0; i<[allNotes count]; i++) {
			NoteObject *aNote = [allNotes objectAtIndex:i];
			NSString *basefilename = [filenameOfNote(aNote) stringByDeletingPathExtension];
			
			if (note != aNote && [basefilename caseInsensitiveCompare:uniqueFilename] == NSOrderedSame) {
				isUnique = NO;
				
				uniqueFilename = [uniqueFilename stringByDeletingPathExtension];
				NSString *numberPath = [[NSNumber numberWithInt:++iteration] stringValue];
				uniqueFilename = [uniqueFilename stringByAppendingPathExtension:numberPath];
				break;
			}
		}
    } while (!isUnique);
	
    return [uniqueFilename stringByAppendingPathExtension:extension];
}

- (OSStatus)noteFileRenamedFromName:(NSString*)oldName toName:(NSString*)newName {
    if (![self currentNoteStorageFormat])
		return noErr;

	NSString *oldPath = [self pathInNotesDirectoryForFilename:oldName];
	NSString *newPath = [self pathInNotesDirectoryForFilename:newName];
	if (!oldPath || !newPath) return paramErr;

	if (rename([oldPath fileSystemRepresentation], [newPath fileSystemRepresentation]) != 0) {
		NSLog(@"Error renaming file %@ to %@: %d", oldName, newName, errno);
		return KNOSStatusFromErrno(errno);
	}

    return noErr;
}

//One getattrlist against the file's own path. The File Manager needed a second call to resolve the
//parent and prove the file was still ours; addressing by path makes that true by construction, and
//so removes the window in which an external editor could move the file in between the two.
- (OSStatus)fileInNotesDirectory:(NSString*)filename hasFileInfo:(KNFileInfo *)info {
	NSString *path = [self pathInNotesDirectoryForFilename:filename];
	if (!path) return paramErr;

	if (info) {
		bzero(info, sizeof(KNFileInfo));

		int posixErr = KNGetFileInfoAtPath([path fileSystemRepresentation], info);
		if (posixErr) {
			NSLog(@"could not read the attributes of %@: %d", path, posixErr);
			return KNOSStatusFromErrno(posixErr);
		}
		return noErr;
	}

	return access([path fileSystemRepresentation], F_OK) == 0 ? noErr : KNOSStatusFromErrno(errno);
}

- (OSStatus)deleteFileInNotesDirectory:(NSString*)filename {
	NSString *path = [self pathInNotesDirectoryForFilename:filename];
	if (!path) return paramErr;

	if (unlink([path fileSystemRepresentation]) != 0) {
		NSLog(@"Error deleting file: %d", errno);
		return KNOSStatusFromErrno(errno);
	}

    return noErr;
}

- (NSMutableData*)dataFromFileInNotesDirectory:(NSString*)filename {
    return [self dataFromFileInNotesDirectory:filename fileSize:0];
}

- (NSMutableData*)dataFromFileInNotesDirectoryForCatalogEntry:(NoteCatalogEntry*)catEntry {
    return [self dataFromFileInNotesDirectory:(NSString*)catEntry->filename fileSize:catEntry->logicalSize];
}

- (NSMutableData*)dataFromFileInNotesDirectory:(NSString*)filename fileSize:(UInt64)givenFileSize {

    UInt64 fileSize = givenFileSize;
    char *notesDataPtr = NULL;

	NSString *path = [self pathInNotesDirectoryForFilename:filename];
	if (!path) return nil;

	int posixErr = KNReadDataAtPath([path fileSystemRepresentation], BlockSizeForNotation(self), &fileSize, (void**)&notesDataPtr, 1);
	if (posixErr) {
		NSLog(@"%s: error %d", _cmd, posixErr);
		return nil;
	}
    if (!notesDataPtr)
		return nil;

    return [[[NSMutableData alloc] initWithBytesNoCopy:notesDataPtr length:fileSize freeWhenDone:YES] autorelease];
}

- (OSStatus)createFileIfNotPresentInNotesDirectory:(NSString*)filename fileWasCreated:(BOOL*)created {
	NSString *path = [self pathInNotesDirectoryForFilename:filename];
	if (!path) return paramErr;

	if (created) *created = NO;

	int wasCreated = 0;
	int posixErr = KNCreateFileIfNotPresentAtPath([path fileSystemRepresentation], &wasCreated);
	if (created) *created = wasCreated ? YES : NO;

	return KNOSStatusFromErrno(posixErr);
}

//Removes scratch files left behind by earlier atomic saves. The atomic-save path below renames its
//temp file into place, which takes it with it, so a completed save can no longer leave one behind --
//but a save interrupted by a crash or force-quit still can, and Notational Velocity's exchange-then-
//delete accumulated hundreds of them over the years. Running this at load (when no save is in flight)
//both cleans up any that exist and keeps them from ever piling up.
- (NSUInteger)removeOrphanedTemporaryFiles {
	NSString *directory = noteDirectoryPath;
	if (![directory length]) return 0;

	NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:NULL];
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSUInteger removed = 0, i = 0;

	for (i = 0; i < [contents count]; i++) {
		NSString *name = [contents objectAtIndex:i];
		if (IsOrphanedTemporaryFileName(name)) {
			if ([fileManager removeItemAtPath:[directory stringByAppendingPathComponent:name] error:NULL])
				removed++;
		}
	}

	if (removed) NSLog(@"removed %lu orphaned temporary file(s) from the notes directory", (unsigned long)removed);
	return removed;
}

- (OSStatus)storeDataAtomicallyInNotesDirectory:(NSData*)data withName:(NSString*)filename {
	return [self storeDataAtomicallyInNotesDirectory:data withName:filename verifyWithSelector:NULL verificationDelegate:nil];
}

- (OSStatus)storeDataAtomicallyInNotesDirectory:(NSData*)data withName:(NSString*)filename
							 verifyWithSelector:(SEL)verificationSel verificationDelegate:(id)verifyDelegate {

	NSString *destPath = [self pathInNotesDirectoryForFilename:filename];
	if (!destPath) return paramErr;

	NSString *tempPath = nil;
	int fd = CreateTemporaryFileInDirectory(noteDirectoryPath, &tempPath);
	if (fd < 0) {
		NSLog(@"error creating temporary file: %d", errno);
		return KNOSStatusFromErrno(errno);
	}

	//write the whole file, and get it onto the disk before anything starts depending on it
	int posixErr = KNWriteDataToDescriptor(fd, BlockSizeForNotation(self), [data length], [data bytes]);
	if (!posixErr && fsync(fd) != 0) posixErr = errno;
	if (close(fd) != 0 && !posixErr) posixErr = errno;

	if (posixErr) {
		NSLog(@"error writing to temporary file: %d", posixErr);
		(void)unlink([tempPath fileSystemRepresentation]);
		return KNOSStatusFromErrno(posixErr);
	}

	//before we move this file into place over the (possibly even soon-to-be-created) Notes & Settings
	//file, try to read it back and see if it can be decrypted and decoded:
	if (verifyDelegate && verificationSel) {
		OSStatus verifyErr = noErr;
		if (noErr != (verifyErr = [[verifyDelegate performSelector:verificationSel withObject:tempPath withObject:filename] intValue])) {
			NSLog(@"couldn't verify written notes, so not continuing to save");
			(void)unlink([tempPath fileSystemRepresentation]);
			return verifyErr;
		}
	}

	//one atomic step, which also removes the temporary file -- so where the exchange it replaces
	//needed a separate delete that could fail on a stale reference, a completed save now leaves
	//nothing behind at all, and only a save interrupted before this point leaves a scratch file
	if ((posixErr = KNReplaceItemAtPath([tempPath fileSystemRepresentation], [destPath fileSystemRepresentation]))) {
		NSLog(@"error moving the temporary file into place as %@: %d", filename, posixErr);
		(void)unlink([tempPath fileSystemRepresentation]);
		return KNOSStatusFromErrno(posixErr);
	}

    return noErr;
}


- (void)notifyOfChangedTrash {
	NSURL *trashURL = [noteDirectoryPath length] ?
		[NotationController trashDirectoryURLForItemAtURL:[NSURL fileURLWithPath:noteDirectoryPath isDirectory:YES]] : nil;

	if (trashURL)
		[[NSWorkspace sharedWorkspace] noteFileSystemChanged:[trashURL path]];
	else
		NSLog(@"notifyOfChangedTrash: could not find the trash");

	 NSString *sillyDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:[(NSString*)CreateRandomizedFileName() autorelease]];
	 [[NSFileManager defaultManager] createDirectoryAtPath:sillyDirectory withIntermediateDirectories:NO attributes:nil error:NULL];
	 NSInteger tag = 0;
	 [[NSWorkspace sharedWorkspace] performFileOperation:NSWorkspaceRecycleOperation source:NSTemporaryDirectory() destination:@""
												   files:[NSArray arrayWithObject:[sillyDirectory lastPathComponent]] tag:&tag];
}

- (OSStatus)moveFileToTrash:(NSString*)filename {
	NSString *path = [self pathInNotesDirectoryForFilename:filename];
	if (!path) return paramErr;

	//-trashItemAtURL: finds the right volume's trash and renames around a file already in it,
	//which is what the loop that used to live here did by hand
	NSError *error = nil;
	if (![[NSFileManager defaultManager] trashItemAtURL:[NSURL fileURLWithPath:path] resultingItemURL:NULL error:&error]) {
		return OSStatusFromError(error);
	}

	//leave the access time alone, as setting only the modification date did
	struct timespec times[2] = { {0, UTIME_OMIT}, KNTimespecFromCFAbsoluteTime(CFAbsoluteTimeGetCurrent()) };

	if (![noteDirectoryPath length] || utimensat(AT_FDCWD, [noteDirectoryPath fileSystemRepresentation], times, 0) != 0)
		NSLog(@"couldn't touch modification date of file's parent folder: error %d", errno);

    return noErr;
}

@end
