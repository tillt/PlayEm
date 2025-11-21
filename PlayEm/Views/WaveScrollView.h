//
//  WaveScrollView.h
//  PlayEm
//
//  Created by Till Toenshoff on 8/23/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <AppKit/AppKit.h>

@class WaveViewController;

NS_ASSUME_NONNULL_BEGIN

@interface WaveScrollView : NSScrollView

@property (assign, nonatomic) BOOL horizontal;
@property (weak, nonatomic) WaveViewController*  markLayerController;
@property (assign, nonatomic) NSSize tileSize;

//@property (strong, nonatomic) CALayer* rastaLayer;

//@property (strong, nonatomic) CAShapeLayer* aheadVibranceFxLayerMask;
//@property (strong, nonatomic) CALayer* aheadVibranceFxLayer;
//@property (strong, nonatomic) CALayer* trailBloomFxLayer;

- (NSMutableArray*)reusableViews;
- (void)setHead:(CGFloat)head;
- (void)resize;

- (void)setupHead;
- (void)addHead;


@end

NS_ASSUME_NONNULL_END
