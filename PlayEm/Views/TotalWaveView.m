//
//  TotalWaveView.m
//  PlayEm
//
//  Created by Till Toenshoff on 14.03.21.
//  Copyright © 2021 Till Toenshoff. All rights reserved.
//

#import "TotalWaveView.h"

#import <QuartzCore/QuartzCore.h>
#import <CoreImage/CoreImage.h>
#import "Defaults.h"
#import "CAShapeLayer+Path.h"

const CGFloat kTotalWaveViewTileWidth = 8.0f;

@interface TileView : NSView
@property (readwrite, nonatomic) NSInteger tag;
@end

@interface TotalWaveView ()
@property (strong, nonatomic) CALayer* headLayer;
@property (strong, nonatomic) CALayer* headBloomFxLayer;
@property (strong, nonatomic) CALayer* aheadVibranceFxLayer;
@property (strong, nonatomic) CALayer* tailBloomFxLayer;
@property (strong, nonatomic) CALayer* rastaLayer;
//@property (strong, nonatomic) CAShapeLayer* aheadVibranceFxLayerMask;
@property (assign, nonatomic) NSSize headImageSize;
@end

@implementation TotalWaveView

- (void)viewDidMoveToSuperview
{
    [super viewDidMoveToSuperview];
    
    self.enclosingScrollView.wantsLayer = YES;
    self.enclosingScrollView.layer = [self makeBackingLayer];
    self.enclosingScrollView.layer.backgroundColor = [[[Defaults sharedDefaults] backColor] CGColor];
    
    self.wantsLayer = YES;
    self.layer = [self makeBackingLayer];
    
    self.layer.allowsEdgeAntialiasing = YES;

    [self updateTiles];
    [self setupHead];
}

- (void)setupHead
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
    _headLayer.bounds = CGRectMake(0.0, 0.0, _headImageSize.width, height);
    _headLayer.position = CGPointMake(0.0, height / 2.0f);
    _headLayer.compositingFilter = [CIFilter filterWithName:@"CISourceAtopCompositing"];
    _headLayer.zPosition = 1.0;
    _headLayer.name = @"HeadLayer";

    _headBloomFxLayer = [CALayer layer];
    _headBloomFxLayer.backgroundFilters = @[ clampFilter, headBloomFilter ];
    _headBloomFxLayer.frame = _headLayer.bounds;
    _headBloomFxLayer.masksToBounds = NO;
    _headBloomFxLayer.zPosition = 1.9;
    _headBloomFxLayer.name = @"HeadBloomFxLayer";
    _headBloomFxLayer.mask = [CAShapeLayer MaskLayerFromRect:_headBloomFxLayer.frame];
    
    _aheadVibranceFxLayer = [CALayer layer];
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
    _rastaLayer.contentsScale = NSViewLayerContentsPlacementScaleProportionallyToFill;
    _rastaLayer.anchorPoint = CGPointMake(1.0, 0.0);
    _rastaLayer.opacity = 0.8f;
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

    _tailBloomFxLayer = [CALayer layer];
    _tailBloomFxLayer.backgroundFilters = @[ tailBloomFilter ];
    _tailBloomFxLayer.anchorPoint = CGPointMake(1.0, 0.0);
    _tailBloomFxLayer.frame = CGRectMake(0.0, 0.0, width, height);
    _tailBloomFxLayer.masksToBounds = NO;
    _tailBloomFxLayer.zPosition = 1.9;
    _tailBloomFxLayer.name = @"TailBloomFxLayer";
    _tailBloomFxLayer.mask = [CAShapeLayer MaskLayerFromRect:_tailBloomFxLayer.frame];

    [self.layer addSublayer:_aheadVibranceFxLayer];
    [self.layer addSublayer:_headLayer];
    [self.layer addSublayer:_headBloomFxLayer];
    [self.layer addSublayer:_tailBloomFxLayer];
    [self.layer addSublayer:_rastaLayer];
}

- (void)updateHeadPosition
{
    if (_frames == 0.0) {
        return;
    }
    
    CGFloat head = 0.5f + (_currentFrame * self.bounds.size.width) / _frames;

    [CATransaction begin];
    [CATransaction setValue:(id)kCFBooleanTrue forKey:kCATransactionDisableActions];
    _headBloomFxLayer.position = CGPointMake(head, _headBloomFxLayer.position.y);
    _headLayer.position = CGPointMake(head, _headLayer.position.y);
    _aheadVibranceFxLayer.position = CGPointMake(head + (_headImageSize.width / 2.0f), 0.0);

    _rastaLayer.frame = NSMakeRect(0.0, 0.0, floor(head), _rastaLayer.bounds.size.height);

    _rastaLayer.position = CGPointMake(floor(head), 0.0);
    _tailBloomFxLayer.position = CGPointMake(head - (_headImageSize.width / 2.0f), 0.0);

    [CATransaction commit];
}

