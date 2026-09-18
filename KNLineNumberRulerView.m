//
//  KNLineNumberRulerView.m
//  Kinetic Notes
//
//  The line-number gutter beside the note editor.

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

#import "KNLineNumberRulerView.h"
#import "KNTextStatistics.h"
#import "GlobalPrefs.h"
#import "LinkingEditor.h"

//space either side of the widest number
#define KNGutterLeadingPadding 10.0f
#define KNGutterTrailingPadding 8.0f

@interface KNLineNumberRulerView (Private)
- (NSFont *)numberFont;
- (void)validateLineStarts;
- (NSUInteger)lineIndexForCharacterIndex:(NSUInteger)charIndex;
- (void)updateThickness;
@end

@implementation KNLineNumberRulerView

- (id)initWithTextView:(NSTextView *)aTextView {
	if ((self = [super initWithScrollView:[aTextView enclosingScrollView] orientation:NSVerticalRuler])) {
		textView = aTextView;
		lineStarts = [[NSMutableData alloc] init];
		lineStartsAreValid = NO;

		[self setClientView:textView];
		[self setReservedThicknessForMarkers:0.0];
		[self setReservedThicknessForAccessoryView:0.0];

		NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
		[center addObserver:self selector:@selector(noteTextDidChange:)
					   name:NSTextStorageDidProcessEditingNotification object:[textView textStorage]];
		[center addObserver:self selector:@selector(needsRedisplay:)
					   name:NSTextViewDidChangeSelectionNotification object:textView];
		//rewrapping, when the editor is resized, moves every line after the first
		[center addObserver:self selector:@selector(needsRedisplay:)
					   name:NSViewFrameDidChangeNotification object:textView];

		[self updateThickness];
	}
	return self;
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[lineStarts release];
	[super dealloc];
}

- (void)noteTextDidChange:(NSNotification *)aNotification {
	//only characters move lines; a change of attributes alone (search-term highlighting) does not
	if ([[aNotification object] editedMask] & NSTextStorageEditedCharacters) {
		lineStartsAreValid = NO;
		[self updateThickness];
	}
	[self setNeedsDisplay:YES];
}

- (void)needsRedisplay:(NSNotification *)aNotification {
	[self setNeedsDisplay:YES];
}

- (void)noteAppearanceChanged {
	[self updateThickness];
	[self setNeedsDisplay:YES];
}

- (void)viewDidChangeEffectiveAppearance {
	[super viewDidChangeEffectiveAppearance];
	[self setNeedsDisplay:YES];
}

- (NSFont *)numberFont {
	//a little smaller than the note's text, with digits of one width so the column stays aligned
	CGFloat bodySize = [[[GlobalPrefs defaultPrefs] noteBodyFont] pointSize];
	if (bodySize <= 0.0) bodySize = [NSFont systemFontSize];
	return [NSFont monospacedDigitSystemFontOfSize:MAX(9.0, floor(bodySize * 0.9)) weight:NSFontWeightRegular];
}

- (void)validateLineStarts {
	if (!lineStartsAreValid) {
		lineCount = KNLineStartIndexes([textView string], lineStarts);
		lineStartsAreValid = YES;
	}
}

//the index of the line holding `charIndex`: the last line starting at or before it
- (NSUInteger)lineIndexForCharacterIndex:(NSUInteger)charIndex {
	[self validateLineStarts];
	const NSUInteger *starts = [lineStarts bytes];
	NSUInteger low = 0, high = lineCount;
	while (high - low > 1) {
		NSUInteger mid = low + (high - low) / 2;
		if (starts[mid] <= charIndex) low = mid;
		else high = mid;
	}
	return low;
}

