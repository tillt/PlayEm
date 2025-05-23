//
//  AudioDevice.h
//  PlayEm
//
//  Created by Till Toenshoff on 1.1.25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//
#import <CoreAudio/CoreAudio.h>             // AudioDeviceID

#ifndef AudioDevice_h
#define AudioDevice_h

@interface AudioDevice : NSObject

+(AudioObjectID)defaultOutputDevice;
/// Get total audio path latency for a device in a specific scope (IN/OUT).
+(AVAudioFramePosition)latencyForDevice:(AudioObjectID)deviceId scope:(AudioObjectPropertyScope)scope;
+(NSString*)nameForDevice:(AudioObjectID)deviceId;

@end
#endif
