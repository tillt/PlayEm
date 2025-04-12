//
//  TableRowView.m
//  PlayEm
//
//  Created by Till Toenshoff on 08.06.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#import "TableRowView.h"

#import <Foundation/Foundation.h>
#import <Quartz/Quartz.h>
#import <QuartzCore/QuartzCore.h>

#import "TableCellView.h"
#import "CAShapeLayer+Path.h"
#import "Defaults.h"
#import "BeatEvent.h"

static const double kFontSize = 11.0f;
static const CGFloat kSelectionCornerRadius = 5.0;

//#define TABLE_ROW_GLOW  1

typedef enum : NSUInteger {
    RoundedNone = 0,
    RoundedTop = 0x01 << 0,
    RoundedBottom = 0x01 << 1,
} RoundingMask;

@interface TableRowView ()

#ifdef TABLE_ROW_GLOW
@property (nonatomic, strong) CALayer* effectLayer;
#endif
@property (nonatomic, strong) CATextLayer* symbolLayer;

@end

@implementation TableRowView
{
    BOOL _subscribedToBeatTicks;
}

#ifdef TABLE_ROW_GLOW
+ (CIFilter*)sharedBloomFilter
{
    static dispatch_once_t once;
    static CIFilter* sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [CIFilter filterWithName:@"CIBloom"];
        [sharedInstance setDefaults];
        [sharedInstance setValue:[NSNumber numberWithFloat:3.0] forKey: @"inputRadius"];
        [sharedInstance setValue:[NSNumber numberWithFloat:0.8] forKey: @"inputIntensity"];
    });
    return sharedInstance;
}

+ (CIFilter*)sharedColorizeFilter
{
    static dispatch_once_t once;
    static CIFilter* sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [CIFilter filterWithName:@"CIColorControls"];
        [sharedInstance setDefaults];
        [sharedInstance setValue:[NSNumber numberWithFloat:1.5] forKey:@"inputSaturation"];
        [sharedInstance setValue:[NSNumber numberWithFloat:1.0] forKey:@"inputContrast"];
        [sharedInstance setValue:[NSNumber numberWithFloat:0.1] forKey:@"inputBrightness"];
    });
    return sharedInstance;
}
#endif

- (id)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        _subscribedToBeatTicks = NO;
        self.wantsLayer = YES;
        self.clipsToBounds = YES;
        self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawOnSetNeedsDisplay;
    }
    return self;
}

- (CALayer*)makeBackingLayer
{
    CALayer* layer = [CALayer layer];
    layer.masksToBounds = NO;
    layer.autoresizingMask = kCALayerNotSizable;
    layer.frame = self.bounds;
    
    CGRect symbolRect = CGRectMake(0.0, 0.0, self.bounds.size.height, self.bounds.size.height);

    _symbolLayer = [CATextLayer layer];
    _symbolLayer.fontSize = kFontSize;
    _symbolLayer.font =  (__bridge  CFTypeRef)[NSFont systemFontOfSize:kFontSize weight:NSFontWeightMedium];
    _symbolLayer.wrapped = NO;
    _symbolLayer.autoresizingMask = kCALayerNotSizable;
    _symbolLayer.truncationMode = kCATruncationEnd;
    _symbolLayer.allowsEdgeAntialiasing = YES;
    _symbolLayer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
    _symbolLayer.foregroundColor = [[Defaults sharedDefaults] lightBeamColor].CGColor;
    _symbolLayer.frame = NSOffsetRect(NSInsetRect(symbolRect, 0.0, 5.0), 8.0, 0.0);
//    _symbolLayer.drawsAsynchronously = YES;
    [layer addSublayer:_symbolLayer];

#ifdef TABLE_ROW_GLOW
    _effectLayer = [CALayer layer];
    _effectLayer.backgroundFilters = @[ [TableRowView sharedBloomFilter], [TableRowView sharedColorizeFilter] ];
    _effectLayer.anchorPoint = CGPointMake(0.5, 0.5);
    _effectLayer.masksToBounds = NO;
    _effectLayer.autoresizingMask = kCALayerNotSizable;
    _effectLayer.zPosition = 1.9;
    _effectLayer.mask = [CAShapeLayer MaskLayerFromRect:self.bounds];
    _effectLayer.frame = self.bounds;
    _effectLayer.hidden = YES;
    _effectLayer.drawsAsynchronously = YES;
    [layer addSublayer:_effectLayer];
#endif
    return layer;
}

