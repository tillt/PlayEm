//
//  AudioQueuePlaybackBackend.h
//  PlayEm
//
//  Created by Till Toenshoff on 01/05/26.
//  Copyright © 2026 Till Toenshoff. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "AudioPlaybackBackend.h"

NS_ASSUME_NONNULL_BEGIN

@interface AudioQueuePlaybackBackend : NSObject <AudioPlaybackBackend>

// Optional tap invoked on the audio queue thread with interleaved float frames.
@property (nonatomic, copy, nullable) void (^tapBlock)(unsigned long long framePosition, float* data, unsigned int frameCount);
@property (nonatomic, weak) id<AudioPlaybackBackendDelegate> delegate;

@end

NS_ASSUME_NONNULL_END
