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

@interface WaveView ()

@property (assign, nonatomic) CGSize headImageSize;

@property (strong, nonatomic) CALayer* headLayer;
@property (strong, nonatomic) CALayer* headBloomFxLayer;
@property (strong, nonatomic) NSArray* trailBloomFxLayers;
@property (strong, nonatomic) CIFilter* headFx;
@property (strong, nonatomic) CALayer* aheadVibranceFxLayer;
@property (strong, nonatomic) CALayer* rastaLayer;

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
    }
    return self;
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


    if (self.enclosingScrollView == nil) {
        [self setupHeadForTotalConfig];
    } else {
        [self setupHeadForScrollConfig];
    }
}

- (void)dealloc
{
}

- (BOOL)wantsLayer
{
    return YES;
}
//
//- (BOOL)wantsUpdateLayer
//{
//    return YES;
//}

- (CALayer*)makeBackingLayer
{
    CALayer* layer = [CALayer layer];
    layer.drawsAsynchronously = YES;
    return layer;
}

- (void)resize
{
    if (self.enclosingScrollView != nil) {
        [self.enclosingScrollView performSelector:@selector(resize)];
        return;
    }

    _aheadVibranceFxLayer.bounds = CGRectMake(0.0f,
                                              0.0f,
                                              self.bounds.size.width,
                                              self.bounds.size.height);
//    _trailBloomFxLayer.bounds = CGRectMake(0.0f,
//                                              0.0f,
//                                              self.bounds.size.width,
//                                              self.bounds.size.height);
    // FIXME: We are redoing the mask layer cause all ways of resizing it
    // ended up with rather weird effects.
    _aheadVibranceFxLayer.mask = [CAShapeLayer MaskLayerFromRect:_aheadVibranceFxLayer.bounds];
    
//    _trailBloomFxLayer.mask = [CAShapeLayer MaskLayerFromRect:_tailBloomFxLayer.bounds];
    
    //[self invalidateBeats];

//    [self updateHeadPosition];
}

/**
 Set the playheads' horizontal positition on screen.
 */
- (void)setHead:(CGFloat)position
{
    _headLayer.position = CGPointMake(position, _headLayer.position.y);
    _headBloomFxLayer.position = CGPointMake(position, _headBloomFxLayer.position.y);
    _aheadVibranceFxLayer.position = CGPointMake(position + (_headImageSize.width / 2.0f), 0.0);

    _rastaLayer.frame = NSMakeRect(0.0, 0.0, floor(position), _rastaLayer.bounds.size.height);

    _rastaLayer.position = CGPointMake(floor(position), 0.0);
    //_trailBloomFxLayer.position = CGPointMake(position - (_headImageSize.width / 2.0f), 0.0);

    CGFloat x = 0.0;
    CGFloat offset = 0.0;
    for (CALayer* layer in _trailBloomFxLayers) {
        layer.position = CGPointMake((position + offset) - x, 0.0);
        x += layer.frame.size.width + 1.0;
    }
}

//- (void)setHead:(CGFloat)head
//{
//    [CATransaction begin];
//    [CATransaction setValue:(id)kCFBooleanTrue forKey:kCATransactionDisableActions];
//    _headBloomFxLayer.position = CGPointMake(head, _headBloomFxLayer.position.y);
//    _headLayer.position = CGPointMake(head, _headLayer.position.y);
//
//
//    _rastaLayer.frame = NSMakeRect(0.0, 0.0, floor(head), _rastaLayer.bounds.size.height);
//
//    _rastaLayer.position = CGPointMake(floor(head), 0.0);
//    _tailBloomFxLayer.position = CGPointMake(head - (_headImageSize.width / 2.0f), 0.0);
//
//    [CATransaction commit];
//}

