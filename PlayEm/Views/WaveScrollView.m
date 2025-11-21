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
    [self.layer addSublayer:wv.trailBloomHostLayer];
}

- (void)createTrail
{
    WaveView* wv = (WaveView*)self.documentView;

    NSImage* image = [NSImage imageNamed:@"CurrentTime"];

    wv.trailBloomHostLayer = [CALayer new];
    //wv.trailBloomHostLayer.backgroundColor = [NSColor redColor].CGColor;
    wv.trailBloomHostLayer.drawsAsynchronously = YES;
    wv.trailBloomHostLayer.autoresizingMask = kCALayerHeightSizable;
    wv.trailBloomHostLayer.masksToBounds = NO;
    wv.trailBloomHostLayer.zPosition = 1.0;
    wv.trailBloomHostLayer.name = @"TrailBloomHostLayer";
    wv.trailBloomHostLayer.anchorPoint = CGPointMake(1.0, 0.0);
    wv.trailBloomHostLayer.bounds = CGRectMake(0.0, 0.0, image.size.width, self.frame.size.height);
    //wv.trailBloomHostLayer.hidden = YES;
    const unsigned int trailingBloomLayerCount = 3;
    CGSize size = CGSizeMake(floor(image.size.width / (2 * trailingBloomLayerCount)), self.frame.size.height);

    for (int i = 0; i < trailingBloomLayerCount; i++) {
        CIFilter* bloom = [CIFilter filterWithName:@"CIBloom"];
        [bloom setDefaults];
        //NSNumber* radius = [NSNumber numberWithFloat:(float)(2.5 + trailingBloomLayerCount - i) * 1.0];
        NSNumber* radius = [NSNumber numberWithFloat:(float)(2.5 + trailingBloomLayerCount - i) * 3.0];
        [bloom setValue: radius forKey: @"inputRadius"];
        //[bloom setValue: [NSNumber numberWithFloat:1.0 + ((trailingBloomLayerCount - i) * 0.1)] forKey: @"inputIntensity"];
        [bloom setValue: [NSNumber numberWithFloat:3.0] forKey: @"inputIntensity"];
        
        CALayer* layer = [CALayer layer];
        layer.backgroundFilters = @[ bloom ];
        layer.drawsAsynchronously = YES;
        layer.autoresizingMask = kCALayerNotSizable;
        //layer.anchorPoint = CGPointMake(0.0, 0.0);
        //layer.bounds = CGRectMake(0.0, 0.0, size.width, size.height);
        //layer.position = CGPointMake((trailingBloomLayerCount - (i + 1)) * size.width, 0.0);
        layer.frame = CGRectMake(wv.trailBloomHostLayer.bounds.size.width - ((i + 1) * size.width), 0.0, size.width, size.height);
        NSColor* color = nil;
        switch(i) {
            case 0:
                color = [NSColor redColor];
                break;
            case 1:
                color = [NSColor greenColor];
                break;
            case 2:
                color = [NSColor blueColor];
                break;
        }
        
        //layer.backgroundColor = color.CGColor;
        layer.mask = [CAShapeLayer MaskLayerFromRect:layer.bounds];
        layer.masksToBounds = YES;
        //layer.zPosition = 3.99 + ((float)i - trailingBloomLayerCount);
        layer.name = [NSString stringWithFormat:@"TrailBloomFxLayer%d", i+1];
        [wv.trailBloomHostLayer addSublayer:layer];
        NSLog(@"trailbloom layer %@", NSStringFromRect(layer.frame));
    }
    NSLog(@"trailbloom host layer %@", NSStringFromRect(wv.trailBloomHostLayer.frame));
    //_trailBloomFxLayers = layers;
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

    //wv.trailBloomHostLayer.bounds = CGRectMake(0.0, 0.0, image.size.width, self.bounds.size.height);
    wv.trailBloomHostLayer.position = CGPointMake(0.0, 0.0);

//    const unsigned int trailFragmentWidth = floor(image.size.width / (2 * wv.trailBloomFxLayers.count));
//    for (CALayer* layer in wv.trailBloomFxLayers) {
//        layer.frame = CGRectMake(0.0, 0.0, trailFragmentWidth, height);
//        NSLog(@"trailing layee %@", NSStringFromRect(layer.frame));
//        layer.mask = [CAShapeLayer MaskLayerFromRect:layer.frame];
//    }
    wv.rastaLayer.backgroundColor = [[NSColor colorWithPatternImage:[NSImage imageNamed:@"LargeRastaPattern"]] CGColor];
    wv.rastaLayer.frame = self.bounds;
}
//
//- (void)setupHead
//{
//    WaveView* wv = (WaveView*)self.documentView;
//
//    NSImage* image = [NSImage imageNamed:@"CurrentTime"];
//    image.resizingMode = NSImageResizingModeTile;
//
//    CGFloat height = floor(self.bounds.size.height);
//
//    wv.headLayer.contents = image;
//    wv.headImageSize = image.size;
//    wv.headLayer.frame = CGRectMake(0.0, 0.0, floor(image.size.width), height);
//    wv.headBloomFxLayer.frame = CGRectMake(0.0, 0.0, 5.0, height);
//    wv.headBloomFxLayer.mask = [CAShapeLayer MaskLayerFromRect:wv.headBloomFxLayer.frame];
//    
//    const unsigned int trailingBloomLayerCount = 3;
//    NSMutableArray* layers = [NSMutableArray array];
//    for (int i = 0; i < trailingBloomLayerCount; i++) {
//        CIFilter* bloom = [CIFilter filterWithName:@"CIBloom"];
//        [bloom setDefaults];
//        [bloom setValue: [NSNumber numberWithFloat:(float)(2.5 + trailingBloomLayerCount - i) * 1.0]
//                 forKey: @"inputRadius"];
//        //[bloom setValue: [NSNumber numberWithFloat:1.0 + ((trailingBloomLayerCount - i) * 0.1)] forKey: @"inputIntensity"];
//        [bloom setValue: [NSNumber numberWithFloat:1.0]
//                 forKey: @"inputIntensity"];
//        
//        CALayer* layer = [CALayer layer];
//        layer.backgroundFilters = @[ bloom ];
//        layer.drawsAsynchronously = YES;
//        layer.anchorPoint = CGPointMake(1.0, 0.0);
//        layer.frame = CGRectMake(0.0, 0.0, floor(image.size.width / (2 * trailingBloomLayerCount)), height);
//        layer.masksToBounds = YES;
//        layer.zPosition = 3.99 + ((float)i - trailingBloomLayerCount);
//        layer.name = [NSString stringWithFormat:@"TrailBloomFxLayer%d", i+1];
//        layer.mask = [CAShapeLayer MaskLayerFromRect:layer.frame];
//        [layers addObject:layer];
//    }
//    wv.trailBloomFxLayers = layers;
//}

