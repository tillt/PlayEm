//
//  TotalIdentificationController+Detection.m
//  PlayEm
//
//  Created by Till Toenshoff on 12/26/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import "TotalIdentificationController+Private.h"
#import "TotalIdentificationController+Refinement.h"

#import <ShazamKit/ShazamKit.h>

#import "../Sample/LazySample.h"
#import "../Metadata/TimedMediaMetaData.h"
#import "../ImageController.h"
#import "../ActivityManager.h"

NS_ASSUME_NONNULL_BEGIN

@implementation TotalIdentificationController (Detection)

- (BOOL)detectTracklist
{
    NSLog(@"detectTracklist");
    self->_session = [[SHSession alloc] init];
    self->_session.delegate = self;

    SampleFormat sampleFormat = self->_sample.sampleFormat;

    AVAudioFrameCount matchWindowFrameCount = self->_hopSize;
    AVAudioChannelLayout* layout = [[AVAudioChannelLayout alloc] initWithLayoutTag:kAudioChannelLayoutTag_Mono];
    AVAudioFormat* format = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32
                                                             sampleRate:sampleFormat.rate
                                                            interleaved:NO
                                                          channelLayout:layout];

    AVAudioPCMBuffer* stream = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:matchWindowFrameCount];

    float* data[self->_sample.sampleFormat.channels];
    const int channels = self->_sample.sampleFormat.channels;
    for (int channel = 0; channel < channels; channel++) {
        data[channel] = (float*)((NSMutableData*)self->_sampleBuffers[channel]).bytes;
    }

#ifdef DEBUG_TAPPING
    FILE* fp = fopen("/tmp/debug_tap.out", "wb");
#endif
    // Pace offline feeding to roughly match live playback signature cadence x32. Anything
    // faster appears to trash the recognition - it feels like buffers get overwritten but
    // that is not clear, so far. Needs more investigation. Also the fact that we need to
    // rely on sleeps is very hacky - we need proper events - maybe KVO?
    useconds_t throttleUsec = (useconds_t)(((double)_hopSize / sampleFormat.rate / 32.0) * 1000000.0);
    if (throttleUsec < 1) {
        throttleUsec = 1;
    }

    // Here we go, all the way through our entire sample.
    while (self->_totalFrameCursor < self->_sample.frames) {
        if (dispatch_block_testcancel(self.queueOperation) != 0) {
            NSLog(@"aborted track detection");
            return NO;
        }
        double progress = (double)self->_totalFrameCursor / self->_sample.frames;
        [[ActivityManager shared] updateActivity:self->_token progress:progress];

        unsigned long long sourceWindowFrameCount = MIN(matchWindowFrameCount,
                                                        self->_sample.frames - self->_totalFrameCursor);
        // This may block for a loooooong time!
        unsigned long long received = [self->_sample rawSampleFromFrameOffset:self->_totalFrameCursor
                                                                       frames:sourceWindowFrameCount
                                                                      outputs:data];

        unsigned long int sourceFrameIndex = 0;
        while(sourceFrameIndex < received) {
            if (dispatch_block_testcancel(self.queueOperation) != 0) {
                NSLog(@"aborted track detection");
                return NO;
            }

            const unsigned long int inputWindowFrameCount = MIN(matchWindowFrameCount, self->_sample.frames - (self->_totalFrameCursor + sourceFrameIndex));

            [stream setFrameLength:(unsigned int)inputWindowFrameCount];
            // TODO: Yikes, this is a total nono -- we are writing to a read-only pointer!
            float* outputBuffer = stream.floatChannelData[0];

            unsigned long long chunkStartFrame = self->_totalFrameCursor + sourceFrameIndex;
            for (unsigned long int outputFrameIndex = 0; outputFrameIndex < inputWindowFrameCount; outputFrameIndex++) {
                double s = 0.0;
                for (int channel = 0; channel < sampleFormat.channels; channel++) {
                    s += data[channel][sourceFrameIndex];
                }
                s /= (float)sampleFormat.channels;

                outputBuffer[outputFrameIndex] = s;
                sourceFrameIndex++;
            }
            self->_sessionFrameOffset = chunkStartFrame;
            NSNumber* offset = [NSNumber numberWithUnsignedLongLong:chunkStartFrame];
            @synchronized (self) {
                [self->_pendingMatchOffsets addObject:offset];
            }

            AVAudioTime* time = [AVAudioTime timeWithSampleTime:chunkStartFrame atRate:sampleFormat.rate];
            self->_matchRequestCount += 1;

            [self->_session matchStreamingBuffer:stream atTime:time];

            // Light pacing so callbacks have a chance to arrive; ~16x realtime.
            usleep(throttleUsec);
        };
        self->_totalFrameCursor += received;
    };
    self->_finishedFeeding = YES;
    return YES;
}

