//
//  TotalWaveView.m
//  PlayEm
//
//  Created by Till Toenshoff on 14.03.21.
//  Copyright © 2021 Till Toenshoff. All rights reserved.
//

#import "TotalWaveView.h"
#import "TileView.h"

#import <QuartzCore/QuartzCore.h>
#import <CoreImage/CoreImage.h>
#import "Defaults.h"
#import "CAShapeLayer+Path.h"
#import "MarkLayerController.h"

const CGFloat kTotalWaveViewTileWidth = 4.0f;

@interface TotalWaveView ()
@property (strong, nonatomic) CALayer* headLayer;
@property (strong, nonatomic) CALayer* headBloomFxLayer;
@property (strong, nonatomic) CALayer* aheadVibranceFxLayer;
@property (strong, nonatomic) CALayer* tailBloomFxLayer;
@property (strong, nonatomic) CALayer* rastaLayer;
@property (assign, nonatomic) NSSize headImageSize;
@end

@implementation TotalWaveView

- (void)viewDidMoveToSuperview
{
    [super viewDidMoveToSuperview];
    
    self.enclosingScrollView.wantsLayer = YES;
    self.enclosingScrollView.layer = [self makeBackingLayer];
    self.enclosingScrollView.layer.backgroundColor = [[[Defaults sharedDefaults] backColor] CGColor];
    self.layerUsesCoreImageFilters = YES;
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

    _tailBloomFxLayer = [CALayer layer];
    _tailBloomFxLayer.backgroundFilters = @[ tailBloomFilter ];
    _tailBloomFxLayer.anchorPoint = CGPointMake(1.0, 0.0);
    _tailBloomFxLayer.frame = CGRectMake(0.0, 0.0, width, height);
    _tailBloomFxLayer.masksToBounds = NO;
    _tailBloomFxLayer.drawsAsynchronously = YES;
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
    if (_frames == 0LL) {
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
    layer.drawsAsynchronously = YES;
    return layer;
}

- (void)updateTiles
{
    NSMutableArray *viewsToRemove = [[NSMutableArray alloc] init];
    for(NSView* view in self.subviews) {
        [viewsToRemove addObject:view];
    }
    [viewsToRemove makeObjectsPerformSelector:@selector(removeFromSuperview)];
    
    NSSize tileSize = { (CGFloat)kTotalWaveViewTileWidth, self.bounds.size.height };
    NSRect documentVisibleRect = NSMakeRect(0.0, 0.0, self.bounds.size.width, self.bounds.size.height);
    //
    const CGFloat xMin = floor(NSMinX(documentVisibleRect) / tileSize.width) * tileSize.width;
    const CGFloat xMax = xMin + (floor((NSMaxX(documentVisibleRect) - xMin) / tileSize.width) * tileSize.width);
    const CGFloat yMin = floor(NSMinY(documentVisibleRect) / tileSize.height) * tileSize.height;
    const CGFloat yMax = ceil((NSMaxY(documentVisibleRect) - yMin) / tileSize.height) * tileSize.height;
    
    for (CGFloat x = xMin; x < xMax; x += tileSize.width) {
        for (CGFloat y = yMin; y < yMax; y += tileSize.height) {
            NSRect rect = NSMakeRect(x, y, tileSize.width, tileSize.height);
            TileView* v = [[TileView alloc] initWithFrame:rect waveLayerDelegate:_markLayerController];
            v.tileTag = x / tileSize.width;
            [self addSubview:v];
            
            [_markLayerController updateTileView:v];
        }
    }
}

- (TileView*)tileWithTag:(NSInteger)tag
{
    NSIndexSet *indexes = [self.subviews indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL* stop) {
       return ((TileView*)obj).tileTag == tag;
    }];

    if (indexes.count == 0) {
        NSLog(@"no tile with tag %ld found", (long)tag);
        return nil;
    }
    if (indexes.count > 1) {
        NSLog(@"more than one tile with tag %ld found", (long)tag);
        return nil;
    }

    return [self.subviews objectsAtIndexes:indexes][0];
}

- (void)resize
{
    _aheadVibranceFxLayer.bounds = CGRectMake(0.0f,
                                              0.0f,
                                              self.bounds.size.width,
                                              self.bounds.size.height);
    _tailBloomFxLayer.bounds = CGRectMake(0.0f,
                                              0.0f,
                                              self.bounds.size.width,
                                              self.bounds.size.height);
    // FIXME: We are redoing the mask layer cause all ways of resizing it
    // ended up with rather weird effects.
    _aheadVibranceFxLayer.mask = [CAShapeLayer MaskLayerFromRect:_aheadVibranceFxLayer.bounds];
    
    _tailBloomFxLayer.mask = [CAShapeLayer MaskLayerFromRect:_tailBloomFxLayer.bounds];
    
    //[self invalidateBeats];

    [self updateHeadPosition];
    [self updateTiles];
}

- (void)invalidateMarks
{
    for (TileView* view in [[self subviews] reverseObjectEnumerator]) {
        [_markLayerController updateTileView:view];
    }
}

- (void)invalidateBeats
{
    for (TileView* view in [[self subviews] reverseObjectEnumerator]) {
        [_markLayerController updateTileView:view];
    }
}

- (void)invalidateTiles
{
    for (TileView* view in [[self subviews] reverseObjectEnumerator]) {
        [view.waveLayer setNeedsDisplay];
        [_markLayerController updateTileView:view];
    }
}

- (void)setFrames:(unsigned long long)frames
{
    if (_frames == frames) {
        return;
    }
    _frames = frames;
    [self invalidateBeats];
    [self invalidateMarks];
}

@end


