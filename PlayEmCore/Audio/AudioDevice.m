//
//  AudioDevice.m
//  PlayEm
//
//  Created by Till Toenshoff on 1.1.25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import "AudioDevice.h"

#import <Foundation/Foundation.h>

#import <AudioToolbox/AudioToolbox.h>
#import <CoreAudio/CoreAudioTypes.h>
#import <CoreFoundation/CoreFoundation.h>
#import <CoreServices/CoreServices.h>

@implementation AudioDevice

+ (AVAudioFramePosition)latencyForDevice:(AudioObjectID)deviceId scope:(AudioObjectPropertyScope)scope
{
    // Get the device latency.
    AudioObjectPropertyAddress deviceLatencyPropertyAddress = {kAudioDevicePropertyLatency, scope, kAudioObjectPropertyElementMain};
    UInt32 deviceLatency;
    UInt32 propertySize = sizeof(deviceLatency);
    OSStatus result = AudioObjectGetPropertyData(deviceId, &deviceLatencyPropertyAddress, 0, NULL, &propertySize, &deviceLatency);
    if (result != noErr) {
        NSLog(@"Failed to get latency, err: %d", result);
        return 0;
    }

    // Get the safety offset.
    AudioObjectPropertyAddress safetyOffsetPropertyAddress = {kAudioDevicePropertySafetyOffset, scope, kAudioObjectPropertyElementMain};
    UInt32 safetyOffset;
    propertySize = sizeof(safetyOffset);
    result = AudioObjectGetPropertyData(deviceId, &safetyOffsetPropertyAddress, 0, NULL, &propertySize, &safetyOffset);
    if (result != noErr) {
        NSLog(@"Failed to get safety offset, err: %d", result);
        return 0;
    }

    // Get the buffer size.
    AudioObjectPropertyAddress bufferSizePropertyAddress = {kAudioDevicePropertyBufferFrameSize, scope, kAudioObjectPropertyElementMain};
    UInt32 bufferSize;
    propertySize = sizeof(bufferSize);
    result = AudioObjectGetPropertyData(deviceId, &bufferSizePropertyAddress, 0, NULL, &propertySize, &bufferSize);
    if (result != noErr) {
        NSLog(@"Failed to get buffer size, err: %d", result);
        return 0;
    }

    AudioObjectPropertyAddress streamsPropertyAddress = {kAudioDevicePropertyStreams, scope, kAudioObjectPropertyElementMain};

    UInt32 streamLatency = 0;
    UInt32 streamsSize = 0;
    AudioObjectGetPropertyDataSize(deviceId, &streamsPropertyAddress, 0, NULL, &streamsSize);
    if (streamsSize >= sizeof(AudioStreamID)) {
        // Get the latency of the first stream.
        NSMutableData* streamIDs = [NSMutableData dataWithLength:streamsSize];
        AudioStreamID* ids = (AudioStreamID*) streamIDs.mutableBytes;
        result = AudioObjectGetPropertyData(deviceId, &streamsPropertyAddress, 0, NULL, &streamsSize, ids);
        if (result != noErr) {
            NSLog(@"Failed to get streams, err: %d", result);
            return 0;
        }

        AudioObjectPropertyAddress streamLatencyPropertyAddress = {kAudioStreamPropertyLatency, scope, kAudioObjectPropertyElementMain};
        propertySize = sizeof(streamLatency);
        result = AudioObjectGetPropertyData(ids[0], &streamLatencyPropertyAddress, 0, NULL, &propertySize, &streamLatency);
        if (result != noErr) {
            NSLog(@"Failed to get stream latency, err: %d", result);
            return 0;
        }
    }

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        AVAudioFramePosition totalLatency = deviceLatency + streamLatency + safetyOffset + bufferSize;
        NSLog(@"%d frames device latency, %d frames output stream latency, %d "
              @"safety offset, %d buffer size resulting in an estimated total "
              @"latency of %lld frames",
              deviceLatency, streamLatency, safetyOffset, bufferSize, totalLatency);
    });
    return deviceLatency + streamLatency + safetyOffset + bufferSize;
}

+ (NSString*)nameForDevice:(AudioObjectID)deviceId
{
    AudioObjectPropertyAddress namePropertyAddress = {kAudioDevicePropertyDeviceNameCFString, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};

    CFStringRef nameRef;
    UInt32 propertySize = sizeof(nameRef);
    OSStatus result = AudioObjectGetPropertyData(deviceId, &namePropertyAddress, 0, NULL, &propertySize, &nameRef);
    if (result != noErr) {
        NSLog(@"Failed to get device's name, err: %d", result);
        return nil;
    }
    NSString* name = (__bridge_transfer NSString*) nameRef;
    return name;
}

+ (Float64)sampleRateForDevice:(AudioObjectID)deviceId
{
    AudioObjectPropertyAddress address = {kAudioDevicePropertyNominalSampleRate, kAudioObjectPropertyScopeOutput, kAudioObjectPropertyElementMain};
    Float64 rate = 0;
    UInt32 size = sizeof(rate);
    OSStatus result = AudioObjectGetPropertyData(deviceId, &address, 0, NULL, &size, &rate);
    if (result != noErr) {
        NSLog(@"Failed to get device sample rate, err: %d", result);
        return 0;
    }
    return rate;
}