/*
 Draws the selection background in its entirety.
 
 Note how this asserts that any selection block - a continuous set of rows -
 has neatly rounded corners at its outer limits.
 */
- (NSBezierPath*)selectionPathWithRoundingMask:(RoundingMask)rounding
{
    const BOOL roundAtTop = (rounding & RoundedTop) == RoundedTop;
    const BOOL roundAtBottom = (rounding & RoundedBottom) == RoundedBottom;

    const CGFloat tr = roundAtTop ? kSelectionCornerRadius : 0.0;
    const CGFloat tl = roundAtTop ? kSelectionCornerRadius : 0.0;
    const CGFloat br = roundAtBottom ? kSelectionCornerRadius : 0.0;
    const CGFloat bl = roundAtBottom ? kSelectionCornerRadius : 0.0;

    NSRect selectionRect = NSInsetRect(self.bounds, 4.0, 0.0);

    if (roundAtTop) {
        selectionRect = NSMakeRect(selectionRect.origin.x, selectionRect.origin.y + 2.0, selectionRect.size.width, selectionRect.size.height - 2.0);
    }
    if (roundAtBottom) {
        selectionRect = NSMakeRect(selectionRect.origin.x, selectionRect.origin.y, selectionRect.size.width, selectionRect.size.height - 2.0);
    }

    NSBezierPath* path = [NSBezierPath bezierPath];
    
    if (roundAtTop) {
        [path moveToPoint:CGPointMake(selectionRect.origin.x + tl, selectionRect.origin.y)];
        [path lineToPoint:CGPointMake(selectionRect.origin.x + selectionRect.size.width - tr, selectionRect.origin.y)];
        [path appendBezierPathWithArcWithCenter:CGPointMake(selectionRect.origin.x + selectionRect.size.width - tr, selectionRect.origin.y + tr)
                                         radius:tr
                                     startAngle:-90.0
                                       endAngle:0.0
                                      clockwise:NO];
    } else {
        [path moveToPoint:CGPointMake(selectionRect.origin.x, selectionRect.origin.y)];
        [path lineToPoint:CGPointMake(selectionRect.origin.x + selectionRect.size.width, selectionRect.origin.y)];
    }

    if (roundAtBottom) {
        [path lineToPoint:CGPointMake(selectionRect.origin.x + selectionRect.size.width, selectionRect.origin.y + selectionRect.size.height - br)];
        [path appendBezierPathWithArcWithCenter:CGPointMake(selectionRect.origin.x + selectionRect.size.width - br, selectionRect.origin.y + selectionRect.size.height - br)
                                         radius:br
                                     startAngle:0.0
                                       endAngle:90.0
                                      clockwise:NO];

        [path lineToPoint:CGPointMake(selectionRect.origin.x + bl, selectionRect.origin.y + selectionRect.size.height)];
        [path appendBezierPathWithArcWithCenter:CGPointMake(selectionRect.origin.x + bl, selectionRect.origin.y + selectionRect.size.height - bl)
                                         radius:bl
                                     startAngle:90.0
                                       endAngle:180.0
                                      clockwise:NO];
    } else {
        [path lineToPoint:CGPointMake(selectionRect.origin.x + selectionRect.size.width, selectionRect.origin.y + selectionRect.size.height)];
        [path lineToPoint:CGPointMake(selectionRect.origin.x, selectionRect.origin.y + selectionRect.size.height)];
    }

    if (roundAtTop) {
        [path lineToPoint:CGPointMake(selectionRect.origin.x, selectionRect.origin.y + tl)];
        [path appendBezierPathWithArcWithCenter:CGPointMake(selectionRect.origin.x + tl, selectionRect.origin.y + tl)
                                         radius:tl
                                     startAngle:180.0
                                       endAngle:270.0
                                      clockwise:NO];
    } else {
        [path lineToPoint:CGPointMake(selectionRect.origin.x, selectionRect.origin.y)];
    }

    return path;
}

