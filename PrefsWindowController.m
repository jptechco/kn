/*Copyright (c) 2010, Zachary Schneirov. All rights reserved.
    This file is part of Notational Velocity.

    Notational Velocity is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    Notational Velocity is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with Notational Velocity.  If not, see <http://www.gnu.org/licenses/>. */


#import "PrefsWindowController.h"
#import "PTKeyComboPanel.h"
#import "PTKeyCombo.h"
#import "NotationPrefsViewController.h"
#import "ExternalEditorListController.h"
#import "NSData_transformations.h"
#import "NSString_NV.h"
#import "NSFileManager_NV.h"
#import "NSBezierPath_NV.h"
#import "NotationPrefs.h"
#import "GlobalPrefs.h"
#import "KNUpdateController.h"
#import "AppController.h"
#include <sys/stat.h>

#define SYSTEM_LIST_FONT_SIZE 12.0f

//the preference panes are only ~368pt wide, which is too narrow to display all the toolbar items on
//modern macOS (they collapse into a ">>" overflow menu, hiding panes). Keep the window at least this
//wide so all five items stay visible beside the window title; narrower panes are centered in the
//extra width. 590 is the smallest that fits in English: the overflow point was measured at 583pt
//against the longest title ("Fonts & Colors", the worst case), with a few points of margin added.
//Other languages' names are longer -- German needs about 700 -- so this is only the floor:
//-measureToolbarWidth finds the real minimum at load.
#define PREFS_MIN_CONTENT_WIDTH 590.0f

/*
 A rounded, lightly filled panel for the Updates pane, in the manner of System Settings' grouped
 forms. Flipped, so its rows are laid out top-down; it draws in -drawRect: rather than through a layer
 so its fill follows the window's light or dark appearance without being told.
 */
@interface KNPrefsCardView : NSView
@end

@implementation KNPrefsCardView

- (BOOL)isFlipped {
	return YES;
}

- (void)drawRect:(NSRect)dirtyRect {
	BOOL dark = [[[self effectiveAppearance] bestMatchFromAppearancesWithNames:
				  [NSArray arrayWithObjects:NSAppearanceNameAqua, NSAppearanceNameDarkAqua, nil]]
				 isEqualToString:NSAppearanceNameDarkAqua];
	NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect([self bounds], 0.5f, 0.5f) xRadius:10.0f yRadius:10.0f];
	[[NSColor colorWithWhite:1.0f alpha:dark ? 0.05f : 0.6f] setFill];
	[path fill];
	[[NSColor colorWithWhite:dark ? 1.0f : 0.0f alpha:dark ? 0.08f : 0.07f] setStroke];
	[path stroke];
}

@end

/*
 The title beside a preference switch. Clicking it flips the switch, as clicking a checkbox's title did,
 and it dims whenever the switch is disabled, through a binding to the switch's enabled state.
 */
@interface KNSwitchLabel : NSTextField {
	NSSwitch *toggle;	//weak: both live in the same pane for as long as it does
}
- (id)initWithTitle:(NSString *)title font:(NSFont *)font toggle:(NSSwitch *)aToggle;
- (NSSwitch *)toggle;
@end

@implementation KNSwitchLabel

- (id)initWithTitle:(NSString *)title font:(NSFont *)font toggle:(NSSwitch *)aToggle {
	if ((self = [super initWithFrame:NSZeroRect])) {
		toggle = aToggle;
		[self setStringValue:title];
		[self setFont:font];
		[self setEditable:NO];
		[self setSelectable:NO];
		[self setBordered:NO];
		[self setBezeled:NO];
		[self setDrawsBackground:NO];
		[self sizeToFit];
		[self bind:NSEnabledBinding toObject:toggle withKeyPath:@"enabled" options:nil];
	}
	return self;
}

- (void)dealloc {
	[self unbind:NSEnabledBinding];
	[super dealloc];
}

- (NSSwitch *)toggle {
	return toggle;
}

//a non-editable text field draws no differently when disabled, so the colour changes here
- (void)setEnabled:(BOOL)flag {
	[super setEnabled:flag];
	[self setTextColor:flag ? [NSColor labelColor] : [NSColor disabledControlTextColor]];
}

- (void)mouseDown:(NSEvent *)event {
	if ([toggle isEnabled]) [toggle performClick:self];
}

@end

//the Updates pane itself is flipped too, so the cards stack from the top
@interface KNFlippedView : NSView
@end

@implementation KNFlippedView
- (BOOL)isFlipped {
	return YES;
}
@end

/*
 The Appearance control on the Fonts & Colors pane: three miniature windows -- Automatic, Light and
 Dark -- after System Settings' own. The thumbnails are drawn rather than loaded, and in fixed colours,
 since each shows one appearance whatever the window's; Automatic is the light one with its right half
 dark. The selected one is ringed in the accent colour. Clicking a thumbnail or its caption selects it
 and sends the action; with focus, the arrow keys move the selection.
 */
#define KN_THUMB_WIDTH 72.0f
#define KN_THUMB_HEIGHT 46.0f
#define KN_THUMB_GAP 12.0f
#define KN_THUMB_PAD 5.0f		//room for the selection ring around a thumbnail
#define KN_CAPTION_HEIGHT 16.0f

@interface KNAppearancePicker : NSControl {
	KNAppearanceMode selectedMode;
}
- (KNAppearanceMode)selectedMode;
- (void)setSelectedMode:(KNAppearanceMode)mode;
+ (NSSize)pickerSize;
//where the thumbnails' vertical centre falls, in the picker's own (flipped) coordinates
+ (CGFloat)thumbnailCenterY;
@end

@implementation KNAppearancePicker

//left to right
static const KNAppearanceMode KNPickerModes[3] = { KNAppearanceFollowSystem, KNAppearanceForceLight, KNAppearanceForceDark };

static NSColor *KNRGB(CGFloat r, CGFloat g, CGFloat b) {
	return [NSColor colorWithSRGBRed:r / 255.0f green:g / 255.0f blue:b / 255.0f alpha:1.0f];
}

+ (NSSize)pickerSize {
	return NSMakeSize(3.0f * KN_THUMB_WIDTH + 2.0f * KN_THUMB_GAP + 2.0f * KN_THUMB_PAD,
					  KN_THUMB_PAD + KN_THUMB_HEIGHT + KN_THUMB_PAD + KN_CAPTION_HEIGHT);
}

+ (CGFloat)thumbnailCenterY {
	return KN_THUMB_PAD + KN_THUMB_HEIGHT / 2.0f;
}

- (id)initWithFrame:(NSRect)frame {
	if ((self = [super initWithFrame:frame])) selectedMode = KNAppearanceFollowSystem;
	return self;
}

- (BOOL)isFlipped {
	return YES;
}

- (NSSize)intrinsicContentSize {
	return [KNAppearancePicker pickerSize];
}

- (NSRect)thumbnailRectAtIndex:(NSUInteger)i {
	return NSMakeRect(KN_THUMB_PAD + i * (KN_THUMB_WIDTH + KN_THUMB_GAP), KN_THUMB_PAD, KN_THUMB_WIDTH, KN_THUMB_HEIGHT);
}

- (NSString *)captionAtIndex:(NSUInteger)i {
	switch (KNPickerModes[i]) {
		case KNAppearanceForceLight: return NSLocalizedString(@"Light", @"Appearance preference: always use the light appearance");
		case KNAppearanceForceDark: return NSLocalizedString(@"Dark", @"Appearance preference: always use the dark appearance");
		default: return NSLocalizedString(@"Automatic", @"Appearance preference: track the macOS light/dark setting");
	}
}

- (NSUInteger)selectedIndex {
	for (NSUInteger i = 0; i < 3; i++) if (KNPickerModes[i] == selectedMode) return i;
	return 0;
}

- (KNAppearanceMode)selectedMode {
	return selectedMode;
}

- (void)setSelectedMode:(KNAppearanceMode)mode {
	selectedMode = mode;
	[self setNeedsDisplay:YES];
}

//one miniature window: a sidebar with a few rows, traffic lights, and a content panel with a heading
//and lines of text
- (void)drawMiniatureWindowInRect:(NSRect)rect dark:(BOOL)dark {
	NSColor *chrome = dark ? KNRGB(43, 43, 43) : KNRGB(230, 230, 230);
	NSColor *panel = dark ? KNRGB(28, 28, 28) : KNRGB(255, 255, 255);
	NSColor *sidebarRow = dark ? KNRGB(85, 85, 85) : KNRGB(196, 196, 196);
	NSColor *heading = dark ? KNRGB(80, 80, 80) : KNRGB(189, 189, 189);
	NSColor *textLine = dark ? KNRGB(66, 66, 66) : KNRGB(214, 214, 214);

	[chrome setFill];
	NSRectFill(rect);

	NSColor *lights[3] = { KNRGB(255, 95, 87), KNRGB(254, 188, 46), KNRGB(40, 200, 64) };
	for (NSUInteger k = 0; k < 3; k++) {
		[lights[k] setFill];
		[[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(NSMinX(rect) + 4.0f + k * 5.5f, NSMinY(rect) + 4.0f, 4.0f, 4.0f)] fill];
	}

	[sidebarRow setFill];
	for (NSUInteger k = 0; k < 4; k++)
		NSRectFill(NSMakeRect(NSMinX(rect) + 4.0f, NSMinY(rect) + 13.0f + k * 6.0f, 11.0f, 2.5f));

	NSRect content = NSMakeRect(NSMinX(rect) + 20.0f, NSMinY(rect) + 9.0f, NSWidth(rect) - 23.0f, NSHeight(rect) - 12.0f);
	[panel setFill];
	[[NSBezierPath bezierPathWithRoundedRect:content xRadius:3.0f yRadius:3.0f] fill];

	[heading setFill];
	NSRectFill(NSMakeRect(NSMinX(content) + 5.0f, NSMinY(content) + 5.0f, 20.0f, 4.0f));
	[textLine setFill];
	for (NSUInteger k = 0; k < 3; k++)
		NSRectFill(NSMakeRect(NSMinX(content) + 5.0f, NSMinY(content) + 14.0f + k * 5.0f, NSWidth(content) - 10.0f, 1.5f));
}