- (ActivityToken*)detectTracklistWithCallback:(nonnull void (^)(BOOL, NSError*, NSArray<TimedMediaMetaData*>*))callback
{
    __weak typeof(self) weakSelf = self;

    self->_completionHandler = [callback copy];
    [self->_identifieds removeAllObjects];
    self->_matchRequestCount = 0;
    self->_matchResponseCount = 0;
    self->_finishedFeeding = NO;
    self->_completionSent = NO;
    self->_totalFrameCursor = 0;
    [self->_pendingMatchOffsets removeAllObjects];

    _token = [[ActivityManager shared] beginActivityWithTitle:@"Tracklist Detection" detail:nil cancellable:YES cancelHandler:^{
        [weakSelf abortWithCallback:^{
            [[ActivityManager shared] updateActivity:self->_token detail:@"aborted"];
            [[ActivityManager shared] completeActivity:self->_token];
            self->_completionHandler(NO, nil, nil);
        }];
    }];

    _queueOperation = dispatch_block_create(DISPATCH_BLOCK_NO_QOS_CLASS, ^{
        [weakSelf detectTracklist];
        [weakSelf checkForCompletion];
    });
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), _queueOperation);

    NSLog(@"starting track list detection");
    return _token;
}

- (void)abortWithCallback:(void (^)(void))callback
{
    NSLog(@"abort of track detection ongoing..");
    if (_queueOperation != NULL) {
        dispatch_block_cancel(_queueOperation);
        dispatch_block_notify(_queueOperation, dispatch_get_main_queue(), ^{
            callback();
        });
    } else {
        callback();
    }
}

- (void)fireCompletion
{
    if (_completionSent) {
        return;
    }
    _completionSent = YES;

    NSLog(@"firing completion after %lu requests / %lu responses (finishedFeeding=%d)",
          (unsigned long)_matchRequestCount,
          (unsigned long)_matchResponseCount,
          _finishedFeeding);

    [[ActivityManager shared] updateActivity:_token detail:@"refining tracklist"];
    NSArray<TimedMediaMetaData*>* refined = [self refineTracklist];

    [[ActivityManager shared] updateActivity:_token detail:@"refinement done"];
    [[ActivityManager shared] completeActivity:_token];

    if (_completionHandler) {
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            TotalIdentificationController* strongSelf = weakSelf;
            if (strongSelf == nil) {
                NSLog(@"lost myself");
                return;
            }
            strongSelf->_completionHandler(YES, nil, refined);
        });
    }
}

- (void)checkForCompletion
{
    if (_completionSent) {
        return;
    }
    if (_finishedFeeding && (_matchResponseCount >= _matchRequestCount)) {
        [self fireCompletion];
    }
}

#pragma mark - Shazam Delegate

- (void)session:(SHSession*)session didFindMatch:(SHMatch*)match
{
    __weak TotalIdentificationController* weakSelf = self;

    NSLog(@"%s", __PRETTY_FUNCTION__);

    dispatch_async(_identifyQueue, ^{
        TotalIdentificationController* strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        NSNumber* offset = nil;
        @synchronized (strongSelf) {
            if (strongSelf->_pendingMatchOffsets.count > 0) {
                offset = strongSelf->_pendingMatchOffsets.firstObject;
                [strongSelf->_pendingMatchOffsets removeObjectAtIndex:0];
            }
        }
        if (offset == nil) {
            offset = [NSNumber numberWithUnsignedLongLong:strongSelf->_sessionFrameOffset];
        }
        TimedMediaMetaData* track = [[TimedMediaMetaData alloc] initWithMatchedMediaItem:match.mediaItems[0] frame:offset];

        NSString* msg = [NSString stringWithFormat:@"%@ - %@", track.meta.artist, track.meta.title];
        [[ActivityManager shared] updateActivity:strongSelf->_token detail:msg];

        void (^continuation)(void) = ^(void) {
            TotalIdentificationController* strongSelf = weakSelf;
            if (strongSelf == nil) {
                return;
            }
            [strongSelf->_identifieds addObject:track];
            unsigned long long next = strongSelf->_matchResponseCount + 1;
            strongSelf->_matchResponseCount = MIN(next, strongSelf->_matchRequestCount);
            [strongSelf checkForCompletion];
        };

        if (track.meta.artworkLocation != nil) {
            [[ImageController shared] resolveDataForURL:track.meta.artworkLocation callback:^(NSData* data){
                track.meta.artwork = data;
                continuation();
            }];
        } else {
            continuation();
        }
    });
}

- (void)session:(SHSession *)session didNotFindMatchForSignature:(SHSignature *)signature error:(nullable NSError *)error
{
    __weak TotalIdentificationController* weakSelf = self;

    NSLog(@"%s: error: %@", __PRETTY_FUNCTION__, error);

    dispatch_async(_identifyQueue, ^{
        TotalIdentificationController* strongSelf = weakSelf;
        if (strongSelf != nil) {
            NSNumber* offset = nil;
            @synchronized (strongSelf) {
                if (strongSelf->_pendingMatchOffsets.count > 0) {
                    offset = strongSelf->_pendingMatchOffsets.firstObject;
                    [strongSelf->_pendingMatchOffsets removeObjectAtIndex:0];
                }
            }
            if (offset == nil) {
                offset = [NSNumber numberWithUnsignedLongLong:strongSelf->_sessionFrameOffset];
            }
            TimedMediaMetaData* track = [TimedMediaMetaData unknownTrackAtFrame:offset];

            [[ActivityManager shared] updateActivity:strongSelf->_token detail:track.meta.title];

            [strongSelf->_identifieds addObject:track];
            unsigned long long next = strongSelf->_matchResponseCount + 1;
            strongSelf->_matchResponseCount = MIN(next, strongSelf->_matchRequestCount);
            [strongSelf checkForCompletion];
        }
    });
}

@end

NS_ASSUME_NONNULL_END
