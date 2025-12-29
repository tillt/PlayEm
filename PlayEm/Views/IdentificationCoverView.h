//
//  IdentificationActiveView.h
//  PlayEm
//
//  Created by Till Toenshoff on 10.06.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

typedef enum : NSUInteger {
    CoverViewStylePumpingToTheBeat = 1 << 1,
    CoverViewStyleSepiaForSecondImageLayer = 1 << 2,
    CoverViewStyleRotatingLaser = 1 << 3,
    CoverViewStyleGlowBehindCoverAtLaser = 1 << 4,
} CoverViewStyleMask;

@interface IdentificationCoverView : NSView <CALayerDelegate>
@property (nonatomic, strong, nullable) NSImage* image;
@property (nonatomic, assign) float overlayIntensity;
@property (nonatomic, assign) float secondImageLayerOpacity;
@property (nonatomic, assign) CoverViewStyleMask style;
@property (nonatomic, strong) CALayer* backingLayer;


- (void)setStill:(BOOL)still animated:(BOOL)animated;

- (void)startAnimating;
- (void)stopAnimating;
- (void)pauseAnimating;
- (void)setImage:(NSImage* _Nullable)image animated:(BOOL)animated;

- (id)initWithFrame:(NSRect)frameRect contentsInsets:(NSEdgeInsets)insets style:(CoverViewStyleMask)style;

@end

NS_ASSUME_NONNULL_END
