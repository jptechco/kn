//
//  KNReleaseNotesWindowController.m
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

#import "KNReleaseNotesWindowController.h"
#import <WebKit/WebKit.h>

#define KNNotesWindowWidth 520.0f
#define KNNotesWindowHeight 560.0f
#define KNNotesMargin 20.0f

static NSString *KNEscapedHTML(NSString *s) {
	NSMutableString *escaped = [NSMutableString stringWithString:s ? s : @""];
	[escaped replaceOccurrencesOfString:@"&" withString:@"&amp;" options:0 range:NSMakeRange(0, [escaped length])];
	[escaped replaceOccurrencesOfString:@"<" withString:@"&lt;" options:0 range:NSMakeRange(0, [escaped length])];
	[escaped replaceOccurrencesOfString:@">" withString:@"&gt;" options:0 range:NSMakeRange(0, [escaped length])];
	[escaped replaceOccurrencesOfString:@"\"" withString:@"&quot;" options:0 range:NSMakeRange(0, [escaped length])];
	return escaped;
}

@interface KNReleaseNotesWindowController () <WKNavigationDelegate>
- (id)initWithVersion:(NSString *)version URL:(NSURL *)url;
- (void)showFallback;
@end

@implementation KNReleaseNotesWindowController

+ (void)showReleaseNotesForVersion:(NSString *)version URL:(NSURL *)url {
	if (!url) return;
	//balanced by the release in -windowWillClose:
	KNReleaseNotesWindowController *controller = [[KNReleaseNotesWindowController alloc] initWithVersion:version URL:url];
	[controller->window center];
	[controller->window makeKeyAndOrderFront:nil];
}

- (id)initWithVersion:(NSString *)version URL:(NSURL *)url {
	if (!(self = [super init])) return nil;

	notesURL = [url retain];

	window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0f, 0.0f, KNNotesWindowWidth, KNNotesWindowHeight)
										 styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
										   backing:NSBackingStoreBuffered defer:NO];
	[window setReleasedWhenClosed:NO];
	[window setDelegate:self];
	[window setMinSize:NSMakeSize(360.0f, 300.0f)];
	[window setTitle:[NSString stringWithFormat:NSLocalizedString(@"What's New in Kinetic Notes %@",
		@"title of the window showing the release notes of an update that installed itself"), version ? version : @""]];

	NSView *content = [window contentView];
	NSRect bounds = [content bounds];

	//why the window has appeared at all: nobody asked for it, so say what happened
	NSTextField *intro = [NSTextField wrappingLabelWithString:[NSString stringWithFormat:
		NSLocalizedString(@"Kinetic Notes updated itself to version %@. Here is what changed.",
						  @"line above the release notes of an update that installed itself"), version ? version : @""]];
	[intro setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
	CGFloat introWidth = NSWidth(bounds) - 2.0f * KNNotesMargin;
	[intro setPreferredMaxLayoutWidth:introWidth];
	NSSize introSize = [intro fittingSize];
	[intro setFrame:NSMakeRect(KNNotesMargin, NSHeight(bounds) - KNNotesMargin + 4.0f - introSize.height, introWidth, introSize.height)];
	[intro setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
	[content addSubview:intro];

	NSButton *continueButton = [NSButton buttonWithTitle:NSLocalizedString(@"Continue", @"button that closes the release notes window")
												  target:window action:@selector(performClose:)];
	[continueButton setKeyEquivalent:@"\r"];
	[continueButton sizeToFit];
	NSRect buttonFrame = [continueButton frame];
	buttonFrame.size.width = MAX(NSWidth(buttonFrame), 90.0f);
	buttonFrame.origin = NSMakePoint(NSWidth(bounds) - KNNotesMargin - NSWidth(buttonFrame), KNNotesMargin - 6.0f);
	[continueButton setFrame:buttonFrame];
	[continueButton setAutoresizingMask:NSViewMinXMargin | NSViewMaxYMargin];
	[content addSubview:continueButton];

	WKWebViewConfiguration *configuration = [[[WKWebViewConfiguration alloc] init] autorelease];
	[configuration setWebsiteDataStore:[WKWebsiteDataStore nonPersistentDataStore]];
	[[configuration defaultWebpagePreferences] setAllowsContentJavaScript:NO];

	CGFloat webTop = NSMinY([intro frame]) - 12.0f;
	CGFloat webBottom = NSMaxY(buttonFrame) + 14.0f;
	NSRect webFrame = NSMakeRect(0.0f, webBottom, NSWidth(bounds), webTop - webBottom);

	//a hairline above and below, so the page reads as a panel inside the window
	for (NSNumber *y in @[@(webTop), @(webBottom - 1.0f)]) {
		NSBox *line = [[[NSBox alloc] initWithFrame:NSMakeRect(0.0f, [y floatValue], NSWidth(bounds), 1.0f)] autorelease];
		[line setBoxType:NSBoxSeparator];
		[line setAutoresizingMask:NSViewWidthSizable | ([y floatValue] == webTop ? NSViewMinYMargin : NSViewMaxYMargin)];
		[content addSubview:line];
	}

	WKWebView *web = [[WKWebView alloc] initWithFrame:webFrame configuration:configuration];
	[web setNavigationDelegate:self];
	[web setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
	[content addSubview:web];
	webView = web;

	[web loadRequest:[NSURLRequest requestWithURL:notesURL cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:20.0]];

	[window setDefaultButtonCell:[continueButton cell]];
	return self;
}

- (void)dealloc {
	[(WKWebView *)webView setNavigationDelegate:nil];
	[webView release];
	[window setDelegate:nil];
	[window release];
	[notesURL release];
	[super dealloc];
}

- (void)windowWillClose:(NSNotification *)notification {
	[(WKWebView *)webView stopLoading];
	[self autorelease];
}

#pragma mark WKNavigationDelegate

//the notes page loads in the window; anything it links to opens in the browser instead
- (void)webView:(WKWebView *)aWebView decidePolicyForNavigationAction:(WKNavigationAction *)action
												 decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
	if ([action navigationType] == WKNavigationTypeLinkActivated) {
		NSURL *target = [[action request] URL];
		NSString *scheme = [[target scheme] lowercaseString];
		if ([scheme isEqualToString:@"https"] || [scheme isEqualToString:@"http"] || [scheme isEqualToString:@"mailto"])
			[[NSWorkspace sharedWorkspace] openURL:target];
		decisionHandler(WKNavigationActionPolicyCancel);
		return;
	}
	decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)webView:(WKWebView *)aWebView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
	[self showFallback];
}

