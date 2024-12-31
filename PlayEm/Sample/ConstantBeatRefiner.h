//
//  ConstantBeatRefiner.h
//  PlayEm
//
//  Created by Till Toenshoff on 06.08.23.
//  Copyright © 2023 Till Toenshoff. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "BeatTrackedSample.h"

NS_ASSUME_NONNULL_BEGIN

typedef struct {
    unsigned long long firstBeatFrame;
    double beatLength;
} BeatConstRegion;

@interface BeatTrackedSample (ConstantBeatRefiner)

- (void)makeConstantBeats;

@end

NS_ASSUME_NONNULL_END
