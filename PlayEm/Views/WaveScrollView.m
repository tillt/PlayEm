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


#import "Scroller.h"
#import "WaveScrollView.h"
#import "WaveView.h"
#import "TileView.h"
#import "LazySample.h"
#import "VisualSample.h"
#import "Defaults.h"
#import "WaveViewController.h"

static const CGFloat kRastaLayerZ = 0.5;
static const CGFloat kAheadVibrancyLayerZ = 0.1;
static const CGFloat kHeadLayerZ = 0.2;
static const CGFloat kHeadBloomFxLayerZ = 1.2;
static const CGFloat kTrailLayerZ = 1.4;

@interface WaveScrollView () // Private
@end

@implementation WaveScrollView

- (nonnull instancetype)initWithFrame:(CGRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        Scroller* scroller = [Scroller new];
        scroller.color = [NSColor redColor];
        self.horizontalScroller = scroller;
        
        self.wantsLayer = YES;
        self.layerUsesCoreImageFilters = YES;
        self.layer = [self makeBackingLayer];
        self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawOnSetNeedsDisplay;
//        self.layer.backgroundColor = [[NSColor blueColor] CGColor];
        self.automaticallyAdjustsContentInsets = NO;
        self.contentInsets = NSEdgeInsetsMake(0.0, 0.0, 0.0, 0.0);
        
        self.backgroundColor = [[Defaults sharedDefaults] backColor];
        
        self.allowsMagnification = NO;
        self.canDrawConcurrently = YES;
        
        self.horizontal = YES;
    }
    return self;
}

- (void)addHead
{
    WaveView* wv = (WaveView*)self.documentView;
    
    wv.aheadVibranceFxLayer.zPosition = kAheadVibrancyLayerZ;

    [self.layer addSublayer:wv.aheadVibranceFxLayer];
    wv.headLayer.zPosition = kHeadLayerZ;
    [self.layer addSublayer:wv.headLayer];
    wv.rastaLayer.zPosition = kRastaLayerZ;
    [self.layer addSublayer:wv.rastaLayer];
    wv.headBloomFxLayer.zPosition = kHeadBloomFxLayerZ;
    [self.layer addSublayer:wv.headBloomFxLayer];
    wv.trailBloomHFxLayer.zPosition = kTrailLayerZ;
    [self.layer addSublayer:wv.trailBloomHFxLayer];
  }

- (void)createTrail
{
    WaveView* wv = (WaveView*)self.documentView;

    NSImage* image = [NSImage imageNamed:@"CurrentTime"];


    CGSize size = CGSizeMake(image.size.width, self.frame.size.height);
    
    CALayer* mask = [CALayer layer];
    mask.contents = [NSImage imageNamed:@"SquareFadeMask"];
    mask.frame = CGRectMake(0.0, 0.0, size.width, size.height);
    mask.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    mask.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
    mask.allowsEdgeAntialiasing = YES;
    mask.magnificationFilter = kCAFilterLinear;
    mask.minificationFilter = kCAFilterLinear;
    
    CIFilter* lightenFilter = [CIFilter filterWithName:@"CIColorControls"];
    [lightenFilter setDefaults];
    [lightenFilter setValue:[NSNumber numberWithFloat:5.5] forKey:@"inputSaturation"];
    [lightenFilter setValue:[NSNumber numberWithFloat:0.3] forKey:@"inputBrightness"];

    CIFilter* bloom = [CIFilter filterWithName:@"CIBloom"];
    [bloom setDefaults];

    //NSNumber* radius = [NSNumber numberWithFloat:3.5f + (trailingBloomLayerCount - i)];
    NSNumber* radius = [NSNumber numberWithFloat:12.0f];
    [bloom setValue: radius forKey: @"inputRadius"];
    [bloom setValue: [NSNumber numberWithFloat:1.0f] forKey: @"inputIntensity"];
    //[bloom setValue: [NSNumber numberWithFloat:0.5] forKey: @"inputIntensity"];
    
    wv.trailBloomHFxLayer = [CALayer layer];
   wv.trailBloomHFxLayer.backgroundFilters = @[bloom, bloom, lightenFilter];
    wv.trailBloomHFxLayer.drawsAsynchronously = YES;
    wv.trailBloomHFxLayer.autoresizingMask = kCALayerNotSizable;
    wv.trailBloomHFxLayer.mask = mask;
    //layer.zPosition = 5.0;
    //layer.anchorPoint = CGPointMake(0.0, 0.0);
    //layer.bounds = CGRectMake(0.0, 0.0, size.width, size.height);
    //layer.position = CGPointMake((trailingBloomLayerCount - (i + 1)) * size.width, 0.0);
//    wv.trailBloomHFxLayer.backgroundColor = [NSColor redColor].CGColor;
    wv.trailBloomHFxLayer.frame = CGRectMake(image.size.width - size.width,
                                             0.0,
                                             size.width,
                                             size.height);
    wv.trailBloomHFxLayer.masksToBounds = YES;
    wv.trailBloomHFxLayer.zPosition = 3.99;
}

