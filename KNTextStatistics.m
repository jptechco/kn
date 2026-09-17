//
//  KNTextStatistics.m
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

#import "KNTextStatistics.h"

NSUInteger KNLineStartIndexes(NSString *string, NSMutableData *starts) {
	NSUInteger length = [string length], index = 0, count = 0;

	[starts setLength:0];

	while (YES) {
		if (starts) [starts appendBytes:&index length:sizeof(index)];
		count++;

		if (index >= length) break;

		NSUInteger lineEnd = 0, contentsEnd = 0;
		[string getLineStart:NULL end:&lineEnd contentsEnd:&contentsEnd forRange:NSMakeRange(index, 0)];

		//the last line has no terminator: there is no line after it
		if (lineEnd == contentsEnd || lineEnd <= index) break;
		index = lineEnd;
	}
	return count;
}

static NSUInteger KNCountComposedCharacters(NSString *string, NSCharacterSet *excluded) {
	__block NSUInteger count = 0;
	[string enumerateSubstringsInRange:NSMakeRange(0, [string length])
							   options:NSStringEnumerationByComposedCharacterSequences | NSStringEnumerationSubstringNotRequired
							usingBlock:^(NSString *substring, NSRange range, NSRange enclosingRange, BOOL *stop) {
		if (![excluded characterIsMember:[string characterAtIndex:range.location]]) count++;
	}];
	return count;
}

NSUInteger KNCountTextUnits(NSString *string, KNTextCountUnit unit) {
	NSUInteger length = [string length];
	if (!length) return 0;

	switch (unit) {
		case KNTextCountCharactersWithSpaces:
			return KNCountComposedCharacters(string, [NSCharacterSet newlineCharacterSet]);

		case KNTextCountCharactersWithoutSpaces:
			return KNCountComposedCharacters(string, [NSCharacterSet whitespaceAndNewlineCharacterSet]);

		case KNTextCountLines:
			return KNLineStartIndexes(string, nil);

		case KNTextCountParagraphs: {
			NSCharacterSet *visible = [[NSCharacterSet whitespaceAndNewlineCharacterSet] invertedSet];
			__block NSUInteger count = 0;
			[string enumerateSubstringsInRange:NSMakeRange(0, length)
									   options:NSStringEnumerationByParagraphs | NSStringEnumerationSubstringNotRequired
									usingBlock:^(NSString *substring, NSRange range, NSRange enclosingRange, BOOL *stop) {
				if ([string rangeOfCharacterFromSet:visible options:0 range:range].location != NSNotFound) count++;
			}];
			return count;
		}

		case KNTextCountWords:
		default: {
			__block NSUInteger count = 0;
			[string enumerateSubstringsInRange:NSMakeRange(0, length)
									   options:NSStringEnumerationByWords | NSStringEnumerationSubstringNotRequired
									usingBlock:^(NSString *substring, NSRange range, NSRange enclosingRange, BOOL *stop) {
				count++;
			}];
			return count;
		}
	}
}