- (void)setupHeadForScrollConfig
{
    _headLayer = [self makeHeadLayer];

    NSImage* image = [NSImage imageNamed:@"CurrentTime"];
    image.resizingMode = NSImageResizingModeTile;

    CGFloat height = floor(self.enclosingScrollView.bounds.size.height);

    _headLayer.contents = image;
    _headLayer.compositingFilter = [CIFilter filterWithName:@"CISourceAtopCompositing"];
    _headImageSize = image.size;
    _headLayer.frame = CGRectMake(0.0, 0.0, floor(_headImageSize.width), height);
    [self.layer addSublayer:_headLayer];

    CIFilter* clampFilter = [CIFilter filterWithName:@"CIAffineClamp"];
    [clampFilter setDefaults];
    CGFloat scaleFactor = 1.15;
    CGAffineTransform transform = CGAffineTransformScale(CGAffineTransformMakeTranslation(0.0, self.enclosingScrollView.bounds.size.height * -(scaleFactor - 1.0) / 2.0), 1.0, scaleFactor);
    [clampFilter setValue:[NSValue valueWithBytes:&transform objCType:@encode(CGAffineTransform)] forKey:@"inputTransform"];
    
    CIFilter* bloomFilter = [CIFilter filterWithName:@"CIBloom"];
    [bloomFilter setDefaults];
    [bloomFilter setValue: [NSNumber numberWithFloat:9.0] forKey: @"inputRadius"];
    [bloomFilter setValue: [NSNumber numberWithFloat:1.5] forKey: @"inputIntensity"];

    _headBloomFxLayer = [self makeHeadBloomFxLayer];
    _headBloomFxLayer.backgroundFilters = @[ clampFilter, bloomFilter ];
    _headBloomFxLayer.frame = CGRectMake(0.0, 0.0, 5.0, height);
    _headBloomFxLayer.mask = [CAShapeLayer MaskLayerFromRect:_headBloomFxLayer.frame];
    [self.layer addSublayer:_headBloomFxLayer];
    
    const unsigned int trailingBloomLayerCount = 3;
    NSMutableArray* layers = [NSMutableArray array];
    for (int i = 0; i < trailingBloomLayerCount; i++) {
        CIFilter* bloom = [CIFilter filterWithName:@"CIBloom"];
        [bloom setDefaults];
        [bloom setValue: [NSNumber numberWithFloat:(float)(2.5 + trailingBloomLayerCount - i) * 1.0]
                 forKey: @"inputRadius"];
        //[bloom setValue: [NSNumber numberWithFloat:1.0 + ((trailingBloomLayerCount - i) * 0.1)] forKey: @"inputIntensity"];
        [bloom setValue: [NSNumber numberWithFloat:1.0]
                 forKey: @"inputIntensity"];
        
        CALayer* layer = [CALayer layer];
        layer.backgroundFilters = @[ bloom ];
        layer.drawsAsynchronously = YES;
        layer.anchorPoint = CGPointMake(1.0, 0.0);
        layer.frame = CGRectMake(0.0, 0.0, floor(_headImageSize.width / (2 * trailingBloomLayerCount)), height);
        layer.masksToBounds = YES;
        layer.zPosition = 3.99 + ((float)i - trailingBloomLayerCount);
        layer.name = [NSString stringWithFormat:@"TrailBloomFxLayer%d", i+1];
        layer.mask = [CAShapeLayer MaskLayerFromRect:layer.frame];
        [layers addObject:layer];
        
        [self.layer addSublayer:layer];
    }
    //_trailBloomFxLayers = [layers copy];
    _trailBloomFxLayers = layers;
}

