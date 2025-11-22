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
    
    [self.layer addSublayer:wv.aheadVibranceFxLayer];
    [self.layer addSublayer:wv.headLayer];
    [self.layer addSublayer:wv.rastaLayer];
    [self.layer addSublayer:wv.headBloomFxLayer];
    for (CALayer* layer in wv.trailBloomFxLayers) {
        [self.layer addSublayer:layer];
    }
}

- (void)createTrail
{
    WaveView* wv = (WaveView*)self.documentView;

    NSImage* image = [NSImage imageNamed:@"CurrentTime"];

    const unsigned int trailingBloomLayerCount = 3;
    CGSize size = CGSizeMake(floor(image.size.width / (2 * trailingBloomLayerCount)), self.frame.size.height);

    NSMutableArray* list = [NSMutableArray array];
    for (int i = 0; i < trailingBloomLayerCount; i++) {
        CIFilter* bloom = [CIFilter filterWithName:@"CIBloom"];
        [bloom setDefaults];

        NSNumber* radius = [NSNumber numberWithFloat:2.5f + (trailingBloomLayerCount - i)];
        [bloom setValue: radius forKey: @"inputRadius"];
        [bloom setValue: [NSNumber numberWithFloat:((trailingBloomLayerCount - i) * 0.1)] forKey: @"inputIntensity"];
        //[bloom setValue: [NSNumber numberWithFloat:0.5] forKey: @"inputIntensity"];
        
        CALayer* layer = [CALayer layer];
        layer.backgroundFilters = @[bloom];
        layer.drawsAsynchronously = YES;
        layer.autoresizingMask = kCALayerNotSizable;
        //layer.anchorPoint = CGPointMake(0.0, 0.0);
        //layer.bounds = CGRectMake(0.0, 0.0, size.width, size.height);
        //layer.position = CGPointMake((trailingBloomLayerCount - (i + 1)) * size.width, 0.0);
        layer.frame = CGRectMake(image.size.width - ((i + 1) * size.width),
                                 0.0,
                                 size.width,
                                 size.height);
        NSColor* color = nil;
        switch(i) {
            case 0:
                color = [NSColor blueColor];
                break;
            case 1:
                color = [NSColor blackColor];
                break;
            case 2:
                color = [NSColor redColor];
                break;
        }
        
//       layer.backgroundColor = color.CGColor;
        layer.mask = [CAShapeLayer MaskLayerFromRect:layer.bounds];
        layer.masksToBounds = YES;
        layer.zPosition = 3.99 + ((float)i - trailingBloomLayerCount);
        layer.name = [NSString stringWithFormat:@"TrailBloomFxLayer%d", i+1];
        [list addObject:layer];
        NSLog(@"trailbloom layer %@", NSStringFromRect(layer.frame));
    }
    wv.trailBloomFxLayers = list;
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

    const unsigned int trailFragmentWidth = wv.trailBloomFxLayers[0].frame.size.width;
    unsigned int i = 0;
    for (CALayer* layer in wv.trailBloomFxLayers) {
        layer.position = CGPointMake((head + 4.0) - (self.documentVisibleRect.origin.x + (i * trailFragmentWidth)) - (trailFragmentWidth / 2.0), layer.position.y);
        i++;
    }
}

- (void)resize
{
    WaveView* wv = (WaveView*)self.documentView;
    wv.aheadVibranceFxLayer.bounds = self.bounds;
    // FIXME: We are redoing the mask layer cause all ways of resizing it ended up with rather weird effects.
    wv.aheadVibranceFxLayer.mask = [CAShapeLayer MaskLayerFromRect:self.bounds];
}

@end
