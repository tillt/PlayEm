//
//  WaveView.h
//  PlayEm
//
//  Created by Till Toenshoff on 16.08.23.
//  Copyright © 2023 Till Toenshoff. All rights reserved.
//

#ifndef WaveView_h
#define WaveView_h

#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

/// WaveView is the document view of the entire sample file.
@interface WaveView : NSView

@property (assign, nonatomic) unsigned long long frames;
@property (strong, nonatomic) NSColor* color;
@property (assign, nonatomic) CGSize headImageSize;
@property (strong, nonatomic) CALayer* headLayer;
@property (strong, nonatomic) CALayer* headBloomFxLayer;
@property (strong, nonatomic) NSArray<CALayer*>* trailBloomFxLayers;
//@property (strong, nonatomic) CALayer* trailBloomHostLayer;
@property (strong, nonatomic) CIFilter* headFx;
@property (strong, nonatomic) CALayer* aheadVibranceFxLayer;
@property (strong, nonatomic) CALayer* rastaLayer;

- (void)setHead:(CGFloat)position;
- (void)resize;

- (void)createHead;
- (void)createTrail;
- (void)setupHead;
- (void)addHead;
@end

#endif /* WaveView_h */
