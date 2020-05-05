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

@interface WaveView ()
- (void)updateHeadPosition;
@end


@interface WaveTileView : NSView
@end


@interface WaveTileView ()
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
    [vibranceFilter setValue:[NSNumber numberWithFloat:0.1] forKey:@"inputSaturation"];
    [vibranceFilter setValue:[NSNumber numberWithFloat:0.001] forKey:@"inputBrightness"];
    
    CIFilter* darkenFilter = [CIFilter filterWithName:@"CIGammaAdjust"];
    [darkenFilter setDefaults];
    [darkenFilter setValue:[NSNumber numberWithFloat:2.5] forKey:@"inputPower"];
    
    //    CIFilter* postFilter = [CIFilter filterWithName:@"CILineOverlay"];
    //    [postFilter setDefaults];
    //    [postFilter setValue:[NSNumber numberWithFloat:0.1] forKey:@"inputThreshold"];
    //    [postFilter setValue:[NSNumber numberWithFloat:0.4] forKey:@"inputEdgeIntensity"];
    
    //    [postFilter setValue:[NSNumber numberWithFloat:1.0] forKey:@"inputContrast"];
    
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
    _trailBloomFxLayer.frame = CGRectMake(0.0, 0.0, width * 4, height);
    _trailBloomFxLayer.masksToBounds = NO;
    _trailBloomFxLayer.zPosition = 1.9;
    _trailBloomFxLayer.name = @"TailBloomFxLayer";
    _trailBloomFxLayer.mask = [CAShapeLayer MaskLayerFromRect:_trailBloomFxLayer.frame];

//    CIFilter* motionBlur = [CIFilter filterWithName:@"CIMotionBlur"];
//    [motionBlur setDefaults];
//    [motionBlur setValue:[NSNumber numberWithFloat:3.0] forKey:@"inputRadius"];
//    [motionBlur setValue:[NSNumber numberWithFloat:0.0] forKey:@"inputAngle"];
    
//    CALayer* layer = [CALayer layer];
//    layer.backgroundFilters = @[ motionBlur ];
//    layer.anchorPoint = CGPointMake(1.0, 0.0);
//    layer.frame = CGRectMake(0.0, 0.0, width * 4, height);
//    layer.masksToBounds = NO;
//    layer.zPosition = 1.9;
//    layer.name = @"MotionBlur";
//    layer.mask = [CAShapeLayer MaskLayerFromRect:layer.frame];
//
//    [self.layer addSublayer:layer];

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
        WaveTileView* view = [reusableViews lastObject];
        [reusableViews removeLastObject];

        // Create one if we did not find a reusable one.
        if (nil == view) {
            view = [[WaveTileView alloc] initWithFrame:NSZeroRect];
        }

        // Place it and install it.
        view.frame = [neededFrame rectValue];
        //view.layer.transform = CATransform3DMakeScale(1.0, 0.1, 1.0);

        [self.documentView addSubview:view];

    }
}

- (void)updatedHeadPosition
{
    CGFloat head = ((WaveView*)self.documentView).head;
    if (NSPointInRect(NSMakePoint(head, 1.0f), self.documentVisibleRect)) {
        _aheadVibranceFxLayer.position = CGPointMake(head + 4.0 - self.documentVisibleRect.origin.x, 0.0f);
        _trailBloomFxLayer.position = CGPointMake((head - 4.0) - self.documentVisibleRect.origin.x, 0.0f);
        _rastaLayer.frame = NSMakeRect(_rastaLayer.frame.origin.x,
                                       _rastaLayer.frame.origin.y,
                                       floor(head - self.documentVisibleRect.origin.x),
                                       _rastaLayer.frame.size.height);
        _rastaLayer.position = CGPointMake(head - self.documentVisibleRect.origin.x, 0.0f);
    } else {
        if (head < self.documentVisibleRect.origin.x) {
            _aheadVibranceFxLayer.position = CGPointMake(0.0f, 0.0f);
            _trailBloomFxLayer.position = CGPointMake(0.0f, 0.0f);
            _rastaLayer.frame = NSMakeRect(_rastaLayer.frame.origin.x,
                                           _rastaLayer.frame.origin.y,
                                           self.documentView.frame.size.width,
                                           _rastaLayer.frame.size.height);
            _rastaLayer.position = CGPointMake(0, 0);
        } else {
            _aheadVibranceFxLayer.position = CGPointMake(self.documentVisibleRect.size.width, 0.0f);
            _trailBloomFxLayer.position = CGPointMake(self.documentVisibleRect.size.width, 0.0f);
            _rastaLayer.frame = NSMakeRect(_rastaLayer.frame.origin.x,
                                           _rastaLayer.frame.origin.y,
                                           self.documentView.frame.size.width,
                                           _rastaLayer.frame.size.height);
            _rastaLayer.position = CGPointMake(self.documentVisibleRect.size.width, 0.0f);
        }
    }
}

