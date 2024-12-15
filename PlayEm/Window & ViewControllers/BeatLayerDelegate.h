//
//  BeatLayerDelegate.h
//  PlayEm
//
//  Created by Till Toenshoff on 13.08.23.
//  Copyright © 2023 Till Toenshoff. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

NS_ASSUME_NONNULL_BEGIN
@class BeatTrackedSample;
@class WaveView;

@interface BeatLayerDelegate : NSObject <CALayerDelegate>

@property (strong, nonatomic) WaveView* waveView;
@property (strong, nonatomic, nullable) BeatTrackedSample* beatSample;
@property (assign, nonatomic) double framesPerPixel;

@end

NS_ASSUME_NONNULL_END
