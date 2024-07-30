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
#import "TableCellView.h"
#import "CAShapeLayer+Path.h"
#import "Defaults.h"

static const double kFontSize = 11.0f;

typedef enum : NSUInteger {
    GlowTriggerNone = 0x00,
    GlowTriggerEmphasized = 0x01 << 0,
    GlowTriggerActive = 0x01 << 1,
    GlowTriggerSelected = 0x01 << 2,
} GlowTriggerMask;

typedef enum : NSUInteger {
    RoundedNone = 0,
    RoundedTop = 0x01 << 0,
    RoundedBottom = 0x01 << 1,
} RoundingMask;

@implementation TableRowView
{
    GlowTriggerMask glowTriggerMask;
}

+ (CIFilter*)sharedBloomFilter
{
    static dispatch_once_t once;
    static CIFilter* sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [CIFilter filterWithName:@"CIBloom"];
        [sharedInstance setDefaults];
        [sharedInstance setValue:[NSNumber numberWithFloat:1.5]
                          forKey: @"inputRadius"];
        [sharedInstance setValue:[NSNumber numberWithFloat:0.8]
                          forKey: @"inputIntensity"];
    });
    return sharedInstance;
}

- (id)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.clipsToBounds = YES;
        self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawOnSetNeedsDisplay;
        glowTriggerMask = GlowTriggerNone;
    }
    return self;
}

- (CALayer*)makeBackingLayer
{
    CALayer* layer = [CALayer layer];
    layer.masksToBounds = NO;
    layer.autoresizingMask = kCALayerWidthSizable;
    layer.frame = self.bounds;
    
    CGRect symbolRect = CGRectMake(0.0, 0.0, self.bounds.size.height, self.bounds.size.height);

    _symbolLayer = [CATextLayer layer];
    _symbolLayer.fontSize = kFontSize;
    _symbolLayer.font =  (__bridge  CFTypeRef)[NSFont systemFontOfSize:kFontSize weight:NSFontWeightMedium];
    _symbolLayer.wrapped = NO;
    _symbolLayer.autoresizingMask = kCALayerWidthSizable;
    _symbolLayer.truncationMode = kCATruncationEnd;
    _symbolLayer.allowsEdgeAntialiasing = YES;
    _symbolLayer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
    _symbolLayer.foregroundColor = [[Defaults sharedDefaults] lightBeamColor].CGColor;
    _symbolLayer.frame = NSInsetRect(symbolRect, 5.0, 5.0);
    [layer addSublayer:_symbolLayer];
    
    _effectLayer = [CALayer layer];
    _effectLayer.backgroundFilters = @[ [TableRowView sharedBloomFilter] ];
    _effectLayer.anchorPoint = CGPointMake(0.5, 0.5);
    _effectLayer.masksToBounds = NO;
    _effectLayer.autoresizingMask = kCALayerWidthSizable;
    _effectLayer.zPosition = 1.9;
    _effectLayer.mask = [CAShapeLayer MaskLayerFromRect:self.bounds];
    _effectLayer.frame = self.bounds;
    _effectLayer.hidden = YES;
    [layer addSublayer:_effectLayer];
    
    return layer;
}

