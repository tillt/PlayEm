//
//  AUPlaybackBackend.h
//  PlayEm
//
//  Created by Till Toenshoff on 01/05/26.
//  Copyright © 2026 Till Toenshoff. All rights reserved.
//

#import <Foundation/Foundation.h>

#import <AudioToolbox/AudioToolbox.h>

#import "AudioPlaybackBackend.h"

@interface AUPlaybackBackend : NSObject <AudioPlaybackBackend>

- (BOOL)setEffectWithDescription:(AudioComponentDescription)description;
- (NSArray<NSNumber*>*)effectParameterList;
- (NSDictionary<NSNumber*, NSDictionary*>*)effectParameterInfo;
- (BOOL)setEffectParameter:(AudioUnitParameterID)parameter value:(AudioUnitParameterValue)value;
- (NSArray<NSDictionary*>*)availableEffects;

@end