- (void)updateThickness {
	[self validateLineStarts];
	NSRange hiddenRange = [textView respondsToSelector:@selector(hiddenYAMLFrontMatterRange)] ?
		[(LinkingEditor *)textView hiddenYAMLFrontMatterRange] : NSMakeRange(NSNotFound, 0);
	NSUInteger visibleLineCount = lineCount;
	if (hiddenRange.location != NSNotFound) {
		const NSUInteger *starts = [lineStarts bytes];
		NSUInteger hiddenLines = 0;
		while (hiddenLines < lineCount && starts[hiddenLines] < NSMaxRange(hiddenRange)) hiddenLines++;
		visibleLineCount -= hiddenLines;
	}

	//room for at least three digits, so the gutter does not change width while a note grows to 100 lines
	NSUInteger digits = 3;
	for (NSUInteger n = visibleLineCount; n >= 1000; n /= 10) digits++;

	NSDictionary *attributes = [NSDictionary dictionaryWithObject:[self numberFont] forKey:NSFontAttributeName];
	CGFloat digitWidth = [@"8" sizeWithAttributes:attributes].width;
	CGFloat newThickness = ceil(KNGutterLeadingPadding + digits * digitWidth + KNGutterTrailingPadding);

	if (newThickness != thickness) {
		thickness = newThickness;
		[self setRuleThickness:thickness];
		[[self scrollView] tile];
	}
}

- (CGFloat)requiredThickness {
	return thickness;
}

- (BOOL)isOpaque {
	return YES;
}

