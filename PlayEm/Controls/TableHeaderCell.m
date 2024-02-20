//
//  TableHeaderCell.m
//  PlayEm
//
//  Created by Till Toenshoff on 19.11.22.
//  Copyright © 2022 Till Toenshoff. All rights reserved.
//

#import "TableHeaderCell.h"
#import "Defaults.h"

@implementation TableRowView

- (void)drawSelectionInRect:(NSRect)dirtyRect
{
    if (self.selectionHighlightStyle != NSTableViewSelectionHighlightStyleNone)
    {
        NSRect selectionRect = NSInsetRect(self.bounds, 1.5, 1.5);
        
        [[[Defaults sharedDefaults] regularBeamColor] setStroke];
        [[[Defaults sharedDefaults] backColor] setFill];

        NSBezierPath* selectionPath = [NSBezierPath bezierPathWithRoundedRect:selectionRect
                                                                      xRadius:3
                                                                      yRadius:3];
        [selectionPath fill];
        [selectionPath stroke];
    }
}

@end
//
//@implementation TableHeaderView
//
//- (id)initWithFrame:(NSRect)frameRect
//{
//    self = [super initWithFrame:frameRect];
//    if (self) {
//    }
//    return self;
//}
//
//- (id)initWithCoder:(NSCoder *)coder
//{
//    self = [super initWithCoder:coder];
//    if (self) {
//    }
//    return self;
//}

/*
- (void)drawRect:(NSRect)dirtyRect
{
    [[NSColor redColor] set];
    NSRectFill(dirtyRect);
    [super drawRect:dirtyRect];
}

 */
//@end

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

   NSGradient *gradient = [[NSGradient alloc]
      initWithStartingColor:[NSColor blackColor]
                endingColor:[NSColor colorWithDeviceWhite:0.9 alpha:1.0]];
   [gradient drawInRect:fillRect angle:90.0];
    
    NSColor* bg = [self.backgroundColor colorWithAlphaComponent:0.9];
    [bg set];
    NSRectFill(fillRect);
   if (isHighlighted) {
      [[NSColor colorWithDeviceWhite:0.2 alpha:0.1] set];
      NSRectFillUsingOperation(fillRect, NSCompositingOperationSourceOver);
   }

   //[[NSColor colorWithDeviceWhite:0.0 alpha:1.0] set];
   //NSRectFill(borderRect);

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
/*
- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
    [self drawInteriorWithFrame:cellFrame inView:controlView];
}

- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
    [];
//    NSRect titleRect = [self titleRectForBounds:cellFrame];
//    [[self attributedStringValue] drawInRect:titleRect];
//    [super drawInteriorWithFrame:<#cellFrame#> inView:<#controlView#>];
}
 */

@end
