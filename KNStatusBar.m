//
//  KNStatusBar.m
//  Kinetic Notes
//
//  The bar beneath the main window that counts the words (or characters, lines or paragraphs) in the
//  note being shown.

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

#import "KNStatusBar.h"
#import "KNTextStatistics.h"
#import "GlobalPrefs.h"

const CGFloat KNStatusBarHeight = 22.0f;

#define KNStatusBarSideMargin 8.0f

//notes up to this long are recounted as soon as they change; longer ones once typing pauses
#define KNImmediateRecountLength 100000

static NSString *KNMenuTitleForUnit(KNTextCountUnit unit) {
	switch (unit) {
		case KNTextCountCharactersWithSpaces:
			return NSLocalizedString(@"Characters (with spaces)", @"status bar count menu: count every character except line breaks");
		case KNTextCountCharactersWithoutSpaces:
			return NSLocalizedString(@"Characters (no spaces)", @"status bar count menu: count characters, leaving out spaces and line breaks");
		case KNTextCountLines:
			return NSLocalizedString(@"Lines", @"status bar count menu: count lines");
		case KNTextCountParagraphs:
			return NSLocalizedString(@"Paragraphs", @"status bar count menu: count paragraphs");
		case KNTextCountWords:
		default:
			return NSLocalizedString(@"Words", @"status bar count menu: count words");
	}
}

static NSString *KNCountLabel(NSUInteger count, KNTextCountUnit unit) {
	NSString *format = nil;
	BOOL one = (count == 1);
	switch (unit) {
		case KNTextCountCharactersWithSpaces:
			format = one ? NSLocalizedString(@"%@ character (with spaces)", @"status bar: a count of exactly one character, spaces included")
						 : NSLocalizedString(@"%@ characters (with spaces)", @"status bar: a count of characters, spaces included");
			break;
		case KNTextCountCharactersWithoutSpaces:
			format = one ? NSLocalizedString(@"%@ character (no spaces)", @"status bar: a count of exactly one character, spaces left out")
						 : NSLocalizedString(@"%@ characters (no spaces)", @"status bar: a count of characters, spaces left out");
			break;
		case KNTextCountLines:
			format = one ? NSLocalizedString(@"%@ line", @"status bar: a count of exactly one line")
						 : NSLocalizedString(@"%@ lines", @"status bar: a count of lines");
			break;
		case KNTextCountParagraphs:
			format = one ? NSLocalizedString(@"%@ paragraph", @"status bar: a count of exactly one paragraph")
						 : NSLocalizedString(@"%@ paragraphs", @"status bar: a count of paragraphs");
			break;
		case KNTextCountWords:
		default:
			format = one ? NSLocalizedString(@"%@ word", @"status bar: a count of exactly one word")
						 : NSLocalizedString(@"%@ words", @"status bar: a count of words");
			break;
	}
	NSString *number = [NSNumberFormatter localizedStringFromNumber:[NSNumber numberWithUnsignedInteger:count]
														numberStyle:NSNumberFormatterDecimalStyle];
	return [NSString stringWithFormat:format, number];
}

@implementation KNStatusBar

- (id)initWithFrame:(NSRect)frame textView:(NSTextView *)aTextView {
	if ((self = [super initWithFrame:frame])) {
		textView = aTextView;

		//one borderless button holds both the count and the caret, so clicking either opens the menu
		countButton = [[NSButton alloc] initWithFrame:NSMakeRect(0.0f, 0.0f, 40.0f, KNStatusBarHeight)];
		[countButton setButtonType:NSButtonTypeMomentaryChange];
		[countButton setBordered:NO];
		[countButton setImagePosition:NSImageTrailing];
		[countButton setImageHugsTitle:YES];
		[countButton setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
		NSImage *caret = [NSImage imageWithSystemSymbolName:@"chevron.up"
								   accessibilityDescription:NSLocalizedString(@"Count options", @"accessibility description of the status bar's caret")];
		caret = [caret imageWithSymbolConfiguration:
				 [NSImageSymbolConfiguration configurationWithPointSize:[NSFont smallSystemFontSize] - 2.0f weight:NSFontWeightSemibold]];
		[countButton setImage:caret];
		[countButton setContentTintColor:[NSColor secondaryLabelColor]];
		[countButton setToolTip:NSLocalizedString(@"Choose what to count", @"tooltip for the status bar's count")];
		[countButton setTarget:self];
		[countButton setAction:@selector(showCountMenu:)];
		[self addSubview:countButton];

		NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
		[center addObserver:self selector:@selector(noteTextDidChange:)
					   name:NSTextStorageDidProcessEditingNotification object:[textView textStorage]];

		[[GlobalPrefs defaultPrefs] registerForSettingChange:@selector(setWordCountUnit:sender:) withTarget:self];

		[self update];
	}
	return self;
}

//GlobalPrefs holds on to the observers it calls back, so in practice the bar lasts as long as the app
- (void)dealloc {
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(update) object:nil];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[countButton release];
	[super dealloc];
}

