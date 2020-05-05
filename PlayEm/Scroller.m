//
//  Scroller.m
//  PlayEm
//
//  Created by Till Toenshoff on 18.10.22.
//  Copyright © 2022 Till Toenshoff. All rights reserved.
//

#import "Scroller.h"

@implementation Scroller

- (void)drawKnob
{
    if (self.color) {
        NSRect knobRect = [self rectForPart:NSScrollerKnob];
        knobRect.origin.y += 1;
        //knobRect.size.width = 7;
        knobRect.size.height -= 2;
        NSBezierPath *bezierPath = [NSBezierPath bezierPathWithRoundedRect:knobRect xRadius:4 yRadius:4];
        [self.color set];
        [bezierPath fill];
    } else {
        [super drawKnob];
    }
}

- (void)drawRect:(NSRect)dirtyRect
{
    [super drawRect:dirtyRect];
    [self drawKnob];
}

- (NSControlSize)controlSize
{
    return NSControlSizeSmall;
}

@end