- (void)drawRect:(NSRect)dirtyRect {
	NSUInteger selected = [self selectedIndex];
	NSMutableParagraphStyle *centered = [[[NSMutableParagraphStyle alloc] init] autorelease];
	[centered setAlignment:NSTextAlignmentCenter];

	for (NSUInteger i = 0; i < 3; i++) {
		NSRect thumb = [self thumbnailRectAtIndex:i];
		NSBezierPath *outline = [NSBezierPath bezierPathWithRoundedRect:thumb xRadius:5.0f yRadius:5.0f];

		[NSGraphicsContext saveGraphicsState];
		[outline addClip];
		if (KNPickerModes[i] == KNAppearanceFollowSystem) {
			[self drawMiniatureWindowInRect:thumb dark:NO];
			NSRect rightHalf = thumb;
			rightHalf.origin.x += floor(NSWidth(thumb) / 2.0f);
			rightHalf.size.width -= floor(NSWidth(thumb) / 2.0f);
			NSRectClip(rightHalf);
			[self drawMiniatureWindowInRect:thumb dark:YES];
		} else {
			[self drawMiniatureWindowInRect:thumb dark:(KNPickerModes[i] == KNAppearanceForceDark)];
		}
		[NSGraphicsContext restoreGraphicsState];

		if (i == selected) {
			NSBezierPath *ring = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(thumb, -2.5f, -2.5f) xRadius:7.0f yRadius:7.0f];
			[ring setLineWidth:3.0f];
			[[NSColor controlAccentColor] setStroke];
			[ring stroke];
		} else {
			[[NSColor separatorColor] setStroke];
			[outline setLineWidth:1.0f];
			[outline stroke];
		}

		NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
			[NSFont systemFontOfSize:[NSFont smallSystemFontSize]], NSFontAttributeName,
			(i == selected) ? [NSColor labelColor] : [NSColor secondaryLabelColor], NSForegroundColorAttributeName,
			centered, NSParagraphStyleAttributeName, nil];
		[[self captionAtIndex:i] drawInRect:NSMakeRect(NSMinX(thumb) - KN_THUMB_GAP / 2.0f, NSMaxY(thumb) + KN_THUMB_PAD + 1.0f,
													   NSWidth(thumb) + KN_THUMB_GAP, KN_CAPTION_HEIGHT) withAttributes:attributes];
	}

	if ([[self window] firstResponder] == self && [[self window] isKeyWindow]) {
		NSSetFocusRingStyle(NSFocusRingOnly);
		[[NSBezierPath bezierPathWithRoundedRect:NSInsetRect([self thumbnailRectAtIndex:selected], -2.5f, -2.5f) xRadius:7.0f yRadius:7.0f] fill];
	}
}

- (void)selectIndex:(NSUInteger)i {
	if (KNPickerModes[i] == selectedMode) return;
	[self setSelectedMode:KNPickerModes[i]];
	[self sendAction:[self action] to:[self target]];
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event {
	return YES;
}

- (void)mouseDown:(NSEvent *)event {
	NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
	for (NSUInteger i = 0; i < 3; i++) {
		NSRect hit = [self thumbnailRectAtIndex:i];
		hit.size.height += KN_THUMB_PAD + KN_CAPTION_HEIGHT;	//the caption too
		if (NSPointInRect(point, NSInsetRect(hit, -KN_THUMB_PAD, -KN_THUMB_PAD))) {
			[self selectIndex:i];
			return;
		}
	}
}

- (BOOL)acceptsFirstResponder {
	return YES;
}

- (BOOL)becomeFirstResponder {
	[self setNeedsDisplay:YES];
	return YES;
}

- (BOOL)resignFirstResponder {
	[self setNeedsDisplay:YES];
	return YES;
}

- (void)keyDown:(NSEvent *)event {
	NSString *chars = [event charactersIgnoringModifiers];
	unichar c = [chars length] ? [chars characterAtIndex:0] : 0;
	NSUInteger i = [self selectedIndex];
	if (c == NSLeftArrowFunctionKey && i > 0) [self selectIndex:i - 1];
	else if (c == NSRightArrowFunctionKey && i < 2) [self selectIndex:i + 1];
	else [super keyDown:event];
}

- (BOOL)isAccessibilityElement {
	return YES;
}

- (NSAccessibilityRole)accessibilityRole {
	return NSAccessibilityRadioGroupRole;
}

- (NSString *)accessibilityLabel {
	return NSLocalizedString(@"Appearance", @"Fonts & Colors preference: label for the light/dark appearance picker");
}

- (id)accessibilityValue {
	return [self captionAtIndex:[self selectedIndex]];
}

@end

@implementation PrefsWindowController

- (id)init {
    if ([super init]) {
		prefsController = [GlobalPrefs defaultPrefs];
		fontPanelWasOpen = NO;
		
		[prefsController registerWithTarget:self forChangesInSettings:
		 @selector(resolveNoteBodyFontFromNotationPrefsFromSender:), 
		 @selector(setCheckSpellingAsYouType:sender:), 
		 @selector(setConfirmNoteDeletion:sender:),
		 @selector(setSideBySideTitleBar:sender:),
		 @selector(setHorizontalLayout:sender:), nil];
    }
    return self;
}

- (void)showWindow:(id)sender {
	if (!window) {
		if (![NSBundle loadNibNamed:@"Preferences" owner:self])  {
			NSLog(@"Failed to load Preferences.nib");
			return;
		}
	}
	
	if (![window isVisible])
		[window center];
	
	[window makeKeyAndOrderFront:self];
}

- (void)windowWillClose:(NSNotification *)aNotification {
	[prefsController performSelector:@selector(synchronize) withObject:nil afterDelay:0.0];
	
	[[NSFontPanel sharedFontPanel] close];
}
- (void)windowDidResignMain:(NSNotification *)aNotification {
	//hide the font panel--don't want to confuse people into thinking it will affect some other part of the program
	fontPanelWasOpen = [[NSFontPanel sharedFontPanel] isVisible];
	[[NSFontPanel sharedFontPanel] orderOut:nil];
}
- (void)windowDidBecomeMain:(NSNotification *)aNotification {
	if (fontPanelWasOpen) {
		[self changeBodyFont:self];
	}
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
	NSLog(@"I need an update: %@", [menu description]);
}

- (IBAction)setAppShortcut:(id)sender {
	[[PTKeyComboPanel sharedPanel] showSheetForHotkey:[prefsController appActivationHotKey] forWindow:window modalDelegate:self];
}

- (void)keyComboPanelEnded:(PTKeyComboPanel*)panel {
	PTKeyCombo *oldKeyCombo = [[prefsController appActivationKeyCombo] retain];
	[prefsController setAppActivationKeyCombo:[panel keyCombo] sender:self];
	
	[appShortcutField setStringValue:[[prefsController appActivationKeyCombo] description]];
		
	if (![prefsController registerAppActivationKeystrokeWithTarget:[NSApp delegate] selector:@selector(toggleNVActivation:)]) {
		[prefsController setAppActivationKeyCombo:oldKeyCombo sender:self];
		NSLog(@"reverting to old (hopefully working key combo");
	}
	
	[oldKeyCombo release];
}

- (IBAction)changeBodyFont:(id)sender {
	[[NSFontManager sharedFontManager] setSelectedFont:[prefsController noteBodyFont] isMultiple:NO];
    [[NSFontManager sharedFontManager] orderFrontFontPanel:self];
}

- (void)changeFont:(id)sender {
	NSFontManager *fontMan = [NSFontManager sharedFontManager];
	NSFont *panelFont = [fontMan convertFont:[fontMan selectedFont]];
	
	if (/*![fontMan fontNamed:[panelFont fontName] hasTraits:NSUnboldFontMask | NSUnitalicFontMask]*/
	([fontMan traitsOfFont:panelFont] & NSItalicFontMask) == NSItalicFontMask ||
	([fontMan traitsOfFont:panelFont] & NSBoldFontMask) == NSBoldFontMask) {
		//revert the font--using a bold or italic variant as the default could cause some notes to lose styles
	//	NSLog(@"traits: %u", [fontMan traitsOfFont:panelFont]); 
		
		[self performSelector:@selector(changeBodyFont:) withObject:sender afterDelay:0.0];
		NSBeep();
	} else {
		[prefsController setNoteBodyFont:panelFont sender:self];
	
		[self previewNoteBodyFont];
	}
}

- (NSUInteger)validModesForFontPanel:(NSFontPanel *)fontPanel {
	
	return NSFontPanelSizeModeMask | NSFontPanelCollectionModeMask;
}

- (void)previewNoteBodyFont {

	if (!centerStyle) {
		centerStyle = [[NSMutableParagraphStyle alloc] init];
		[centerStyle setAlignment:NSCenterTextAlignment];
	}

	NSFont *font = [prefsController noteBodyFont];
	//use the user's foreground text color (which falls back to the semantic [NSColor textColor] and so
	//adapts to Dark Mode) rather than a hard-coded black that stayed invisible on a dark pane
	NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:font ? font : [NSFont systemFontOfSize:12.0],
		NSFontAttributeName, [prefsController foregroundTextColor], NSForegroundColorAttributeName, centerStyle, NSParagraphStyleAttributeName, nil];

	NSString *fontNameAndSize = font ? [NSString stringWithFormat:@"%@ %g", [font fontName], [font pointSize]] : @"Unknown";
	NSAttributedString *attributedString = [[NSAttributedString alloc] initWithString:fontNameAndSize attributes:attributes];
	
	[[bodyTextFontField cell] setAttributedStringValue:attributedString];
    [bodyTextFontField updateCell:[bodyTextFontField cell]];
	
	[attributedString autorelease];
	
}

