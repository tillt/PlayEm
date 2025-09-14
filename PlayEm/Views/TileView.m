//
//  TileView.m
//  PlayEm
//
//  Created by Till Toenshoff on 8/23/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>
#import "TileView.h"

@implementation TileView

- (nonnull instancetype)initWithFrame:(CGRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawOnSetNeedsDisplay;
        self.layer = [self makeBackingLayer];
    }
    return self;
}

- (CALayer*)makeBackingLayer
{
    CALayer* layer = [CALayer layer];
    layer.drawsAsynchronously = YES;
    layer.masksToBounds = NO;
    return layer;
}

- (BOOL)wantsLayer
{
    return YES;
}


@end
