//
//  AudioDevice.h
//  PlayEm
//
//  Created by Till Toenshoff on 1.1.25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//
#import <CoreAudio/CoreAudio.h>             // AudioDeviceID
#import <AVFoundation/AVAudioFormat.h>      // AVAudioFramePosition

#ifndef AudioDevice_h
#define AudioDevice_h

@interface AudioDevice : NSObject

/*!
 @brief Returns the default audio output device ID.
 */
+ (AudioObjectID)defaultOutputDevice;

/*!
 @brief Estimates total path latency in frames for the given device/scope.
 @discussion Fetches device latency, safety offset, buffer size, and the first
             stream’s latency, and sums them. Returns 0 on error.
 */
+ (AVAudioFramePosition)latencyForDevice:(AudioObjectID)deviceId scope:(AudioObjectPropertyScope)scope;

/*!
 @brief Returns the human-readable device name, or nil on error.
 */
+ (NSString*)nameForDevice:(AudioObjectID)deviceId;

@end
#endif