- (IBAction)changedBackgroundTextColorWell:(id)sender {
	[prefsController setBackgroundTextColor:[backgroundColorWell color] sender:self];
}
- (IBAction)changedForegroundTextColorWell:(id)sender {
	[prefsController setForegroundTextColor:[foregroundColorWell color] sender:self];
}
- (IBAction)changedSearchHighlightColorWell:(id)sender {
	[prefsController setSearchTermHighlightColor:[searchHighlightColorWell color] sender:self];
}
- (IBAction)changedHighlightSearchTerms:(id)sender {
	[prefsController setShouldHighlightSearchTerms:[highlightSearchTermsButton state] sender:self];
}
- (IBAction)changedStyledTextBehavior:(id)sender {
    [prefsController setPastePreservesStyle:[styledTextButton state] sender:self];
}
- (IBAction)changedAutoSuggestLinks:(id)sender {
    [prefsController setLinksAutoSuggested:[autoSuggestLinksButton state] sender:self];
}

- (IBAction)changedMakeURLsClickable:(id)sender {
	[prefsController setMakeURLsClickable:[makeURLsClickable state] sender:self];
}

- (IBAction)changedNoteDeletion:(id)sender {
	[prefsController setConfirmNoteDeletion:[confirmDeletionButton state] sender:self];
}

- (IBAction)changedNotesFolderLocation:(id)sender {
    NSLog(@"Changed notes folder menu");
}

- (IBAction)changedQuitBehavior:(id)sender {
    [prefsController setQuitWhenClosingWindow:[quitWhenClosingButton state] sender:self];
}

- (IBAction)changedTitleBarLayout:(id)sender {
	[prefsController setSideBySideTitleBar:[sideBySideTitleBarButton state] sender:self];
}

- (IBAction)changedShowsLineNumbers:(id)sender {
	[prefsController setShowsLineNumbers:[showsLineNumbersButton state] sender:self];
}

- (IBAction)changedShowsWordCount:(id)sender {
	[prefsController setShowsWordCount:[showsWordCountButton state] sender:self];
}

- (IBAction)changedAppearanceMode:(id)sender {
	[prefsController setAppearanceMode:[appearancePicker selectedMode] sender:self];
}

//The View menu's layout switch does more than flip the preference -- it turns the split view and keeps
//each layout's divider position -- so the popup goes through that same action rather than the setter.
- (IBAction)changedLayout:(id)sender {
	BOOL wantsHorizontal = ([layoutButton indexOfSelectedItem] == 0);
	if (wantsHorizontal != [prefsController horizontalLayout])
		[(AppController *)[NSApp delegate] switchViewLayout:self];
}

- (IBAction)openProjectPage:(id)sender {
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:KNProjectURLString]];
}

- (void)refreshLastChecked {
	NSDate *date = [[KNUpdateController sharedInstance] lastUpdateCheckDate];
	if (date) {
		NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
		[formatter setDateStyle:NSDateFormatterMediumStyle];
		[formatter setTimeStyle:NSDateFormatterShortStyle];
		[lastCheckedField setStringValue:[formatter stringFromDate:date]];
	} else {
		[lastCheckedField setStringValue:NSLocalizedString(@"Never", @"Updates preference: Last checked, before any check has run")];
	}
}

- (void)updateCheckDidFinish:(NSNotification *)aNotification {
	[self refreshLastChecked];
}

- (IBAction)checkForUpdatesNow:(id)sender {
	[[KNUpdateController sharedInstance] checkForUpdates:sender];
}

- (IBAction)changedAutomaticallyChecksForUpdates:(id)sender {
	BOOL on = ([automaticallyChecksButton state] == NSControlStateValueOn);
	[[KNUpdateController sharedInstance] setAutomaticallyChecksForUpdates:on];

	//Sparkle only auto-downloads if it is also auto-checking, so automatic downloads follow this toggle:
	//disable it when checks are off, and clear it so the UI never claims a state Sparkle won't honour
	[automaticallyDownloadsButton setEnabled:on];
	if (!on) {
		[automaticallyDownloadsButton setState:NSControlStateValueOff];
		[[KNUpdateController sharedInstance] setAutomaticallyDownloadsUpdates:NO];
	}
}

- (IBAction)changedAutomaticallyDownloadsUpdates:(id)sender {
	[[KNUpdateController sharedInstance]
		setAutomaticallyDownloadsUpdates:([automaticallyDownloadsButton state] == NSControlStateValueOn)];
}

- (IBAction)changedSpellChecking:(id)sender {
    [prefsController setCheckSpellingAsYouType:[checkSpellingButton state] sender:self];
}


- (IBAction)changedTabBehavior:(id)sender {
    if (sender != self)
	[self performSelector:@selector(changedTabBehavior:) withObject:self afterDelay:0.0];
    else
	[prefsController setTabIndenting:[[tabKeyRadioMatrix cellAtRow:0 column:0] state] sender:self];
}

- (IBAction)changedExternalEditorsMenu:(id)sender {
	//not currently called as an action in practice
	[self _selectDefaultExternalEditor];
}

- (void)_selectDefaultExternalEditor {
	ExternalEditor *ed = [[ExternalEditorListController sharedInstance] defaultExternalEditor];
	NSInteger idx = ed ? [externalEditorMenuButton indexOfItemWithRepresentedObject:ed] : 0;
	if (idx > -1) {
		[externalEditorMenuButton selectItemAtIndex:idx];
	}
}

- (IBAction)changedTableText:(id)sender {
	if (sender == tableTextMenuButton) {
		if ([tableTextSizeField selectedTag] != 3) [tableTextSizeField setFloatValue:[prefsController tableFontSize]];
		[self performSelector:@selector(changedTableText:) withObject:nil afterDelay:0.0];
	} else {
		[window makeFirstResponder:window];
		float newFontSize = 0.0;
		switch ([tableTextMenuButton selectedTag]) {
			case 1:
				newFontSize = [NSFont smallSystemFontSize];
				break;
			case 2:
				newFontSize = /*[NSFont systemFontSize]*/ SYSTEM_LIST_FONT_SIZE;
				break;
			case 3:
				newFontSize = [tableTextSizeField floatValue];
		}
		[tableTextSizeField setHidden:([tableTextMenuButton selectedTag] != 3)];
		if (![tableTextSizeField isHidden])
			[tableTextSizeField selectText:sender];
		
		[prefsController setTableFontSize:newFontSize sender:self];
	}	
}

- (IBAction)changedTitleCompletion:(id)sender {
    [prefsController setAutoCompleteSearches:[completeNoteTitlesButton state] sender:self];
}

- (IBAction)changedSoftTabs:(id)sender {
	[prefsController setSoftTabs:[softTabsButton state] sender:self];
}

- (void)settingChangedForSelectorString:(NSString*)selectorString {
    if ([selectorString isEqualToString:SEL_STR(resolveNoteBodyFontFromNotationPrefsFromSender:)]) {
		[self previewNoteBodyFont];
	} else if ([selectorString isEqualToString:SEL_STR(setCheckSpellingAsYouType:sender:)]) {
		[checkSpellingButton setState:[prefsController checkSpellingAsYouType]];
	} else if ([selectorString isEqualToString:SEL_STR(setConfirmNoteDeletion:sender:)]) {
		[confirmDeletionButton setState:[prefsController confirmNoteDeletion]];
	} else if ([selectorString isEqualToString:SEL_STR(setSideBySideTitleBar:sender:)]) {
		[sideBySideTitleBarButton setState:[prefsController sideBySideTitleBar]];
	} else if ([selectorString isEqualToString:SEL_STR(setHorizontalLayout:sender:)]) {
		[layoutButton selectItemAtIndex:[prefsController horizontalLayout] ? 0 : 1];
	}
}