- (void)settingChangedForSelectorString:(NSString *)selectorString {
	if ([selectorString isEqualToString:SEL_STR(setWordCountUnit:sender:)]) {
		[self update];
	}
}

- (void)noteTextDidChange:(NSNotification *)aNotification {
	if (![self window] || !([[aNotification object] editedMask] & NSTextStorageEditedCharacters)) return;

	//a burst of edits is counted once. The count is read after the text storage has finished
	//processing, and never while it is mid-edit.
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(update) object:nil];
	NSTimeInterval delay = ([[textView textStorage] length] > KNImmediateRecountLength) ? 0.3 : 0.0;
	[self performSelector:@selector(update) withObject:nil afterDelay:delay];
}

- (void)update {
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(update) object:nil];
	if (![self window]) return;

	//the editor is hidden while no note (or more than one) is selected; there is nothing to count then,
	//but the caret stays so the unit can still be changed
	NSString *title = @"";
	if (textView && ![textView isHidden]) {
		KNTextCountUnit unit = [[GlobalPrefs defaultPrefs] wordCountUnit];
		title = KNCountLabel(KNCountTextUnits([textView string], unit), unit);
	}

	NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
								[NSFont systemFontOfSize:[NSFont smallSystemFontSize]], NSFontAttributeName,
								[NSColor secondaryLabelColor], NSForegroundColorAttributeName, nil];
	[countButton setAttributedTitle:[[[NSAttributedString alloc] initWithString:title attributes:attributes] autorelease]];
	[countButton setImagePosition:[title length] ? NSImageTrailing : NSImageOnly];

	[self resizeSubviewsWithOldSize:[self frame].size];
}

//the count sits at the trailing edge, under the editor in both layouts
- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
	[countButton sizeToFit];
	NSRect buttonFrame = [countButton frame];
	buttonFrame.size.height = KNStatusBarHeight - 1.0f;
	buttonFrame.origin.x = NSWidth([self bounds]) - KNStatusBarSideMargin - NSWidth(buttonFrame);
	buttonFrame.origin.y = 0.0f;
	[countButton setFrame:buttonFrame];
}

- (IBAction)showCountMenu:(id)sender {
	NSMenu *menu = [[[NSMenu alloc] initWithTitle:@""] autorelease];
	KNTextCountUnit current = [[GlobalPrefs defaultPrefs] wordCountUnit];

	//in the order the options were asked for: the finest unit first
	KNTextCountUnit order[] = { KNTextCountCharactersWithSpaces, KNTextCountCharactersWithoutSpaces,
								KNTextCountWords, KNTextCountLines, KNTextCountParagraphs };
	for (NSUInteger i = 0; i < sizeof(order) / sizeof(order[0]); i++) {
		NSMenuItem *item = [menu addItemWithTitle:KNMenuTitleForUnit(order[i]) action:@selector(chooseCountUnit:) keyEquivalent:@""];
		[item setTarget:self];
		[item setTag:order[i]];
		[item setState:(order[i] == current) ? NSControlStateValueOn : NSControlStateValueOff];
	}

	//open upward, as the caret promises: the bar is at the bottom of the window, so the menu's top-left
	//corner goes a menu's height above the button
	NSRect buttonFrame = [countButton frame];
	NSPoint location = NSMakePoint(NSMinX(buttonFrame), NSMaxY(buttonFrame) + [menu size].height + 2.0f);
	[menu popUpMenuPositioningItem:nil atLocation:location inView:self];
}

- (IBAction)chooseCountUnit:(id)sender {
	[[GlobalPrefs defaultPrefs] setWordCountUnit:(KNTextCountUnit)[sender tag] sender:self];
	//the preference does not call back the sender that changed it
	[self update];
}

- (BOOL)isOpaque {
	return YES;
}

- (void)drawRect:(NSRect)dirtyRect {
	//never past the bar's own bounds, however large a rect AppKit asks for: the split view is right above
	NSRect bounds = [self bounds];
	[[NSColor windowBackgroundColor] set];
	NSRectFill(NSIntersectionRect(dirtyRect, bounds));

	//a hairline along the top, dividing the bar from the notes and the editor above it
	[[NSColor separatorColor] set];
	NSRectFillUsingOperation(NSMakeRect(0.0f, NSHeight(bounds) - 1.0f, NSWidth(bounds), 1.0f), NSCompositingOperationSourceOver);
}

@end
