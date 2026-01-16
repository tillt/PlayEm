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

/// Returns the nominal sample rate (Hz) for the given device, or 0 on error.
///
/// - Parameter deviceId: Target device.
/// - Returns: Sample rate in Hz, or 0 on error.
+ (Float64)sampleRateForDevice:(AudioObjectID)deviceId;
+ (BOOL)device:(AudioObjectID)deviceId supportsSampleRate:(Float64)rate;
+ (BOOL)setSampleRate:(Float64)rate forDevice:(AudioObjectID)deviceId;
/// Attempt to set the device to the given rate and validate within the timeout (async).
/// Completion is invoked on the main queue with YES if the device reports the requested rate (within 0.5 Hz) before timeout.
+ (void)switchDevice:(AudioObjectID)deviceId
       toSampleRate:(Float64)rate
            timeout:(NSTimeInterval)timeoutSeconds
         completion:(void (^)(BOOL success))completion;
/// Returns the highest available nominal sample rate the device reports, or 0 on error.
+ (Float64)highestSupportedSampleRateForDevice:(AudioObjectID)deviceId;

@end
#endif
