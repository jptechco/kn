//
//  KNSupportController.h
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

#import <Cocoa/Cocoa.h>

/*
 Asking for donations, and nothing else. The whole feature is this class: it adds one item to the
 Help menu, and choosing it explains what donations pay for and hands the sponsorship URL to the
 user's browser.

 Nothing is measured. There is no analytics, no telemetry, no "has this user donated" state, and no
 network call of any kind -- the only thing that ever reaches the network is the browser, after the
 user has clicked the button asking for it.

 To remove the feature entirely:
   1. delete this file and KNSupportController.m, and their four entries in project.pbxproj
   2. delete the #import and the -installMenuItemInMainMenu call in AppController.m
   3. delete the "Support Development" block from the tail of each of the seven Localizable.strings
   4. delete .github/FUNDING.yml and the "Support development" section of README.md

 To extend it -- an in-app donation panel is a possibility, not a promise -- replace the body of
 -showSupportOptions: below. Neither AppController, the menu code, nor MainMenu.nib needs to know.
 */

@interface KNSupportController : NSObject

+ (KNSupportController*)sharedInstance;

//Appends a separator and the "Support Development..." item to the Help menu. Called once, at launch,
//because MainMenu.nib is Interface Builder 3 format and is never re-saved to add an item to it.
//Idempotent, and does nothing at all if the Help menu cannot be identified.
- (void)installMenuItemInMainMenu;

//What the menu item does: explain, then, if the user agrees, open the sponsorship page.
- (IBAction)showSupportOptions:(id)sender;

@end
