//
//  KNSecureArchiving.m
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

#import "KNSecureArchiving.h"

NSSet *KNPropertyListClasses(void) {
	static NSSet *classes = nil;
	if (!classes) {
		classes = [[NSSet alloc] initWithObjects:[NSString class], [NSNumber class], [NSDate class],
				   [NSData class], [NSArray class], [NSDictionary class], [NSSet class], nil];
	}
	return classes;
}

NSData *KNArchivedDataWithRootObject(id rootObject) {
	NSError *error = nil;
	NSData *data = [NSKeyedArchiver archivedDataWithRootObject:rootObject requiringSecureCoding:YES error:&error];
	if (!data) NSLog(@"KNArchivedDataWithRootObject: could not archive %@: %@", [rootObject class], error);

	return data;
}

BOOL KNArchiveRootObject(id rootObject, NSString *key, NSMutableData *data) {
	NSCParameterAssert(key != nil && data != nil);

	NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initRequiringSecureCoding:YES];
	@try {
		[archiver encodeObject:rootObject forKey:key];
		[archiver finishEncoding];
	} @catch (NSException *e) {
		NSLog(@"KNArchiveRootObject: could not archive %@ (%@, %@)", [rootObject class], [e name], [e reason]);
		[archiver release];
		return NO;
	}

	//-initForWritingWithMutableData: appended into the caller's buffer as it encoded; the replacement
	//accumulates internally and hands the result over at finishEncoding, so copy it across here
	[data setData:[archiver encodedData]];
	[archiver release];

	return [data length] > 0;
}

//shared by both unarchive entry points: `classes` nil means decode the root object of an archive
//written by +archivedDataWithRootObject:, otherwise decode `key` out of a nested archive
static id KNUnarchive(NSSet *classes, NSString *key, NSData *data) {
	if (![data length]) return nil;

	NSError *error = nil;
	NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingFromData:data error:&error];
	if (!unarchiver) {
		NSLog(@"KNUnarchive: data is not a keyed archive: %@", error);
		return nil;
	}
	//report failures as errors rather than exceptions so the retry below is reachable without
	//unwinding through the caller's @try
	[unarchiver setDecodingFailurePolicy:NSDecodingFailurePolicySetErrorAndReturn];

	id object = [unarchiver decodeObjectOfClasses:classes forKey:key ? key : NSKeyedArchiveRootObjectKey];

	if (!object && [unarchiver error]) {
		//a class in the graph was not on the allowed list, or the archive is damaged. Retry without
		//the class check so a database that opened before still opens -- see the note in the header.
		NSError *secureError = [[[unarchiver error] retain] autorelease];
		[unarchiver release];

		unarchiver = [[NSKeyedUnarchiver alloc] initForReadingFromData:data error:&error];
		if (!unarchiver) return nil;
		[unarchiver setRequiresSecureCoding:NO];
		[unarchiver setDecodingFailurePolicy:NSDecodingFailurePolicySetErrorAndReturn];

		object = [unarchiver decodeObjectForKey:key ? key : NSKeyedArchiveRootObjectKey];
		if (object) {
			NSLog(@"KNUnarchive: secure decode of %@ failed (%@); succeeded without the class check",
				  key ? key : @"root", [secureError localizedDescription]);
		}
	}

	[object retain];
	[unarchiver finishDecoding];
	[unarchiver release];

	return [object autorelease];
}

id KNUnarchiveObjectOfClass(Class aClass, NSData *data) {
	return KNUnarchive([NSSet setWithObject:aClass], nil, data);
}

id KNUnarchiveObjectOfClasses(NSSet *classes, NSData *data, NSString *key) {
	return KNUnarchive(classes, key, data);
}