- (void)setupHeadForTotalConfig
{
    _headLayer = [CALayer layer];
    
    NSImage* image = [NSImage imageNamed:@"TinyTotalCurrentTime"];
    image.resizingMode = NSImageResizingModeTile;
    
    CIFilter* clampFilter = [CIFilter filterWithName:@"CIAffineClamp"];
    [clampFilter setDefaults];

    CGFloat scaleFactor = 1.05;

    CGAffineTransform transform = CGAffineTransformScale(CGAffineTransformMakeTranslation(0.0, self.bounds.size.height * -(scaleFactor - 1.0) / 2.0), 1.0, scaleFactor);
    [clampFilter setValue:[NSValue valueWithBytes:&transform objCType:@encode(CGAffineTransform)] forKey:@"inputTransform"];

    CIFilter* headBloomFilter = [CIFilter filterWithName:@"CIBloom"];
    [headBloomFilter setDefaults];
    [headBloomFilter setValue: [NSNumber numberWithFloat:8.0] forKey: @"inputRadius"];
    [headBloomFilter setValue: [NSNumber numberWithFloat:1.0] forKey: @"inputIntensity"];

    CGFloat height = self.bounds.size.height;
    CGFloat width = self.bounds.size.width;

    CIFilter* vibranceFilter = [CIFilter filterWithName:@"CIColorControls"];
    [vibranceFilter setDefaults];
    [vibranceFilter setValue:[NSNumber numberWithFloat:0.1] forKey:@"inputSaturation"];
    [vibranceFilter setValue:[NSNumber numberWithFloat:0.001] forKey:@"inputBrightness"];

    CIFilter* darkenFilter = [CIFilter filterWithName:@"CIGammaAdjust"];
    [darkenFilter setDefaults];
    [darkenFilter setValue:[NSNumber numberWithFloat:2.5] forKey:@"inputPower"];

    _headLayer.contents = image;
    _headImageSize = image.size;
    _headLayer.drawsAsynchronously = YES;
    _headLayer.bounds = CGRectMake(0.0, 0.0, _headImageSize.width, height);
    _headLayer.position = CGPointMake(0.0, height / 2.0f);
    _headLayer.compositingFilter = [CIFilter filterWithName:@"CISourceAtopCompositing"];
    _headLayer.zPosition = 1.0;
    _headLayer.name = @"HeadLayer";

    _headBloomFxLayer = [CALayer layer];
    _headBloomFxLayer.backgroundFilters = @[ clampFilter, headBloomFilter ];
    _headBloomFxLayer.frame = _headLayer.bounds;
    _headBloomFxLayer.drawsAsynchronously = YES;
    _headBloomFxLayer.masksToBounds = NO;
    _headBloomFxLayer.zPosition = 1.9;
    _headBloomFxLayer.name = @"HeadBloomFxLayer";
    _headBloomFxLayer.mask = [CAShapeLayer MaskLayerFromRect:_headBloomFxLayer.frame];
    
    _aheadVibranceFxLayer = [CALayer layer];
    _aheadVibranceFxLayer.drawsAsynchronously = YES;
    _aheadVibranceFxLayer.backgroundFilters = @[ darkenFilter, vibranceFilter ];
    _aheadVibranceFxLayer.anchorPoint = CGPointMake(0.0, 0.0);
    _aheadVibranceFxLayer.bounds = CGRectMake(0.0, 0.0, width, height);
    _aheadVibranceFxLayer.position = CGPointMake(_headImageSize.width / 2.0f, 0.0);
    _aheadVibranceFxLayer.masksToBounds = NO;
    _aheadVibranceFxLayer.zPosition = 1.0;
    _aheadVibranceFxLayer.name = @"AheadVibranceFxLayer";
    _aheadVibranceFxLayer.mask = [CAShapeLayer MaskLayerFromRect:_aheadVibranceFxLayer.frame];
    
    _rastaLayer = [CALayer layer];
    _rastaLayer.backgroundColor = [[NSColor colorWithPatternImage:[NSImage imageNamed:@"RastaPattern"]] CGColor];
    _rastaLayer.autoresizingMask = kCALayerNotSizable;
    _rastaLayer.contentsScale = NSViewLayerContentsPlacementScaleProportionallyToFill;
    _rastaLayer.anchorPoint = CGPointMake(1.0, 0.0);
    _rastaLayer.opacity = 0.8f;
    _rastaLayer.drawsAsynchronously = YES;
    _rastaLayer.frame = NSMakeRect(0.0,
                                   0.0,
                                   self.bounds.size.width,
                                   self.bounds.size.height);
    _rastaLayer.zPosition = 1.1;
    _rastaLayer.compositingFilter = [CIFilter filterWithName:@"CISourceAtopCompositing"];

    CIFilter* tailBloomFilter = [CIFilter filterWithName:@"CIBloom"];
    [tailBloomFilter setDefaults];
    [tailBloomFilter setValue: [NSNumber numberWithFloat:3.0] forKey: @"inputRadius"];
    [tailBloomFilter setValue: [NSNumber numberWithFloat:1.0] forKey: @"inputIntensity"];

    
    CALayer* layer = [CALayer layer];
    layer.backgroundFilters = @[ tailBloomFilter ];
    layer.anchorPoint = CGPointMake(1.0, 0.0);
    layer.frame = CGRectMake(0.0, 0.0, width, height);
    layer.masksToBounds = NO;
    layer.drawsAsynchronously = YES;
    layer.zPosition = 1.9;
    layer.name = @"TailBloomFxLayer";
    layer.mask = [CAShapeLayer MaskLayerFromRect:layer.frame];
    _trailBloomFxLayers = @[layer];

    [self.layer addSublayer:_aheadVibranceFxLayer];
    [self.layer addSublayer:_headLayer];
    [self.layer addSublayer:_headBloomFxLayer];
    [self.layer addSublayer:layer];
    [self.layer addSublayer:_rastaLayer];
}

@end

