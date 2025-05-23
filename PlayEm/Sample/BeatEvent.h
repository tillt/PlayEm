//
//  BeatEvent.h
//  PlayEm
//
//  Created by Till Toenshoff on 12/20/24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//
#import <Foundation/Foundation.h>

#ifndef BeatEvent_h
#define BeatEvent_h

NS_ASSUME_NONNULL_BEGIN

typedef enum : NSUInteger {
    BeatEventStyleBeat  = 0x01,
    BeatEventStyleBar   = 0x02,
    BeatEventStyleFound = 0x04,
    BeatEventStyleAlarm = 0x08,
} BeatEventStyle;

typedef struct {
    BeatEventStyle      style;
    unsigned long long  frame;
    double              bpm;
    size_t              index;
    double              energy;
    double              peak;
} BeatEvent;

extern NSString * const kBeatTrackedSampleTempoChangeNotification;
extern NSString * const kBeatTrackedSampleBeatNotification;

extern NSString * const kBeatNotificationKeyBar;
extern NSString * const kBeatNotificationKeyBeat;
extern NSString * const kBeatNotificationKeyFrame;
extern NSString * const kBeatNotificationKeyTempo;
extern NSString * const kBeatNotificationKeyStyle;
extern NSString * const kBeatNotificationKeyLocalEnergy;
extern NSString * const kBeatNotificationKeyLocalPeak;
extern NSString * const kBeatNotificationKeyTotalEnergy;
extern NSString * const kBeatNotificationKeyTotalPeak;

NS_ASSUME_NONNULL_END
#endif /* BeatEvent_h */
