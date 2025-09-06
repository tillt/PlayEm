//
//  WaveScrollView.m
//  PlayEm
//
//  Created by Till Toenshoff on 8/23/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import <CoreImage/CoreImage.h>

#import "CAShapeLayer+Path.h"
#import "NSBezierPath+CGPath.h"

#import "WaveScrollView.h"
#import "TileView.h"
#import "LazySample.h"
#import "VisualSample.h"
#import "Defaults.h"

const CGFloat kDirectWaveViewTileWidth = 256.0f;

@interface WaveTileView : TileView
+ (CALayer*)makeOverheadLayer;
@end

@interface WaveScrollView () // Private
@property (nonatomic, strong) NSMutableArray* reusableViews;
- (void)updateTiles;
@end

@implementation WaveScrollView

- (nonnull instancetype)initWithFrame:(CGRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.automaticallyAdjustsContentInsets = NO;
        self.contentInsets = NSEdgeInsetsMake(0.0, 0.0, 0.0, 0.0);
        
        self.backgroundColor = [[Defaults sharedDefaults] backColor];
        
        self.allowsMagnification = NO;
        
        self.horizontal = YES;
        
        self.tileSize = NSMakeSize(kDirectWaveViewTileWidth, self.bounds.size.height);

        CIFilter* vibranceFilter = [CIFilter filterWithName:@"CIColorControls"];
        [vibranceFilter setDefaults];
        [vibranceFilter setValue:[NSNumber numberWithFloat:0.10] forKey:@"inputSaturation"];
        [vibranceFilter setValue:[NSNumber numberWithFloat:0.0001] forKey:@"inputBrightness"];

        CIFilter* darkenFilter = [CIFilter filterWithName:@"CIGammaAdjust"];
        [darkenFilter setDefaults];
        [darkenFilter setValue:[NSNumber numberWithFloat:2.5] forKey:@"inputPower"];
        
        _rastaLayer = [CATiledLayer layer];
        _rastaLayer.backgroundColor = [[NSColor colorWithPatternImage:[NSImage imageNamed:@"LargeRastaPattern"]] CGColor];
        _rastaLayer.contentsScale = NSViewLayerContentsPlacementScaleProportionallyToFill;
        _rastaLayer.anchorPoint = CGPointMake(1.0, 0.0);
        _rastaLayer.autoresizingMask = kCALayerWidthSizable;
        _rastaLayer.frame = NSMakeRect(self.bounds.origin.x,
                                       self.bounds.origin.y,
                                       self.bounds.size.width,
                                       self.bounds.size.height);
        _rastaLayer.zPosition = 1.1;
        _rastaLayer.opacity = 0.7;
        _rastaLayer.compositingFilter = [CIFilter filterWithName:@"CISourceAtopCompositing"];
        
        _aheadVibranceFxLayer = [CATiledLayer layer];
        _aheadVibranceFxLayer.backgroundFilters = @[ darkenFilter, vibranceFilter ];
        _aheadVibranceFxLayer.anchorPoint = CGPointMake(0.0, 0.0);
        // FIXME: This looks weird - why 4?
        _aheadVibranceFxLayer.frame = CGRectMake(0.0, 0.0, self.bounds.size.width * 4, self.bounds.size.height);
        _aheadVibranceFxLayer.masksToBounds = NO;
        _aheadVibranceFxLayer.zPosition = 1.0;
        
        _aheadVibranceFxLayerMask = [CAShapeLayer layer];
        NSRect rect = _aheadVibranceFxLayer.frame;
        _aheadVibranceFxLayerMask.fillRule = kCAFillRuleEvenOdd;
        NSBezierPath* path = [NSBezierPath bezierPath];
        [path appendBezierPathWithRect:rect];
        _aheadVibranceFxLayerMask.path = [NSBezierPath CGPathFromPath:path];
        _aheadVibranceFxLayer.mask = _aheadVibranceFxLayerMask;
        
        CIFilter* trailBloomFilter = [CIFilter filterWithName:@"CIBloom"];
        [trailBloomFilter setDefaults];
        [trailBloomFilter setValue:[NSNumber numberWithFloat:3.0] forKey:@"inputRadius"];
        [trailBloomFilter setValue:[NSNumber numberWithFloat:1.0] forKey:@"inputIntensity"];
        
        _trailBloomFxLayer = [CATiledLayer layer];
        _trailBloomFxLayer.backgroundFilters = @[ trailBloomFilter ];
        _trailBloomFxLayer.anchorPoint = CGPointMake(1.0, 0.0);
        // FIXME: This looks weird - why 4?
        _trailBloomFxLayer.frame = CGRectMake(0.0, 0.0, self.bounds.size.width * 4, self.bounds.size.height);
        _trailBloomFxLayer.masksToBounds = NO;
        _trailBloomFxLayer.zPosition = 1.9;
        _trailBloomFxLayer.name = @"TailBloomFxLayer";
        _trailBloomFxLayer.mask = [CAShapeLayer MaskLayerFromRect:_trailBloomFxLayer.frame];
    }
    return self;
}

- (void)viewDidMoveToSuperview
{
    [super viewDidMoveToSuperview];

    [self.layer addSublayer:_trailBloomFxLayer];
    [self.layer addSublayer:_aheadVibranceFxLayer];
    [self.layer addSublayer:_rastaLayer];
}

