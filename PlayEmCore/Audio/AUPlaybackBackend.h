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

/// Select an AudioUnit effect by component description (nil to disable).
- (BOOL)setEffectWithDescription:(AudioComponentDescription)description;

/// List parameter IDs for the current effect.
- (NSArray<NSNumber*>*)effectParameterList;

/// Metadata for current effect parameters keyed by ID.
- (NSDictionary<NSNumber*, NSDictionary*>*)effectParameterInfo;

/// Set a parameter on the active effect.
- (BOOL)setEffectParameter:(AudioUnitParameterID)parameter value:(AudioUnitParameterValue)value;

/// Available AudioUnit effects (array of dictionaries with name/component).
- (NSArray<NSDictionary*>*)availableEffects;

/// Enable or bypass the currently instantiated effect (keeps parameters intact).
- (BOOL)setEffectEnabled:(BOOL)enabled;

@end