+ (AudioObjectID)defaultOutputDevice
{
    UInt32 deviceId;
    UInt32 propertySize = sizeof(deviceId);
    AudioObjectPropertyAddress theAddress = {kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};

    OSStatus result = AudioObjectGetPropertyData(kAudioObjectSystemObject, &theAddress, 0, NULL, &propertySize, &deviceId);
    if (result != noErr) {
        NSLog(@"Failed to get device's name, err: %d", result);
        return 0;
    }

    return deviceId;
}

+ (BOOL)device:(AudioObjectID)deviceId supportsSampleRate:(Float64)rate
{
    if (deviceId == 0 || rate <= 0) {
        return NO;
    }
    AudioObjectPropertyAddress addr = {kAudioDevicePropertyAvailableNominalSampleRates, kAudioObjectPropertyScopeOutput, kAudioObjectPropertyElementMain};
    UInt32 dataSize = 0;
    OSStatus result = AudioObjectGetPropertyDataSize(deviceId, &addr, 0, NULL, &dataSize);
    if (result != noErr || dataSize == 0) {
        return NO;
    }
    UInt32 rangeCount = dataSize / sizeof(AudioValueRange);
    NSMutableData* data = [NSMutableData dataWithLength:dataSize];
    result = AudioObjectGetPropertyData(deviceId, &addr, 0, NULL, &dataSize, data.mutableBytes);
    if (result != noErr) {
        return NO;
    }
    AudioValueRange* ranges = (AudioValueRange*) data.mutableBytes;
    for (UInt32 i = 0; i < rangeCount; i++) {
        if (rate >= ranges[i].mMinimum && rate <= ranges[i].mMaximum) {
            return YES;
        }
    }
    return NO;
}

+ (BOOL)setSampleRate:(Float64)rate forDevice:(AudioObjectID)deviceId
{
    if (deviceId == 0 || rate <= 0) {
        return NO;
    }
    AudioObjectPropertyAddress address = {kAudioDevicePropertyNominalSampleRate, kAudioObjectPropertyScopeOutput, kAudioObjectPropertyElementMain};
    UInt32 size = sizeof(rate);
    OSStatus result = AudioObjectSetPropertyData(deviceId, &address, 0, NULL, size, &rate);
    if (result != noErr) {
        NSLog(@"Failed to set device sample rate to %.2f Hz, err: %d", rate, result);
        return NO;
    }
    return YES;
}

+ (void)switchDevice:(AudioObjectID)deviceId
       toSampleRate:(Float64)rate
            timeout:(NSTimeInterval)timeoutSeconds
         completion:(void (^)(BOOL success))completion
{
    if (deviceId == 0 || rate <= 0 || timeoutSeconds < 0) {
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO);
            });
        }
        return;
    }
    if (![self device:deviceId supportsSampleRate:rate]) {
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO);
            });
        }
        return;
    }
    Float64 before = [self sampleRateForDevice:deviceId];
    if (fabs(before - rate) < 0.5) {
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(YES);
            });
        }
        return;
    }
    if (![self setSampleRate:rate forDevice:deviceId]) {
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO);
            });
        }
        return;
    }
    const NSTimeInterval interval = 0.05;
    NSUInteger attempts = (NSUInteger) ceil(timeoutSeconds / interval);
    if (attempts == 0) {
        attempts = 1;
    }

    __block BOOL matched = NO;
    __block NSUInteger remaining = attempts;
    dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_UTILITY, 0);

    __block void (^checkBlock)(void) = ^{
        Float64 current = [self sampleRateForDevice:deviceId];
        if (fabs(current - rate) < 0.5) {
            matched = YES;
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(YES);
                });
            }
            return;
        }
        if (remaining == 0) {
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(NO);
                });
            }
            return;
        }
        remaining--;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(interval * NSEC_PER_SEC)), queue, checkBlock);
    };

    dispatch_async(queue, checkBlock);
}

+ (Float64)highestSupportedSampleRateForDevice:(AudioObjectID)deviceId
{
    if (deviceId == 0) {
        return 0;
    }
    AudioObjectPropertyAddress addr = {kAudioDevicePropertyAvailableNominalSampleRates, kAudioObjectPropertyScopeOutput, kAudioObjectPropertyElementMain};
    UInt32 dataSize = 0;
    OSStatus result = AudioObjectGetPropertyDataSize(deviceId, &addr, 0, NULL, &dataSize);
    if (result != noErr || dataSize < sizeof(AudioValueRange)) {
        return 0;
    }
    UInt32 rangeCount = dataSize / sizeof(AudioValueRange);
    NSMutableData* data = [NSMutableData dataWithLength:dataSize];
    result = AudioObjectGetPropertyData(deviceId, &addr, 0, NULL, &dataSize, data.mutableBytes);
    if (result != noErr) {
        return 0;
    }
    AudioValueRange* ranges = (AudioValueRange*) data.mutableBytes;
    Float64 maxRate = 0;
    for (UInt32 i = 0; i < rangeCount; i++) {
        if (ranges[i].mMaximum > maxRate) {
            maxRate = ranges[i].mMaximum;
        }
    }
    return maxRate;
}

@end