- (void)setCurrentFrame:(unsigned long long)frame
{
    if (_currentFrame == frame) {
        return;
    }

    _currentFrame = frame;
    [self updateHeadPosition];
}

- (CALayer*)makeBackingLayer
{
    CALayer* layer = [CALayer layer];
    return layer;
}

- (void)updateTiles
{
    NSSize tileSize = { (CGFloat)kTotalWaveViewTileWidth, self.bounds.size.height };

    NSRect documentVisibleRect = self.bounds;
//
    const CGFloat xMin = floor(NSMinX(documentVisibleRect) / tileSize.width) * tileSize.width;
    const CGFloat xMax = xMin + (floor((NSMaxX(documentVisibleRect) - xMin) / tileSize.width) * tileSize.width);
    const CGFloat yMin = floor(NSMinY(documentVisibleRect) / tileSize.height) * tileSize.height;
    const CGFloat yMax = ceil((NSMaxY(documentVisibleRect) - yMin) / tileSize.height) * tileSize.height;

    NSMutableArray<TileView*>* sv = [NSMutableArray array];
    for (CGFloat x = xMin; x < xMax; x += tileSize.width) {
        for (CGFloat y = yMin; y < yMax; y += tileSize.height) {
            NSRect rect = NSMakeRect(x, y, tileSize.width, tileSize.height);
            //NSLog(@"rect %@", NSStringFromRect(rect));
            TileView* v = [[TileView alloc] initWithFrame:rect];
            //[v setValue:[NSString stringWithFormat:@"%dx%d", x / tileSize.width, y / tileSize.height] forKey:@""]
            v.tag = x / tileSize.width;
            v.layer.delegate = self.layerDelegate;
            [v.layer setNeedsDisplay];
            [sv addObject:v];
        }
    }
    for (NSView* v in [sv reverseObjectEnumerator]) {
        [self addSubview:v];
        [v.layer setNeedsDisplay];
    }
}

- (void)addSubview:(NSView*)view
{
    view.layer = [view makeBackingLayer];
    view.layerContentsRedrawPolicy = NSViewLayerContentsRedrawOnSetNeedsDisplay;
    //[view.layer setValue:[NSNumber numberWithBool:YES] forKey:@"isTotalView"];

    [super addSubview:view];
    
    view.layer.delegate = self.layerDelegate;
    [view.layer setNeedsDisplay];
}

- (void)resize
{
    _aheadVibranceFxLayer.bounds = CGRectMake(0.0f,
                                              0.0f,
                                              self.bounds.size.width,
                                              self.bounds.size.height);
    // FIXME: We are redoing the mask layer cause all ways of resizing it
    // ended up with rather weird effects.
    _aheadVibranceFxLayer.mask = [CAShapeLayer MaskLayerFromRect:_aheadVibranceFxLayer.bounds];
    
    [self updateHeadPosition];

    NSSize tileSize = { (CGFloat)kTotalWaveViewTileWidth, self.bounds.size.height };

    NSRect documentVisibleRect = self.bounds;

    const CGFloat xMin = floor(NSMinX(documentVisibleRect) / tileSize.width) * tileSize.width;
    const CGFloat xMax = xMin + (ceil((NSMaxX(documentVisibleRect) - xMin) / tileSize.width) * tileSize.width);
    const CGFloat yMin = floor(NSMinY(documentVisibleRect) / tileSize.height) * tileSize.height;
    const CGFloat yMax = ceil((NSMaxY(documentVisibleRect) - yMin) / tileSize.height) * tileSize.height;

    NSMutableArray* sv = [NSMutableArray array];
    for (CGFloat x = xMin; x < xMax; x += tileSize.width) {
        for (CGFloat y = yMin; y < yMax; y += tileSize.height) {
            NSInteger tag = x / tileSize.width;
            if ([self viewWithTag:tag] == nil) {
                NSLog(@"needs a new one for %ld", tag);
                NSRect rect = NSMakeRect(x, y, tileSize.width, tileSize.height);
                TileView* v = [[TileView alloc] initWithFrame:rect];
                v.layer.delegate = self.layerDelegate;
                v.tag = tag;
                [v.layer setNeedsDisplay];
                [sv addObject:v];
            } else {
                NSLog(@"view %ld found", tag);
            }
        }
    }
    for (NSView* v in [sv reverseObjectEnumerator]) {
        [self addSubview:v];
    }
}

- (void)refresh
{
    for (TileView* view in [[self subviews] reverseObjectEnumerator]) {
        [view.layer setNeedsDisplay];
    }
    [self setNeedsDisplay:YES];
}

@end


@implementation TileView

@synthesize tag;


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