- (NSMenu*)directorySelectionMenu {
    NSMenu *theMenu = [[[NSMenu alloc] initWithTitle:@"Note Directory Menu"] autorelease];
    
    NSString *directoryPath = [prefsController pathForDefaultDirectoryIsStale:NULL];
    NSString *name = [prefsController displayNameForDefaultDirectory];
    if (!name)
		name = NSLocalizedString(@"<Directory unknown>", nil);
	
	NSImage *iconImage = [directoryPath length] ? [NSImage smallIconForFileAtPath:directoryPath] : nil;
	
    NSMenuItem *theMenuItem = [[[NSMenuItem alloc] initWithTitle:name action:nil keyEquivalent:@""] autorelease];
    
    if (iconImage)
		[theMenuItem setImage:iconImage];
    
    [theMenu addItem:theMenuItem];
    
    [theMenu addItem:[NSMenuItem separatorItem]];
    
    theMenuItem = [[[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Other...", @"title of menu item for selecting a different notes folder")
											  action:@selector(changeDefaultDirectory) keyEquivalent:@""] autorelease];
    [theMenuItem setTarget:self];
    [theMenu addItem:theMenuItem];
    
    return theMenu;
}

//Two paths name the same directory when they name the same object on disk, which a string comparison
//would miss across a symlink or a differently-spelled but equivalent path.
static BOOL KNPathsAreSameDirectory(NSString *one, NSString *two) {
	struct stat a, b;

	if (![one length] || ![two length]) return NO;
	if (stat([one fileSystemRepresentation], &a) != 0) return NO;
	if (stat([two fileSystemRepresentation], &b) != 0) return NO;

	return a.st_dev == b.st_dev && a.st_ino == b.st_ino;
}

- (void)changeDefaultDirectory {
	NSString *directoryPath = [self newNotesDirectoryFromOpenPanel];

	if (directoryPath) {
		
		//make sure we're not choosing the same folder as what we started with, because:
		//-[NotationController initWithBookmarkData:] might attempt to initialize journaling, which will already be in use
		NSString *currentPath = [prefsController pathForDefaultDirectoryIsStale:NULL];
		if (!currentPath || !KNPathsAreSameDirectory(currentPath, directoryPath)) {
			
			NSData *bookmark = [NSData bookmarkDataForPath:directoryPath];
			if (bookmark) {
				[prefsController setBookmarkDataForDefaultDirectory:bookmark sender:self];
				
				//check for potential synchronization problems; (e.g., simplenote w/ dropbox or writeroom):
				[[prefsController notationPrefs] checkForKnownRedundantSyncConduitsAtPath:directoryPath];
			}
		} else {
			NSLog(@"This folder is already chosen!");
		}
		
	}

	[folderLocationsMenuButton setMenu:[self directorySelectionMenu]];

	if ([folderLocationsMenuButton numberOfItems] > 0)
		[folderLocationsMenuButton selectItemAtIndex:0];
}

- (NSString*)newNotesDirectoryFromOpenPanel {
    NSString *startingDirectory = [prefsController pathForDefaultDirectoryIsStale:NULL];
    
    NSOpenPanel *openPanel = [NSOpenPanel openPanel];
    [openPanel setCanCreateDirectories:YES];
    [openPanel setCanChooseFiles:NO];
    [openPanel setCanChooseDirectories:YES];
    [openPanel setResolvesAliases:YES];
    [openPanel setAllowsMultipleSelection:NO];
    [openPanel setTreatsFilePackagesAsDirectories:NO];
    [openPanel setTitle:NSLocalizedString(@"Select a folder",@"title of open panel for selecting a notes folder")];
    [openPanel setPrompt:NSLocalizedString(@"Select", @"title of open panel button to select a folder")];
    [openPanel setMessage:NSLocalizedString(@"Select the folder that Notational Velocity should use for reading and storing notes.",nil)];
    
    if ([openPanel runModalForDirectory:startingDirectory file:@"Notational Data" types:nil] == NSModalResponseOK)
		return [[[openPanel filename] copy] autorelease];
    
    return nil;
}

- (NotationPrefsViewController*)notationPrefsViewController {
	if (!notationPrefsViewController) {
		notationPrefsViewController = [[NotationPrefsViewController alloc] init];
	}
	return notationPrefsViewController;
}

- (NSView*)databaseView {
    if (![notationPrefsView subviews] || ![[notationPrefsView subviews] count])
		[notationPrefsView addSubview:[[self notationPrefsViewController] view]];
	
    return databaseView;
}

//Every pane's toolbar icon is an SF Symbol (available on the 13.0 deployment target), so all five
//share one modern, monochrome style that adapts to Light/Dark Mode. This replaces the old per-pane
//.tiff bitmaps, whose shaded early-2010s look no longer matched. The .tiff files stay in the project
//but are no longer loaded here.
static NSString *KNPaneSymbolName(NSString *paneIdentifier) {
	if ([paneIdentifier isEqualToString:@"General"])        return @"gearshape";
	if ([paneIdentifier isEqualToString:@"Notes"])          return @"tray.full";
	if ([paneIdentifier isEqualToString:@"Editing"])        return @"square.and.pencil";
	if ([paneIdentifier isEqualToString:@"Fonts & Colors"]) return @"textformat";
	if ([paneIdentifier isEqualToString:@"Updates"])        return @"arrow.triangle.2.circlepath";
	return nil;
}

- (void)addToolbarItemWithName:(NSString*)name {
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:name];

	NSString *localizedTitle = [[NSBundle mainBundle] localizedStringForKey:name value:@"" table:nil];
    [item setPaletteLabel:localizedTitle];
    [item setLabel:localizedTitle];
    //[item setToolTip:@"General settings: appearance and behavior"];
	NSString *symbolName = KNPaneSymbolName(name);
	NSImage *icon = symbolName ? [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:localizedTitle] : nil;
	if (!icon)  //fall back to the legacy .tiff if a symbol is somehow unavailable
		icon = [[[NSImage alloc] initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:name ofType:@"tiff"]] autorelease];
    [item setImage:icon];
    [item setTarget:self];
    [item setAction:@selector(switchViews:)];
    [items setObject:item forKey:name];
    [item release];
}

/*
 Some pane controls are built here rather than in Preferences.nib, which is Interface Builder 3
 format in seven localizations and is never re-saved. This has to happen before -switchViews: runs at
 the end of -awakeFromNib: that method sizes the window from [prefsView frame], so the pane must have
 grown by then, and it reassigns the pane's origin and autoresizing mask afterwards.

 -liftControlsInPane:above:by: does the shared geometry. The pane's coordinates are un-flipped, with
 y = 0 at the bottom, so making it taller adds the space at the top; moving the controls above some
 line up into that space opens a gap at the line instead, which is where the caller puts its new
 controls. Everything is measured off the pane rather than written down, because the compiled nib that
 actually ships does not match designable.nib's frames, and the frames vary by localization.
 */

//the pitch the panes' checkbox rows are spaced on
#define PREFS_ROW_PITCH 25.0f

- (void)liftControlsInPane:(NSView *)pane above:(CGFloat)y by:(CGFloat)delta {

	//-setFrame: would move the controls on its own, because they are pinned to the pane's top and
	//autoresizing moves them -- but only for as long as every one of them keeps that mask, and it would
	//move all of them. Suspend autoresizing and move exactly the ones above the line here, so the
	//result does not depend on masks set in a nib that cannot be opened.
	BOOL wasAutoresizing = [pane autoresizesSubviews];
	[pane setAutoresizesSubviews:NO];

	NSRect paneFrame = [pane frame];
	paneFrame.size.height += delta;
	[pane setFrame:paneFrame];

	for (NSView *subview in [pane subviews]) {
		if (NSMinY([subview frame]) >= y) {
			NSPoint origin = [subview frame].origin;
			origin.y += delta;
			[subview setFrameOrigin:origin];
		}
	}

	[pane setAutoresizesSubviews:wasAutoresizing];
}

//the pane's lowest control, which gives both the margin a new bottom row should sit on and the inset
//the pane's controls are aligned to
- (NSView *)lowestControlInPane:(NSView *)pane {
	NSView *lowest = nil;
	for (NSView *subview in [pane subviews]) {
		if (!lowest || NSMinY([subview frame]) < NSMinY([lowest frame])) lowest = subview;
	}
	return lowest;
}

