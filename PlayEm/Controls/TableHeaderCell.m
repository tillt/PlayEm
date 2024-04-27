//
//  TableHeaderCell.m
//  PlayEm
//
//  Created by Till Toenshoff on 19.11.22.
//  Copyright © 2022 Till Toenshoff. All rights reserved.
//

#import "TableHeaderCell.h"
#import "Defaults.h"

typedef enum : NSUInteger {
    RoundedNone = 0,
    RoundedTop = 0x01 << 0,
    RoundedBottom = 0x01 << 1,
} RoundingMask;

@implementation TableRowView

- (NSBezierPath*)selectionPathWithRoundingMask:(RoundingMask)rounding
{
    CGFloat radius = 5.0;
    BOOL roundAtTop = (rounding & RoundedTop) == RoundedTop;
    BOOL roundAtBottom = (rounding & RoundedBottom) == RoundedBottom;

    CGFloat tr = roundAtTop ? radius : 0.0;
    CGFloat tl = roundAtTop ? radius : 0.0;
    CGFloat br = roundAtBottom ? radius : 0.0;
    CGFloat bl = roundAtBottom ? radius : 0.0;

    NSRect selectionRect = self.bounds;
    selectionRect = NSMakeRect(selectionRect.origin.x + 4.0, selectionRect.origin.y, selectionRect.size.width - 8.0, selectionRect.size.height);

    if (roundAtTop) {
        selectionRect = NSMakeRect(selectionRect.origin.x, selectionRect.origin.y + 2.0, selectionRect.size.width, selectionRect.size.height - 2.0);
    }
    if (roundAtBottom) {
        selectionRect = NSMakeRect(selectionRect.origin.x, selectionRect.origin.y, selectionRect.size.width, selectionRect.size.height - 2.0);
    }

    NSBezierPath* path = [NSBezierPath bezierPath];
    
    if (roundAtTop) {
        [path moveToPoint:CGPointMake(selectionRect.origin.x + tl, selectionRect.origin.y)];
        [path lineToPoint:CGPointMake(selectionRect.origin.x + selectionRect.size.width - tr, selectionRect.origin.y)];
        [path appendBezierPathWithArcWithCenter:CGPointMake(selectionRect.origin.x + selectionRect.size.width - tr, selectionRect.origin.y + tr)
                                         radius:tr
                                     startAngle:-90.0
                                       endAngle:0.0
                                      clockwise:NO];
    } else {
        [path moveToPoint:CGPointMake(selectionRect.origin.x, selectionRect.origin.y)];
        [path lineToPoint:CGPointMake(selectionRect.origin.x + selectionRect.size.width, selectionRect.origin.y)];
    }

    if (roundAtBottom) {
        [path lineToPoint:CGPointMake(selectionRect.origin.x + selectionRect.size.width, selectionRect.origin.y + selectionRect.size.height - br)];
        [path appendBezierPathWithArcWithCenter:CGPointMake(selectionRect.origin.x + selectionRect.size.width - br, selectionRect.origin.y + selectionRect.size.height - br)
                                         radius:br
                                     startAngle:0.0
                                       endAngle:90.0
                                      clockwise:NO];

        [path lineToPoint:CGPointMake(selectionRect.origin.x + bl, selectionRect.origin.y + selectionRect.size.height)];
        [path appendBezierPathWithArcWithCenter:CGPointMake(selectionRect.origin.x + bl, selectionRect.origin.y + selectionRect.size.height - bl)
                                         radius:bl
                                     startAngle:90.0
                                       endAngle:180.0
                                      clockwise:NO];
    } else {
        [path lineToPoint:CGPointMake(selectionRect.origin.x + selectionRect.size.width, selectionRect.origin.y + selectionRect.size.height)];
        [path lineToPoint:CGPointMake(selectionRect.origin.x, selectionRect.origin.y + selectionRect.size.height)];
        //[path moveToPoint:CGPointMake(selectionRect.origin.x, selectionRect.origin.y + selectionRect.size.height)];
    }

    if (roundAtTop) {
        [path lineToPoint:CGPointMake(selectionRect.origin.x, selectionRect.origin.y + tl)];
        [path appendBezierPathWithArcWithCenter:CGPointMake(selectionRect.origin.x + tl, selectionRect.origin.y + tl)
                                         radius:tl
                                     startAngle:180.0
                                       endAngle:270.0
                                      clockwise:NO];
    } else {
        [path lineToPoint:CGPointMake(selectionRect.origin.x, selectionRect.origin.y)];
    }

    //[path closePath];

    return path;
}

- (void)drawSelectionInRect:(NSRect)dirtyRect
{
//    if (self.selectionHighlightStyle == NSTableViewSelectionHighlightStyleNone) {
//        return;
//    }

    NSColor* highlighted = [NSColor unemphasizedSelectedTextBackgroundColor];
    NSColor* focussed = [[Defaults sharedDefaults] regularBeamColor];

    NSColor* color = highlighted;

    if (self.isEmphasized) {
        color = focussed;
    }

    [color setFill];
    [color setStroke];

    RoundingMask roundingMask = RoundedNone;

    if (!self.previousRowSelected) {
        roundingMask |= RoundedTop;
    }

    if (!self.nextRowSelected) {
        roundingMask |= RoundedBottom;
    }

    NSBezierPath* path = [self selectionPathWithRoundingMask:roundingMask];

    [path fill];
    [path stroke];
}

@end

@implementation TableHeaderCell

- (id)initTextCell:(NSString *)string
{
    self = [super initTextCell:string];
    if (self) {
        //self.textColor = [NSColor colorWithRed:1 green:0 blue:1 alpha:1];
        //self.backgroundColor = [NSColor controlBackgroundColor];
        NSDictionary* attr = @{ NSForegroundColorAttributeName: [NSColor controlColor]};
        NSAttributedString* astring = [[NSAttributedString alloc] initWithString:string attributes:attr];
        [self setAttributedStringValue:astring];
    }
    return self;
}

- (void)drawWithFrame:(CGRect)cellFrame
          highlighted:(BOOL)isHighlighted
               inView:(NSView *)view
{
    CGRect fillRect, borderRect;
    CGRectDivide(cellFrame, &borderRect, &fillRect, 1.0, CGRectMaxYEdge);

    NSColor* bg = [self.backgroundColor colorWithAlphaComponent:0.9];
    [bg set];
    NSRectFill(fillRect);

    if (isHighlighted) {
//        //[[NSColor colorWithDeviceWhite:0.2 alpha:0.1] set];
        [[NSColor colorWithDeviceWhite:1.0 alpha:1.0] set];
        NSRectFillUsingOperation(fillRect, NSCompositingOperationSourceOver);
    }

    [self drawInteriorWithFrame:CGRectInset(fillRect, 0.0, 7.0) inView:view];
}

- (void)drawWithFrame:(CGRect)cellFrame inView:(NSView *)view
{
   [self drawWithFrame:cellFrame highlighted:NO inView:view];
}

- (void)highlight:(BOOL)isHighlighted
        withFrame:(NSRect)cellFrame
           inView:(NSView *)view
{
   [self drawWithFrame:cellFrame highlighted:isHighlighted inView:view];
}

@end
