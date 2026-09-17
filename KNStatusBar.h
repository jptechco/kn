//
//  KNStatusBar.h
//  Kinetic Notes
//
//  The bar beneath the main window that counts the words (or characters, lines or paragraphs) in the
//  note being shown.

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

//the bar's height, which AppController takes out of the split view when the bar is shown
extern const CGFloat KNStatusBarHeight;

@interface KNStatusBar : NSView {
	NSTextView *textView;	//not retained: the window owns both
	NSButton *countButton;
	BOOL updateIsPending;
}

- (id)initWithFrame:(NSRect)frame textView:(NSTextView *)aTextView;

//recount now, e.g. because the editor was shown or hidden. Nothing is counted while the bar is out of
//the window, so this is also what brings it up to date when it is put back.
- (void)update;

- (IBAction)showCountMenu:(id)sender;
- (IBAction)chooseCountUnit:(id)sender;

@end
