//
//  IdentificationActiveView.m
//  PlayEm
//
//  Created by Till Toenshoff on 10.06.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#import "IdentificationActiveView.h"
#import <Quartz/Quartz.h>

@implementation IdentificationActiveView

- (id)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.autoresizingMask = NSViewHeightSizable | NSViewWidthSizable;
        self.clipsToBounds = YES;
        self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawOnSetNeedsDisplay;
    }
    return self;
}

- (CALayer*)makeBackingLayer
{
    CALayer* layer = [CALayer layer];
    layer.masksToBounds = NO;
    layer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    layer.frame = self.bounds;

    _imageLayer = [CALayer layer];
    _imageLayer.contents = [NSImage imageNamed:@"IdentificationActiveStill"];
    _imageLayer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    _imageLayer.allowsEdgeAntialiasing = YES;
    _imageLayer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
    _imageLayer.frame = NSInsetRect(self.bounds, 0.0, 5.0);
    [layer addSublayer:_imageLayer];

    return layer;
}

- (void)startAnimating
{
    CABasicAnimation* animation = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    animation.fillMode = kCAFillModeBoth;
    animation.removedOnCompletion = NO;
    animation.duration = 2.0f;
    CGFloat angleToAdd   = -M_PI_2 * 4;
    [_imageLayer setValue:@(M_PI_2 * 4.0) forKeyPath:@"transform.rotation.z"];

    animation.toValue = @(0.0);        // model value was already changed. End at that value
    animation.byValue = @(angleToAdd); // start from - this value (it's toValue - byValue (see above))
    animation.repeatCount = HUGE_VALF;
    // Add the animation. Once it completed it will be removed and you will see the value
    // of the model layer which happens to be the same value as the animation stopped at.
    [_imageLayer addAnimation:animation forKey:@"rotation"];
}

- (void)stopAnimating
{
    
}


@end
