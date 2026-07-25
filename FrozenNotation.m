//
//  FrozenNotation.m
//  Notation
//
//  Created by Zachary Schneirov on 4/4/06.

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


#import "FrozenNotation.h"
#import "DeletedNoteObject.h"
#import "KNSecureArchiving.h"
#import "NoteObject.h"
#import "PassphraseRetriever.h"
#import "NSData_transformations.h"
#import "NotationPrefs.h"

@implementation FrozenNotation

+ (BOOL)supportsSecureCoding { return YES; }

+ (NSSet*)notesArchiveClasses {
	//the class list for the inner archive: an array of notes, or -- in the WAL and in the deleted set
	//-- the tombstones that stand in for them
	return [NSSet setWithObjects:[NSArray class], [NSSet class], [NoteObject class], [DeletedNoteObject class], nil];
}

- (id)initWithCoder:(NSCoder*)decoder {
	if ([decoder containsValueForKey:VAR_STR(prefs)]) {
		prefs = [[decoder decodeObjectOfClass:[NotationPrefs class] forKey:VAR_STR(prefs)] retain];
		notesData = [[decoder decodeObjectOfClass:[NSData class] forKey:VAR_STR(notesData)] retain];
		//the deleted set holds DeletedNoteObject tombstones and is not encrypted with the notes
		deletedNoteSet = [[decoder decodeObjectOfClasses:[NSSet setWithObjects:[NSSet class], [DeletedNoteObject class], nil]
												  forKey:VAR_STR(deletedNoteSet)] retain];
	} else {
		NSLog(@"FrozenNotation: decoding legacy %@", decoder);
		prefs = [[decoder decodeObject] retain];
		notesData = [[decoder decodeObject] retain];
		(void)[decoder decodeObject];
	}	
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
	if ([coder allowsKeyedCoding]) {
		[coder encodeObject:prefs forKey:VAR_STR(prefs)];
		[coder encodeObject:notesData forKey:VAR_STR(notesData)];
		[coder encodeObject:deletedNoteSet forKey:VAR_STR(deletedNoteSet)];
	} else {
		[coder encodeObject:prefs];
		[coder encodeObject:notesData];
		[coder encodeObject:deletedNoteSet];
	}
}

- (BOOL)hasEncodedNotesData {
	return [notesData length] > 0;
}

- (id)initWithNotes:(NSMutableArray*)notes deletedNotes:(NSMutableSet*)antiNotes prefs:(NotationPrefs*)somePrefs {
	
	if ([super init]) {

		notesData = [[NSMutableData alloc] init];
		if (!KNArchiveRootObject(notes, @"notes", notesData)) return nil;

		prefs = [somePrefs retain];
		deletedNoteSet = [antiNotes retain];		
		
		NSMutableData *oldNotesData = notesData;
		notesData = [[notesData compressedData] retain];
		[oldNotesData release];
		
		//ostensibly to create more entropy in the first blocks, relying on CBC dependency to crack
		//[notesData reverseBytes];
		
		if ([somePrefs doesEncryption]) {
			//compress?, reverse?, encrypt notesData based on notationprefs
			//we also want to have the salt reset here, but that requires knowing the original password
			
			if (![prefs encryptDataInNewSession:notesData]) {
				NSLog(@"Couldn't encrypt data!");
				return nil;
			}
		}
		
		if (![notesData length]) {
			NSLog(@"%s: empty notesData; returning nil", _cmd);
			return nil;
		}
	}
	
	return self;
}

- (void)dealloc {
	[allNotes release];
	[notesData release];
	[prefs release];
	[deletedNoteSet release];
	
	[super dealloc];
}

+ (NSData*)frozenDataWithExistingNotes:(NSMutableArray*)notes 
						  deletedNotes:(NSMutableSet*)antiNotes 
								 prefs:(NotationPrefs*)prefs {
	FrozenNotation *frozenNotation = [[FrozenNotation alloc] initWithNotes:notes deletedNotes:antiNotes prefs:prefs];

	if (!frozenNotation)
		return nil;
	
	NSData *encodedNotationData = KNArchivedDataWithRootObject(frozenNotation);
	[frozenNotation autorelease];
	
	return encodedNotationData;
}

- (NSMutableArray*)unpackedNotesWithPrefs:(NotationPrefs*)somePrefs returningError:(OSStatus*)err {
	
	//decrypt notesData if necessary, then unarchive
	
	*err = noErr;
	
	@try {
		if ([somePrefs doesEncryption]) {
			if (![somePrefs decryptDataWithCurrentSettings:notesData]) {
				NSLog(@"Error decrypting data!");
				*err = kNoAuthErr;
				return nil;
			}
		}
		
		NSMutableData *oldNotesData = notesData;
		notesData = [[notesData uncompressedData] retain];
		[oldNotesData autorelease];
		
		if (!notesData) {
			*err = kCompressionErr;
			NSLog(@"Error decompressing data");
			return nil;
		}
		allNotes = [KNUnarchiveObjectOfClasses([FrozenNotation notesArchiveClasses], notesData, @"notes") retain];

	} @catch (NSException *e) {
		*err = kCoderErr;
		NSLog(@"(VERIFY) Error unarchiving notes from data (%@, %@)", [e name], [e reason]);
		return nil;
	}
	
	return allNotes;
}


- (NSMutableArray*)unpackedNotesReturningError:(OSStatus*)err {
	
	//decrypt notesData, grabbing password from from keychain or user as necessary, then unarchive
	
	*err = noErr;
	
	if (!allNotes) {
		
		@try {
			if ([prefs doesEncryption]) {
				BOOL keychainGood = YES;
				if (![prefs storesPasswordInKeychain] || !(keychainGood = [prefs canLoadPassphraseData:[prefs passwordDataFromKeychain]])) {
					
					if (!keychainGood) {
						//reset keychain identifier in case database file was duplicated and password was changed, and this is the old DB
						[prefs forgetKeychainIdentifier];
					}
					int result = [[PassphraseRetriever retrieverWithNotationPrefs:prefs] loadedUserPassphraseData];
					
					if (!result) {
						//must have clicked cancel or equivalent
						*err = kPassCanceledErr;
						return (nil);
					}
					//if result is 1, passphrase should already be loaded
				}
				if (![prefs decryptDataWithCurrentSettings:notesData]) {
					NSLog(@"Error decrypting data!");
					*err = kNoAuthErr;
					return(nil);
				}
			}
			
			//[notesData reverseBytes];
			
			NSMutableData *oldNotesData = notesData;
			notesData = [[notesData uncompressedData] retain];
			[oldNotesData autorelease];
			
			if (!notesData) {
				*err = kCompressionErr;
				NSLog(@"Error decompressing data");
				return(nil);
			}
            allNotes = [KNUnarchiveObjectOfClasses([FrozenNotation notesArchiveClasses], notesData, @"notes") retain];

            if (!allNotes) {
                //a database written before 2009 holds a non-keyed archive, which NSKeyedUnarchiver
                //cannot read at all. NSUnarchiver is deprecated with no replacement, so this stays.
                allNotes = [[NSUnarchiver unarchiveObjectWithData:notesData] retain];
            }
		} @catch (NSException *e) {
			*err = kCoderErr;
			NSLog(@"Error unarchiving notes from data (%@, %@)", [e name], [e reason]);
			return(nil);
		}
	}
	
	return allNotes;
}

- (NSMutableSet*)deletedNotes {
	return deletedNoteSet;
}

- (NotationPrefs*)notationPrefs {
	return prefs;
}


@end
