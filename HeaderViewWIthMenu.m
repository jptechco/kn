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


#import "HeaderViewWIthMenu.h"
#import "NoteAttributeColumn.h"

@implementation HeaderViewWithMenu

- (id)init {
	if ([super init]) {
		isReloading = NO;
	}
	return self;
}

+ (NSColor*)headerBackgroundColor {
	//the semantic color for window chrome, opaque and appearance-aware. Note that it is not what
	//makes the header read as a header: measured on macOS 26, windowBackgroundColor,
	//controlBackgroundColor and textBackgroundColor all resolve to the same value as each other in
	//both appearances (white, and #1E1E1E in Dark Mode). The heading band is distinct from the rows
	//only because super draws its own tint over this fill, which is why the fill goes down first.
	return [NSColor windowBackgroundColor];
}

- (BOOL)isOpaque {
	return YES;
}

- (void)viewDidChangeEffectiveAppearance {
	[super viewDidChangeEffectiveAppearance];
	[self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
	//NSTableHeaderView and NSTableHeaderCell stopped painting an opaque bezel in 10.16, and the rows
	//are laid out underneath the header, so without a fill of our own the note titles scroll straight
	//through the column headings. Fill first and let super draw the titles, the column separators and
	//the sort indicator on top; the header is also wider than the sum of its cells, and the dead space
	//past the last column is only ever covered here.
	[[HeaderViewWithMenu headerBackgroundColor] set];
	NSRectFill(dirtyRect);

	[super drawRect:dirtyRect];
}

- (void)_resizeColumn:(NSInteger)resizedColIdx withEvent:(id)event {	
	//use a more understandable column resizing by changing the resizing mask immediately before calling through to the private method,
	//and reverting it back to the original at the next runloop iteration
	NSUInteger originalResizingMask = 0;
	int i;
	//change all user-resizable-only columns
	for (i=0; i<[[self tableView] numberOfColumns]; i++) {
		NoteAttributeColumn *col = [[[self tableView] tableColumns] objectAtIndex:i];
		if ((originalResizingMask = [col resizingMask]) == NSTableColumnUserResizingMask) {
			[col setResizingMask: NSTableColumnAutoresizingMask | NSTableColumnUserResizingMask];
			[col performSelector:@selector(setResizingMaskNumber:) withObject:[NSNumber numberWithUnsignedInt:originalResizingMask] afterDelay:0];
		}
	}
	
	[super _resizeColumn:resizedColIdx withEvent:event];
}
	
- (void)setIsReloading:(BOOL)reloading {
	isReloading = reloading;
}

- (void)resetCursorRects {
	if (!isReloading) {
		[super resetCursorRects];
	}
}

- (NSMenu *)menuForEvent:(NSEvent *)theEvent {
    
    if ([[self tableView] respondsToSelector:@selector(menuForColumnConfiguration:)]) {
	NSPoint theClickPoint = [self convertPoint:[theEvent locationInWindow] fromView:NULL];
	int theColumn = [self columnAtPoint:theClickPoint];
	NSTableColumn *theTableColumn = nil;
	if (theColumn > -1)
	    theTableColumn = [[[self tableView] tableColumns] objectAtIndex:theColumn];
	
	NSMenu *theMenu = [[self tableView] performSelector:@selector(menuForColumnConfiguration:) withObject:theTableColumn];
	return theMenu;
    }
    
    return nil;
}


@end
