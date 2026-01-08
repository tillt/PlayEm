//
//  AudioDevice.h
//  PlayEm
//
//  Created by Till Toenshoff on 1.1.25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//
#import <AVFoundation/AVAudioFormat.h>  // AVAudioFramePosition
#import <CoreAudio/CoreAudio.h>         // AudioDeviceID

#ifndef AudioDevice_h
#define AudioDevice_h

@interface AudioDevice : NSObject

/// Returns the default audio output device ID.
+ (AudioObjectID)defaultOutputDevice;

/// Estimates total path latency in frames for the given device/scope.
///
/// Fetches device latency, safety offset, buffer size, and the first stream’s latency, and sums them. Returns 0 on error.
///
/// - Parameters:
///   - deviceId: Target device.
///   - scope: Property scope.
/// - Returns: Latency in frames, or 0 on error.
+ (AVAudioFramePosition)latencyForDevice:(AudioObjectID)deviceId scope:(AudioObjectPropertyScope)scope;

/// Returns the human-readable device name, or nil on error.
///
/// - Parameter deviceId: Target device.
/// - Returns: Device name or nil.
+ (NSString*)nameForDevice:(AudioObjectID)deviceId;

@end
#endif