@end


@interface WaveView () // Private

@property (strong, nonatomic) NSArray* trailBloomFxLayers;
@property (nonatomic, assign) BOOL followTime;
@property (nonatomic, assign) BOOL userMomentum;

@end

@implementation WaveView

- (void)viewDidMoveToSuperview
{
    [super viewDidMoveToSuperview];
    
    self.wantsLayer = YES;
    self.layer = [self makeBackingLayer];
    self.layer.masksToBounds = NO;

    _headLayer = [CALayer layer];
    
    NSImage* image = [NSImage imageNamed:@"CurrentTime"];
    image.resizingMode = NSImageResizingModeTile;
    
    CIFilter* clampFilter = [CIFilter filterWithName:@"CIAffineClamp"];
    [clampFilter setDefaults];

    //CGFloat scaleFactor = 1.15;
    CGFloat scaleFactor = 1.05;

    CGAffineTransform transform = CGAffineTransformScale(CGAffineTransformMakeTranslation(0.0, self.enclosingScrollView.bounds.size.height * -(scaleFactor - 1.0) / 2.0), 1.0, scaleFactor);
    [clampFilter setValue:[NSValue valueWithBytes:&transform objCType:@encode(CGAffineTransform)] forKey:@"inputTransform"];

    CIFilter* clampFilter2 = [CIFilter filterWithName:@"CIAffineClamp"];
    [clampFilter2 setDefaults];

    CIFilter* bloomFilter = [CIFilter filterWithName:@"CIBloom"];
    [bloomFilter setDefaults];
    [bloomFilter setValue: [NSNumber numberWithFloat:7.0] forKey: @"inputRadius"];
    [bloomFilter setValue: [NSNumber numberWithFloat:1.0] forKey: @"inputIntensity"];

    CIFilter* headFilter = [CIFilter filterWithName:@"CISourceAtopCompositing"];
    [headFilter setDefaults];

    CGFloat height = self.enclosingScrollView.bounds.size.height;
    
    _headLayer.contents = image;
    _headImageSize = image.size;
    _headLayer.anchorPoint = CGPointMake(0.5, 0.0);
    _headLayer.frame = CGRectMake(0.0, 0.0, _headImageSize.width, height);
    _headLayer.compositingFilter = [CIFilter filterWithName:@"CISourceAtopCompositing"];
    _headLayer.zPosition = 1.1;
    _headLayer.name = @"HeadLayer";

    _headBloomFxLayer = [CALayer layer];
    _headBloomFxLayer.backgroundFilters = @[ clampFilter, bloomFilter ];
    _headBloomFxLayer.anchorPoint = CGPointMake(0.5, 0.0);
    _headBloomFxLayer.frame = CGRectMake(0.0, 0.0, 5.0, height);
    _headBloomFxLayer.masksToBounds = NO;
    _headBloomFxLayer.zPosition = 1.9;
    _headBloomFxLayer.name = @"HeadBloomFxLayer";
    _headBloomFxLayer.mask = [CAShapeLayer MaskLayerFromRect:_headBloomFxLayer.frame];

    [self.layer addSublayer:_headLayer];
    [self.layer addSublayer:_headBloomFxLayer];

    const unsigned int layerCount = 3;
    NSMutableArray* layers = [NSMutableArray array];
    for (int i = 0; i < layerCount; i++) {
        CIFilter* bloom = [CIFilter filterWithName:@"CIBloom"];
        [bloom setDefaults];
        [bloom setValue: [NSNumber numberWithFloat:(float)(2+layerCount-i) * 1.0] forKey: @"inputRadius"];
        [bloom setValue: [NSNumber numberWithFloat:1.0] forKey: @"inputIntensity"];

        CALayer* layer = [CALayer layer];
        layer.backgroundFilters = @[ bloom ];
        layer.anchorPoint = CGPointMake(1.0, 0.0);
        layer.frame = CGRectMake(0.0, 0.0, floor(_headImageSize.width / (2 * layerCount)), height);
        layer.masksToBounds = NO;
        layer.zPosition = 1.99;
        layer.name = [NSString stringWithFormat:@"TrailBloomFxLayer%d", i+1];
        layer.mask = [CAShapeLayer MaskLayerFromRect:layer.frame];
        [layers addObject:layer];

        [self.layer addSublayer:layer];
    }
    _trailBloomFxLayers = [layers copy];

    _followTime = YES;
    _userMomentum = NO;
}

