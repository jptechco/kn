//
//  KNReleaseNotesWindowController.h
//  Kinetic Notes
//
//  "What's New": the release notes of an update that installed itself without being shown.

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
 A window showing one version's release notes -- the same page Sparkle's update window would have shown
 -- for an update that downloaded and installed itself on quit, which the user therefore never saw
 described. KNUpdateController decides when; this class only presents.

 The page is loaded without JavaScript into a non-persistent web view, so it can neither run script nor
 leave cookies or cache behind. Links on it open in the default browser rather than in the window. If
 the page cannot be loaded (most often: offline), the window says so and offers the page's address.
 */
@interface KNReleaseNotesWindowController : NSObject <NSWindowDelegate>
{
	NSWindow *window;
	id webView;			//WKWebView; typed id so this header needs no WebKit import
	NSURL *notesURL;
	BOOL showingFallback;
}

//Shows the window for `version` (e.g. @"1.8"), loading `url`. The controller keeps itself alive while
//the window is open and releases itself when it closes, so the caller need not hold on to it.
+ (void)showReleaseNotesForVersion:(NSString *)version URL:(NSURL *)url;

@end
