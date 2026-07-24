//
//  KNMigrationController.h
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

#import <Cocoa/Cocoa.h>

/*
 Imports notes from an existing Notational Velocity installation the first time Kinetic Notes runs.

 The governing rule of this whole file: Notational Velocity's directory is read and nothing else.
 It is never written to, renamed, moved, or deleted, on any path, including failures. NV's keychain
 item is likewise only ever read. A user who dislikes this fork must be left with a working NV.

 The copy is staged into a sibling directory and only moved into place once it has been opened and
 verified, so an interrupted import can never leave a half-populated notes directory that the app
 would then treat as authoritative.
 */

extern NSString *KNNotationalVelocityBundleIdentifier;
extern NSString *KNNotationalVelocityDefaultDirectoryName;

@interface KNMigrationController : NSObject

//YES when Kinetic Notes has no usable notes directory yet, i.e. this is genuinely a first run.
//Migration is only ever offered in that case, which is what makes it impossible to run twice.
+ (BOOL)isFirstRun;

//Path of a Notational Velocity notes directory containing a non-empty database, or nil.
//Prefers the location NV last recorded in its own preferences, then the default location.
+ (NSString*)detectedNotationalVelocityDirectory;

//NV holds its database open while running, so a copy taken now could be torn. This is the only
//condition that refuses an import; see the note on the journal filename in the implementation.
+ (BOOL)isNotationalVelocityRunning;

//A write-ahead journal left behind by a crash or a force-quit. Reported so the import can say so,
//not a reason to refuse: the journal is copied and replayed like any other launch would replay it.
+ (BOOL)directoryHasUnflushedJournal:(NSString*)directory;

//Path of the staged copy, if a previous attempt was interrupted and left one behind.
+ (NSString*)stagedImportDirectory;

@end
