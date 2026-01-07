//
//  AudioPlaybackBackend.h
//  PlayEm
//
//  Created by Till Toenshoff on 01/05/26.
//  Copyright © 2026 Till Toenshoff. All rights reserved.
//
//  Backend protocol to abstract playback implementations (AudioQueue,
//  AVAudioEngine, etc.).

#import <Foundation/Foundation.h>

@class LazySample;
@class AudioPlaybackBackend;

NS_ASSUME_NONNULL_BEGIN

@protocol AudioPlaybackBackendDelegate <NSObject>
@optional
- (void)playbackBackendDidStart:(AudioPlaybackBackend*)backend;
- (void)playbackBackendDidPause:(AudioPlaybackBackend*)backend;
- (void)playbackBackendDidEnd:(AudioPlaybackBackend*)backend;
@end

@protocol AudioPlaybackBackend <NSObject>

@property (nonatomic, weak) id<AudioPlaybackBackendDelegate> delegate;
@property (nonatomic, assign, readonly) BOOL playing;
@property (nonatomic, assign, readonly) BOOL paused;
@property (nonatomic, assign) float volume;
@property (nonatomic, assign) float tempo;

- (void)prepareWithSample:(LazySample*)sample;
- (void)play;
- (void)pause;
- (void)stop;
- (void)seekToFrame:(unsigned long long)frame;
- (unsigned long long)currentFrame;
- (NSTimeInterval)currentTime;

@end

NS_ASSUME_NONNULL_END
