//
//  IdentificationActiveView.m
//  PlayEm
//
//  Created by Till Toenshoff on 10.06.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#import "IdentificationCoverView.h"
#import <Quartz/Quartz.h>
#import "CAShapeLayer+Path.h"
NSString * const kLayerImageName = @"IdentificationActiveStill";
NSString * const kLayerMaskImageName = @"IdentificationActiveStill";

@implementation IdentificationCoverView

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

    _maskLayer = [CALayer layer];
    _maskLayer.frame = CGRectMake(-self.bounds.size.width / 2, -self.bounds.size.height / 2, self.bounds.size.width * 2, self.bounds.size.height * 2);
    _maskLayer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    _maskLayer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
    _maskLayer.allowsEdgeAntialiasing = YES;
    _maskLayer.contents = [NSImage imageNamed:@"FadeMask"];;

    _imageLayer = [CALayer layer];
    _imageLayer.frame = self.bounds;
    _imageLayer.contents = [NSImage imageNamed:@"UnknownSong"];
    _imageLayer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    _imageLayer.allowsEdgeAntialiasing = YES;
    _imageLayer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
    _imageLayer.frame = NSInsetRect(self.bounds, 0.0, 5.0);
    _imageLayer.mask = _maskLayer;
    [layer addSublayer:_imageLayer];

    _overlayLayer = [CALayer layer];
    _overlayLayer.contents = [NSImage imageNamed:kLayerImageName];
    _overlayLayer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    _overlayLayer.allowsEdgeAntialiasing = YES;
    _overlayLayer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
    _overlayLayer.opacity = 0.5;
    _overlayLayer.frame = CGRectMake(-self.bounds.size.width / 2, -self.bounds.size.height / 2, self.bounds.size.width * 2, self.bounds.size.height * 2);
    [layer addSublayer:_overlayLayer];

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
    [_overlayLayer setValue:@(M_PI_2 * 4.0) forKeyPath:@"transform.rotation.z"];
    [_maskLayer setValue:@(M_PI_2 * 4.0) forKeyPath:@"transform.rotation.z"];

    animation.toValue = @(0.0);        // model value was already changed. End at that value
    animation.byValue = @(angleToAdd); // start from - this value (it's toValue - byValue (see above))
    animation.repeatCount = HUGE_VALF;
    // Add the animation. Once it completed it will be removed and you will see the value
    // of the model layer which happens to be the same value as the animation stopped at.
    [_overlayLayer addAnimation:animation forKey:@"rotation"];
    [_maskLayer addAnimation:animation forKey:@"rotation"];
}

- (void)stopAnimating
{
    [_overlayLayer removeAllAnimations];
    [_maskLayer removeAllAnimations];
}


@end
