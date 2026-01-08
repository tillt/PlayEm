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
extern NSString* const kPlaybackFXStateChanged;

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

/// Toggle between play and pause.
- (void)togglePause;

/// Start playback if prepared.
- (void)play;

/// Pause playback if currently playing.
- (void)pause;

/// Prepare and play a sample at the given frame (or keep paused if requested).
///
/// - Parameters:
///   - sample: Sample to play.
///   - frame: Start frame.
///   - paused: If YES, remain paused after preparing.
- (void)playSample:(LazySample*)sample frame:(unsigned long long)frame paused:(BOOL)paused;

/// Install a tap callback that receives interleaved mixer audio.
/// - Parameter tap: Callback invoked with frame position and interleaved float frames.
- (void)startTapping:(TapBlock _Nullable)tap;

/// Remove the tap callback.
- (void)stopTapping;

/// Current playback time in seconds.
- (NSTimeInterval)currentTime;

/// Seek to the specified time in seconds.
///
/// - Parameter time: Target time in seconds.
- (void)setCurrentTime:(NSTimeInterval)time;

/// Currently loaded sample (if any).
///
/// - Returns: Loaded sample or nil.
- (LazySample*)sample;

/// Asynchronously decode a sample; callback on completion (YES on success).
///
/// - Parameters:
///   - sample: Sample to decode.
///   - callback: Completion invoked on main queue.
- (void)decodeAsyncWithSample:(LazySample*)sample callback:(void (^)(BOOL))callback;

/// Abort pending decode; callback once aborted.
///
/// - Parameter callback: Invoked when abort finishes.
- (void)decodeAbortWithCallback:(void (^)(void))callback;

/// Total device/graph latency in frames.
- (AVAudioFramePosition)totalLatency;

/// Convert time delta to frame delta.
///
/// - Parameter timestamp: Time delta in seconds.
/// - Returns: Equivalent frame count.
- (AVAudioFramePosition)frameCountDeltaWithTimeDelta:(NSTimeInterval)timestamp;

/// Convert frame delta to time delta.
///
/// - Parameter timestamp: Frame delta.
/// - Returns: Equivalent seconds.
- (NSTimeInterval)timeDeltaWithFrameCountDelta:(AVAudioFramePosition)timestamp;

/// Select an effect from the available list by index; -1 disables effects.
///
/// - Parameter index: Effect index or -1 to disable.
/// - Returns: YES on success.
- (BOOL)selectEffectAtIndex:(NSInteger)index;

/// Enumerate available effects asynchronously.
///
/// - Parameter completion: Invoked on main queue with results.
- (void)refreshAvailableEffectsAsync:(void (^)(NSArray<NSDictionary*>* effects))completion;

/// Select an effect by AudioComponentDescription; indexHint is the list index or -1.
///
/// - Parameters:
///   - description: Component description.
///   - indexHint: List index or -1 if unknown.
/// - Returns: YES on success.
- (BOOL)selectEffectWithDescription:(AudioComponentDescription)description indexHint:(NSInteger)indexHint;

/// Current effect parameter metadata (id -> info dict).
///
/// - Returns: Parameter info keyed by ID.
- (NSDictionary<NSNumber*, NSDictionary*>*)effectParameterInfo;

/// Set a parameter on the active effect.
///
/// - Parameters:
///   - parameter: Parameter ID.
///   - value: Target value.
/// - Returns: YES on success.
- (BOOL)setEffectParameter:(AudioUnitParameterID)parameter value:(AudioUnitParameterValue)value;

/// Enable or bypass the active effect without changing selection.
///
/// - Parameter enabled: YES to enable, NO to bypass.
/// - Returns: YES on success.
- (BOOL)setEffectEnabled:(BOOL)enabled;

@end

NS_ASSUME_NONNULL_END
