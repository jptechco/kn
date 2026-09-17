//
//  KNTextStatistics.h
//  Kinetic Notes
//
//  Line starts and the counts shown in the status bar.

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

#import <Foundation/Foundation.h>
#import "GlobalPrefs.h"

//Fills `starts` (which may be nil) with the character index at which each line of `string` begins, and
//returns how many lines there are. A line ends at any of the terminators -[NSString getLineStart:...]
//recognizes, including CRLF as one. A string that ends in a terminator has a final, empty line after
//it -- the line the insertion point sits on -- so "a\n" is two lines; the empty string is one.
//The line-number gutter and the status bar's line count both come from here, so they always agree.
NSUInteger KNLineStartIndexes(NSString *string, NSMutableData *starts);

//How many of `unit` `string` contains:
// - words: as NSStringEnumerationByWords finds them, which handles languages written without spaces
// - characters: user-perceived characters (an emoji or an accented letter is one), never counting line
//   breaks; "without spaces" also leaves out every other kind of whitespace
// - lines: as KNLineStartIndexes counts them, except that an empty note has none
// - paragraphs: runs of text between line breaks that contain something other than whitespace
NSUInteger KNCountTextUnits(NSString *string, KNTextCountUnit unit);