- (NSBezierPath*)selectionPathWithRoundingMask:(RoundingMask)rounding
{
    CGFloat radius = 5.0;
    BOOL roundAtTop = (rounding & RoundedTop) == RoundedTop;
    BOOL roundAtBottom = (rounding & RoundedBottom) == RoundedBottom;

    CGFloat tr = roundAtTop ? radius : 0.0;
    CGFloat tl = roundAtTop ? radius : 0.0;
    CGFloat br = roundAtBottom ? radius : 0.0;
    CGFloat bl = roundAtBottom ? radius : 0.0;

    NSRect selectionRect = self.bounds;
    selectionRect = NSMakeRect(selectionRect.origin.x + 4.0, selectionRect.origin.y, selectionRect.size.width - 8.0, selectionRect.size.height);

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

- (void)setSelected:(BOOL)selected
{
    [super setSelected:selected];

    if (selected) {
        [self addGlowReason:GlowTriggerSelected];
    } else {
        [self removeGlowReason:GlowTriggerSelected];
    }
}

- (void)setEmphasized:(BOOL)emphasized
{
    [super setEmphasized:emphasized];

    if (emphasized) {
        [self addGlowReason:GlowTriggerEmphasized];
    } else {
        [self removeGlowReason:GlowTriggerEmphasized];
    }
}

- (void)setExtraState:(ExtraState)extraState
{
    for (int i = 0; i < [self numberOfColumns]; i++) {
        TableCellView* view = [self viewAtColumn:i];
        view.extraState = extraState;
    }
    if ((extraState == kExtraStatePlaying) | (extraState == kExtraStateActive)) {
        if (extraState == kExtraStatePlaying) {
            _symbolLayer.string = @"􀊥";
        } else {
            _symbolLayer.string = @"􀊄";
        }
        [self addGlowReason:GlowTriggerActive];
        _symbolLayer.hidden = NO;
    } else {
        [self removeGlowReason:GlowTriggerActive];
        _symbolLayer.string = @"";
        _symbolLayer.hidden = YES;
    }
    _extraState = extraState;
}

- (void)addGlowReason:(GlowTriggerMask)triggerMask
{
    glowTriggerMask |= triggerMask;
    [self updatedGlow];
}

- (void)removeGlowReason:(GlowTriggerMask)triggerMask
{
    glowTriggerMask &= triggerMask ^ 0xFFFF;
    [self updatedGlow];
}

- (void)updatedGlow
{
    BOOL showGlow = ((glowTriggerMask & (GlowTriggerSelected | GlowTriggerEmphasized)) == (GlowTriggerSelected | GlowTriggerEmphasized))
                    | ((glowTriggerMask & GlowTriggerActive) == GlowTriggerActive);
    _effectLayer.hidden = !showGlow;
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

- (CAAnimationGroup*)effectAnimation
{
    CAAnimationGroup* upGroup = [CAAnimationGroup animation];
    NSMutableArray* animations = [NSMutableArray array];

    CABasicAnimation* animation = [CABasicAnimation animationWithKeyPath:@"backgroundFilters.CIBloom.inputRadius"];
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    animation.fromValue = [NSNumber numberWithFloat:3.5];
    animation.toValue = [NSNumber numberWithFloat:1.0];
    animation.fillMode = kCAFillModeBoth;
    animation.removedOnCompletion = NO;
    [animation setValue:@"ActiveAnimationUp" forKey:@"name"];

    [animations addObject:animation];

    upGroup.removedOnCompletion = NO;
    upGroup.duration = 0.2;
    upGroup.animations = animations;

    CAAnimationGroup* downGroup = [CAAnimationGroup animation];
    animations = [NSMutableArray array];

    animation = [CABasicAnimation animationWithKeyPath:@"backgroundFilters.CIBloom.inputRadius"];
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    animation.fromValue = [NSNumber numberWithFloat:1.0];
    animation.toValue = [NSNumber numberWithFloat:3.5];
    animation.fillMode = kCAFillModeBoth;
    animation.removedOnCompletion = NO;

    [animations addObject:animation];

    downGroup.removedOnCompletion = NO;
    downGroup.duration = 1.8;
    downGroup.animations = animations;
    [downGroup setValue:@"ActiveAnimationDown" forKey:@"name"];

    CAAnimationGroup* group = [CAAnimationGroup animation];
    animations = [NSMutableArray array];

    [animations addObject:upGroup];
    [animations addObject:downGroup];

    group.removedOnCompletion = NO;
    group.animations = animations;
    group.repeatCount = HUGE_VALF;
    [group setValue:@"EffectActiveAnimations" forKey:@"name"];

    return group;
}


@end
