//
//  KNUpdateController.m
//  Kinetic Notes
//
//  Automatic updates: the Sparkle updater, and the unobtrusive "Update Available" indicator.

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

#import "KNUpdateController.h"
#import <Sparkle/Sparkle.h>

NSString *KNUpdateToolbarItemIdentifier = @"UpdateAvailable";

//the indicator sits immediately after the search field, which is the toolbar's only other item
#define KNUpdateToolbarItemIndex 1

static KNUpdateController *sharedInstance = nil;

//declared here rather than in the header so the header needs no Sparkle import
@interface KNUpdateController () <SPUStandardUserDriverDelegate>
@end

@implementation KNUpdateController

+ (KNUpdateController*)sharedInstance {
	//started on the main thread at launch, and Sparkle calls its delegate back on the main thread;
	//nothing else reaches this class, so no synchronization
	if (sharedInstance == nil)
		sharedInstance = [[KNUpdateController alloc] init];
	return sharedInstance;
}

- (void)installInMenuItem:(NSMenuItem*)item {

	if (!updaterController) {
		//YES: start the updater now. Sparkle does not check on a first launch, and asks permission
		//before its first scheduled check, so nothing reaches the network unannounced. The updater
		//delegate is nil -- the stock behaviour is what we want -- but the user-driver delegate is
		//this class, which is what suppresses the alert for scheduled checks. See below.
		updaterController = [[SPUStandardUpdaterController alloc] initWithStartingUpdater:YES
																		 updaterDelegate:nil
																	  userDriverDelegate:self];
	}

	if (!item) return;

	//the nib's title is untranslated in Spanish and inconsistently punctuated elsewhere -- the item
	//has never been visible, so nobody has seen it. Set it from the strings tables instead.
	[item setTitle:NSLocalizedString(@"Check for Updates…", @"application menu item that checks for a new version")];

	//SPUStandardUpdaterController answers -validateMenuItem: for this action, enabling the item only
	//while a check is actually possible, so AppController's own -validateMenuItem: is never asked
	[item setTarget:updaterController];
	[item setAction:@selector(checkForUpdates:)];
	[item setHidden:NO];
}

- (void)setToolbar:(NSToolbar*)aToolbar {
	//not retained: the toolbar belongs to the window, which outlives this object in every case that
	//matters, and retaining it here would be a cycle through the item's target
	toolbar = aToolbar;
}

- (NSToolbarItem*)updateToolbarItem {

	if (updateToolbarItem) return updateToolbarItem;

	NSString *title = NSLocalizedString(@"Update Available", @"toolbar button shown when a new version was found by a scheduled check");

	//NSBezelStyleInline is the small filled badge AppKit uses for this kind of in-place notice; it
	//reads as an indicator rather than as a command, which is the point
	NSButton *button = [NSButton buttonWithTitle:title target:updaterController action:@selector(checkForUpdates:)];
	[button setBezelStyle:NSBezelStyleInline];
	[button setControlSize:NSControlSizeSmall];
	[button setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
	[button setToolTip:NSLocalizedString(@"A new version of Kinetic Notes is ready to install.", @"tooltip of the Update Available toolbar button")];
	[[button cell] setAccessibilityLabel:title];
	[button sizeToFit];

	//no -setMinSize:/-setMaxSize:, which are deprecated as of macOS 12: the button reports an
	//intrinsic content size, and the item measures itself from that
	updateToolbarItem = [[NSToolbarItem alloc] initWithItemIdentifier:KNUpdateToolbarItemIdentifier];
	[updateToolbarItem setView:button];
	[updateToolbarItem setLabel:title];

	return updateToolbarItem;
}

- (void)showUpdateIndicator {

	if (updateIsWaiting || !toolbar) return;
	updateIsWaiting = YES;

	//the search field is item 0 and yields width readily (its maxSize is unbounded), so inserting
	//after it puts the indicator at the right-hand end of the row without disturbing anything
	if ([[toolbar items] count] >= KNUpdateToolbarItemIndex)
		[toolbar insertItemWithItemIdentifier:KNUpdateToolbarItemIdentifier atIndex:KNUpdateToolbarItemIndex];
}

- (void)hideUpdateIndicator {

	if (!updateIsWaiting) return;
	updateIsWaiting = NO;

	NSUInteger i = [[toolbar items] indexOfObject:[self updateToolbarItem]];
	if (i != NSNotFound) [toolbar removeItemAtIndex:i];
}

#pragma mark SPUStandardUserDriverDelegate

//Without this, Sparkle assumes the application has no way to show a reminder of its own and logs a
//warning when the alert is declined.
- (BOOL)supportsGentleScheduledUpdateReminders {
	return YES;
}

/*
 The whole point of the feature. An update found by a check the user asked for is in "immediate
 focus" -- they chose the menu item and are waiting for an answer, so Sparkle should answer. An
 update found on a timer is not: it arrives while the user is in the middle of something, most often
 seconds after launch, which is exactly when they opened the application to do something else.
 Returning NO there suppresses Sparkle's window and hands the notification to -showUpdateIndicator.
 */
- (BOOL)standardUserDriverShouldHandleShowingScheduledUpdate:(SUAppcastItem *)update
										 andInImmediateFocus:(BOOL)immediateFocus {
	return immediateFocus;
}

- (void)standardUserDriverWillHandleShowingUpdate:(BOOL)handleShowingUpdate
										forUpdate:(SUAppcastItem *)update
											state:(SPUUserUpdateState *)state {
	//Sparkle is showing its own window for this one; ours would be redundant
	if (!handleShowingUpdate) [self showUpdateIndicator];
}

//the user clicked the indicator, or opened Sparkle's window some other way -- the reminder has done
//its job and the window now carries the message
- (void)standardUserDriverDidReceiveUserAttentionForUpdate:(SUAppcastItem *)update {
	[self hideUpdateIndicator];
}

//installed, skipped, deferred or failed: whatever the outcome, nothing is waiting any more
- (void)standardUserDriverWillFinishUpdateSession {
	[self hideUpdateIndicator];
}

//never deallocated: the updater must outlive every check it schedules

@end
