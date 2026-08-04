//
//  KNUpdateController.h
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

#import <Cocoa/Cocoa.h>

/*
 Checking for new versions, and nothing else. Sparkle fetches the appcast named by SUFeedURL in
 Info.plist and verifies every download against the EdDSA public key in SUPublicEDKey before it is
 unpacked; a download that fails that check is discarded, not installed.

 Nothing is measured. Sparkle sends no profile of the system unless the application asks it to, and
 this class never does. Notational Velocity bundled Sparkle 1.5b6, which was built for ppc/i386/x86_64
 and so could never load on Apple Silicon; it was removed in the rebrand, and this is its replacement.

 MainMenu.nib already carries a "Check for Updates..." item, left over from that version, with neither
 a target nor an action -- and, in Spanish, with an untranslated title. The nib is Interface Builder 3
 format and is never re-saved, so the item gets its target, its action and its title here, at launch.

 A scheduled check does NOT interrupt the user. Sparkle's own alert window appears only for a check
 the user asked for, by choosing the menu item; a check that happens on a timer puts a small "Update
 Available" button in the toolbar instead, and waits. This is Sparkle's "gentle reminders" facility,
 not a fork of it.

 To remove the feature entirely:
   1. delete this file and KNUpdateController.m, and their four entries in project.pbxproj
   2. delete the #import and the three KNUpdateController lines in AppController.m -- the two in
      -runDelayedUIActionsAfterLaunch and -awakeFromNib, and the toolbar-delegate branch -- then hide
      the menu item again, as -runDelayedUIActionsAfterLaunch used to
   3. remove Frameworks/Sparkle.framework, its file reference and its two build-file entries (the
      Frameworks phase and the CopyFiles phase) from project.pbxproj, and the framework's three
      build settings: CODE_SIGN_ENTITLEMENTS, LD_RUNPATH_SEARCH_PATHS, and the
      "$(SRCROOT)/Frameworks" entry in FRAMEWORK_SEARCH_PATHS
   4. remove the SU* keys from Info.plist and the Sparkle section from Acknowledgments.txt
   5. delete the "Update Available" and "Check for Updates" blocks from the seven Localizable.strings
 */

//the toolbar item the indicator lives in. AppController's toolbar delegate vends it by this name.
extern NSString *KNUpdateToolbarItemIdentifier;

@interface KNUpdateController : NSObject
{
	//SPUStandardUpdaterController. Typed as id so this header needs no Sparkle import, which keeps
	//the framework out of every translation unit but KNUpdateController.m.
	id updaterController;

	NSToolbarItem *updateToolbarItem;
	NSToolbar *toolbar;
	BOOL updateIsWaiting;
}

+ (KNUpdateController*)sharedInstance;

//Starts the updater and points the supplied menu item at it, retitling it in the current language.
//Idempotent. Unhides the item, which the nib leaves visible but which AppController hid for as long
//as choosing it would have done nothing.
- (void)installInMenuItem:(NSMenuItem*)item;

//The toolbar the "Update Available" indicator is inserted into and removed from. Weak: the toolbar
//is owned by its window, and outlives this call either way.
- (void)setToolbar:(NSToolbar*)aToolbar;

//The indicator itself, for AppController's -toolbar:itemForItemIdentifier:willBeInsertedIntoToolbar:.
//Built on first use, so a launch in which no update is ever found never allocates it.
- (NSToolbarItem*)updateToolbarItem;

//The Updates preference pane drives these. They forward to the SPUUpdater behind updaterController,
//so that pane's "Check Now" button and its two "automatically…" toggles need no Sparkle import of
//their own -- the framework stays confined to KNUpdateController.m. Sparkle persists both flags in
//its own defaults, so setting them is all the persistence there is.
- (IBAction)checkForUpdates:(id)sender;
- (BOOL)automaticallyChecksForUpdates;
- (void)setAutomaticallyChecksForUpdates:(BOOL)value;
- (BOOL)automaticallyDownloadsUpdates;
- (void)setAutomaticallyDownloadsUpdates:(BOOL)value;

@end