//a checkbox for a pane row: its title measured, but the row's own height kept, so it lines up with the
//nib's checkboxes rather than sitting a point or two off their baseline
- (NSButton *)newCheckboxWithTitle:(NSString *)title action:(SEL)action inRow:(NSRect)row likeControl:(NSView *)sibling {
	NSButton *checkbox = [[NSButton alloc] initWithFrame:row];
	[checkbox setButtonType:NSButtonTypeSwitch];
	[checkbox setTitle:title];
	[checkbox setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
	[checkbox setTarget:self];
	[checkbox setAction:action];
	[checkbox sizeToFit];
	[checkbox setFrame:NSMakeRect(NSMinX(row), NSMinY(row), NSWidth([checkbox frame]), NSHeight(row))];
	//same mask as the row it was measured from, so it travels with the group if the pane resizes
	[checkbox setAutoresizingMask:[sibling autoresizingMask]];
	return checkbox;
}

//widen `pane` if `control` (already placed in it) extends past its right edge, keeping `leftInset` on
//the left. -switchViews: centers panes narrower than the window, so a wider pane costs nothing but a
//wider Preferences window in the languages that need it.
- (void)widenPane:(NSView *)pane toFitControl:(NSView *)control leftInset:(CGFloat)leftInset {
	CGFloat needed = NSMaxX([control frame]) + leftInset;
	NSRect paneFrame = [pane frame];
	if (needed > paneFrame.size.width) {
		paneFrame.size.width = needed;
		[pane setFrame:paneFrame];
	}
}

//The search-field checkbox heads the General pane's group of checkboxes, above "Auto-select notes by
//title": the controls above that checkbox move up a row to make room, and the rest stay where they are.
- (void)addTitleBarLayoutCheckbox {

	if (sideBySideTitleBarButton || !generalView || !completeNoteTitlesButton) return;

	NSRect anchor = [completeNoteTitlesButton frame];
	[self liftControlsInPane:generalView above:NSMaxY(anchor) by:PREFS_ROW_PITCH];

	sideBySideTitleBarButton = [self newCheckboxWithTitle:NSLocalizedString(@"Show the search field beside the window title",
																			@"General preference: put the search field on the title's row rather than beneath it")
												   action:@selector(changedTitleBarLayout:)
													inRow:NSOffsetRect(anchor, 0.0f, PREFS_ROW_PITCH)
											  likeControl:completeNoteTitlesButton];

	//the title is longer in some languages than the pane is wide; widen rather than truncate
	[self widenPane:generalView toFitControl:sideBySideTitleBarButton leftInset:NSMinX(anchor)];

	[generalView addSubview:sideBySideTitleBarButton];
}

//a right-aligned, non-editable label for a pane's labels' column
- (NSTextField *)newColumnLabelWithString:(NSString *)string {
	NSTextField *label = [[NSTextField alloc] initWithFrame:NSZeroRect];
	[label setStringValue:string];
	[label setAlignment:NSTextAlignmentRight];
	[label setEditable:NO];
	[label setSelectable:NO];
	[label setBordered:NO];
	[label setBezeled:NO];
	[label setDrawsBackground:NO];
	[label setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
	[label sizeToFit];
	return label;
}

/*
 Layout -- Horizontal or Vertical, the same switch as the View menu's -- goes directly under List Text
 Size. That row and everything above it move up by one row's pitch, and the new row takes the space
 that opens, its popup and label in exactly the frames List Text Size's had.

 The row is found by membership rather than by a cutoff, because its label's frame varies by language:
 English's is one line tall and centred on the popup, but German's is two lines tall with its text at
 the top, so it hangs well below the popup's centre. The pitch is measured between controls only --
 popups, fields and buttons -- for the same reason.
 */
- (void)addLayoutControl {

	if (layoutButton || !generalView || !tableTextMenuButton) return;

	NSRect sizeRow = [tableTextMenuButton frame];
	CGFloat sizeCenter = NSMidY(sizeRow);

	//List Text Size's label: a non-editable field ending left of the popup whose frame spans the popup's
	//centre. Any such field is on the row; so is anything else spanning that centre.
	NSTextField *sizeLabel = nil;
	NSMutableArray *rowAndAbove = [NSMutableArray array];
	CGFloat nextCenter = -CGFLOAT_MAX;
	for (NSView *subview in [generalView subviews]) {
		NSRect f = [subview frame];
		BOOL isLabel = [subview isKindOfClass:[NSTextField class]] && ![(NSTextField *)subview isEditable];
		BOOL onRow = NSMinY(f) <= sizeCenter && NSMaxY(f) >= sizeCenter;
		if (onRow && isLabel && NSMaxX(f) <= NSMinX(sizeRow) + 2.0f) sizeLabel = (NSTextField *)subview;
		if (onRow || NSMinY(f) > sizeCenter) {
			[rowAndAbove addObject:subview];
		} else if (!isLabel && NSMidY(f) > nextCenter) {
			nextCenter = NSMidY(f);
		}
	}
	CGFloat pitch = (nextCenter == -CGFLOAT_MAX) ? 40.0f : sizeCenter - nextCenter;
	NSRect sizeLabelFrame = sizeLabel ? [sizeLabel frame] : NSZeroRect;

	//as -liftControlsInPane:above:by:, but moving the row by membership
	BOOL wasAutoresizing = [generalView autoresizesSubviews];
	[generalView setAutoresizesSubviews:NO];
	NSRect paneFrame = [generalView frame];
	paneFrame.size.height += pitch;
	[generalView setFrame:paneFrame];
	for (NSView *subview in rowAndAbove) {
		NSPoint origin = [subview frame].origin;
		origin.y += pitch;
		[subview setFrameOrigin:origin];
	}
	[generalView setAutoresizesSubviews:wasAutoresizing];

	layoutButton = [[NSPopUpButton alloc] initWithFrame:sizeRow pullsDown:NO];
	[layoutButton addItemWithTitle:NSLocalizedString(@"Horizontal", @"General preference: Layout popup, note list beside the note")];
	[layoutButton addItemWithTitle:NSLocalizedString(@"Vertical", @"General preference: Layout popup, note list above the note")];
	[layoutButton setFont:[tableTextMenuButton font]];
	[layoutButton setTarget:self];
	[layoutButton setAction:@selector(changedLayout:)];
	[layoutButton sizeToFit];
	NSRect popFrame = sizeRow;
	popFrame.size.width = MAX(NSWidth([layoutButton frame]), NSWidth(sizeRow));
	[layoutButton setFrame:popFrame];
	[layoutButton setAutoresizingMask:[tableTextMenuButton autoresizingMask]];

	layoutLabel = [self newColumnLabelWithString:NSLocalizedString(@"Layout:", @"General preference: label for the horizontal/vertical layout popup")];
	NSRect labelFrame = [layoutLabel frame];
	if (sizeLabel) {
		//List Text Size's label's own frame, so the text sits on the popup the same way in every language;
		//widened leftwards only if this title needs more room
		[layoutLabel setFont:[sizeLabel font]];
		[layoutLabel setAlignment:[sizeLabel alignment]];
		[layoutLabel sizeToFit];
		CGFloat needed = NSWidth([layoutLabel frame]);
		labelFrame = sizeLabelFrame;
		if (needed > NSWidth(labelFrame)) {
			labelFrame.origin.x = MAX(0.0f, NSMaxX(labelFrame) - needed);
			labelFrame.size.width = NSMaxX(sizeLabelFrame) - NSMinX(labelFrame);
		}
		[layoutLabel setAutoresizingMask:[sizeLabel autoresizingMask]];
	} else {
		labelFrame.origin = NSMakePoint(MAX(0.0f, NSMinX(sizeRow) - 2.0f - NSWidth(labelFrame)), floor(sizeCenter - NSHeight(labelFrame) / 2.0f));
		[layoutLabel setAutoresizingMask:[tableTextMenuButton autoresizingMask]];
	}
	[layoutLabel setFrame:labelFrame];

	[self widenPane:generalView toFitControl:layoutButton leftInset:NSMinX(labelFrame)];

	[generalView addSubview:layoutLabel];
	[generalView addSubview:layoutButton];
}

/*
 The General and Editing panes' toggles are switches rather than checkboxes. Their nib cannot be
 re-saved, so each checkbox is swapped at load for its title, left where the checkbox stood, and an
 NSSwitch to the right of it; -alignSwitchesInPane: then lines a pane's switches up in one column past
 its longest title. The switch takes over the checkbox's target, action, state and autoresizing, and its
 ivar.
 */
+ (NSSwitch *)switchReplacingCheckbox:(NSButton *)checkbox {
	//the title is a KNSwitchLabel, which dims with the switch and flips it when clicked

	NSView *pane = [checkbox superview];
	NSRect row = [checkbox frame];

	NSSwitch *toggle = [[[NSSwitch alloc] initWithFrame:NSZeroRect] autorelease];
	[toggle setControlSize:NSControlSizeMini];
	[pane addSubview:toggle];	//before measuring; see -addRowToCard:…
	[toggle setFrameSize:[toggle intrinsicContentSize]];
	[toggle setFrameOrigin:NSMakePoint(0.0f, floor(NSMidY(row) - NSHeight([toggle frame]) / 2.0f))];
	[toggle setTarget:[checkbox target]];
	[toggle setAction:[checkbox action]];
	[toggle setState:[checkbox state]];
	[toggle setEnabled:[checkbox isEnabled]];
	[toggle setAutoresizingMask:[checkbox autoresizingMask]];

	KNSwitchLabel *label = [[[KNSwitchLabel alloc] initWithTitle:[checkbox title] font:[checkbox font] toggle:toggle] autorelease];
	[label setFrameOrigin:NSMakePoint(NSMinX(row), floor(NSMidY(row) - NSHeight([label frame]) / 2.0f))];
	[label setAutoresizingMask:[checkbox autoresizingMask]];
	[toggle setFrameOrigin:NSMakePoint(NSMaxX([label frame]) + 8.0f, NSMinY([toggle frame]))];

	[pane addSubview:label];
	[checkbox removeFromSuperview];
	return toggle;
}

//one column for all of a view's switches, 8pt past the end of its longest title
+ (void)alignSwitchesInView:(NSView *)view {
	CGFloat column = 0.0f;
	for (NSView *subview in [view subviews]) {
		if ([subview isKindOfClass:[KNSwitchLabel class]])
			column = MAX(column, NSMaxX([subview frame]) + 8.0f);
	}
	for (NSView *subview in [view subviews]) {
		if ([subview isKindOfClass:[NSSwitch class]])
			[subview setFrameOrigin:NSMakePoint(column, NSMinY([subview frame]))];
	}
}

//aligned, then the pane widened if the column runs past its right edge
- (void)alignSwitchesInPane:(NSView *)pane {
	[PrefsWindowController alignSwitchesInView:pane];
	CGFloat leftInset = CGFLOAT_MAX;
	for (NSView *subview in [pane subviews]) leftInset = MIN(leftInset, NSMinX([subview frame]));
	for (NSView *subview in [pane subviews]) {
		if ([subview isKindOfClass:[NSSwitch class]]) [self widenPane:pane toFitControl:subview leftInset:leftInset];
	}
}

/*
 Search Highlight differs: its checkbox sits in the labels' column, its title doubling as the row's
 label, with the highlight colour's well beside it. Its title stays a right-aligned label there, the
 well keeps its place in the controls' column alongside the other two, and the switch follows it.
 */
- (void)convertSearchHighlightCheckbox {
	if (![highlightSearchTermsButton isKindOfClass:[NSButton class]] || !searchHighlightColorWell) return;

	NSRect row = [highlightSearchTermsButton frame];
	NSSwitch *toggle = [PrefsWindowController switchReplacingCheckbox:highlightSearchTermsButton];
	highlightSearchTermsButton = toggle;
	KNSwitchLabel *label = nil;
	for (NSView *subview in [fontsColorsView subviews]) {
		if ([subview isKindOfClass:[KNSwitchLabel class]] && [(KNSwitchLabel *)subview toggle] == toggle) label = (KNSwitchLabel *)subview;
	}

	NSRect wellFrame = [searchHighlightColorWell frame];
	CGFloat center = NSMidY(wellFrame);
	[label setFrameOrigin:NSMakePoint(NSMaxX(row) - NSWidth([label frame]), floor(center - NSHeight([label frame]) / 2.0f))];
	[toggle setFrameOrigin:NSMakePoint(NSMaxX(wellFrame) + 6.0f, floor(center - NSHeight([toggle frame]) / 2.0f))];
}

- (void)convertCheckboxesToSwitches {
	if (!generalView || [completeNoteTitlesButton isKindOfClass:[NSSwitch class]]) return;

	completeNoteTitlesButton = [PrefsWindowController switchReplacingCheckbox:completeNoteTitlesButton];
	confirmDeletionButton = [PrefsWindowController switchReplacingCheckbox:confirmDeletionButton];
	quitWhenClosingButton = [PrefsWindowController switchReplacingCheckbox:quitWhenClosingButton];

	styledTextButton = [PrefsWindowController switchReplacingCheckbox:styledTextButton];
	checkSpellingButton = [PrefsWindowController switchReplacingCheckbox:checkSpellingButton];
	softTabsButton = [PrefsWindowController switchReplacingCheckbox:softTabsButton];
	makeURLsClickable = [PrefsWindowController switchReplacingCheckbox:makeURLsClickable];
	autoSuggestLinksButton = [PrefsWindowController switchReplacingCheckbox:autoSuggestLinksButton];

	//these three were built in code and are owned here, unlike the nib's
	id *owned[] = { &sideBySideTitleBarButton, &showsLineNumbersButton, &showsWordCountButton };
	for (NSUInteger i = 0; i < sizeof(owned) / sizeof(owned[0]); i++) {
		NSButton *checkbox = *owned[i];
		if (!checkbox) continue;
		*owned[i] = [[PrefsWindowController switchReplacingCheckbox:checkbox] retain];
		[checkbox release];
	}

	[self alignSwitchesInPane:generalView];
	[self alignSwitchesInPane:editingView];
	[self convertSearchHighlightCheckbox];
}

/*
 The Editing pane gains a Display group at its foot -- "Show line numbers" and "Show word count" --
 laid out like the pane's Links group above it: a right-aligned label in the labels' column, the
 checkboxes in the controls' column, and a little more space between the groups than within one.
 */
- (void)addDisplayCheckboxes {

	if (showsLineNumbersButton || !editingView) return;

	NSView *lowest = [self lowestControlInPane:editingView];
	if (!lowest) return;

	//the gap between two groups is wider than the pitch within one; measure it off Soft tabs and the
	//Links group's first row rather than assume it
	CGFloat groupGap = 10.0f;
	if (softTabsButton && makeURLsClickable && NSMinY([softTabsButton frame]) > NSMinY([makeURLsClickable frame]))
		groupGap = MAX(0.0f, NSMinY([softTabsButton frame]) - NSMinY([makeURLsClickable frame]) - PREFS_ROW_PITCH);

	NSRect bottomRow = [lowest frame];
	[self liftControlsInPane:editingView above:NSMinY(bottomRow) by:2.0f * PREFS_ROW_PITCH + groupGap];

	NSRect wordCountRow = bottomRow;
	NSRect lineNumbersRow = NSOffsetRect(bottomRow, 0.0f, PREFS_ROW_PITCH);

	showsLineNumbersButton = [self newCheckboxWithTitle:NSLocalizedString(@"Show line numbers",
																		  @"Editing preference: number the lines beside the note text")
												 action:@selector(changedShowsLineNumbers:)
												  inRow:lineNumbersRow likeControl:lowest];
	showsWordCountButton = [self newCheckboxWithTitle:NSLocalizedString(@"Show word count",
																		@"Editing preference: show a bar beneath the window counting the words in the note")
											   action:@selector(changedShowsWordCount:)
												inRow:wordCountRow likeControl:lowest];

	//the group's label goes in the labels' column, right-aligned with the lowest label already there
	//(Links:), which is any non-editable text field ending left of the checkboxes
	NSTextField *columnLabel = nil;
	for (NSView *subview in [editingView subviews]) {
		if (![subview isKindOfClass:[NSTextField class]] || [(NSTextField *)subview isEditable]) continue;
		if (NSMaxX([subview frame]) > NSMinX(bottomRow)) continue;
		if (!columnLabel || NSMinY([subview frame]) < NSMinY([columnLabel frame])) columnLabel = (NSTextField *)subview;
	}

	displayLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
	[displayLabel setStringValue:NSLocalizedString(@"Display:", @"Editing preference: label for the line-number and word-count checkboxes")];
	[displayLabel setAlignment:NSTextAlignmentRight];
	[displayLabel setEditable:NO];
	[displayLabel setSelectable:NO];
	[displayLabel setBordered:NO];
	[displayLabel setBezeled:NO];
	[displayLabel setDrawsBackground:NO];
	[displayLabel setFont:columnLabel ? [columnLabel font] : [NSFont systemFontOfSize:[NSFont systemFontSize]]];
	[displayLabel sizeToFit];
	NSRect labelFrame = [displayLabel frame];
	CGFloat labelRight = columnLabel ? NSMaxX([columnLabel frame]) : NSMinX(bottomRow) - 3.0f;
	labelFrame.origin.x = MAX(0.0f, labelRight - NSWidth(labelFrame));
	labelFrame.size.width = labelRight - NSMinX(labelFrame);
	labelFrame.origin.y = floor(NSMidY(lineNumbersRow) - NSHeight(labelFrame) / 2.0f);
	[displayLabel setFrame:labelFrame];
	[displayLabel setAutoresizingMask:[lowest autoresizingMask]];

	[self widenPane:editingView toFitControl:showsLineNumbersButton leftInset:NSMinX(labelFrame)];
	[self widenPane:editingView toFitControl:showsWordCountButton leftInset:NSMinX(labelFrame)];

	[editingView addSubview:displayLabel];
	[editingView addSubview:showsLineNumbersButton];
	[editingView addSubview:showsWordCountButton];
}

/*
 The Appearance control -- a label and a KNAppearancePicker letting the user follow the system appearance
 or pin the app dark or light -- is built in code, the nib being un-editable. Unlike the General pane's
 checkbox, this pane cannot lean on -widenPane:: the Body Font field is width-sizable, so growing the pane
 *width* stretches that field until it runs under the fixed "Set…" button. So this lays out by hand
 instead. It leaves the pane width alone, grows only the *height* to make room, gives the Body Font row
 a generous gap above, and puts the picker below it. Everything is measured off existing controls, since
 the shipped nib's frames differ from designable.nib's and vary by localization.
 */
- (void)addAppearanceControl {

	if (appearancePicker || !fontsColorsView || !bodyTextFontField) return;

	const CGFloat gap = 48.0f;			//breathing room above and below the Body Font row
	const CGFloat bottomMargin = 12.0f;	//space beneath the Appearance picker's captions

	NSRect fieldFrame = [bodyTextFontField frame];
	CGFloat fieldY = NSMinY(fieldFrame);
	CGFloat fieldCenter = NSMidY(fieldFrame);

	//split the pane's controls into the Body Font row (the cluster sharing the field's baseline: its
	//label, the field, the Set button) and the colour rows above it, which move as a group
	NSTextField *bodyFontLabel = nil;
	NSMutableArray *bodyRow = [NSMutableArray arrayWithObject:bodyTextFontField];
	NSMutableArray *upperRows = [NSMutableArray array];
	CGFloat lowestUpperCenter = CGFLOAT_MAX;
	for (NSView *sv in [fontsColorsView subviews]) {
		if (sv == bodyTextFontField) continue;
		if (fabs(NSMinY([sv frame]) - fieldY) < 16.0f) {
			[bodyRow addObject:sv];
			if (!bodyFontLabel && [sv isKindOfClass:[NSTextField class]]) bodyFontLabel = (NSTextField *)sv;
		} else if (NSMinY([sv frame]) > fieldY) {
			[upperRows addObject:sv];
			lowestUpperCenter = MIN(lowestUpperCenter, NSMidY([sv frame]));
		}
	}

	//target row centres, bottom-up: the Appearance picker a bottom margin off the floor, the Body Font
	//row a little above its top, and the colour rows `gap` above that. Grow the pane's height (and lift
	//the colour rows with it) by whatever the top row has to rise; the top margin is preserved.
	NSSize pickerSize = [KNAppearancePicker pickerSize];
	CGFloat bodyCenterTarget = bottomMargin + pickerSize.height + 30.0f;
	CGFloat upperCenterTarget = bodyCenterTarget + gap;
	CGFloat shift = (lowestUpperCenter == CGFLOAT_MAX) ? 0.0f : (upperCenterTarget - lowestUpperCenter);
	if (shift < 0.0f) shift = 0.0f;

	if (shift > 0.0f) {
		BOOL wasAutoresizing = [fontsColorsView autoresizesSubviews];
		[fontsColorsView setAutoresizesSubviews:NO];
		NSRect pf = [fontsColorsView frame];
		pf.size.height += shift;
		[fontsColorsView setFrame:pf];
		for (NSView *sv in upperRows) {
			NSPoint o = [sv frame].origin;
			o.y += shift;
			[sv setFrameOrigin:o];
		}
		[fontsColorsView setAutoresizesSubviews:wasAutoresizing];
	}

	//move the Body Font row to its target centre (the pane grew with autoresizing off, so the field
	//has not moved and fieldCenter still holds)
	CGFloat bodyMove = bodyCenterTarget - fieldCenter;
	for (NSView *sv in bodyRow) {
		NSPoint o = [sv frame].origin;
		o.y += bodyMove;
		[sv setFrameOrigin:o];
	}

	//the thumbnails' left edges line up with the Body Font field's
	appearancePicker = [[KNAppearancePicker alloc] initWithFrame:NSMakeRect(NSMinX(fieldFrame) - KN_THUMB_PAD, bottomMargin,
																			pickerSize.width, pickerSize.height)];
	[appearancePicker setTarget:self];
	[appearancePicker setAction:@selector(changedAppearanceMode:)];
	[appearancePicker setAutoresizingMask:NSViewMinYMargin];
	//the picker is flipped; this is the thumbnails' centre in the pane's own coordinates
	CGFloat thumbCenterY = bottomMargin + pickerSize.height - [KNAppearancePicker thumbnailCenterY];

	//right-aligned label, its right edge matching the Body Font label's column, centred on the thumbnails
	CGFloat labelRight = bodyFontLabel ? NSMaxX([bodyFontLabel frame]) : (NSMinX(fieldFrame) - 8.0f);
	appearanceLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(0.0f, floor(thumbCenterY - 9.0f), labelRight, 18.0f)];
	[appearanceLabel setStringValue:NSLocalizedString(@"Appearance:",
		@"Fonts & Colors preference: label for the light/dark appearance picker")];
	[appearanceLabel setAlignment:NSTextAlignmentRight];
	[appearanceLabel setEditable:NO];
	[appearanceLabel setSelectable:NO];
	[appearanceLabel setBordered:NO];
	[appearanceLabel setBezeled:NO];
	[appearanceLabel setDrawsBackground:NO];
	[appearanceLabel setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
	[appearanceLabel setAutoresizingMask:NSViewMinYMargin];

	[fontsColorsView addSubview:appearanceLabel];
	[fontsColorsView addSubview:appearancePicker];
}

/*
 The Updates pane is a whole new pane rather than a control added to an existing one, so there is no
 nib view to grow: it is built from nothing here, in the manner of System Settings' grouped forms.
 Three cards stack top-down: the app's icon, name and version over a Check for Updates button; a link
 to the project page; and the two toggles -- automatic checks and, dependent on them, automatic
 downloads -- above the date of the last check. They drive the Sparkle updater through
 KNUpdateController. The pane is flipped; its own frame height is what sizes the window.
 */

//a plain, non-editable label
- (NSTextField *)newUpdatesLabelWithString:(NSString *)string font:(NSFont *)font color:(NSColor *)color {
	NSTextField *label = [[NSTextField alloc] initWithFrame:NSZeroRect];
	[label setStringValue:string];
	[label setEditable:NO];
	[label setSelectable:NO];
	[label setBordered:NO];
	[label setBezeled:NO];
	[label setDrawsBackground:NO];
	[label setFont:font];
	[label setTextColor:color];
	[label sizeToFit];
	return label;
}

//a hairline across a card, inset by the card's padding
- (void)addSeparatorToCard:(NSView *)card atY:(CGFloat)y inset:(CGFloat)inset {
	NSBox *line = [[[NSBox alloc] initWithFrame:NSMakeRect(inset, y, NSWidth([card frame]) - 2.0f * inset, 1.0f)] autorelease];
	[line setBoxType:NSBoxSeparator];
	[card addSubview:line];
}

//one row of the settings card: a title on the left, `control` right-aligned, both centred on the row
- (void)addRowToCard:(NSView *)card title:(NSString *)title control:(NSView *)control
			   atY:(CGFloat)y height:(CGFloat)height inset:(CGFloat)inset {
	NSTextField *label = [[self newUpdatesLabelWithString:title font:[NSFont systemFontOfSize:[NSFont systemFontSize]]
													color:[NSColor labelColor]] autorelease];
	NSRect lf = [label frame];
	lf.origin = NSMakePoint(inset, floor(y + (height - NSHeight(lf)) / 2.0f));
	[label setFrame:lf];
	[card addSubview:label];

	//added before it is measured: an NSSwitch reports its control size's dimensions only once it is
	//in a view, and the regular size until then
	[card addSubview:control];
	if ([control isKindOfClass:[NSSwitch class]]) [control setFrameSize:[control intrinsicContentSize]];
	NSRect cf = [control frame];
	cf.origin = NSMakePoint(NSWidth([card frame]) - inset - NSWidth(cf), floor(y + (height - NSHeight(cf)) / 2.0f));
	[control setFrame:cf];
}

- (NSSwitch *)newUpdatesSwitchWithAction:(SEL)action {
	NSSwitch *toggle = [[NSSwitch alloc] initWithFrame:NSZeroRect];
	[toggle setControlSize:NSControlSizeMini];
	[toggle setTarget:self];
	[toggle setAction:action];
	return toggle;
}

- (void)buildUpdatesView {

	if (updatesView) return;

	const CGFloat width = 480.0f;		//the pane
	const CGFloat margin = 20.0f;		//around the cards
	const CGFloat cardGap = 12.0f;		//between them
	const CGFloat pad = 16.0f;			//inside them
	const CGFloat rowHeight = 40.0f;	//a settings row
	const CGFloat cardWidth = width - 2.0f * margin;

	NSString *appName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];
	if (![appName length]) appName = [[NSProcessInfo processInfo] processName];
	CGFloat y = margin;

	updatesView = [[KNFlippedView alloc] initWithFrame:NSMakeRect(0.0f, 0.0f, width, 0.0f)];

	//--- the app: icon, name and version, then Check for Updates beneath a separator
	const CGFloat iconSize = 64.0f;
	KNPrefsCardView *appCard = [[[KNPrefsCardView alloc] initWithFrame:NSMakeRect(margin, y, cardWidth, 0.0f)] autorelease];

	NSImageView *icon = [[[NSImageView alloc] initWithFrame:NSMakeRect(pad, pad, iconSize, iconSize)] autorelease];
	[icon setImage:[NSApp applicationIconImage]];
	[icon setImageScaling:NSImageScaleProportionallyUpOrDown];
	[appCard addSubview:icon];

	NSTextField *nameLabel = [[self newUpdatesLabelWithString:appName font:[NSFont systemFontOfSize:22.0f weight:NSFontWeightSemibold]
														color:[NSColor labelColor]] autorelease];
	NSString *version = [NSString stringWithFormat:NSLocalizedString(@"Version %@ (%@)", @"Updates preference: the version and, in parentheses, the build number"),
						 [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"],
						 [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"]];
	NSTextField *versionLabel = [[self newUpdatesLabelWithString:version font:[NSFont systemFontOfSize:[NSFont systemFontSize]]
														   color:[NSColor secondaryLabelColor]] autorelease];
	//the two lines centred as a block on the icon
	CGFloat textHeight = NSHeight([nameLabel frame]) + 2.0f + NSHeight([versionLabel frame]);
	CGFloat textX = pad + iconSize + 16.0f;
	CGFloat textY = floor(pad + (iconSize - textHeight) / 2.0f);
	[nameLabel setFrameOrigin:NSMakePoint(textX, textY)];
	[versionLabel setFrameOrigin:NSMakePoint(textX, textY + NSHeight([nameLabel frame]) + 2.0f)];
	[appCard addSubview:nameLabel];
	[appCard addSubview:versionLabel];

	CGFloat cardY = pad + iconSize + 14.0f;
	[self addSeparatorToCard:appCard atY:cardY inset:pad];
	cardY += 1.0f + 12.0f;

	NSButton *checkNowButton = [[[NSButton alloc] initWithFrame:NSZeroRect] autorelease];
	[checkNowButton setBezelStyle:NSBezelStyleRounded];
	[checkNowButton setControlSize:NSControlSizeLarge];
	[checkNowButton setTitle:NSLocalizedString(@"Check for Updates", @"Updates preference: button that checks for a new version immediately")];
	[checkNowButton setFont:[NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:NSControlSizeLarge]]];
	[checkNowButton setTarget:self];
	[checkNowButton setAction:@selector(checkForUpdatesNow:)];
	[checkNowButton sizeToFit];
	[checkNowButton setFrameOrigin:NSMakePoint(pad - 2.0f, cardY)];
	[appCard addSubview:checkNowButton];
	cardY += NSHeight([checkNowButton frame]) + pad - 2.0f;

	[appCard setFrameSize:NSMakeSize(cardWidth, cardY)];
	[updatesView addSubview:appCard];
	y += cardY + cardGap;

	//--- the project page
	KNPrefsCardView *linkCard = [[[KNPrefsCardView alloc] initWithFrame:NSMakeRect(margin, y, cardWidth, rowHeight)] autorelease];
	NSButton *projectLink = [[[NSButton alloc] initWithFrame:NSZeroRect] autorelease];
	[projectLink setBordered:NO];
	[projectLink setButtonType:NSButtonTypeMomentaryChange];
	[projectLink setAttributedTitle:[[[NSAttributedString alloc] initWithString:NSLocalizedString(@"GitHub Project", @"Updates preference: link to the project's page")
		attributes:[NSDictionary dictionaryWithObjectsAndKeys:[NSColor linkColor], NSForegroundColorAttributeName,
					[NSFont systemFontOfSize:[NSFont systemFontSize]], NSFontAttributeName, nil]] autorelease]];
	[projectLink setToolTip:KNProjectURLString];
	[projectLink setTarget:self];
	[projectLink setAction:@selector(openProjectPage:)];
	[projectLink sizeToFit];
	[projectLink setFrameOrigin:NSMakePoint(pad, floor((rowHeight - NSHeight([projectLink frame])) / 2.0f))];
	[linkCard addSubview:projectLink];
	[updatesView addSubview:linkCard];
	y += rowHeight + cardGap;

	//--- the toggles and the last check
	KNPrefsCardView *settingsCard = [[[KNPrefsCardView alloc] initWithFrame:NSMakeRect(margin, y, cardWidth, 3.0f * rowHeight)] autorelease];

	automaticallyChecksButton = [self newUpdatesSwitchWithAction:@selector(changedAutomaticallyChecksForUpdates:)];
	[self addRowToCard:settingsCard title:NSLocalizedString(@"Automatically check for updates", @"Updates preference: toggle Sparkle's scheduled update checks")
			   control:automaticallyChecksButton atY:0.0f height:rowHeight inset:pad];
	[self addSeparatorToCard:settingsCard atY:rowHeight inset:pad];

	automaticallyDownloadsButton = [self newUpdatesSwitchWithAction:@selector(changedAutomaticallyDownloadsUpdates:)];
	[self addRowToCard:settingsCard title:NSLocalizedString(@"Automatically download updates", @"Updates preference: toggle automatic download and install of updates")
			   control:automaticallyDownloadsButton atY:rowHeight height:rowHeight inset:pad];
	[self addSeparatorToCard:settingsCard atY:2.0f * rowHeight inset:pad];

	lastCheckedField = [self newUpdatesLabelWithString:@"" font:[NSFont systemFontOfSize:[NSFont systemFontSize]]
												 color:[NSColor secondaryLabelColor]];
	[lastCheckedField setAlignment:NSTextAlignmentRight];
	[lastCheckedField setFrameSize:NSMakeSize(cardWidth / 2.0f, NSHeight([lastCheckedField frame]))];
	[self addRowToCard:settingsCard title:NSLocalizedString(@"Last checked", @"Updates preference: label for the date of the most recent update check")
			   control:lastCheckedField atY:2.0f * rowHeight height:rowHeight inset:pad];
	[updatesView addSubview:settingsCard];
	y += 3.0f * rowHeight + 8.0f;

	//--- a footnote on when a downloaded update takes effect
	NSString *note = [NSString stringWithFormat:NSLocalizedString(@"Downloaded updates install the next time you quit %@.",
		@"Updates preference: footnote; the app's name is substituted"), appName];
	NSTextField *footnote = [[self newUpdatesLabelWithString:note font:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]
													   color:[NSColor secondaryLabelColor]] autorelease];
	[footnote setFrameOrigin:NSMakePoint(margin + 4.0f, y)];
	[updatesView addSubview:footnote];
	y += NSHeight([footnote frame]) + margin;

	[updatesView setFrameSize:NSMakeSize(width, y)];

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateCheckDidFinish:)
												 name:KNUpdateCheckDidFinishNotification object:nil];
}

