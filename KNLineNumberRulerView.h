//
//  KNLineNumberRulerView.h
//  Kinetic Notes
//
//  The line-number gutter beside the note editor.

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
 A vertical ruler that numbers the lines of the note in its scroll view's text view. The numbers are
 drawn, never inserted into the text, so they cannot be selected, copied, dragged, printed or exported.
 Lines are the note's own lines, not the rows they wrap onto: a wrapped line is numbered once, on its
 first row. The line holding the insertion point (every line a selection touches) is drawn brighter,
 on a faint band.

 Install with -[NSScrollView setVerticalRulerView:] and -setRulersVisible:, as LinkingEditor does.
 */
@interface KNLineNumberRulerView : NSRulerView {
	NSTextView *textView;			//not retained: the text view owns the scroll view that owns this
	NSMutableData *lineStarts;
	NSUInteger lineCount;
	BOOL lineStartsAreValid;
	CGFloat thickness;
}

- (id)initWithTextView:(NSTextView *)aTextView;

//for a change in the fonts or colors the gutter derives its own from
- (void)noteAppearanceChanged;

@end
