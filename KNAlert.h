//
//  KNAlert.h
//  Kinetic Notes
//
//  NSAlert-backed replacements for the deprecated NSRunAlertPanel family.

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
 NSRunAlertPanel and friends were deprecated in 10.10. These are the direct replacements, kept as
 functions so the ~38 call sites inherited from Notational Velocity stay one-liners.

 Two differences from the functions they replace, both deliberate:

 - Buttons are named by position rather than role. NSRunAlertPanel's "default/alternate/other"
   returned NSAlertDefaultReturn/NSAlertAlternateReturn/NSAlertOtherReturn (1/0/-1); these return
   NSAlertFirstButtonReturn/NSAlertSecondButtonReturn/NSAlertThirdButtonReturn (1000/1001/1002).
   The on-screen order is unchanged: the first button is the rightmost and is the default.
   Every call site had to be updated to compare against the new constants -- the old and new
   values overlap at nothing, so a missed comparison fails closed rather than silently inverting.

 - `message` is plain text, not a printf format string. NSRunAlertPanel ran its message argument
   through a format pass, which meant any '%' that survived into an already-substituted string was
   reinterpreted. Several inherited call sites pass a -stringWithFormat: result here, so dropping
   the second pass removes a latent crash rather than changing intended behavior.

 A nil or empty button title is skipped. If no title is given for the first button, NSAlert
 supplies its own localized "OK", matching what NSRunAlertPanel did with a nil default button.
 */

NSModalResponse KNRunAlert(NSString *title, NSString *message,
						   NSString *firstButton, NSString *secondButton, NSString *thirdButton);

//as above, but with NSAlertStyleCritical -- replaces NSRunCriticalAlertPanel
NSModalResponse KNRunCriticalAlert(NSString *title, NSString *message,
								   NSString *firstButton, NSString *secondButton, NSString *thirdButton);

//replaces the NSBeginAlertSheet calls that passed no did-end selector: shows the sheet and returns
//immediately, with nothing to do when it is dismissed
void KNBeginAlertSheet(NSWindow *window, NSString *title, NSString *message, NSString *buttonTitle);
