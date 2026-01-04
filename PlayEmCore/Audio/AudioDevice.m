//
//  AudioDevice.m
//  PlayEm
//
//  Created by Till Toenshoff on 1.1.25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudioTypes.h>
#import <CoreServices/CoreServices.h>
#import <CoreFoundation/CoreFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import "AudioDevice.h"

@implementation AudioDevice

+ (AVAudioFramePosition)latencyForDevice:(AudioObjectID)deviceId scope:(AudioObjectPropertyScope)scope
{
    // Get the device latency.
    AudioObjectPropertyAddress deviceLatencyPropertyAddress = { kAudioDevicePropertyLatency, scope, kAudioObjectPropertyElementMain };
    UInt32 deviceLatency;
    UInt32 propertySize = sizeof(deviceLatency);
    OSStatus result = AudioObjectGetPropertyData(deviceId, &deviceLatencyPropertyAddress, 0, NULL, &propertySize, &deviceLatency);
    if (result != noErr) {
        NSLog(@"Failed to get latency, err: %d", result);
        return 0;
    }
    
    // Get the safety offset.
    AudioObjectPropertyAddress safetyOffsetPropertyAddress = { kAudioDevicePropertySafetyOffset, scope, kAudioObjectPropertyElementMain };
    UInt32 safetyOffset;
    propertySize = sizeof(safetyOffset);
    result = AudioObjectGetPropertyData(deviceId, &safetyOffsetPropertyAddress, 0, NULL, &propertySize, &safetyOffset);
    if (result != noErr) {
        NSLog(@"Failed to get safety offset, err: %d", result);
        return 0;
    }
    
    // Get the buffer size.
    AudioObjectPropertyAddress bufferSizePropertyAddress = { kAudioDevicePropertyBufferFrameSize, scope, kAudioObjectPropertyElementMain };
    UInt32 bufferSize;
    propertySize = sizeof(bufferSize);
    result = AudioObjectGetPropertyData(deviceId, &bufferSizePropertyAddress, 0, NULL, &propertySize, &bufferSize);
    if (result != noErr) {
        NSLog(@"Failed to get buffer size, err: %d", result);
        return 0;
    }
    
    AudioObjectPropertyAddress streamsPropertyAddress = { kAudioDevicePropertyStreams, scope, kAudioObjectPropertyElementMain };
    
    UInt32 streamLatency = 0;
    UInt32 streamsSize = 0;
    AudioObjectGetPropertyDataSize (deviceId, &streamsPropertyAddress, 0, NULL, &streamsSize);
    if (streamsSize >= sizeof(AudioStreamID)) {
        // Get the latency of the first stream.
        NSMutableData* streamIDs = [NSMutableData dataWithLength:streamsSize];
        AudioStreamID* ids = (AudioStreamID*)streamIDs.mutableBytes;
        result = AudioObjectGetPropertyData(deviceId, &streamsPropertyAddress, 0, NULL, &streamsSize, ids);
        if (result != noErr) {
            NSLog(@"Failed to get streams, err: %d", result);
            return 0;
        }
        
        AudioObjectPropertyAddress streamLatencyPropertyAddress = { kAudioStreamPropertyLatency, scope, kAudioObjectPropertyElementMain };
        propertySize = sizeof(streamLatency);
        result = AudioObjectGetPropertyData(ids[0], &streamLatencyPropertyAddress, 0, NULL, &propertySize, &streamLatency);
        if (result != noErr) {
            NSLog(@"Failed to get stream latency, err: %d", result);
            return 0;
        }
    }
    
    AVAudioFramePosition totalLatency = deviceLatency + streamLatency + safetyOffset + bufferSize;
    
    NSLog(@"%d frames device latency, %d frames output stream latency, %d safety offset, %d buffer size resulting in an estimated total latency of %lld frames", deviceLatency, streamLatency, safetyOffset, bufferSize, totalLatency);
    
    return totalLatency;
}

+ (NSString*)nameForDevice:(AudioObjectID)deviceId
{
    AudioObjectPropertyAddress namePropertyAddress = {
        kAudioDevicePropertyDeviceNameCFString,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    
    CFStringRef nameRef;
    UInt32 propertySize = sizeof(nameRef);
    OSStatus result = AudioObjectGetPropertyData(deviceId,
                                                 &namePropertyAddress,
                                                 0,
                                                 NULL,
                                                 &propertySize,
                                                 &nameRef);
    if (result != noErr) {
        NSLog(@"Failed to get device's name, err: %d", result);
        return nil;
    }
    NSString* name = (__bridge_transfer NSString*)nameRef;
    return name;
}

+ (AudioObjectID)defaultOutputDevice
{
    UInt32 deviceId;
    UInt32 propertySize = sizeof(deviceId);
    AudioObjectPropertyAddress theAddress = {
        kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    
    OSStatus result = AudioObjectGetPropertyData(kAudioObjectSystemObject,
                                                 &theAddress,
                                                 0,
                                                 NULL,
                                                 &propertySize,
                                                 &deviceId);
    if (result != noErr) {
        NSLog(@"Failed to get device's name, err: %d", result);
        return 0;
    }
    
    return deviceId;
}

@end
