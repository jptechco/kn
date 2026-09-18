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
#include <sys/stat.h>

#define SYSTEM_LIST_FONT_SIZE 12.0f

//the preference panes are only ~368pt wide, which is too narrow to display all the toolbar items on
//modern macOS (they collapse into a ">>" overflow menu, hiding panes). Keep the window at least this
//wide so all six items stay visible beside the window title; narrower panes are centered in the
//extra width. The Hooks item adds another toolbar slot beyond the previously measured 590pt minimum.
#define PREFS_MIN_CONTENT_WIDTH 660.0f

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

- (IBAction)changedShowsLineNumbers:(id)sender {
	[prefsController setShowsLineNumbers:[showsLineNumbersButton state] sender:self];
}

- (IBAction)changedShowsWordCount:(id)sender {
	[prefsController setShowsWordCount:[showsWordCountButton state] sender:self];
}

- (IBAction)changedAppearanceMode:(id)sender {
	[prefsController setAppearanceMode:(KNAppearanceMode)[appearanceModeButton indexOfSelectedItem] sender:self];
}

- (IBAction)checkForUpdatesNow:(id)sender {
	[[KNUpdateController sharedInstance] checkForUpdates:sender];
}

- (IBAction)changedAutomaticallyChecksForUpdates:(id)sender {
	BOOL on = ([automaticallyChecksButton state] == NSControlStateValueOn);
	[[KNUpdateController sharedInstance] setAutomaticallyChecksForUpdates:on];

	//Sparkle only auto-downloads if it is also auto-checking, so Auto-Update follows this toggle:
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

- (IBAction)changedAutomaticallyCommitAndPush:(id)sender {
	[prefsController setAutomaticallyCommitAndPushNotes:
		([automaticallyCommitAndPushButton state] == NSControlStateValueOn) sender:self];
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

//Every pane's toolbar icon is an SF Symbol (available on the 13.0 deployment target), so all five
//share one modern, monochrome style that adapts to Light/Dark Mode. This replaces the old per-pane
//.tiff bitmaps, whose shaded early-2010s look no longer matched. The .tiff files stay in the project
//but are no longer loaded here.
static NSString *KNPaneSymbolName(NSString *paneIdentifier) {
	if ([paneIdentifier isEqualToString:@"General"])        return @"gearshape";
	if ([paneIdentifier isEqualToString:@"Notes"])          return @"tray.full";
	if ([paneIdentifier isEqualToString:@"Editing"])        return @"square.and.pencil";
	if ([paneIdentifier isEqualToString:@"Fonts & Colors"]) return @"textformat";
	if ([paneIdentifier isEqualToString:@"Hooks"])          return @"terminal";
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
 The Color Scheme control -- a label + popup letting the user follow the system appearance or pin the
 app dark/light -- is built in code, the nib being un-editable. Unlike the General pane's checkbox,
 this pane cannot lean on -widenPane:: the Body Font field is width-sizable, so growing the pane
 *width* stretches that field until it runs under the fixed "Set…" button. So this lays out by hand instead. It leaves the pane width alone, grows only
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

/*
 The Updates pane is a whole new pane rather than a control added to an existing one, so unlike the
 two above there is no nib view to grow: it is built from nothing here. It holds a "Check Now" button
 and two toggles -- "Check for Updates Automatically" and, indented beneath it as its sub-option,
 "Auto-Update" -- which drive the Sparkle updater through KNUpdateController. Coordinates are
 un-flipped (y = 0 at the bottom); the pane is narrower than PREFS_MIN_CONTENT_WIDTH, so -switchViews:
 centres it in the window. Its own frame height is what sizes the pane, so it is set generously.
 */
- (void)buildUpdatesView {

	if (updatesView) return;

	const CGFloat leftInset = 20.0f;

	updatesView = [[NSView alloc] initWithFrame:NSMakeRect(0.0f, 0.0f, 420.0f, 150.0f)];

	//"Check Now" -- a momentary push button, top of the pane
	NSButton *checkNowButton = [[[NSButton alloc] initWithFrame:NSMakeRect(leftInset, 104.0f, 120.0f, 32.0f)] autorelease];
	[checkNowButton setBezelStyle:NSBezelStyleRounded];
	[checkNowButton setButtonType:NSButtonTypeMomentaryPushIn];
	[checkNowButton setTitle:NSLocalizedString(@"Check Now",
		@"Updates preference: button that checks for a new version immediately")];
	[checkNowButton setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
	[checkNowButton setTarget:self];
	[checkNowButton setAction:@selector(checkForUpdatesNow:)];
	[checkNowButton sizeToFit];
	NSRect cnFrame = [checkNowButton frame];
	if (cnFrame.size.width < 100.0f) cnFrame.size.width = 100.0f;	//keep a comfortable minimum
	cnFrame.origin = NSMakePoint(leftInset, 104.0f);
	[checkNowButton setFrame:cnFrame];
	[checkNowButton setAutoresizingMask:NSViewMinYMargin];
	[updatesView addSubview:checkNowButton];

	//caption beside the button, so it reads "Check Now  for the most recent version". A plain label:
	//no custom text colour, so it uses the adaptive labelColor and stays legible in Dark Mode.
	NSTextField *checkNowCaption = [[[NSTextField alloc] initWithFrame:NSMakeRect(0.0f, 0.0f, 260.0f, 18.0f)] autorelease];
	[checkNowCaption setStringValue:NSLocalizedString(@"for the most recent version",
		@"Updates preference: caption beside the Check Now button")];
	[checkNowCaption setEditable:NO];
	[checkNowCaption setSelectable:NO];
	[checkNowCaption setBordered:NO];
	[checkNowCaption setBezeled:NO];
	[checkNowCaption setDrawsBackground:NO];
	[checkNowCaption setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
	[checkNowCaption sizeToFit];
	NSRect capFrame = [checkNowCaption frame];
	capFrame.origin = NSMakePoint(NSMaxX(cnFrame) + 8.0f, NSMidY(cnFrame) - NSHeight(capFrame) / 2.0f);
	[checkNowCaption setFrame:capFrame];
	[checkNowCaption setAutoresizingMask:NSViewMinYMargin];
	[updatesView addSubview:checkNowCaption];
	//grow the pane if the button+caption run past its right edge, so nothing is clipped
	[self widenPane:updatesView toFitControl:checkNowCaption leftInset:leftInset];

	//"Check for Updates Automatically" -- Sparkle's scheduled checks
	automaticallyChecksButton = [[NSButton alloc] initWithFrame:NSMakeRect(leftInset, 64.0f, 320.0f, 18.0f)];
	[automaticallyChecksButton setButtonType:NSButtonTypeSwitch];
	[automaticallyChecksButton setTitle:NSLocalizedString(@"Check for Updates Automatically",
		@"Updates preference: toggle Sparkle's scheduled update checks")];
	[automaticallyChecksButton setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
	[automaticallyChecksButton setTarget:self];
	[automaticallyChecksButton setAction:@selector(changedAutomaticallyChecksForUpdates:)];
	[automaticallyChecksButton sizeToFit];
	[automaticallyChecksButton setFrameOrigin:NSMakePoint(leftInset, 64.0f)];
	[automaticallyChecksButton setAutoresizingMask:NSViewMinYMargin];
	[updatesView addSubview:automaticallyChecksButton];

	//"Auto-Update" -- automatic download+install; indented to read as a sub-option of the toggle above
	automaticallyDownloadsButton = [[NSButton alloc] initWithFrame:NSMakeRect(leftInset + 18.0f, 36.0f, 320.0f, 18.0f)];
	[automaticallyDownloadsButton setButtonType:NSButtonTypeSwitch];
	[automaticallyDownloadsButton setTitle:NSLocalizedString(@"Auto-Update",
		@"Updates preference: toggle automatic download and install of updates")];
	[automaticallyDownloadsButton setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
	[automaticallyDownloadsButton setTarget:self];
	[automaticallyDownloadsButton setAction:@selector(changedAutomaticallyDownloadsUpdates:)];
	[automaticallyDownloadsButton sizeToFit];
	[automaticallyDownloadsButton setFrameOrigin:NSMakePoint(leftInset + 18.0f, 36.0f)];
	[automaticallyDownloadsButton setAutoresizingMask:NSViewMinYMargin];
	[updatesView addSubview:automaticallyDownloadsButton];
}

- (void)buildHooksView {
	if (hooksView) return;

	const CGFloat leftInset = 20.0f;
	hooksView = [[NSView alloc] initWithFrame:NSMakeRect(0.0f, 0.0f, 480.0f, 130.0f)];

	automaticallyCommitAndPushButton = [[NSButton alloc]
		initWithFrame:NSMakeRect(leftInset, 84.0f, 440.0f, 18.0f)];
	[automaticallyCommitAndPushButton setButtonType:NSButtonTypeSwitch];
	[automaticallyCommitAndPushButton setTitle:NSLocalizedString(
		@"Automatically pull, commit, and push note changes",
		@"Hooks preference: commit and push changes when the notes folder is a Git repository")];
	[automaticallyCommitAndPushButton setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
	[automaticallyCommitAndPushButton setTarget:self];
	[automaticallyCommitAndPushButton setAction:@selector(changedAutomaticallyCommitAndPush:)];
	[automaticallyCommitAndPushButton sizeToFit];
	[automaticallyCommitAndPushButton setFrameOrigin:NSMakePoint(leftInset, 84.0f)];
	[hooksView addSubview:automaticallyCommitAndPushButton];

	NSTextField *caption = [[[NSTextField alloc]
		initWithFrame:NSMakeRect(leftInset + 18.0f, 34.0f, 430.0f, 38.0f)] autorelease];
	[caption setStringValue:NSLocalizedString(
		@"When the notes folder is a Git repository root, Kinetic Notes periodically pulls remote changes and commits and pushes saved local changes.",
		@"Hooks preference: explanation of automatic Git operations")];
	[caption setEditable:NO];
	[caption setSelectable:NO];
	[caption setBordered:NO];
	[caption setBezeled:NO];
	[caption setDrawsBackground:NO];
	[caption setTextColor:[NSColor secondaryLabelColor]];
	[caption setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
	[[caption cell] setWraps:YES];
	[hooksView addSubview:caption];
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
	[self addDisplayCheckboxes];
	[showsLineNumbersButton setState:[prefsController showsLineNumbers]];
	[showsWordCountButton setState:[prefsController showsWordCount]];
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

	[self buildHooksView];
	[self addToolbarItemWithName:@"Hooks"];

	[self buildUpdatesView];
	[self addToolbarItemWithName:@"Updates"];

	//reflect Sparkle's current state; Auto-Update is meaningful only while auto-checking is on
	KNUpdateController *updateController = [KNUpdateController sharedInstance];
	BOOL autoChecks = [updateController automaticallyChecksForUpdates];
	[automaticallyChecksButton setState:autoChecks ? NSControlStateValueOn : NSControlStateValueOff];
	[automaticallyDownloadsButton setState:[updateController automaticallyDownloadsUpdates] ? NSControlStateValueOn : NSControlStateValueOff];
	[automaticallyDownloadsButton setEnabled:autoChecks];
	[automaticallyCommitAndPushButton setState:[prefsController automaticallyCommitAndPushNotes] ?
		NSControlStateValueOn : NSControlStateValueOff];
		
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
    return [NSArray arrayWithObjects:@"General", @"Notes", @"Editing", @"Fonts & Colors", @"Hooks", @"Updates", nil];
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
	} else if([sender isEqualToString:@"Hooks"]) {
		prefsView = hooksView;
	} else if([sender isEqualToString:@"Updates"]) {
		prefsView = updatesView;
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