- (void)setExtraState:(ExtraState)extraState
{
    for (int i = 0; i < [self numberOfColumns]; i++) {
        TableCellView* view = [self viewAtColumn:i];
        view.extraState = extraState;
    }

    BOOL needsBeatTicks = NO;

    if ((extraState == kExtraStatePlaying) | (extraState == kExtraStateActive)) {
        if (extraState == kExtraStatePlaying) {
            _symbolLayer.string = @"􀊥";
            needsBeatTicks = YES;
        } else {
            _symbolLayer.string = @"􀊄";
            [_symbolLayer removeAllAnimations];
#ifdef TABLE_ROW_GLOW
            [_effectLayer removeAllAnimations];
#endif
        }
        _symbolLayer.hidden = NO;
    } else {
        _symbolLayer.string = @"";
        _symbolLayer.hidden = YES;
        [_symbolLayer removeAllAnimations];
#ifdef TABLE_ROW_GLOW
        [_effectLayer removeAllAnimations];
#endif
    }

    if (needsBeatTicks && !_subscribedToBeatTicks) {
        // We out to react to beat ticks, subscribe to the notification.
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(beatEffect:)
                                                     name:kBeatTrackedSampleBeatNotification
                                                   object:nil];
        _subscribedToBeatTicks = YES;
    }
    
    if (!needsBeatTicks && _subscribedToBeatTicks) {
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:kBeatTrackedSampleBeatNotification
                                                      object:nil];
        _subscribedToBeatTicks = NO;
    }
}

- (void)drawSelectionInRect:(NSRect)dirtyRect
{
    NSColor* highlighted = [NSColor unemphasizedSelectedTextBackgroundColor];
    NSColor* focussed = [[Defaults sharedDefaults] regularBeamColor];

    NSColor* color = highlighted;

    if (self.isEmphasized) {
        color = focussed;
    }

    [color setFill];
    [color setStroke];

    RoundingMask roundingMask = RoundedNone;

    if (!self.previousRowSelected) {
        roundingMask |= RoundedTop;
    }

    if (!self.nextRowSelected) {
        roundingMask |= RoundedBottom;
    }

    NSBezierPath* path = [self selectionPathWithRoundingMask:roundingMask];

    [path fill];
    [path stroke];
}

- (void)beatEffect:(NSNotification*)notification
{
    const NSDictionary* dict = notification.object;
    const unsigned int style = [dict[kBeatNotificationKeyStyle] intValue];
    const float tempo = [dict[kBeatNotificationKeyTempo] floatValue];
    const float barDuration = 4.0f * 60.0f / tempo;
    
    if ((style & BeatEventStyleBar) == BeatEventStyleBar) {
        // For creating a discrete effect accross the timeline, a keyframe animation is the
        // right thing as it even allows us to animate strings.
        {
            CAKeyframeAnimation* animation = [CAKeyframeAnimation animationWithKeyPath:@"string"];
            animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
            animation.values = @[ @"􀊧", @"􀊥" ];
            animation.fillMode = kCAFillModeBoth;
            [animation setValue:@"barSyncedSymbol" forKey:@"name"];
            animation.removedOnCompletion = NO;
            // We animate throughout an entire bar.
            animation.repeatCount = 2;
            animation.duration = barDuration / 2.0;
            [_symbolLayer addAnimation:animation forKey:@"barSynced"];
        }
    }

#ifdef TABLE_ROW_GLOW
    const BeatEventStyle mask = BeatEventStyleBar | BeatEventStyleAlarm;
    if ((style & mask) == mask) {
        CAKeyframeAnimation* animation = [CAKeyframeAnimation animationWithKeyPath:@"hidden"];
        animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
        animation.values = @[ @(NO), @(YES)];
        animation.fillMode = kCAFillModeBoth;
        [animation setValue:@"barSyncedEffect" forKey:@"name"];
        animation.removedOnCompletion = NO;
        // We animate throughout an entire bar.
        animation.repeatCount = 1;
        animation.duration = barDuration;
        [_effectLayer addAnimation:animation forKey:@"barSynced"];
    }
#endif
}

@end
