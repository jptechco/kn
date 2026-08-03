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
#include <sys/stat.h>

#define SYSTEM_LIST_FONT_SIZE 12.0f

//the preference panes are only ~368pt wide, which is too narrow to display all four
//toolbar items on modern macOS (they collapse into a ">>" overflow menu). Keep the window
//at least this wide so every pane's toolbar item is always visible; narrower panes are
//centered within the extra width.
#define PREFS_MIN_CONTENT_WIDTH 540.0f

@implementation PrefsWindowController

- (id)init {
    if ([super init]) {
		prefsController = [GlobalPrefs defaultPrefs];
		fontPanelWasOpen = NO;
		
		[prefsController registerWithTarget:self forChangesInSettings:
		 @selector(resolveNoteBodyFontFromNotationPrefsFromSender:), 
		 @selector(setCheckSpellingAsYouType:sender:), 
		 @selector(setConfirmNoteDeletion:sender:),
		 @selector(setSideBySideTitleBar:sender:), nil];
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

- (IBAction)changedAppearanceMode:(id)sender {
	[prefsController setAppearanceMode:(KNAppearanceMode)[appearanceModeButton indexOfSelectedItem] sender:self];
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

- (void)addToolbarItemWithName:(NSString*)name {
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:name];
	
	NSString *localizedTitle = [[NSBundle mainBundle] localizedStringForKey:name value:@"" table:nil];
    [item setPaletteLabel:localizedTitle];
    [item setLabel:localizedTitle];
    //[item setToolTip:@"General settings: appearance and behavior"];
    [item setImage:[[[NSImage alloc] initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:name ofType:@"tiff"]] autorelease]];
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

 -openBottomRowInPane: does the shared geometry: it grows the pane by one row and shifts its existing
 controls up to open a gap at the bottom, returning that vacated row's frame for the caller to place a
 new control into. The pane's coordinates are un-flipped, with y = 0 at the bottom, so making it
 taller adds the space at the top; shifting everything up opens the gap at the bottom instead, which
 keeps the new control in the group rather than stranded above the labels.
 */
- (NSRect)openBottomRowInPane:(NSView *)pane measuredRow:(NSView **)outMeasuredRow {

	if (outMeasuredRow) *outMeasuredRow = nil;

	//the pitch the pane's controls are spaced on. Everything else is measured off the pane rather
	//than written down here: the compiled nib that actually ships does not match designable.nib's
	//frames, so hardcoding the margins puts the new row in the wrong place.
	const CGFloat rowPitch = 25.0f;

	//the lowest control gives both the margin the new row should sit on and the inset the pane's
	//controls are aligned to
	NSView *lowest = nil;
	NSEnumerator *probe = [[pane subviews] objectEnumerator];
	NSView *subview;
	while ((subview = [probe nextObject])) {
		if (!lowest || NSMinY([subview frame]) < NSMinY([lowest frame])) lowest = subview;
	}
	if (!lowest) return NSZeroRect;
	if (outMeasuredRow) *outMeasuredRow = lowest;

	//captured before the shift below: this is the slot the shift vacates at the bottom
	NSRect bottomRow = [lowest frame];

	//-setFrame: would move the controls on its own, because they are pinned to the pane's top and
	//autoresizing moves them -- but only for as long as every one of them keeps that mask. Suspend
	//autoresizing and move them here, so the result does not depend on masks set in a nib that
	//cannot be opened.
	BOOL wasAutoresizing = [pane autoresizesSubviews];
	[pane setAutoresizesSubviews:NO];

	NSRect paneFrame = [pane frame];
	paneFrame.size.height += rowPitch;
	[pane setFrame:paneFrame];

	NSEnumerator *subviews = [[pane subviews] objectEnumerator];
	while ((subview = [subviews nextObject])) {
		NSPoint origin = [subview frame].origin;
		origin.y += rowPitch;
		[subview setFrameOrigin:origin];
	}

	[pane setAutoresizesSubviews:wasAutoresizing];

	return bottomRow;
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

- (void)addTitleBarLayoutCheckbox {

	if (sideBySideTitleBarButton || !generalView) return;

	NSView *lowest = nil;
	NSRect bottomRow = [self openBottomRowInPane:generalView measuredRow:&lowest];
	if (!lowest) return;

	sideBySideTitleBarButton = [[NSButton alloc] initWithFrame:bottomRow];
	[sideBySideTitleBarButton setButtonType:NSButtonTypeSwitch];
	[sideBySideTitleBarButton setTitle:NSLocalizedString(@"Show the search field beside the window title",
														@"General preference: put the search field on the title's row rather than beneath it")];
	[sideBySideTitleBarButton setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
	[sideBySideTitleBarButton setTarget:self];
	[sideBySideTitleBarButton setAction:@selector(changedTitleBarLayout:)];

	//sizeToFit measures the title; keep the row's own height so this checkbox lines up with the
	//ones above it rather than sitting a point or two off their baseline
	[sideBySideTitleBarButton sizeToFit];
	[sideBySideTitleBarButton setFrame:NSMakeRect(NSMinX(bottomRow), NSMinY(bottomRow),
												  NSWidth([sideBySideTitleBarButton frame]), NSHeight(bottomRow))];
	//same mask as the row it was measured from, so it travels with the group if the pane resizes
	[sideBySideTitleBarButton setAutoresizingMask:[lowest autoresizingMask]];

	//the title is longer in some languages than the pane is wide; widen rather than truncate
	[self widenPane:generalView toFitControl:sideBySideTitleBarButton leftInset:NSMinX(bottomRow)];

	[generalView addSubview:sideBySideTitleBarButton];
}

/*
 The Color Scheme control -- a label + popup letting the user follow the system appearance or pin the
 app dark/light -- is built in code, the nib being un-editable. Unlike the General pane's checkbox,
 this pane cannot use -openBottomRowInPane:: the Body Font field is width-sizable, so growing the pane
 *width* (which -openBottomRowInPane: and -widenPane: can do) stretches that field until it runs under
 the fixed "Set…" button. So this lays out by hand instead. It leaves the pane width alone, grows only
 the *height* to make room, gives the Body Font row a generous gap above and below, and drops the
 Color Scheme row below it. Everything is measured off existing controls, since the shipped nib's
 frames differ from designable.nib's and vary by localization.
 */
- (void)addAppearanceControl {

	if (appearanceModeButton || !fontsColorsView || !bodyTextFontField) return;

	const CGFloat gap = 48.0f;			//breathing room above and below the Body Font row
	const CGFloat bottomMargin = 16.0f;	//space beneath the Color Scheme popup

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

	//target row centres, bottom-up: the Color Scheme popup a bottom margin off the floor, the Body
	//Font row `gap` above it, and the colour rows `gap` above that. Grow the pane's height (and lift
	//the colour rows with it) by whatever the top row has to rise; the top margin is preserved.
	const CGFloat popupHeight = 24.0f;
	CGFloat rowCenterY = bottomMargin + popupHeight / 2.0f;
	CGFloat bodyCenterTarget = rowCenterY + gap;
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

	appearanceModeButton = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(NSMinX(fieldFrame), 0.0f, 100.0f, 24.0f) pullsDown:NO];
	[appearanceModeButton addItemWithTitle:NSLocalizedString(@"Follow System",
		@"Color Scheme preference: track the macOS light/dark setting")];
	[appearanceModeButton addItemWithTitle:NSLocalizedString(@"Force Dark",
		@"Color Scheme preference: always use the dark appearance")];
	[appearanceModeButton addItemWithTitle:NSLocalizedString(@"Force Light",
		@"Color Scheme preference: always use the light appearance")];
	[appearanceModeButton setTarget:self];
	[appearanceModeButton setAction:@selector(changedAppearanceMode:)];
	[appearanceModeButton sizeToFit];

	//align under the Body Font field, vertically centred on the row
	NSRect popFrame = [appearanceModeButton frame];
	popFrame.origin.x = NSMinX(fieldFrame);
	popFrame.origin.y = rowCenterY - NSHeight(popFrame) / 2.0f;
	[appearanceModeButton setFrame:popFrame];
	[appearanceModeButton setAutoresizingMask:NSViewMinYMargin];

	//right-aligned label, its right edge matching the Body Font label's column
	CGFloat labelRight = bodyFontLabel ? NSMaxX([bodyFontLabel frame]) : (NSMinX(fieldFrame) - 8.0f);
	appearanceLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(0.0f, rowCenterY - 9.0f, labelRight, 18.0f)];
	[appearanceLabel setStringValue:NSLocalizedString(@"Color Scheme:",
		@"Fonts & Colors preference: label for the light/dark appearance popup")];
	[appearanceLabel setAlignment:NSTextAlignmentRight];
	[appearanceLabel setEditable:NO];
	[appearanceLabel setSelectable:NO];
	[appearanceLabel setBordered:NO];
	[appearanceLabel setBezeled:NO];
	[appearanceLabel setDrawsBackground:NO];
	[appearanceLabel setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
	[appearanceLabel setAutoresizingMask:NSViewMinYMargin];

	[fontsColorsView addSubview:appearanceLabel];
	[fontsColorsView addSubview:appearanceModeButton];
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
	[self addAppearanceControl];
	[appearanceModeButton selectItemAtIndex:[prefsController appearanceMode]];
    [styledTextButton setState:[prefsController pastePreservesStyle]];
    [autoSuggestLinksButton setState:[prefsController linksAutoSuggested]];
	[softTabsButton setState:[prefsController softTabs]];
	[makeURLsClickable setState:[prefsController URLsAreClickable]];
    [self previewNoteBodyFont];
	[appShortcutField setStringValue:[[prefsController appActivationKeyCombo] description]];
	[searchHighlightColorWell setColor:[prefsController searchTermHighlightColorRaw:YES]];
	[highlightSearchTermsButton setState:[prefsController highlightSearchTerms]];
	[foregroundColorWell setColor:[prefsController foregroundTextColor]];
	[backgroundColorWell setColor:[prefsController backgroundTextColor]];
    
    items = [[NSMutableDictionary alloc] init];
    
    [self addToolbarItemWithName:@"General"];
    [self addToolbarItemWithName:@"Notes"];	
    [self addToolbarItemWithName:@"Editing"];
	[self addToolbarItemWithName:@"Fonts & Colors"];
		
    toolbar = [[NSToolbar alloc] initWithIdentifier:@"preferencePanes"];
    [toolbar setDelegate:self];
    [toolbar setAllowsUserCustomization:NO];
    [toolbar setAutosavesConfiguration:NO]; 
    [window setToolbar:toolbar];
    [toolbar release];  //setToolbar retains the toolbar we pass, so release the one we used.
	
	[window setShowsToolbarButton:NO];

    [self switchViews:nil];  //select last selected pane by default
    
}


- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)itemIdentifier willBeInsertedIntoToolbar:(BOOL)flag {
    return [items objectForKey:itemIdentifier];
}

- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar*)theToolbar {
    return [self toolbarDefaultItemIdentifiers:theToolbar];
}

- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar*)theToolbar {
    return [NSArray arrayWithObjects:@"General", @"Notes", @"Editing", @"Fonts & Colors", nil];
}

- (NSArray *)toolbarSelectableItemIdentifiers: (NSToolbar *)toolbar {
    //make all of them selectable. This puts that little grey outline thing around an item when you select it.
    return [items allKeys];
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
    newFrame.size.width = MAX(viewFrameForWindow.size.width, PREFS_MIN_CONTENT_WIDTH);
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
