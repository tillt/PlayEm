//
//  TiledScrollView.m
//  PlayEm
//
//  Created by Till Toenshoff on 05.12.20.
//  Copyright © 2020 Till Toenshoff. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>
#import <CoreImage/CoreImage.h>

#import "TiledScrollView.h"
#import "Sample.h"
#import "VisualSample.h"
#import "CAShapeLayer+Path.h"
#import "NSBezierPath+CGPath.h"
#import "Scroller.h"
#import "Defaults.h"

const CGFloat kDirectWaveViewTileWidth = 256.0f;

@interface TiledScrollView () // Private
@property (nonatomic, strong) NSMutableArray* reusableViews;
- (void)updateTiles;
@end

@interface WaveTileView : NSView
- (CALayer*)makeOverheadLayer;
@end

@implementation TiledScrollView

- (void)viewDidMoveToSuperview
{
    [super viewDidMoveToSuperview];
    
    self.automaticallyAdjustsContentInsets = NO;
    self.contentInsets = NSEdgeInsetsMake(0.0, 0.0, 0.0, 0.0);
    
    self.backgroundColor = [[Defaults sharedDefaults] backColor];
    
    self.allowsMagnification = NO;
    
    Scroller* scroller = [Scroller new];
    scroller.color = [NSColor redColor];
    self.horizontalScroller = scroller;
    
    self.wantsLayer = YES;
    self.layer = [self makeBackingLayer];
    self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawOnSetNeedsDisplay;
    self.layer.masksToBounds = NO;
    
    CGFloat width = self.bounds.size.width;
    CGFloat height = self.bounds.size.height;
    
    CIFilter* vibranceFilter = [CIFilter filterWithName:@"CIColorControls"];
    [vibranceFilter setDefaults];
    [vibranceFilter setValue:[NSNumber numberWithFloat:0.10] forKey:@"inputSaturation"];
    [vibranceFilter setValue:[NSNumber numberWithFloat:0.0001] forKey:@"inputBrightness"];

    CIFilter* darkenFilter = [CIFilter filterWithName:@"CIGammaAdjust"];
    [darkenFilter setDefaults];
    [darkenFilter setValue:[NSNumber numberWithFloat:2.5] forKey:@"inputPower"];
    
    _rastaLayer = [CALayer layer];
    _rastaLayer.backgroundColor = [[NSColor colorWithPatternImage:[NSImage imageNamed:@"LargeRastaPattern"]] CGColor];
    _rastaLayer.contentsScale = NSViewLayerContentsPlacementScaleProportionallyToFill;
    _rastaLayer.anchorPoint = CGPointMake(1.0, 0.0);
    _rastaLayer.frame = NSMakeRect(0.0,
                                   0.0,
                                   self.bounds.size.width,
                                   self.bounds.size.height);
    _rastaLayer.zPosition = 1.1;
    _rastaLayer.opacity = 0.7;
    _rastaLayer.compositingFilter = [CIFilter filterWithName:@"CISourceAtopCompositing"];
    
    _aheadVibranceFxLayer = [CALayer layer];
    _aheadVibranceFxLayer.backgroundFilters = @[ darkenFilter, vibranceFilter ];
    _aheadVibranceFxLayer.anchorPoint = CGPointMake(0.0, 0.0);
    // FIXME: This looks weird - why 4?
    _aheadVibranceFxLayer.frame = CGRectMake(0.0, 0.0, width * 4, height);
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
    
    _trailBloomFxLayer = [CALayer layer];
    _trailBloomFxLayer.backgroundFilters = @[ trailBloomFilter ];
    _trailBloomFxLayer.anchorPoint = CGPointMake(1.0, 0.0);
    // FIXME: This looks weird - why 4?
    _trailBloomFxLayer.frame = CGRectMake(0.0, 0.0, width * 4, height);
    _trailBloomFxLayer.masksToBounds = NO;
    _trailBloomFxLayer.zPosition = 1.9;
    _trailBloomFxLayer.name = @"TailBloomFxLayer";
    _trailBloomFxLayer.mask = [CAShapeLayer MaskLayerFromRect:_trailBloomFxLayer.frame];

    [self.layer addSublayer:_trailBloomFxLayer];
    [self.layer addSublayer:_aheadVibranceFxLayer];
    [self.layer addSublayer:_rastaLayer];

    [self updateTiles];
    
    [[NSNotificationCenter defaultCenter]
       addObserver:self
          selector:@selector(WillStartLiveScroll:)
              name:NSScrollViewWillStartLiveScrollNotification
            object:self];
    [[NSNotificationCenter defaultCenter]
       addObserver:self
          selector:@selector(DidLiveScroll:)
              name:NSScrollViewDidLiveScrollNotification
            object:self];
    [[NSNotificationCenter defaultCenter]
       addObserver:self
          selector:@selector(DidEndLiveScroll:)
              name:NSScrollViewDidEndLiveScrollNotification
            object:self];
}

- (void)WillStartLiveScroll:(NSNotification*)notification
{
    [(WaveView*)self.documentView updateHeadPosition];
}

- (void)DidLiveScroll:(NSNotification*)notification
{
    [(WaveView*)self.documentView updateHeadPosition];
}

- (void)DidEndLiveScroll:(NSNotification*)notification
{
    [(WaveView*)self.documentView updateHeadPosition];
}

- (NSMutableArray*)reusableViews
{
    if (_reusableViews == nil) {
        _reusableViews = [NSMutableArray array];
    }
    return _reusableViews;
}

- (void)reflectScrolledClipView:(NSClipView *)view
{
    [super reflectScrolledClipView:view];
    [self updateTiles];
}

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
            view = [[WaveTileView alloc] initWithFrame:NSZeroRect];
            view.layerContentsRedrawPolicy = NSViewLayerContentsRedrawOnSetNeedsDisplay;
            view.layer = [view makeBackingLayer];
            view.layer.delegate = ((WaveView*)self.documentView).waveLayerDelegate;

            overheadLayer = [view makeOverheadLayer];
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
    CGFloat head = ((WaveView*)self.documentView).head;
    _rastaLayer.frame = NSMakeRect(_rastaLayer.frame.origin.x,
                                   _rastaLayer.frame.origin.y,
                                   self.documentVisibleRect.size.width,
                                   _rastaLayer.frame.size.height);
    if (NSPointInRect(NSMakePoint(head, 1.0f), self.documentVisibleRect)) {
        _aheadVibranceFxLayer.position = CGPointMake(head + 0.0 - self.documentVisibleRect.origin.x, 0.0f);
        _trailBloomFxLayer.position = CGPointMake((head + 4.0) - self.documentVisibleRect.origin.x, 0.0f);
    } else {
        if (head < self.documentVisibleRect.origin.x) {
            _aheadVibranceFxLayer.position = CGPointMake(0.0f, 0.0f);
            _trailBloomFxLayer.position = CGPointMake(0.0f, 0.0f);
        } else {
            _aheadVibranceFxLayer.position = CGPointMake(self.documentVisibleRect.size.width, 0.0f);
            _trailBloomFxLayer.position = CGPointMake(self.documentVisibleRect.size.width, 0.0f);
        }
    }
}

@end


@implementation WaveTileView

- (CALayer*)makeOverheadLayer
{
    CALayer* layer = [CALayer layer];
    layer.masksToBounds = NO;
    return layer;
}

- (CALayer*)makeBackingLayer
{
    CALayer* layer = [CALayer layer];
    layer.masksToBounds = NO;
    return layer;
}

- (BOOL)wantsLayer
{
    return YES;
}

@end