- (void)dealloc
{
}

- (void)rightMouseDown:(NSEvent*)event
{
    _followTime = YES;
    [self updateScrollingState];
}

- (void)addSubview:(NSView*)view
{
    view.layer = [view makeBackingLayer];
    //view.layerContentsRedrawPolicy = NSViewLayerContentsRedrawOnSetNeedsDisplay;

    [super addSubview:view];
    
    view.layer.delegate = self.layerDelegate;
    [view.layer setNeedsDisplay];
}

- (CALayer*)makeBackingLayer
{
    CALayer* layer = [CALayer layer];
    return layer;
}

- (void)setFrames:(unsigned long long)frames
{
    if (_frames == frames) {
        return;
    }
    _frames = frames;
    for (WaveTileView* view in [self subviews]) {
        view.layer.delegate = self.layerDelegate;
        [view.layer setNeedsDisplay];
    }
    self.currentFrame = 0;
}

- (void)layout
{
    [super layout];
    [self updateHeadPosition];
}

- (void)updateHeadPosition
{
    if (_frames == 0.0) {
        return;
    }
    
    _head = ( _currentFrame * self.bounds.size.width) / _frames;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    _headLayer.position = CGPointMake(_head, 0.0);
    _headBloomFxLayer.position = CGPointMake(_head, 0.0);
    
    CGFloat x = 0;
    for (CALayer* layer in _trailBloomFxLayers) {
        layer.position = CGPointMake((_head - 2.0) - x, 0.0);
        x += layer.frame.size.width;
    }

    [(TiledScrollView*)self.enclosingScrollView updatedHeadPosition];
    [CATransaction commit];
}

- (void)setCurrentFrame:(unsigned long long)frame
{
    if (_currentFrame == frame) {
        return;
    }
    if (_frames == 0.0) {
        return;
    }
    _currentFrame = frame;
    
    [self updateScrollingState];
}

- (void)updateScrollingState
{
    CGFloat head = (_currentFrame * self.bounds.size.width) / _frames;
   
    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    if (_followTime) {
        [self scrollRectToVisible:CGRectMake(floor(head - (self.enclosingScrollView.bounds.size.width / 2.0)),
                                             0.0,
                                             self.enclosingScrollView.bounds.size.width,
                                             self.bounds.size.height)];
    } else {
        // If the user has just requested some scrolling, do not interfere but wait
        // as long as that state is up.
        if (!_userMomentum) {
            // If the head came back into the middle of the screen, snap back to following
            // time with the scrollview.
            const CGFloat delta = 1.0f;
            CGFloat visibleCenter = self.enclosingScrollView.documentVisibleRect.origin.x + (self.enclosingScrollView.documentVisibleRect.size.width / 2.0f);
            if (visibleCenter - delta <= head && visibleCenter + delta >= head) {
                _followTime = YES;
            }
        }
    }
    [self updateHeadPosition];
    [CATransaction commit];
}

- (void)userInitiatedScrolling
{
    _userMomentum = YES;
    _followTime = NO;
}

- (void)userEndsScrolling
{
    _userMomentum = NO;
}

@end


@implementation WaveTileView


- (CALayer*)makeBackingLayer
{
    CALayer* layer = [CALayer layer];
    return layer;
}

- (BOOL)wantsLayer
{
    return YES;
}

@end