- (void)WillStartLiveScroll:(NSNotification*)notification
{
    [(WaveView*)self.documentView updateHeadPositionTransaction];
}

- (void)DidLiveScroll:(NSNotification*)notification
{
    [(WaveView*)self.documentView updateHeadPositionTransaction];
}

- (void)DidEndLiveScroll:(NSNotification*)notification
{
    [(WaveView*)self.documentView updateHeadPositionTransaction];
}

/**
 Should get called whenever the visible tiles could possibly be outdated.
 */
- (void)updateTiles
{
    NSSize tileSize = { kDirectWaveViewTileWidth, self.bounds.size.height };

    NSMutableArray* reusableViews = self.reusableViews;
    NSRect documentVisibleRect = self.documentVisibleRect;
    // Lie to get the last tile invisilbe, always. That way we wont regularly
    // see updates of the right most tile when the scrolling follows playback.
    documentVisibleRect.size.width += tileSize.width;

    const CGFloat xMin = floor(NSMinX(documentVisibleRect) / tileSize.width) * tileSize.width;
    const CGFloat xMax = xMin + (ceil((NSMaxX(documentVisibleRect) - xMin) / tileSize.width) * tileSize.width);
    const CGFloat yMin = floor(NSMinY(documentVisibleRect) / tileSize.height) * tileSize.height;
    const CGFloat yMax = ceil((NSMaxY(documentVisibleRect) - yMin) / tileSize.height) * tileSize.height;

    // Figure out the tile frames we would need to get full coverage and add them to
    // the to-do list.
    NSMutableSet* neededTileFrames = [NSMutableSet set];
    for (CGFloat x = xMin; x < xMax; x += tileSize.width) {
        for (CGFloat y = yMin; y < yMax; y += tileSize.height) {
            NSRect rect = NSMakeRect(x, y, tileSize.width, tileSize.height);
            [neededTileFrames addObject:[NSValue valueWithRect:rect]];
        }
    }
    
    assert(self.documentView != nil);

    // See if we already have subviews that cover these needed frames.
    for (NSView* subview in [[self.documentView subviews] copy]) {
        NSValue* frameRectVal = [NSValue valueWithRect:subview.frame];
        // If we don't need this one any more.
        if (![neededTileFrames containsObject:frameRectVal]) {
            // Then recycle it.
            [reusableViews addObject:subview];
            [subview removeFromSuperview];
        } else {
            // Take this frame rect off the to-do list.
            [neededTileFrames removeObject:frameRectVal];
        }
    }

    // Add needed tiles from the to-do list.
    for (NSValue* neededFrame in neededTileFrames) {
        CALayer* overheadLayer = nil;
        WaveTileView* view = [reusableViews lastObject];
        [reusableViews removeLastObject];

        // Create one if we did not find a reusable one.
        if (nil == view) {
            view = [self createTile];

            overheadLayer = [WaveTileView makeOverheadLayer];
            overheadLayer.delegate = ((WaveView*)self.documentView).beatLayerDelegate;
            [view.layer addSublayer:overheadLayer];
        } else {
            assert(view.layer);
            overheadLayer = view.layer.sublayers[0];
            assert(overheadLayer);
        }

        [self.documentView addSubview:view];

        // Place it and install it.
        view.frame = [neededFrame rectValue];
        view.layer.frame = [neededFrame rectValue];
        overheadLayer.frame = CGRectMake(0.0, 0.0, view.frame.size.width, view.frame.size.height);

        assert(view.layer);
        [view.layer setNeedsDisplay];

        assert(overheadLayer);
        [overheadLayer setNeedsDisplay];
    }
}

- (void)updatedHeadPosition
{
    WaveView* wv = (WaveView*)self.documentView;
    _rastaLayer.frame = NSMakeRect(_rastaLayer.frame.origin.x,
                                   _rastaLayer.frame.origin.y,
                                   self.documentVisibleRect.size.width,
                                   _rastaLayer.frame.size.height);
    if (NSPointInRect(NSMakePoint(wv.head, 1.0f), self.documentVisibleRect)) {
        _aheadVibranceFxLayer.position = CGPointMake(wv.head + 0.0 - self.documentVisibleRect.origin.x, self.bounds.origin.y);
        _trailBloomFxLayer.position = CGPointMake((wv.head + 4.0) - self.documentVisibleRect.origin.x, self.bounds.origin.y);
    } else {
        if (wv.head < self.documentVisibleRect.origin.x) {
            _aheadVibranceFxLayer.position = CGPointMake(self.bounds.origin.x, self.documentVisibleRect.origin.y);
            _trailBloomFxLayer.position = CGPointMake(self.bounds.origin.x, self.documentVisibleRect.origin.y);
        } else {
            _aheadVibranceFxLayer.position = CGPointMake(self.documentVisibleRect.size.width, self.bounds.origin.y);
            _trailBloomFxLayer.position = CGPointMake(self.documentVisibleRect.size.width, self.bounds.origin.y);
        }
    }
}

@end


@implementation WaveTileView

+ (CALayer*)makeOverheadLayer
{
    CALayer* layer = [CALayer layer];
    layer.masksToBounds = NO;
    return layer;
}

@end
