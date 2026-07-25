//
//  KNSecureArchiving.h
//  Kinetic Notes
//
//  NSSecureCoding-based replacements for the deprecated NSKeyedArchiver entry points.

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

#import <Cocoa/Cocoa.h>

/*
 +archivedDataWithRootObject: and +unarchiveObjectWithData: were deprecated in 10.14 in favour of
 the secure-coding variants. These wrap the replacements.

 The wire format does not change. -initRequiringSecureCoding:YES and
 -initForWritingWithMutableData: both emit a binary property list (NSPropertyListBinaryFormat_v1_0,
 the NSKeyedArchiver default since 10.2) with the same object table, so the archives this writes are
 byte-identical to the ones the previous build wrote -- verified by archiving the same graph both
 ways and comparing. Secure coding is a decode-side class check; it adds nothing to the output.
 That matters because the notes database is compared byte-for-byte across builds, and because a
 database written here still has to open in Notational Velocity and in the Stage-1 build.

 Reading is where the behaviour could change, so it is deliberately forgiving. Under secure coding
 every decoded object's class must appear in the allowed set, and a class that was missed throws
 rather than returning nil -- which for this application means a database that used to open stops
 opening. KNUnarchive* therefore try the secure decode first and, if it fails, retry with secure
 coding off and log the reason. A note database is the user's own file, already sitting inside the
 notes directory; the retry keeps the failure mode no worse than the one being replaced while the
 first attempt still does the checking in every normal case. The one caller that reads a *foreign*
 database -- the first-run import, which resolves Notational Velocity's own directory -- gets the
 same treatment, since refusing to import a database NV itself can open would be the wrong trade.

 Non-keyed archives are not covered here. NSUnarchiver has no secure-coding equivalent and no
 replacement at all, so the pre-2009 .Blor-era read path in -[FrozenNotation unpackedNotesReturningError:]
 and the Stickies importer keep using it directly.
 */

//archives with requiringSecureCoding:YES. Returns nil and logs on failure, which can only happen if
//a class in the graph does not implement NSSecureCoding -- a programming error, not bad input.
NSData *KNArchivedDataWithRootObject(id rootObject);

//as above, but writes into an existing NSMutableData the way -initForWritingWithMutableData: did,
//for the two nested archives that are compressed and encrypted in place afterwards
BOOL KNArchiveRootObject(id rootObject, NSString *key, NSMutableData *data);

//decodes an archive whose root is expected to be `aClass`. See the note on the fallback above.
id KNUnarchiveObjectOfClass(Class aClass, NSData *data);

//as above, for a root object that may be any of several classes (a container, or the WAL's
//NoteObject-or-DeletedNoteObject record)
id KNUnarchiveObjectOfClasses(NSSet *classes, NSData *data, NSString *key);

//the plist leaf classes that turn up inside the archived dictionaries and arrays (NSString,
//NSNumber, NSDate, NSData, NSArray, NSDictionary, NSSet). Union this with the model classes a
//given graph can contain.
NSSet *KNPropertyListClasses(void);
