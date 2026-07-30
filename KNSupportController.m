//
//  KNSupportController.m
//  Kinetic Notes
//
//  The "Support Development" Help-menu item and the sponsorship page it opens.

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

#import "KNSupportController.h"
#import "KNAlert.h"

//the project's donation page, and the only URL this feature knows about
static NSString *KNSponsorshipURLString = @"https://www.kineticnotes.com/donate";

//the selector every item already in the Help menu sends. Named as a string rather than with
//@selector so this class needs no header from the class that implements it.
static NSString *KNHelpMenuActionName = @"showHelpDocument:";

//MainMenu.nib tags the Help items by what they open: 1 shortcuts, 2 acknowledgments, 3 product
//site, 4 development site. The tags are the same in all seven localizations, so the acknowledgments
//item -- the one this feature sits above -- can be found without matching any title.
#define KNAcknowledgmentsItemTag 2

static KNSupportController *sharedInstance = nil;

@implementation KNSupportController

+ (KNSupportController*)sharedInstance {
	//the menu item is installed on the main thread at launch and acted on from the main thread;
	//nothing else has a reason to reach this class, so no synchronization
	if (sharedInstance == nil)
		sharedInstance = [[KNSupportController alloc] init];
	return sharedInstance;
}

/*
 The Help menu carries no tag and no NSName in MainMenu.nib, so -[NSMenu itemWithTag:] -- how
 BookmarksController and AppController find their own menus -- is not available here, and matching on
 the title would mean matching seven localizations of it. Identify it instead by the action its
 existing items send, which is the same in every localization.
 */
- (NSMenu*)helpMenu {

	if ([NSApp helpMenu]) return [NSApp helpMenu];

	SEL helpAction = NSSelectorFromString(KNHelpMenuActionName);
	NSMenu *mainMenu = [NSApp mainMenu];
	NSInteger i, j;

	for (i = 0; i < [mainMenu numberOfItems]; i++) {
		NSMenu *submenu = [[mainMenu itemAtIndex:i] submenu];

		for (j = 0; j < [submenu numberOfItems]; j++) {
			if ([[submenu itemAtIndex:j] action] == helpAction) return submenu;
		}
	}

	//nothing in the menu bar sends that action any more; fall back to the last menu, which is where
	//Help sits. Better a plausible guess than nowhere, and both paths are still only ever a menu.
	return [mainMenu numberOfItems] ? [[mainMenu itemAtIndex:[mainMenu numberOfItems] - 1] submenu] : nil;
}

- (void)installMenuItemInMainMenu {

	NSMenu *helpMenu = [self helpMenu];
	if (!helpMenu) return;

	//installed once per launch; -indexOfItemWithTarget:andAction: reports -1 when it is not there yet
	if ([helpMenu indexOfItemWithTarget:self andAction:@selector(showSupportOptions:)] != -1) return;

	NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Support Development…", @"Help menu item that opens the project's sponsorship page")
												  action:@selector(showSupportOptions:) keyEquivalent:@""] autorelease];
	[item setTarget:self];

	//it belongs directly above Acknowledgments, in the group the nib already separates off for the
	//items that are about the project rather than about using it -- so no separator of our own
	NSInteger acknowledgments = [self indexOfHelpItemWithTag:KNAcknowledgmentsItemTag inMenu:helpMenu];
	if (acknowledgments != -1) {
		[helpMenu insertItem:item atIndex:acknowledgments];
		return;
	}

	//no acknowledgments item to sit above: end of the menu, separated from whatever precedes it
	[helpMenu addItem:[NSMenuItem separatorItem]];
	[helpMenu addItem:item];
}

//index of a nib-authored Help item by its tag, or -1. Matching on the action as well keeps this
//from finding some unrelated item that happens to carry the same tag.
- (NSInteger)indexOfHelpItemWithTag:(NSInteger)tag inMenu:(NSMenu*)menu {

	SEL helpAction = NSSelectorFromString(KNHelpMenuActionName);
	NSInteger i;

	for (i = 0; i < [menu numberOfItems]; i++) {
		NSMenuItem *item = [menu itemAtIndex:i];
		if ([item action] == helpAction && [item tag] == tag) return i;
	}
	return -1;
}

- (IBAction)showSupportOptions:(id)sender {

	//three paragraphs, kept as three strings: shorter units to translate, and the thanks can be
	//reworded or dropped without disturbing the rest
	NSString *message = [NSString stringWithFormat:@"%@\n\n%@\n\n%@",
		NSLocalizedString(@"Kinetic Notes is maintained by a volunteer, and donations help fund ongoing development.", @"first paragraph of the donation request"),
		NSLocalizedString(@"If this app has been useful to you, please consider supporting ongoing maintenance and new features. Donations are completely optional and help keep the project alive.", @"second paragraph of the donation request"),
		NSLocalizedString(@"Thank you for supporting the project.", @"closing line of the donation request")];

	//first button is the rightmost and the default; see KNAlert.h
	NSModalResponse response = KNRunAlert(NSLocalizedString(@"Support Kinetic Notes", @"title of the alert shown by the Support Development menu item"), message,
										  NSLocalizedString(@"Support Development", @"button that opens the sponsorship page; no ellipsis, unlike the menu item"),
										  NSLocalizedString(@"Not Now", @"button that dismisses the donation request"), nil);

	if (response == NSAlertFirstButtonReturn)
		[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:KNSponsorshipURLString]];

	//declining is deliberately not recorded: nothing to store, and nothing to ask about again
}

@end