//- (void)updateHeadPosition:(CGFloat)head
//{
//    _headBloomFxLayer.position = CGPointMake(head, _headBloomFxLayer.position.y);
//    _headLayer.position = CGPointMake(head, _headLayer.position.y);
//    _aheadVibranceFxLayer.position = CGPointMake(head + (_headImageSize.width / 2.0f), 0.0);
//
//    _rastaLayer.frame = NSMakeRect(0.0, 0.0, floor(head), _rastaLayer.bounds.size.height);
//
//    _rastaLayer.position = CGPointMake(floor(head), 0.0);
//    _tailBloomFxLayer.position = CGPointMake(head - (_headImageSize.width / 2.0f), 0.0);
//}


- (void)setHead:(CGFloat)head
{
    WaveView* wv = (WaveView*)self.documentView;

//    _rastaLayer.frame = NSMakeRect(0.0, 0.0, floor(position), _rastaLayer.bounds.size.height);
//    _rastaLayer.position = CGPointMake(floor(position), 0.0);

    //wv.tailBloomFxLayer.position = CGPointMake(head - (_headImageSize.width / 2.0f), 0.0);

    
//    wv.rastaLayer.frame = NSMakeRect(   wv.rastaLayer.frame.origin.x,
//                                        wv.rastaLayer.frame.origin.y,
//                                        self.documentVisibleRect.size.width,
//                                        wv.rastaLayer.frame.size.height);

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
    wv.trailBloomHostLayer.position = CGPointMake((head + 4.0) - self.documentVisibleRect.origin.x, 0.0);
    //wv.aheadVibranceFxLayer.position = CGPointMake(head + (wv.headImageSize.width / 2.0f), 0.0);

    //wv.rastaLayer.position = CGPointMake(floor(head)  + 0.0 - self.documentVisibleRect.origin.x, 0.0);
    // wv.rastaLayer.position = CGPointMake(0, wv.rastaLayer.position.y);
    //wv.headLayer.hidden = NO;
}

- (void)resize
{
    WaveView* wv = (WaveView*)self.documentView;
    CGRect rect = CGRectMake(0.0f,
                             0.0f,
                             self.bounds.size.width,
                             self.bounds.size.height);
    wv.aheadVibranceFxLayer.bounds = rect;
    // FIXME: We are redoing the mask layer cause all ways of resizing it
    // ended up with rather weird effects.
    wv.aheadVibranceFxLayer.mask = [CAShapeLayer MaskLayerFromRect:rect];
}

@end