- (void)drawRect:(NSRect)dirtyRect {
	GlobalPrefs *prefs = [GlobalPrefs defaultPrefs];
	NSColor *background = [prefs backgroundTextColor];
	NSColor *foreground = [prefs foregroundTextColor];

	//the gutter continues the editor's own background, so the numbers read as part of the page. The
	//scroll view can ask for more than the gutter (a rect spanning the whole scroll view); filling all of
	//it would paint over the notes list and the text, so only the gutter's own bounds are filled.
	[background set];
	NSRectFill(NSIntersectionRect(dirtyRect, [self bounds]));
	NSRectClip([self bounds]);

	//nothing to number while no note is shown
	if ([textView isHiddenOrHasHiddenAncestor]) return;

	NSLayoutManager *layoutManager = [textView layoutManager];
	NSTextContainer *container = [textView textContainer];
	NSString *string = [textView string];
	NSUInteger length = [string length];
	if (!layoutManager || !container) return;

	[self validateLineStarts];
	const NSUInteger *starts = [lineStarts bytes];
	NSRange hiddenRange = [textView respondsToSelector:@selector(hiddenYAMLFrontMatterRange)] ?
		[(LinkingEditor *)textView hiddenYAMLFrontMatterRange] : NSMakeRange(NSNotFound, 0);
	NSUInteger firstVisibleLine = 0;
	if (hiddenRange.location != NSNotFound)
		while (firstVisibleLine < lineCount && starts[firstVisibleLine] < NSMaxRange(hiddenRange)) firstVisibleLine++;

	NSPoint containerOrigin = [textView textContainerOrigin];
	NSRect visibleInContainer = NSOffsetRect([textView visibleRect], -containerOrigin.x, -containerOrigin.y);
	NSRange glyphRange = [layoutManager glyphRangeForBoundingRect:visibleInContainer inTextContainer:container];
	NSRange charRange = [layoutManager characterRangeForGlyphRange:glyphRange actualGlyphRange:NULL];

	//every line the selection touches is the active one; usually that is the one holding the insertion point
	NSRange selection = [textView selectedRange];
	NSUInteger firstActiveLine = [self lineIndexForCharacterIndex:selection.location];
	NSUInteger lastActiveLine = firstActiveLine;
	if (selection.length) {
		//a selection ending just after a line break does not reach into the next line
		lastActiveLine = [self lineIndexForCharacterIndex:NSMaxRange(selection) - 1];
	}

	NSFont *font = [self numberFont];
	NSColor *mutedColor = [foreground colorWithAlphaComponent:0.35];
	NSColor *activeColor = [foreground colorWithAlphaComponent:0.85];
	NSColor *bandColor = [foreground colorWithAlphaComponent:0.07];
	NSMutableDictionary *attributes = [NSMutableDictionary dictionaryWithObject:font forKey:NSFontAttributeName];

	CGFloat rightEdge = NSWidth([self bounds]) - KNGutterTrailingPadding;

	NSUInteger firstLine = MAX([self lineIndexForCharacterIndex:charRange.location], firstVisibleLine);
	for (NSUInteger line = firstLine; line < lineCount; line++) {
		NSUInteger lineStart = starts[line];
		if (lineStart > NSMaxRange(charRange)) break;

		//the rectangle the line occupies, in the text view, and the baseline of its first row
		NSRect lineRect;
		CGFloat baseline;
		if (lineStart < length) {
			NSUInteger lineEnd = (line + 1 < lineCount) ? starts[line + 1] : length;
			NSRange lineGlyphs = [layoutManager glyphRangeForCharacterRange:NSMakeRange(lineStart, lineEnd - lineStart)
													   actualCharacterRange:NULL];
			NSRect firstRow = [layoutManager lineFragmentRectForGlyphAtIndex:lineGlyphs.location effectiveRange:NULL];
			NSRect lastRow = [layoutManager lineFragmentRectForGlyphAtIndex:NSMaxRange(lineGlyphs) - 1 effectiveRange:NULL];
			lineRect = NSUnionRect(firstRow, lastRow);
			if ([[NSCharacterSet newlineCharacterSet] characterIsMember:[string characterAtIndex:lineStart]]) {
				//an empty line holds only its line break, which has no baseline of its own: place the number
				//where text in the line break's font would sit
				NSFont *breakFont = [[textView textStorage] attribute:NSFontAttributeName atIndex:lineStart effectiveRange:NULL];
				baseline = NSMinY(firstRow) + [layoutManager defaultBaselineOffsetForFont:breakFont ? breakFont : [prefs noteBodyFont]];
			} else {
				//the typesetter's baseline for the row, which a larger font anywhere on it moves down; it is
				//measured up from the row's bottom
				baseline = NSMaxY(firstRow) - [[layoutManager typesetter] baselineOffsetInLayoutManager:layoutManager
																							glyphIndex:lineGlyphs.location];
			}
		} else {
			//the empty line after a final line break, which has no glyphs and lives in the extra fragment
			lineRect = [layoutManager extraLineFragmentRect];
			if (NSIsEmptyRect(lineRect)) break;
			NSFont *typingFont = [[textView typingAttributes] objectForKey:NSFontAttributeName];
			if (!typingFont) typingFont = [prefs noteBodyFont];
			baseline = NSMinY(lineRect) + [layoutManager defaultBaselineOffsetForFont:typingFont];
		}

		CGFloat top = [self convertPoint:NSMakePoint(0.0, NSMinY(lineRect) + containerOrigin.y) fromView:textView].y;
		CGFloat bottom = [self convertPoint:NSMakePoint(0.0, NSMaxY(lineRect) + containerOrigin.y) fromView:textView].y;
		CGFloat baselineInGutter = [self convertPoint:NSMakePoint(0.0, baseline + containerOrigin.y) fromView:textView].y;

		BOOL active = (line >= firstActiveLine && line <= lastActiveLine);
		if (active) {
			[bandColor set];
			NSRectFillUsingOperation(NSMakeRect(0.0, MIN(top, bottom), NSWidth([self bounds]), fabs(bottom - top)),
									 NSCompositingOperationSourceOver);
		}

		[attributes setObject:active ? activeColor : mutedColor forKey:NSForegroundColorAttributeName];
		NSString *label = [NSString stringWithFormat:@"%lu", (unsigned long)(line - firstVisibleLine + 1)];
		NSSize size = [label sizeWithAttributes:attributes];

		//the gutter is flipped, like the text view, so a string's origin is its top: lift it off the baseline by the ascender
		[label drawAtPoint:NSMakePoint(rightEdge - size.width, baselineInGutter - [font ascender]) withAttributes:attributes];
	}
}

@end
