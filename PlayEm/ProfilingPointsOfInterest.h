//
//  ProfilingPointsOfInterest.h
//  PlayEm
//
//  Created by Till Toenshoff on 20.02.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#import <OSLog/OSLog.h>

#ifndef ProfilingPointsOfInterest_h
#define ProfilingPointsOfInterest_h

typedef enum : NSUInteger {
    POICADisplayLink,
    POISetCurrentFrame,
    POIVisualsFromOrigin,
    POIGetCurrentFrame,
    POIAudioBufferCallback,
    POIUpdateScrollingState,
    POIUpdateHeadPosition,
    POIScrollPoint,
    POIStringStuff,
    POIWaveViewSetCurrentFrame,
    POITotalViewSetCurrentFrame,
    POIBeatStuff,
    POIPrepareVisualsFromOrigin,
    POILazySampleDecodeAborting,
    POILazySampleDecodeAborted,
    POILazySampleDecodeAbortNotification,
    POILazySampleDecodeReturned,
    POILazySampleDecodeAbortHang,
} PointsOfInterest;

extern os_log_t pointsOfInterest;

#endif /* ProfilingPointsOfInterest_h */
