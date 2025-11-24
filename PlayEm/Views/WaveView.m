//
//  WaveView.m
//  PlayEm
//
//  Created by Till Toenshoff on 16.08.23.
//  Copyright © 2023 Till Toenshoff. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreImage/CoreImage.h>
#import "WaveView.h"
#import "CAShapeLayer+Path.h"
#import "NSBezierPath+CGPath.h"
#import "ProfilingPointsOfInterest.h"

static const CGFloat kRastaLayerZ = 1.5;
static const CGFloat kAheadVibrancyLayerZ = 1.0;
static const CGFloat kHeadLayerZ = 1.1;
static const CGFloat kHeadBloomFxLayerZ = 1.2;
static const CGFloat kMarkerLayerZ = 10.0;

@interface WaveView ()
@end

@implementation WaveView

- (nonnull instancetype)initWithFrame:(CGRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawOnSetNeedsDisplay;
        self.wantsLayer = YES;
        self.layer = [self makeBackingLayer];
        self.layer.masksToBounds = NO;
        self.layerUsesCoreImageFilters = YES;
        self.markLayer = [self makeMarkLayer];
        self.markLayer.masksToBounds = NO;
    }
    return self;
}

- (CALayer*)makeMarkLayer
{
    CALayer* layer = [CALayer layer];
    
    layer.drawsAsynchronously = YES;
    layer.zPosition = 5.1;
    layer.name = @"WaveMarkLayer";

    return layer;
}

- (CALayer*)makeHeadLayer
{
    CALayer* layer = [CALayer layer];
    
    layer.anchorPoint = CGPointMake(0.5, 0.0);
    layer.drawsAsynchronously = YES;
    layer.zPosition = 1.1;
    layer.name = @"HeadLayer";

    return layer;
}

- (CALayer*)makeHeadBloomFxLayer
{
    CALayer* layer = [CALayer layer];

    layer.anchorPoint = CGPointMake(0.5, 0.0);
    layer.masksToBounds = NO;
    layer.drawsAsynchronously = YES;
    layer.zPosition = 1.9;
    layer.name = @"HeadBloomFxLayer";

    return layer;
}


- (void)viewDidMoveToSuperview
{
    [super viewDidMoveToSuperview];

    [self createHead];

    if (self.enclosingScrollView == nil) {
        [self setupHead];
        [self addHead];
        self.markLayer.frame = self.bounds;
        [self.layer addSublayer:self.markLayer];
    } else {
        [self.enclosingScrollView performSelector:@selector(createTrail)];
        [self.enclosingScrollView performSelector:@selector(setupHead)];
        [self.enclosingScrollView performSelector:@selector(addHead)];
        self.markLayer.frame = self.enclosingScrollView.documentVisibleRect;
        [self.enclosingScrollView.layer addSublayer:self.markLayer];
    }
}

- (void)dealloc
{
}

- (BOOL)wantsLayer
{
    return YES;
}

- (CALayer*)makeBackingLayer
{
    CALayer* layer = [CALayer layer];
    layer.drawsAsynchronously = YES;
    return layer;
}

