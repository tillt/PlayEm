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

    _imageCopyLayer = [CALayer layer];
    _imageCopyLayer.frame = self.bounds;
    _imageCopyLayer.opacity = 0.07;
    _imageCopyLayer.contents = [NSImage imageNamed:@"UnknownSong"];
    _imageCopyLayer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    _imageCopyLayer.allowsEdgeAntialiasing = YES;
    _imageCopyLayer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
    _imageCopyLayer.frame = NSInsetRect(self.bounds, 0.0, 5.0);
    _imageCopyLayer.mask = _maskLayer;
    
    CIFilter* blurFilter = [CIFilter filterWithName:@"CIGaussianBlur"];
    [blurFilter setDefaults];
    [blurFilter setValue:[NSNumber numberWithFloat:1.3] forKey:@"inputRadius"];

    CIFilter* vibranceFilter = [CIFilter filterWithName:@"CIColorControls"];
    [vibranceFilter setDefaults];
    [vibranceFilter setValue:[NSNumber numberWithFloat:0.1] forKey:@"inputSaturation"];
    [vibranceFilter setValue:[NSNumber numberWithFloat:0.001] forKey:@"inputBrightness"];


    CIFilter* darkenFilter = [CIFilter filterWithName:@"CIGammaAdjust"];
    [darkenFilter setDefaults];
    [darkenFilter setValue:[NSNumber numberWithFloat:2.5] forKey:@"inputPower"];
    
    CIFilter* clampFilter = [CIFilter filterWithName:@"CIAffineClamp"];
    [clampFilter setDefaults];
    
    CIFilter* pixelateFilter = [CIFilter filterWithName:@"CISepiaTone"];
    [pixelateFilter setDefaults];
    
    CIFilter* bloomFilter = [CIFilter filterWithName:@"CIBloom"];
    [bloomFilter setDefaults];
    [bloomFilter setValue: [NSNumber numberWithFloat:5.0] forKey: @"inputRadius"];
    [bloomFilter setValue: [NSNumber numberWithFloat:0.7] forKey: @"inputIntensity"];

    //[pixelateFilter setValue:[NSNumber numberWithFloat:15] forKey:@"inputScale"];
    
    //CIComicEffect
    
    _imageCopyLayer.filters = @[ pixelateFilter   ];
    [layer addSublayer:_imageCopyLayer];

    _imageLayer = [CALayer layer];
    _imageLayer.frame = self.bounds;
    _imageLayer.contents = [NSImage imageNamed:@"UnknownSong"];
    _imageLayer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    _imageLayer.allowsEdgeAntialiasing = YES;
    _imageLayer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
    _imageLayer.frame = NSInsetRect(self.bounds, 0.0, 5.0);
    _imageLayer.mask = _maskLayer;
    _imageLayer.filters = @[ bloomFilter     ];
    [layer addSublayer:_imageLayer];

    _overlayLayer = [CALayer layer];
    _overlayLayer.contents = [NSImage imageNamed:kLayerImageName];
    _overlayLayer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    _overlayLayer.allowsEdgeAntialiasing = YES;
    _overlayLayer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
    _overlayLayer.opacity = 0.2;
    _overlayLayer.anchorPoint = CGPointMake(0.5, 0.508);
    _overlayLayer.frame = _maskLayer.frame;
    [layer addSublayer:_overlayLayer];

    return layer;
}

- (void)setImage:(NSImage*)image
{
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        [context setDuration:2.0f];
        self.animator.imageLayer.contents = image;
        self.animator.imageCopyLayer.contents = image;
    }];
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