- (void)webView:(WKWebView *)aWebView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
	[self showFallback];
}

//a server error still "succeeds" as a navigation; a missing page should read as missing, not as a 404 page
- (void)webView:(WKWebView *)aWebView decidePolicyForNavigationResponse:(WKNavigationResponse *)response
												   decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler {
	NSURLResponse *urlResponse = [response response];
	if ([urlResponse isKindOfClass:[NSHTTPURLResponse class]] && [(NSHTTPURLResponse *)urlResponse statusCode] >= 400) {
		decisionHandler(WKNavigationResponsePolicyCancel);
		[self showFallback];
		return;
	}
	decisionHandler(WKNavigationResponsePolicyAllow);
}

- (void)showFallback {
	if (showingFallback) return;
	showingFallback = YES;

	NSString *message = NSLocalizedString(@"The release notes could not be loaded. You can read them online:",
										  @"shown in the release notes window when the page cannot be loaded, e.g. offline");
	NSString *address = KNEscapedHTML([notesURL absoluteString]);
	NSString *html = [NSString stringWithFormat:
		@"<!DOCTYPE html><html><head><meta charset=\"utf-8\"><style>:root{color-scheme:light dark}"
		@"body{font:13px/1.55 -apple-system,sans-serif;margin:0;padding:1rem 1.25rem}a{word-break:break-all}</style></head>"
		@"<body><p>%@</p><p><a href=\"%@\">%@</a></p></body></html>", KNEscapedHTML(message), address, address];
	//no base URL: the fallback is inert apart from its one link, which the policy above hands to the browser
	[(WKWebView *)webView loadHTMLString:html baseURL:nil];
}

@end
