//
//  KNAlert.m
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

#import "KNAlert.h"

//shared setup for all three entry points; caller owns the returned alert
static NSAlert *KNAlertWithStyle(NSAlertStyle style, NSString *title, NSString *message,
								 NSString *firstButton, NSString *secondButton, NSString *thirdButton) {
	NSAlert *alert = [[NSAlert alloc] init];
	[alert setAlertStyle:style];

	//NSAlert raises on a nil messageText, and a few inherited call sites build their title with
	//-stringWithFormat: from a value that could come back nil
	[alert setMessageText:title ? title : @""];

	//call sites that had nothing to say for the second line passed @"" rather than nil; leaving
	//informativeText unset keeps the alert single-line instead of reserving an empty row for it
	if ([message length]) [alert setInformativeText:message];

	//order matters: the first button added is the rightmost and becomes the default, which is how
	//NSRunAlertPanel treated its defaultButton argument
	if ([firstButton length]) [alert addButtonWithTitle:firstButton];
	if ([secondButton length]) [alert addButtonWithTitle:secondButton];
	if ([thirdButton length]) [alert addButtonWithTitle:thirdButton];

	return alert;
}

NSModalResponse KNRunAlert(NSString *title, NSString *message,
						   NSString *firstButton, NSString *secondButton, NSString *thirdButton) {
	NSAlert *alert = KNAlertWithStyle(NSAlertStyleWarning, title, message, firstButton, secondButton, thirdButton);
	NSModalResponse response = [alert runModal];
	[alert release];
	return response;
}

NSModalResponse KNRunCriticalAlert(NSString *title, NSString *message,
								   NSString *firstButton, NSString *secondButton, NSString *thirdButton) {
	NSAlert *alert = KNAlertWithStyle(NSAlertStyleCritical, title, message, firstButton, secondButton, thirdButton);
	NSModalResponse response = [alert runModal];
	[alert release];
	return response;
}

void KNBeginAlertSheet(NSWindow *window, NSString *title, NSString *message, NSString *buttonTitle) {
	NSAlert *alert = KNAlertWithStyle(NSAlertStyleWarning, title, message, buttonTitle, nil, nil);

	//the sheet machinery keeps the alert alive until it is dismissed, so hand off our reference
	//here rather than trying to release it after a call that returns immediately
	[alert beginSheetModalForWindow:window completionHandler:nil];
	[alert autorelease];
}
