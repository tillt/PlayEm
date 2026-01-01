//
//  TotalIdentificationController.m
//  PlayEm
//
//  Created by Till Toenshoff on 12/26/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import "TotalIdentificationController+Private.h"

#import "../Sample/LazySample.h"
#import "../Metadata/TimedMediaMetaData.h"

NS_ASSUME_NONNULL_BEGIN

// Test-only setter to inject raw hits for refinement without exposing the property publicly.
#ifdef DEBUG
@interface TotalIdentificationController (TestingAccess)
- (void)testing_setIdentifieds:(NSArray<TimedMediaMetaData *> *)hits;
@end

@implementation TotalIdentificationController (TestingAccess)
- (void)testing_setIdentifieds:(NSArray<TimedMediaMetaData *> *)hits
{
    self.identifieds = [hits mutableCopy];
}
@end
#endif

@implementation TotalIdentificationController

- (id)initWithSample:(LazySample*)sample
{
    self = [super init];
    if (self) {
        _sample = sample;
        // Use a larger hop size for offline detection to reduce Shazam request count (~2s chunks).
        _hopSize = (AVAudioFrameCount)4096 * 256;
        _identifieds = [NSMutableArray array];
        _identifyQueue = dispatch_queue_create("com.playem.identification.queue", DISPATCH_QUEUE_SERIAL);

        NSMutableArray* buffers = [NSMutableArray array];
        for (int channel = 0; channel < sample.sampleFormat.channels; channel++) {
            NSMutableData* buffer = [NSMutableData dataWithCapacity:_hopSize * _sample.frameSize];
            [buffers addObject:buffer];
        }
        _sampleBuffers = buffers;
        _pendingMatchOffsets = [NSMutableArray array];
        _lastMatchFrameByID = [NSMutableDictionary dictionary];
        _idealTrackMinSeconds = 4.0 * 60.0;
        _idealTrackMaxSeconds = 12.0 * 60.0;
        _minScoreThreshold = 0.2;
        _duplicateMergeWindowSeconds = 90.0;
        _debugScoring = YES;
        _referenceArtist = nil;
    }
    return self;
}

@end

NS_ASSUME_NONNULL_END
