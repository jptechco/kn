//
//  NotationFileManager.h
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


#import <Cocoa/Cocoa.h>
#import "NotationController.h"
#import "BufferUtils.h"

extern NSString *NotesDatabaseFileName;

typedef union VolumeUUID {
	u_int32_t value[2];
	struct {
		u_int32_t high;
		u_int32_t low;
	} v;
} VolumeUUID;


@interface NotationController (NotationFileManager)

CFUUIDRef CopyHFSVolumeUUIDForMount(const char *mntonname);
long BlockSizeForNotation(NotationController *controller);
UInt32 diskUUIDIndexForNotation(NotationController *controller);

- (void)purgeOldPerDiskInfoFromNotes;
- (NSUInteger)removeOrphanedTemporaryFiles;
- (void)initializeDiskUUIDIfNecessary;

- (BOOL)notesDirectoryIsTrashed;

//Every note file is addressed as the notes directory plus the note's filename, so a path is never
//stale in the way an FSRef was: it does not follow a file renamed out from under us, and the
//directory scan is what notices such a rename and updates the note's filename to match.
- (NSString*)noteDirectoryPath;
- (NSString*)pathInNotesDirectoryForFilename:(NSString*)filename;
- (BOOL)notesDirectoryContainsFile:(NSString*)filename;

- (OSStatus)renameAndForgetNoteDatabaseFile:(NSString*)newfilename;
- (BOOL)removeSpuriousDatabaseFileNotes;

- (void)relocateNotesDirectory;

+ (NSString*)defaultNotesDirectoryPathReturningError:(OSStatus*)outErr;

- (NSMutableData*)dataFromFileInNotesDirectory:(NSString*)filename;
- (NSMutableData*)dataFromFileInNotesDirectoryForCatalogEntry:(NoteCatalogEntry*)catEntry;
- (NSMutableData*)dataFromFileInNotesDirectory:(NSString*)filename fileSize:(UInt64)givenFileSize;
- (OSStatus)noteFileRenamedFromName:(NSString*)oldName toName:(NSString*)newName;
- (NSString*)uniqueFilenameForTitle:(NSString*)title fromNote:(NoteObject*)note;
- (OSStatus)fileInNotesDirectory:(NSString*)filename hasFileInfo:(KNFileInfo *)info;
- (OSStatus)deleteFileInNotesDirectory:(NSString*)filename;
- (OSStatus)createFileIfNotPresentInNotesDirectory:(NSString*)filename fileWasCreated:(BOOL*)created;
- (OSStatus)storeDataAtomicallyInNotesDirectory:(NSData*)data withName:(NSString*)filename;
- (OSStatus)storeDataAtomicallyInNotesDirectory:(NSData*)data withName:(NSString*)filename
							 verifyWithSelector:(SEL)verifySel verificationDelegate:(id)verifyDelegate;
+ (NSURL*)trashDirectoryURLForItemAtURL:(NSURL*)itemURL;
- (OSStatus)moveFileToTrash:(NSString*)filename;
- (void)notifyOfChangedTrash;
@end

@interface NSObject (NotationFileManagerDelegate)
- (NSNumber*)verifyDataAtTemporaryPath:(NSString*)tempPath withFinalName:(NSString*)filename;
@end
