//
//  AudioController.h
//  PlayEm
//
//  Created by Till Toenshoff on 30.05.20.
//  Copyright © 2020 Till Toenshoff. All rights reserved.
//

#import <Foundation/Foundation.h>

#import <AVFoundation/AVFoundation.h>

#import "../Sample/SampleFormat.h"
#import "AudioPlaybackBackend.h"
NS_ASSUME_NONNULL_BEGIN

extern const unsigned int kPlaybackBufferFrames;
extern const unsigned int kPlaybackBufferCount;

extern NSString* const kAudioControllerChangedPlaybackStateNotification;
extern NSString* const kPlaybackStateStarted;
extern NSString* const kPlaybackStatePaused;
extern NSString* const kPlaybackStatePlaying;
extern NSString* const kPlaybackStateEnded;

@class LazySample;

typedef void (^TapBlock)(unsigned long long framePosition, float* frameData, unsigned int frameCount);

@interface AudioController : NSObject

@property (nonatomic, assign, readonly) SampleFormat sampleFormat;
@property (nonatomic, assign) AVAudioFramePosition currentFrame;
@property (nonatomic, assign, readonly) NSTimeInterval expectedDuration;
@property (nonatomic, assign) double outputVolume;
@property (nonatomic, assign, readonly) int64_t currentOffset;
@property (nonatomic, assign, readonly) BOOL playing;
@property (nonatomic, assign, readonly) BOOL paused;
@property (nonatomic, assign) float tempoShift;
@property (nonatomic, strong, readonly) NSArray<NSDictionary*>* availableEffects;
@property (nonatomic, assign, readonly) NSInteger currentEffectIndex;

- (instancetype)init;
- (void)togglePause;
- (void)play;
- (void)pause;
- (void)playSample:(LazySample*)sample frame:(unsigned long long)frame paused:(BOOL)paused;
- (void)startTapping:(TapBlock _Nullable)tap;
- (void)stopTapping;
- (NSTimeInterval)currentTime;
- (void)setCurrentTime:(NSTimeInterval)time;
- (LazySample*)sample;
- (void)decodeAsyncWithSample:(LazySample*)sample callback:(void (^)(BOOL))callback;
- (void)decodeAbortWithCallback:(void (^)(void))callback;
- (AVAudioFramePosition)totalLatency;
- (AVAudioFramePosition)frameCountDeltaWithTimeDelta:(NSTimeInterval)timestamp;
- (NSTimeInterval)timeDeltaWithFrameCountDelta:(AVAudioFramePosition)timestamp;
- (BOOL)selectEffectAtIndex:(NSInteger)index;
- (void)refreshAvailableEffectsAsync:(void (^)(NSArray<NSDictionary*>* effects))completion;
- (BOOL)selectEffectWithDescription:(AudioComponentDescription)description indexHint:(NSInteger)indexHint;
- (NSDictionary<NSNumber*, NSDictionary*>*)effectParameterInfo;
- (BOOL)setEffectParameter:(AudioUnitParameterID)parameter value:(AudioUnitParameterValue)value;

@end

NS_ASSUME_NONNULL_END
