//
//  TableHeaderCell.m
//  PlayEm
//
//  Created by Till Toenshoff on 19.11.22.
//  Copyright © 2022 Till Toenshoff. All rights reserved.
//

#import "TableHeaderCell.h"
#import "Defaults.h"

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