- (void)awakeFromNib {

	[window setDelegate:self];
	
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(changedTableText:)
												 name:NSControlTextDidEndEditingNotification object:tableTextSizeField];
    
    [tabKeyRadioMatrix setState:[prefsController tabKeyIndents] atRow:0 column:0];
    [tabKeyRadioMatrix setState:![prefsController tabKeyIndents] atRow:1 column:0];
    
    float fontSize = [prefsController tableFontSize];
    int fontButtonIndex = 3;
    if (fontSize == [NSFont smallSystemFontSize]) fontButtonIndex = 0;
    else if (fontSize == /*[NSFont systemFontSize]*/ SYSTEM_LIST_FONT_SIZE) fontButtonIndex = 1;
    [tableTextMenuButton selectItemAtIndex:fontButtonIndex];
    [tableTextSizeField setFloatValue:fontSize];
    [tableTextSizeField setHidden:(fontButtonIndex != 3)];
    
	[externalEditorMenuButton setMenu:[[ExternalEditorListController sharedInstance] addEditorPrefsMenu]];
	[self _selectDefaultExternalEditor];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(changedExternalEditorsMenu:) 
												 name:ExternalEditorsChangedNotification object:nil];
	
    [completeNoteTitlesButton setState:[prefsController autoCompleteSearches]];
    [checkSpellingButton setState:[prefsController checkSpellingAsYouType]];
    [confirmDeletionButton setState:[prefsController confirmNoteDeletion]];
    [quitWhenClosingButton setState:[prefsController quitWhenClosingWindow]];
	[self addTitleBarLayoutCheckbox];
	[sideBySideTitleBarButton setState:[prefsController sideBySideTitleBar]];

	[self addLayoutControl];
	[layoutButton selectItemAtIndex:[prefsController horizontalLayout] ? 0 : 1];
	[self addDisplayCheckboxes];
	[showsLineNumbersButton setState:[prefsController showsLineNumbers]];
	[showsWordCountButton setState:[prefsController showsWordCount]];
	[self addAppearanceControl];
	[appearancePicker setSelectedMode:[prefsController appearanceMode]];
    [styledTextButton setState:[prefsController pastePreservesStyle]];
    [autoSuggestLinksButton setState:[prefsController linksAutoSuggested]];
	[softTabsButton setState:[prefsController softTabs]];
	[makeURLsClickable setState:[prefsController URLsAreClickable]];
    [self previewNoteBodyFont];
	[appShortcutField setStringValue:[[prefsController appActivationKeyCombo] description]];
	[searchHighlightColorWell setColor:[prefsController searchTermHighlightColorRaw:YES]];
	[highlightSearchTermsButton setState:[prefsController highlightSearchTerms]];
	[self convertCheckboxesToSwitches];
	[foregroundColorWell setColor:[prefsController foregroundTextColor]];
	[backgroundColorWell setColor:[prefsController backgroundTextColor]];
    
    items = [[NSMutableDictionary alloc] init];
    
    [self addToolbarItemWithName:@"General"];
    [self addToolbarItemWithName:@"Notes"];	
    [self addToolbarItemWithName:@"Editing"];
	[self addToolbarItemWithName:@"Fonts & Colors"];

	[self buildUpdatesView];
	[self addToolbarItemWithName:@"Updates"];

	//reflect Sparkle's current state; automatic downloads are meaningful only while auto-checking is on
	KNUpdateController *updateController = [KNUpdateController sharedInstance];
	BOOL autoChecks = [updateController automaticallyChecksForUpdates];
	[automaticallyChecksButton setState:autoChecks ? NSControlStateValueOn : NSControlStateValueOff];
	[automaticallyDownloadsButton setState:[updateController automaticallyDownloadsUpdates] ? NSControlStateValueOn : NSControlStateValueOff];
	[automaticallyDownloadsButton setEnabled:autoChecks];
	[self refreshLastChecked];
		
    toolbar = [[NSToolbar alloc] initWithIdentifier:@"preferencePanes"];
    [toolbar setDelegate:self];
    [toolbar setAllowsUserCustomization:NO];
    [toolbar setAutosavesConfiguration:NO]; 
    [window setToolbar:toolbar];
    [toolbar release];  //setToolbar retains the toolbar we pass, so release the one we used.
	
	[window setShowsToolbarButton:NO];
	[self measureToolbarWidth];

    [self switchViews:nil];  //select last selected pane by default
    
}


- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)itemIdentifier willBeInsertedIntoToolbar:(BOOL)flag {
    return [items objectForKey:itemIdentifier];
}

- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar*)theToolbar {
    return [self toolbarDefaultItemIdentifiers:theToolbar];
}

- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar*)theToolbar {
    return [NSArray arrayWithObjects:@"General", @"Notes", @"Editing", @"Fonts & Colors", @"Updates", nil];
}

- (NSArray *)toolbarSelectableItemIdentifiers: (NSToolbar *)toolbar {
    //make all of them selectable. This puts that little grey outline thing around an item when you select it.
    return [items allKeys];
}

/*
 The narrowest window at which every toolbar item shows, in the language running. The toolbar collapses
 items it cannot fit into a ">>" menu, and how much room it needs depends on the translated pane names,
 both as item labels and as the window title beside them. So rather than a figure per language, this
 widens the (not yet visible) window in steps until the toolbar reports every item visible, with the
 longest pane name as the title, and keeps that width plus a margin.
 */
- (void)measureToolbarWidth {

	minContentWidth = PREFS_MIN_CONTENT_WIDTH;
	if (!toolbar || ![[toolbar items] count]) return;

	NSString *savedTitle = [window title];
	NSRect savedFrame = [window frame];

	NSString *longestTitle = savedTitle;
	CGFloat longestWidth = 0.0f;
	NSDictionary *titleAttributes = [NSDictionary dictionaryWithObject:[NSFont titleBarFontOfSize:0.0f] forKey:NSFontAttributeName];
	for (NSString *name in [self toolbarDefaultItemIdentifiers:toolbar]) {
		NSString *title = [[NSBundle mainBundle] localizedStringForKey:name value:@"" table:nil];
		CGFloat width = [title sizeWithAttributes:titleAttributes].width;
		if (width > longestWidth) { longestWidth = width; longestTitle = title; }
	}
	[window setTitle:longestTitle];

	NSView *frameView = [[window contentView] superview];
	for (CGFloat width = PREFS_MIN_CONTENT_WIDTH; width <= 1400.0f; width += 10.0f) {
		NSRect frame = savedFrame;
		frame.size.width = width;
		[window setFrame:frame display:NO];
		[frameView layoutSubtreeIfNeeded];
		if ([[toolbar visibleItems] count] >= [[toolbar items] count]) {
			minContentWidth = MAX(PREFS_MIN_CONTENT_WIDTH, width + 10.0f);
			break;
		}
	}

	[window setTitle:savedTitle];
	[window setFrame:savedFrame display:NO];
}

