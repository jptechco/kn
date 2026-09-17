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
#import "KNReleaseNotesWindowController.h"

NSString *KNUpdateToolbarItemIdentifier = @"UpdateAvailable";

//the indicator sits immediately after the search field, which is the toolbar's only other item
#define KNUpdateToolbarItemIndex 1

static KNUpdateController *sharedInstance = nil;

//An update that downloaded itself and is waiting to install on quit, recorded so that the next launch
//can show its release notes: a dictionary of the three keys below. Removed once the notes are shown,
//or as soon as the user sees Sparkle's own window for the update, which carries the same notes.
static NSString *KNSilentUpdateKey = @"KNUpdateInstallingSilently";
static NSString *KNSilentUpdateBuildKey = @"build";
static NSString *KNSilentUpdateVersionKey = @"version";
static NSString *KNSilentUpdateNotesURLKey = @"releaseNotesURL";

KNSilentUpdateAction KNSilentUpdateActionForBuilds(NSInteger recordedBuild, NSInteger runningBuild) {
	if (recordedBuild <= 0 || runningBuild <= 0) return KNSilentUpdateForget;
	if (runningBuild == recordedBuild) return KNSilentUpdateShowNotes;
	//a newer build than the one recorded was installed some other way, and the record is stale
	if (runningBuild > recordedBuild) return KNSilentUpdateForget;
	//still running the old build: the install on quit has not happened yet (a crash, or a forced quit)
	return KNSilentUpdateWait;
}

//declared here rather than in the header so the header needs no Sparkle import
@interface KNUpdateController () <SPUUpdaterDelegate, SPUStandardUserDriverDelegate>
//the SPUUpdater behind updaterController, typed here where Sparkle is known
- (SPUUpdater*)updater;
- (void)forgetSilentUpdate;
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
		//before its first scheduled check, so nothing reaches the network unannounced. Both delegates
		//are this class: the user-driver delegate is what suppresses the alert for scheduled checks,
		//and the updater delegate only watches for an update that will install itself unseen. It
		//changes nothing about how updates are found or installed. See below.
		updaterController = [[SPUStandardUpdaterController alloc] initWithStartingUpdater:YES
																		 updaterDelegate:self
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

#pragma mark Preferences pane passthrough

//These keep Sparkle behind this class for the Updates preference pane. updaterController is normally
//started at launch by -installInMenuItem:; guard anyway by reusing that same idempotent path -- a nil
//menu item just starts the updater and returns -- so the pane works even if it is somehow reached
//first. SPUStandardUpdaterController.updater is the SPUUpdater carrying the two flags.
- (SPUUpdater*)updater {
	if (!updaterController) [self installInMenuItem:nil];
	return [updaterController updater];
}

- (IBAction)checkForUpdates:(id)sender {
	if (!updaterController) [self installInMenuItem:nil];
	//the same action the menu item and the "Update Available" toolbar button use
	[updaterController checkForUpdates:sender];
}

- (BOOL)automaticallyChecksForUpdates {
	return [[self updater] automaticallyChecksForUpdates];
}
- (void)setAutomaticallyChecksForUpdates:(BOOL)value {
	[[self updater] setAutomaticallyChecksForUpdates:value];
}
- (BOOL)automaticallyDownloadsUpdates {
	return [[self updater] automaticallyDownloadsUpdates];
}
- (void)setAutomaticallyDownloadsUpdates:(BOOL)value {
	[[self updater] setAutomaticallyDownloadsUpdates:value];
}

#pragma mark Release notes for updates that installed themselves

/*
 With Auto-Update on, Sparkle downloads an update in the background and installs it when the application
 quits, and the user never sees the window that would have shown them what changed. Only that path is
 recorded -- Sparkle announces it with -updater:willInstallUpdateOnQuit:immediateInstallationBlock:,
 which fires for nothing else -- and the next launch of the new build shows the notes, once.

 Everyone else is left alone: an update installed from Sparkle's window came with its notes; a fresh
 download from the website was never recorded; and a silently downloaded update that Sparkle ends up
 presenting after all (a critical update, or one left waiting too long) clears the record when shown.
 */
- (BOOL)updater:(SPUUpdater *)updater willInstallUpdateOnQuit:(SUAppcastItem *)item
			immediateInstallationBlock:(void (^)(void))immediateInstallHandler {

	NSInteger build = [[item versionString] integerValue];
	NSURL *notesURL = [item releaseNotesURL];

	//only a page served over HTTPS is shown; without one there is nothing worth a window
	if (build > 0 && [[[notesURL scheme] lowercaseString] isEqualToString:@"https"]) {
		NSString *version = [item displayVersionString];
		[[NSUserDefaults standardUserDefaults] setObject:[NSDictionary dictionaryWithObjectsAndKeys:
			[NSNumber numberWithInteger:build], KNSilentUpdateBuildKey,
			[version length] ? version : [item versionString], KNSilentUpdateVersionKey,
			[notesURL absoluteString], KNSilentUpdateNotesURLKey, nil] forKey:KNSilentUpdateKey];
	} else {
		[self forgetSilentUpdate];
	}

	//NO: Sparkle keeps charge of the install, exactly as it would with no delegate
	return NO;
}

- (void)forgetSilentUpdate {
	[[NSUserDefaults standardUserDefaults] removeObjectForKey:KNSilentUpdateKey];
}

- (void)showReleaseNotesIfUpdateInstalledSilently {

	NSDictionary *record = [[NSUserDefaults standardUserDefaults] dictionaryForKey:KNSilentUpdateKey];
	if (!record) return;

	NSInteger recordedBuild = [[record objectForKey:KNSilentUpdateBuildKey] integerValue];
	NSInteger runningBuild = [[[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"] integerValue];

	switch (KNSilentUpdateActionForBuilds(recordedBuild, runningBuild)) {
		case KNSilentUpdateWait:
			return;
		case KNSilentUpdateForget:
			[self forgetSilentUpdate];
			return;
		case KNSilentUpdateShowNotes:
			break;
	}

	//forgotten before showing, so a crash while the window is up cannot make it appear on every launch
	[self forgetSilentUpdate];

	id urlString = [record objectForKey:KNSilentUpdateNotesURLKey];
	NSURL *notesURL = [urlString isKindOfClass:[NSString class]] ? [NSURL URLWithString:urlString] : nil;
	if (![[[notesURL scheme] lowercaseString] isEqualToString:@"https"]) return;

	id version = [record objectForKey:KNSilentUpdateVersionKey];
	[KNReleaseNotesWindowController showReleaseNotesForVersion:[version isKindOfClass:[NSString class]] ? version : @""
														  URL:notesURL];
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
	//Sparkle is showing its own window for this one, which carries the release notes: the indicator
	//would be redundant, and so would showing the notes again after the update installs
	if (handleShowingUpdate) [self forgetSilentUpdate];
	else [self showUpdateIndicator];
}

//the user clicked the indicator, or opened Sparkle's window some other way -- the reminder has done
//its job and the window now carries the message
- (void)standardUserDriverDidReceiveUserAttentionForUpdate:(SUAppcastItem *)update {
	[self hideUpdateIndicator];
	[self forgetSilentUpdate];
}

//installed, skipped, deferred or failed: whatever the outcome, nothing is waiting any more
- (void)standardUserDriverWillFinishUpdateSession {
	[self hideUpdateIndicator];
}

//never deallocated: the updater must outlive every check it schedules

@end