- (void)setupHead
{
    WaveView* wv = (WaveView*)self.documentView;

    NSImage* image = [NSImage imageNamed:@"CurrentTime"];
    image.resizingMode = NSImageResizingModeTile;

    wv.headLayer.contents = image;
    wv.headImageSize = image.size;

    wv.headLayer.frame = CGRectMake(0.0, 0.0, image.size.width, self.bounds.size.height);
    
    wv.aheadVibranceFxLayer.bounds = self.bounds;
    wv.aheadVibranceFxLayer.position = CGPointMake(0.0, 0.0);
    wv.aheadVibranceFxLayer.mask = [CAShapeLayer MaskLayerFromRect:self.bounds];

    wv.headBloomFxLayer.frame = CGRectMake(0.0, 0.0, 5.0, self.bounds.size.height);
    wv.headBloomFxLayer.mask = [CAShapeLayer MaskLayerFromRect:wv.headBloomFxLayer.bounds];

    wv.rastaLayer.backgroundColor = [[NSColor colorWithPatternImage:[NSImage imageNamed:@"LargeRastaPattern"]] CGColor];
    wv.rastaLayer.frame = self.bounds;
}

- (void)setHead:(CGFloat)head
{
    WaveView* wv = (WaveView*)self.documentView;

    // Check if head position is within visible window. When the head is prior to the visible
    // window, we know all display is covered by a vibrance reduced wave. When the head is
    // past the visible window, all displayed is covered by the fully colored variant.
    if (NSPointInRect(NSMakePoint(head, 1.0f), self.documentVisibleRect)) {
        wv.aheadVibranceFxLayer.position = CGPointMake(head + 0.0 - self.documentVisibleRect.origin.x, self.bounds.origin.y);
    } else {
        if (head < self.documentVisibleRect.origin.x) {
            wv.aheadVibranceFxLayer.position = CGPointMake(self.bounds.origin.x, self.documentVisibleRect.origin.y);
        } else {
            wv.aheadVibranceFxLayer.position = CGPointMake(self.documentVisibleRect.size.width, self.bounds.origin.y);
        }
    }
    wv.headBloomFxLayer.position = CGPointMake(head + 0.0 - self.documentVisibleRect.origin.x, wv.headBloomFxLayer.position.y);
    wv.headLayer.position = CGPointMake(head + 0.0 - self.documentVisibleRect.origin.x, wv.headLayer.position.y);
    //wv.rastaLayer.position = CGPointMake(0, wv.rastaLayer.position.y);

    const unsigned int trailFragmentWidth = wv.trailBloomHFxLayer.frame.size.width;
    wv.trailBloomHFxLayer.position = CGPointMake((head + 4.0) - (self.documentVisibleRect.origin.x) - (trailFragmentWidth / 2.0), wv.trailBloomHFxLayer.position.y);
}

- (void)resize
{
    WaveView* wv = (WaveView*)self.documentView;
    wv.aheadVibranceFxLayer.bounds = self.bounds;
    // FIXME: We are redoing the mask layer cause all ways of resizing it ended up with rather weird effects.
    wv.aheadVibranceFxLayer.mask = [CAShapeLayer MaskLayerFromRect:self.bounds];
}

@end