- (void)switchViews:(NSToolbarItem *)item {
    NSString *sender = nil;
	
    if (item == nil) {
        sender = [prefsController lastSelectedPreferencesPane];
        [toolbar setSelectedItemIdentifier:sender];
    } else {
        sender = [item itemIdentifier];
		[prefsController setLastSelectedPreferencesPane:sender sender:self];
    }
	
    NSView *prefsView = nil;
	
    [window setTitle:[[NSBundle mainBundle] localizedStringForKey:sender value:@"" table:nil]];
	
    if ([sender isEqualToString:@"General"]){
         prefsView = generalView;
    } else if([sender isEqualToString:@"Notes"]) {
        prefsView = [self databaseView];
    } else if([sender isEqualToString:@"Editing"]) {
        prefsView = editingView;
    } else if([sender isEqualToString:@"Fonts & Colors"]) {
        prefsView = fontsColorsView;
	} else if([sender isEqualToString:@"Updates"]) {
		prefsView = updatesView;
		[self refreshLastChecked];
	} else {
		NSLog(@"unknown sender: %@", sender);
	}
    
    if (prefsView == databaseView)
		[folderLocationsMenuButton setMenu:[self directorySelectionMenu]];
	
	NSAssert(prefsView != nil, @"switching to a nil prefs view!");
    
	[[NSFontPanel sharedFontPanel] close];
	
	//fix this math to convert between window and view coordinates for resolution independence

	float userSpaceScaleFactor = [window userSpaceScaleFactor];

    //to stop flicker, we make a temp blank view.

	NSRect windowContentFrame = ScaleRectWithFactor([[window contentView] frame], userSpaceScaleFactor);
    NSView *tempView = [[NSView alloc] initWithFrame:[[window contentView] frame]];
    [window setContentView:tempView];
    [tempView release];

    NSRect newFrame = [window frame];
	NSRect viewFrameForWindow = ScaleRectWithFactor([prefsView frame], userSpaceScaleFactor);
    newFrame.size.height = viewFrameForWindow.size.height + ([window frame].size.height - windowContentFrame.size.height);
    newFrame.size.width = MAX(viewFrameForWindow.size.width, minContentWidth);
    newFrame.origin.y += (windowContentFrame.size.height - viewFrameForWindow.size.height);

    [window setShowsResizeIndicator:YES];
    [window setFrame:newFrame display:YES animate:YES];

	//the window may be wider than the pane (so the toolbar always fits); host the pane in a
	//container and center it horizontally rather than letting it stretch left-aligned.
	NSRect contentBounds = [[window contentView] frame];
	if (contentBounds.size.width > viewFrameForWindow.size.width) {
		NSView *container = [[[NSView alloc] initWithFrame:contentBounds] autorelease];
		NSRect paneFrame = [prefsView frame];
		paneFrame.origin.x = floorf((contentBounds.size.width - paneFrame.size.width) / 2.0f);
		paneFrame.origin.y = contentBounds.size.height - paneFrame.size.height;
		[prefsView setFrame:paneFrame];
		[prefsView setAutoresizingMask:NSViewMinXMargin | NSViewMaxXMargin | NSViewMinYMargin];
		[container addSubview:prefsView];
		[window setContentView:container];
	} else {
		[window setContentView:prefsView];
	}
}

NSRect ScaleRectWithFactor(NSRect rect, float factor) {
	NSRect newRect = rect;
	newRect.size.width *= factor;
	newRect.size.height *= factor;
	newRect.origin.x *= factor;
	newRect.origin.y *= factor;
	
	//these may still need to be rounded up
	
	return newRect;
}

@end
