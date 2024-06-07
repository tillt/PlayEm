//
//  AudioController.h
//  PlayEm
//
//  Created by Till Toenshoff on 30.05.20.
//  Copyright © 2020 Till Toenshoff. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

extern const unsigned int kPlaybackBufferFrames;
extern const unsigned int kPlaybackBufferCount;

@class LazySample;

@protocol AudioControllerDelegate <NSObject>

- (void)audioControllerPlaybackStarted;
- (void)audioControllerPlaybackPaused;
- (void)audioControllerPlaybackPlaying;
- (void)audioControllerPlaybackEnded;

@end

typedef void (^TapBlock) (unsigned long long, float*, unsigned int);

@interface AudioController : NSObject

@property (nonatomic, weak) id<AudioControllerDelegate> delegate;
@property (nonatomic, strong) LazySample* sample;
@property (nonatomic, assign) AVAudioFramePosition currentFrame;

@property (nonatomic, assign) double outputVolume;

@property (nonatomic, assign, readonly) int64_t currentOffset;
@property (nonatomic, assign, readonly) BOOL playing;
@property (nonatomic, assign, readonly) BOOL paused;

@property (nonatomic, assign) double tempoShift;

- (id)init;
- (void)playPause;
- (void)playWhenReady:(unsigned long long)nextFrame paused:(BOOL)paused;
- (void)startTapping:(TapBlock)tap;
- (void)stopTapping;

@end

NS_ASSUME_NONNULL_END