- (void)createHead
{
    BOOL scrolling = self.enclosingScrollView != nil;
    
    _headLayer = [self makeHeadLayer];
    _headLayer.compositingFilter = [CIFilter filterWithName:@"CISourceAtopCompositing"];
    
    CIFilter* clampFilter = [CIFilter filterWithName:@"CIAffineClamp"];
    [clampFilter setDefaults];
    CGFloat scaleFactor = scrolling ? 1.05 : 1.05;
    CGAffineTransform transform = CGAffineTransformScale(CGAffineTransformMakeTranslation(0.0, self.enclosingScrollView.bounds.size.height * -(scaleFactor - 1.0) / 2.0), 1.0, scaleFactor);
    [clampFilter setValue:[NSValue valueWithBytes:&transform objCType:@encode(CGAffineTransform)] forKey:@"inputTransform"];
    
    CIFilter* bloomFilter = [CIFilter filterWithName:@"CIBloom"];
    [bloomFilter setDefaults];
    [bloomFilter setValue: @(self.bounds.size.height / 20.0) forKey: @"inputRadius"];
    [bloomFilter setValue: @(1.0f) forKey: @"inputIntensity"];

    CIFilter* lightenFilter = [CIFilter filterWithName:@"CIColorControls"];
    [lightenFilter setDefaults];
    [lightenFilter setValue:@(3.0f) forKey:@"inputSaturation"];
    [lightenFilter setValue:@(0.20f) forKey:@"inputBrightness"];

    _headBloomFxLayer = [self makeHeadBloomFxLayer];
    _headBloomFxLayer.backgroundFilters = @[ clampFilter, bloomFilter, bloomFilter,lightenFilter];

    CIFilter* vibranceFilter = [CIFilter filterWithName:@"CIColorControls"];
    [vibranceFilter setDefaults];
    [vibranceFilter setValue:@(0.1) forKey:@"inputSaturation"];
    [vibranceFilter setValue:@(0.0001f) forKey:@"inputBrightness"];

    CIFilter* darkenFilter = [CIFilter filterWithName:@"CIGammaAdjust"];
    [darkenFilter setDefaults];
    [darkenFilter setValue:@(2.5f) forKey:@"inputPower"];

    _aheadVibranceFxLayer = [CALayer layer];
    _aheadVibranceFxLayer.drawsAsynchronously = YES;
    _aheadVibranceFxLayer.backgroundFilters = @[ darkenFilter, vibranceFilter ];
    _aheadVibranceFxLayer.anchorPoint = CGPointMake(0.0, 0.0);
    _aheadVibranceFxLayer.masksToBounds = NO;
    _aheadVibranceFxLayer.name = @"AheadVibranceFxLayer";

    _rastaLayer = [CALayer layer];
    _rastaLayer.drawsAsynchronously = YES;
    _rastaLayer.contentsScale = NSViewLayerContentsPlacementScaleProportionallyToFill;
    _rastaLayer.anchorPoint = CGPointMake(0.0, 0.0);
    _rastaLayer.autoresizingMask = kCALayerWidthSizable;
    _rastaLayer.opacity = 0.7;
    _rastaLayer.compositingFilter = [CIFilter filterWithName:@"CISourceAtopCompositing"];
}

- (void)addHead
{
    _aheadVibranceFxLayer.zPosition = kAheadVibrancyLayerZ;
    [self.layer addSublayer:_aheadVibranceFxLayer];

    _headLayer.zPosition = kHeadLayerZ;
    [self.layer addSublayer:_headLayer];

    _rastaLayer.zPosition = kRastaLayerZ;
    [self.layer addSublayer:_rastaLayer];

    _headBloomFxLayer.zPosition = kHeadBloomFxLayerZ;
    [self.layer addSublayer:_headBloomFxLayer];
}

- (void)addMarkers
{
    _markLayer.zPosition = kMarkerLayerZ;
    [self.layer addSublayer:_markLayer];
}

- (void)setupHead
{
    NSImage* image = [NSImage imageNamed:@"TotalCurrentTime"];
    image.resizingMode = NSImageResizingModeTile;
    
    CGFloat height = floor(self.bounds.size.height);

    _headImageSize = image.size;

    _aheadVibranceFxLayer.bounds = CGRectMake(0.0, 0.0, self.bounds.size.width, self.bounds.size.height);
    _aheadVibranceFxLayer.position = CGPointMake(floor(_headImageSize.width / 2.0f), 0.0);
    _aheadVibranceFxLayer.mask = [CAShapeLayer MaskLayerFromRect:_aheadVibranceFxLayer.bounds];

    _headLayer.contents = image;
    _headLayer.frame = CGRectMake(0.0, 0.0, floor(image.size.width), height);

    _headBloomFxLayer.frame = CGRectMake(0.0, 0.0, 5.0, height);
    _headBloomFxLayer.mask = [CAShapeLayer MaskLayerFromRect:_headBloomFxLayer.frame];
    
    _rastaLayer.backgroundColor = [[NSColor colorWithPatternImage:[NSImage imageNamed:@"RastaPattern"]] CGColor];
    _rastaLayer.frame = self.bounds;
}

- (void)resize
{
    _aheadVibranceFxLayer.bounds = self.bounds;
    // FIXME: We are redoing the mask layer cause all ways of resizing it ended up with rather weird effects.
    _aheadVibranceFxLayer.mask = [CAShapeLayer MaskLayerFromRect:self.bounds];
}

/**
 Set the playheads' horizontal positition on screen.
 */
- (void)setHead:(CGFloat)position
{
    _headLayer.position = CGPointMake(position, _headLayer.position.y);
    _headBloomFxLayer.position = CGPointMake(position, _headBloomFxLayer.position.y);
    _aheadVibranceFxLayer.position = CGPointMake(position + (_headImageSize.width / 2.0f), 0.0);
    _rastaLayer.position = CGPointMake(0, _rastaLayer.position.y);
}

@end

