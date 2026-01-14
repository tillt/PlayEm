//
//  MediaMetaData+MixWheel.h
//  PlayEm
//
//  Created by Till Toenshoff on 1/14/26.
//  Copyright © 2026 Till Toenshoff. All rights reserved.
//
#import "MediaMetaData.h"

#ifndef MediaMetaData_MixWheel_h
#define MediaMetaData_MixWheel_h

@interface MediaMetaData (MixWheel)

/// Converts whatever comes in into a MixWheel key value.
+ (NSString* _Nullable)correctedKeyNotation:(NSString* _Nullable)key;

@end

#endif /* MediaMetaData_MixWheel_h */
