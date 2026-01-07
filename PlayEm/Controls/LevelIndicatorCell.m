//
//  LevelIndicatorCell.m
//  PlayEm
//
//  Created by Till Toenshoff on 13.11.22.
//  Copyright © 2022 Till Toenshoff. All rights reserved.
//

#import "LevelIndicatorCell.h"

#import "Defaults.h"

@implementation LevelIndicatorCell

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView*)controlView
{
    double level = MAX(MIN(self.doubleValue, 1.0), 0.0);
    NSColor* fillColor = [[Defaults sharedDefaults] lightFakeBeamColor];

    //    NSBezierPath* indicatorPath = [NSBezierPath
    //    bezierPathWithRoundedRect:NSInsetRect(cellFrame, 0, 7) xRadius:3
    //    yRadius:3]; [indicatorPath setLineWidth:2];
    //    [[NSColor controlBackgroundColor] setStroke];
    //    [indicatorPath stroke];

    NSRect levelRect = NSInsetRect(cellFrame, 0, 7);
    levelRect.size.width = levelRect.size.width * level;
    NSBezierPath* levelPath = [NSBezierPath bezierPathWithRoundedRect:levelRect xRadius:3 yRadius:3];
    [fillColor setFill];
    [levelPath fill];
}

@end
