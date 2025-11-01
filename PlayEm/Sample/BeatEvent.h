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
    BeatEventStyleBeat  = 1 << 0,
    BeatEventStyleBar   = 1 << 1,

    BeatEventStyleFound = 1 << 2,

    BeatEventStyleAlarmIntro = 1 << 3,
    BeatEventStyleAlarmBuildup = 1 << 4,
    BeatEventStyleAlarmTeardown = 1 << 5,
    BeatEventStyleAlarmOutro = 1 << 6,

    BeatEventStyleMarkIntro = 1 << 7,
    BeatEventStyleMarkBuildup = 1 << 8,
    BeatEventStyleMarkTeardown = 1 << 9,
    BeatEventStyleMarkOutro = 1 << 10,
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
extern NSString * const kBeatNotificationKeyTotalBeats;

NS_ASSUME_NONNULL_END
#endif /* BeatEvent_h */
