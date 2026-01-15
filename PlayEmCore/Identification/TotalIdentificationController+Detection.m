//
//  TotalIdentificationController+Detection.m
//  PlayEm
//
//  Created by Till Toenshoff on 12/26/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import <ShazamKit/ShazamKit.h>
#import <float.h>
#import <limits.h>
#import <math.h>

#import "../ActivityManager.h"
#import "../PECLocalization.h"
#import "../ImageController.h"
#import "../Metadata/TimedMediaMetaData.h"
#import "../Sample/LazySample.h"
#import "TotalIdentificationController+Private.h"
#import "TotalIdentificationController+Refinement.h"

NS_ASSUME_NONNULL_BEGIN

@interface TotalIdentificationController (RefinementLogging)
- (void)logTracklist:(NSArray<TimedMediaMetaData*>*)tracks tag:(NSString*)tag includeDuration:(BOOL)includeDuration;
@end

static BOOL AppendSignatureBuffer(SHSignatureGenerator* generator, AVAudioPCMBuffer* buffer, AVAudioTime* time, NSError** errorOut)
{
    if (generator == nil) {
        NSLog(@"[Detect] SHSignatureGenerator unavailable (nil instance)");
        return NO;
    }
    BOOL ok = [generator appendBuffer:buffer atTime:time error:errorOut];
    if (!ok && errorOut != NULL) {
        NSLog(@"[Detect] signature append returned NO error=%@", *errorOut);
    }
    return ok;
}

static uint64_t HashAudioSlice(float* const* channels, uint32_t channelCount, AVAudioFrameCount frames)
{
    const uint64_t kOffsetBasis = 1469598103934665603ULL;
    const uint64_t kPrime = 1099511628211ULL;
    uint64_t hash = kOffsetBasis;
    if (channels == NULL || frames == 0 || channelCount == 0) {
        return hash;
    }
    size_t byteCount = (size_t) frames * sizeof(float);
    for (uint32_t channel = 0; channel < channelCount; channel++) {
        const uint8_t* bytes = (const uint8_t*) channels[channel];
        for (size_t i = 0; i < byteCount; i++) {
            hash ^= bytes[i];
            hash *= kPrime;
        }
    }
    return hash;
}

@implementation TotalIdentificationController (Detection)

- (BOOL)detectTracklistStreaming
{
    NSLog(@"detectTracklist (streaming)");
    _session = [[SHSession alloc] init];
    _session.delegate = self;

    SampleFormat sampleFormat = _sample.sampleFormat;

    AVAudioFrameCount matchWindowFrameCount = _hopSize;
    AVAudioChannelLayout* layout = [[AVAudioChannelLayout alloc] initWithLayoutTag:kAudioChannelLayoutTag_Mono];
    AVAudioFormat* format = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32
                                                             sampleRate:_sample.renderedSampleRate
                                                            interleaved:NO
                                                          channelLayout:layout];

    AVAudioPCMBuffer* stream = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:matchWindowFrameCount];

    float* data[_sample.sampleFormat.channels];
    const int channels = _sample.sampleFormat.channels;
    uint64_t lastSliceHash = 0;
    for (int channel = 0; channel < channels; channel++) {
        data[channel] = (float*) ((NSMutableData*) _sampleBuffers[channel]).bytes;
    }

    // Here we go, all the way through our entire sample.
    while (_totalFrameCursor < _sample.frames) {
        if (dispatch_block_testcancel(_queueOperation) != 0) {
            NSLog(@"aborted track detection");
            return NO;
        }
        double progress = (double) _totalFrameCursor / _sample.frames;
        [[ActivityManager shared] updateActivity:_token progress:progress];
        if (_debugScoring) {
            double bucket = floor(progress * 10.0) / 10.0;
            if (bucket > _lastProgressLogged) {
                _lastProgressLogged = bucket;
                NSLog(@"[Detect] progress %.0f%% (%llu/%llu frames)", progress * 100.0, _totalFrameCursor, _sample.frames);
            }
        }

        unsigned long long sourceWindowFrameCount = MIN(matchWindowFrameCount, _sample.frames - _totalFrameCursor);
        unsigned long long received = [_sample rawSampleFromFrameOffset:_totalFrameCursor frames:sourceWindowFrameCount outputs:data];
        if (received == 0) {
            NSLog(@"no audio frames returned at offset %llu "
                  @"(sourceWindowFrameCount=%llu)",
                  _totalFrameCursor, sourceWindowFrameCount);
            _finishedFeeding = YES;
            return YES;
        }

        unsigned long int sourceFrameIndex = 0;
        while (sourceFrameIndex < received) {
            if (dispatch_block_testcancel(_queueOperation) != 0) {
                NSLog(@"aborted track detection");
                return NO;
            }

            const unsigned long int inputWindowFrameCount = MIN(matchWindowFrameCount, _sample.frames - (_totalFrameCursor + sourceFrameIndex));
            if (inputWindowFrameCount == 0) {
                break;
            }

            [stream setFrameLength:(unsigned int) inputWindowFrameCount];
            // TODO: Yikes, this is a total nono -- we are writing to a read-only
            // pointer!
            float* outputBuffer = stream.floatChannelData[0];

            unsigned long long chunkStartFrame = _totalFrameCursor + sourceFrameIndex;
            for (unsigned long int outputFrameIndex = 0; outputFrameIndex < inputWindowFrameCount; outputFrameIndex++) {
                double s = 0.0;
                for (int channel = 0; channel < sampleFormat.channels; channel++) {
                    s += data[channel][sourceFrameIndex];
                }
                s /= (float) sampleFormat.channels;

                outputBuffer[outputFrameIndex] = s;
                sourceFrameIndex++;
            }
            lastSliceHash = HashAudioSlice(stream.floatChannelData, (uint32_t) stream.format.channelCount, inputWindowFrameCount);

            _sessionFrameOffset = chunkStartFrame;
            NSNumber* offset = [NSNumber numberWithUnsignedLongLong:chunkStartFrame];
            dispatch_sync(_identifyQueue, ^{
                [_pendingMatchOffsets addObject:offset];
                _inFlightCount += 1;
                if (_inFlightCount > _maxInFlightCount) {
                    _maxInFlightCount = _inFlightCount;
                }
                _requestStartTimeByOffset[offset] = @(CFAbsoluteTimeGetCurrent());
                _requestSliceHashByOffset[offset] = [NSString stringWithFormat:@"%016llx", lastSliceHash];
            });
            _matchRequestCount += 1;

            AVAudioTime* time = [AVAudioTime timeWithSampleTime:chunkStartFrame atRate:_sample.renderedSampleRate];
            [_session matchStreamingBuffer:stream atTime:time];
        };
        _totalFrameCursor += received;
    };
    _finishedFeeding = YES;
    return YES;
}

- (BOOL)detectTracklist
{
//    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
//    self.useStreamingMatch = [defaults boolForKey:@"UseStreamingMatch"];
//    if (self.useStreamingMatch) {
//        return [self detectTracklistStreaming];
//    }

    NSLog(@"detectTracklist");
    _session = [[SHSession alloc] init];
    _session.delegate = self;

    SampleFormat sampleFormat = _sample.sampleFormat;

    AVAudioFrameCount matchWindowFrameCount = _hopSize;
    BOOL downmixToMono = NO;
    AVAudioChannelLayout* layout = [[AVAudioChannelLayout alloc] initWithLayoutTag:downmixToMono ? kAudioChannelLayoutTag_Mono : kAudioChannelLayoutTag_Stereo];
    AVAudioFormat* format = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32
                                                             sampleRate:_sample.renderedSampleRate
                                                            interleaved:NO
                                                          channelLayout:layout];

    AVAudioPCMBuffer* stream = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:matchWindowFrameCount];

    float* data[_sample.sampleFormat.channels];
    const int channels = _sample.sampleFormat.channels;
    for (int channel = 0; channel < channels; channel++) {
        data[channel] = (float*) ((NSMutableData*) _sampleBuffers[channel]).bytes;
    }

#ifdef DEBUG_TAPPING
    FILE* fp = fopen("/tmp/debug_tap.out", "wb");
#endif
    // min is 3, max is 12.
    double targetSignatureSeconds = 10.0;
    SHSignatureGenerator* generator = [[SHSignatureGenerator alloc] init];
    double accumulatedSeconds = 0.0;
    unsigned long long signatureStartFrame = 0;
    unsigned long long signatureLocalFrame = 0;
    uint64_t lastSliceHash = 0;
    //defaults = [NSUserDefaults standardUserDefaults];
    BOOL useNilTime = NO;

    static BOOL loggedAppendFailure = NO;
    static BOOL loggedAppendSuccess = NO;
    // Here we go, all the way through our entire sample.
    while (_totalFrameCursor < _sample.frames) {
        if (dispatch_block_testcancel(_queueOperation) != 0) {
            NSLog(@"aborted track detection");
            return NO;
        }
        double progress = (double) _totalFrameCursor / _sample.frames;
        [[ActivityManager shared] updateActivity:_token progress:progress];
        if (_debugScoring) {
            double bucket = floor(progress * 10.0) / 10.0;
            if (bucket > _lastProgressLogged) {
                _lastProgressLogged = bucket;
                NSLog(@"[Detect] progress %.0f%% (%llu/%llu frames)", progress * 100.0, _totalFrameCursor, _sample.frames);
            }
        }

        unsigned long long sourceWindowFrameCount = MIN(matchWindowFrameCount, _sample.frames - _totalFrameCursor);
        // This may block for a loooooong time!
        unsigned long long received = [_sample rawSampleFromFrameOffset:_totalFrameCursor frames:sourceWindowFrameCount outputs:data];
        if (received == 0) {
            NSLog(@"no audio frames returned at offset %llu "
                  @"(sourceWindowFrameCount=%llu)",
                  _totalFrameCursor, sourceWindowFrameCount);
            _finishedFeeding = YES;
            return YES;
        }

        unsigned long int sourceFrameIndex = 0;
        while (sourceFrameIndex < received) {
            if (dispatch_block_testcancel(_queueOperation) != 0) {
                NSLog(@"aborted track detection");
                return NO;
            }

            const unsigned long long availableFrames = received - sourceFrameIndex;
            AVAudioFrameCount inputWindowFrameCount = (AVAudioFrameCount) MIN((unsigned long long) matchWindowFrameCount, availableFrames);
            if (inputWindowFrameCount == 0) {
                break;
            }

            [stream setFrameLength:(unsigned int) inputWindowFrameCount];
            // TODO: Yikes, this is a total nono -- we are writing to a read-only
            // pointer!
            float* outputLeft = stream.floatChannelData[0];
            float* outputRight = stream.floatChannelData[1];

            unsigned long long chunkStartFrame = _totalFrameCursor + sourceFrameIndex;
            for (AVAudioFrameCount outputFrameIndex = 0; outputFrameIndex < inputWindowFrameCount; outputFrameIndex++) {
                float left = 0.0f;
                float right = 0.0f;
                if (sampleFormat.channels >= 2) {
                    left = data[0][sourceFrameIndex];
                    right = data[1][sourceFrameIndex];
                } else if (sampleFormat.channels == 1) {
                    left = data[0][sourceFrameIndex];
                    right = data[0][sourceFrameIndex];
                }
                if (downmixToMono) {
                    float mono = (left + right) * 0.5f;
                    left = mono;
                    right = mono;
                }
                outputLeft[outputFrameIndex] = left;
                outputRight[outputFrameIndex] = right;
                sourceFrameIndex++;
            }
            lastSliceHash = HashAudioSlice(stream.floatChannelData, (uint32_t) stream.format.channelCount, inputWindowFrameCount);
            if (accumulatedSeconds == 0.0) {
                signatureStartFrame = chunkStartFrame;
                signatureLocalFrame = 0;
            }
            NSError* signatureError = nil;
            AVAudioTime* time = nil;
            if (!useNilTime) {
                time = [AVAudioTime timeWithSampleTime:(AVAudioFramePosition) signatureLocalFrame atRate:_sample.renderedSampleRate];
            }
            BOOL appended = AppendSignatureBuffer(generator, stream, time, &signatureError);
            if (!appended) {
                NSLog(@"[Detect] signature append failed offset=%llu error=%@", chunkStartFrame, signatureError);
                if (!loggedAppendFailure) {
                    loggedAppendFailure = YES;
                    fprintf(stderr, "[Detect] signature append failed at offset=%llu\n", chunkStartFrame);
                }
                continue;
            }
            signatureLocalFrame += (unsigned long long) inputWindowFrameCount;
            if (_debugScoring && !loggedAppendSuccess) {
                loggedAppendSuccess = YES;
            }
            accumulatedSeconds += (double) inputWindowFrameCount / _sample.renderedSampleRate;

            BOOL shouldMatch = (accumulatedSeconds >= targetSignatureSeconds);
            if (shouldMatch) {
                SHSignature* signature = [generator signature];
                if (signature == nil) {
                    NSLog(@"[Detect] signature generation failed offset=%llu", signatureStartFrame);
                    generator = [[SHSignatureGenerator alloc] init];
                    accumulatedSeconds = 0.0;
                    signatureLocalFrame = 0;
                    continue;
                }

                dispatch_semaphore_wait(_matchInFlightSemaphore, DISPATCH_TIME_FOREVER);
                _sessionFrameOffset = signatureStartFrame;
                NSNumber* offset = [NSNumber numberWithUnsignedLongLong:signatureStartFrame];

                dispatch_sync(_identifyQueue, ^{
                    [_pendingMatchOffsets addObject:offset];
                    _inFlightCount += 1;
                    if (_inFlightCount > _maxInFlightCount) {
                        _maxInFlightCount = _inFlightCount;
                    }
                    _requestStartTimeByOffset[offset] = @(CFAbsoluteTimeGetCurrent());
                    _requestSliceHashByOffset[offset] = [NSString stringWithFormat:@"%016llx", lastSliceHash];
                });
                _matchRequestCount += 1;
                [_session matchSignature:signature];
                generator = [[SHSignatureGenerator alloc] init];
                accumulatedSeconds = 0.0;
                signatureLocalFrame = 0;
            }
        };
        _totalFrameCursor += received;
    };
    _finishedFeeding = YES;
    return YES;
}

- (ActivityToken*)detectTracklistWithCallback:(nonnull void (^)(BOOL, NSError*, NSArray<TimedMediaMetaData*>*))callback
{
    __weak typeof(self) weakSelf = self;
    __block BOOL done = NO;
    __block dispatch_block_t queueBlock = NULL;

    _completionHandler = [callback copy];
    [_identifieds removeAllObjects];
    _matchRequestCount = 0;
    _matchResponseCount = 0;
    _inFlightCount = 0;
    _maxInFlightCount = 0;
    _responseLatencySum = 0.0;
    _responseLatencyMin = DBL_MAX;
    _responseLatencyMax = 0.0;
    _firstMatchFrame = ULLONG_MAX;
    [_matchFrames removeAllObjects];
    _finishedFeeding = NO;
    _completionSent = NO;
    _totalFrameCursor = 0;
    [_pendingMatchOffsets removeAllObjects];
    [_requestStartTimeByOffset removeAllObjects];

    _token = [[ActivityManager shared] beginActivityWithTitle:PECLocalizedString(@"activity.tracklist_detection.title", @"Title for tracklist detection activity")
                                                       detail:nil
                                                  cancellable:YES
                                                cancelHandler:^{
                                                    [weakSelf abortWithCallback:^{
                                                        TotalIdentificationController* strongSelf = weakSelf;
                                                        if (strongSelf == nil) {
                                                            return;
                                                        }
                                                        [[ActivityManager shared] updateActivity:strongSelf->_token detail:PECLocalizedString(@"activity.tracklist_detection.aborted", @"Detail when tracklist detection is aborted")];
                                                        [[ActivityManager shared] completeActivity:strongSelf->_token];
                                                        strongSelf->_completionHandler(NO, nil, nil);
                                                    }];
                                                }];

    dispatch_block_t block = dispatch_block_create(DISPATCH_BLOCK_NO_QOS_CLASS, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        done = [strongSelf detectTracklist];
    });

    queueBlock = block;
    _queueOperation = block;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), queueBlock);

    NSLog(@"starting track list detection");
    dispatch_block_notify(_queueOperation, dispatch_get_main_queue(), ^{
        TotalIdentificationController* strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        if (queueBlock != NULL && dispatch_block_testcancel(queueBlock) != 0) {
            return;
        }
        NSLog(@"track detection feed finished with %d - checking completion", done);
        [strongSelf checkForCompletion];
    });
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

    double avgLatency = 0.0;
    if (_matchResponseCount > 0) {
        avgLatency = _responseLatencySum / (double) _matchResponseCount;
    }
    double minLatency = _responseLatencyMin == DBL_MAX ? 0.0 : _responseLatencyMin;
    if (_debugScoring) {
        NSLog(@"firing completion after %lu requests / %lu responses "
              @"(finishedFeeding=%d) inFlightMax=%lu "
              @"latency(avg/min/max)=%.3f/%.3f/%.3f",
              (unsigned long) _matchRequestCount, (unsigned long) _matchResponseCount, _finishedFeeding, (unsigned long) _maxInFlightCount, avgLatency,
              minLatency, _responseLatencyMax);
    }
    if (_debugScoring && _firstMatchFrame != ULLONG_MAX) {
        double rate = _sample != nil ? _sample.renderedSampleRate : 0.0;
        double firstMatchSeconds = rate > 0.0 ? ((double) _firstMatchFrame / rate) : 0.0;
        NSMutableArray<NSNumber*>* sorted = [_matchFrames mutableCopy];
        [sorted sortUsingComparator:^NSComparisonResult(NSNumber* a, NSNumber* b) {
            if (a.unsignedLongLongValue < b.unsignedLongLongValue) {
                return NSOrderedAscending;
            }
            if (a.unsignedLongLongValue > b.unsignedLongLongValue) {
                return NSOrderedDescending;
            }
            return NSOrderedSame;
        }];
        NSMutableArray<NSNumber*>* deltas = [NSMutableArray array];
        for (NSUInteger i = 1; i < sorted.count; i++) {
            unsigned long long prev = sorted[i - 1].unsignedLongLongValue;
            unsigned long long cur = sorted[i].unsignedLongLongValue;
            if (cur > prev) {
                [deltas addObject:@(cur - prev)];
            }
        }
        double medianSeconds = 0.0;
        double p25Seconds = 0.0;
        double p75Seconds = 0.0;
        double meanSeconds = 0.0;
        if (deltas.count > 0 && rate > 0.0) {
            [deltas sortUsingComparator:^NSComparisonResult(NSNumber* a, NSNumber* b) {
                if (a.unsignedLongLongValue < b.unsignedLongLongValue) {
                    return NSOrderedAscending;
                }
                if (a.unsignedLongLongValue > b.unsignedLongLongValue) {
                    return NSOrderedDescending;
                }
                return NSOrderedSame;
            }];
            unsigned long long sumFrames = 0;
            for (NSNumber* n in deltas) {
                sumFrames += n.unsignedLongLongValue;
            }
            meanSeconds = ((double) sumFrames / (double) deltas.count) / rate;
            NSUInteger mid = deltas.count / 2;
            NSUInteger p25 = (NSUInteger) ((double) (deltas.count - 1) * 0.25);
            NSUInteger p75 = (NSUInteger) ((double) (deltas.count - 1) * 0.75);
            medianSeconds = ((double) deltas[mid].unsignedLongLongValue) / rate;
            p25Seconds = ((double) deltas[p25].unsignedLongLongValue) / rate;
            p75Seconds = ((double) deltas[p75].unsignedLongLongValue) / rate;
        }
        NSLog(@"[ShazamTiming] firstMatch=%.2fs "
              @"delta(mean/p25/p50/p75)=%.2f/%.2f/%.2f/%.2f samples=%lu",
              firstMatchSeconds, meanSeconds, p25Seconds, medianSeconds, p75Seconds, (unsigned long) _matchFrames.count);
    }

    NSArray<TimedMediaMetaData*>* refined = nil;
    if (self.skipRefinement) {
        refined = [_identifieds copy];
        if (_debugScoring) {
            [self logTracklist:refined tag:@"Shazam" includeDuration:NO];
        }
        [[ActivityManager shared] updateActivity:_token detail:PECLocalizedString(@"activity.tracklist_detection.baseline_done", @"Detail when baseline detection is done")];
    } else {
        [[ActivityManager shared] updateActivity:_token detail:PECLocalizedString(@"activity.tracklist_detection.refining", @"Detail while refining tracklist")];
        refined = [self refineTracklist];
        [[ActivityManager shared] updateActivity:_token detail:PECLocalizedString(@"activity.tracklist_detection.refinement_done", @"Detail when tracklist refinement is done")];
    }
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
    if (_finishedFeeding) {
        if (self.useStreamingMatch) {
            if (_streamingCompletionScheduled) {
                return;
            }
            _streamingCompletionScheduled = YES;
            __weak typeof(self) weakSelf = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t) (3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                TotalIdentificationController* strongSelf = weakSelf;
                if (strongSelf == nil || strongSelf->_completionSent) {
                    return;
                }
                [strongSelf fireCompletion];
            });
            return;
        }
        if (self.skipRefinement) {
            if (_matchRequestCount > 0 && _matchResponseCount < _matchRequestCount) {
                __weak typeof(self) weakSelf = self;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t) (0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    TotalIdentificationController* strongSelf = weakSelf;
                    if (strongSelf == nil || strongSelf->_completionSent) {
                        return;
                    }
                    [strongSelf checkForCompletion];
                });
                return;
            }
            [self fireCompletion];
            return;
        }
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t) (3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            TotalIdentificationController* strongSelf = weakSelf;
            if (strongSelf == nil || strongSelf->_completionSent) {
                return;
            }
            [strongSelf fireCompletion];
        });
        return;
    }
    return;
}

#pragma mark - Shazam Delegate

- (void)session:(SHSession*)session didFindMatch:(SHMatch*)match
{
    __weak TotalIdentificationController* weakSelf = self;

    dispatch_async(_identifyQueue, ^{
        TotalIdentificationController* strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        NSNumber* offset = nil;
        if (strongSelf->_pendingMatchOffsets.count > 0) {
            offset = strongSelf->_pendingMatchOffsets.firstObject;
            [strongSelf->_pendingMatchOffsets removeObjectAtIndex:0];
        }
        if (offset == nil) {
            offset = [NSNumber numberWithUnsignedLongLong:strongSelf->_sessionFrameOffset];
        }
        NSNumber* startTime = strongSelf->_requestStartTimeByOffset[offset];
        if (startTime != nil) {
            double latency = CFAbsoluteTimeGetCurrent() - startTime.doubleValue;
            strongSelf->_responseLatencySum += latency;
            strongSelf->_responseLatencyMin = MIN(strongSelf->_responseLatencyMin, latency);
            strongSelf->_responseLatencyMax = MAX(strongSelf->_responseLatencyMax, latency);
            [strongSelf->_requestStartTimeByOffset removeObjectForKey:offset];
        }
        NSString* sliceHash = strongSelf->_requestSliceHashByOffset[offset];
        if (sliceHash != nil) {
            [strongSelf->_requestSliceHashByOffset removeObjectForKey:offset];
        } else {
            sliceHash = @"-";
        }
        if (strongSelf->_inFlightCount > 0) {
            strongSelf->_inFlightCount -= 1;
        }
        if (!strongSelf.useStreamingMatch) {
            dispatch_semaphore_signal(strongSelf->_matchInFlightSemaphore);
        }
        NSArray<SHMatchedMediaItem*>* items = match.mediaItems;
        if (items.count == 0) {
            TimedMediaMetaData* track = [TimedMediaMetaData unknownTrackAtFrame:offset];
            //            NSString* runID = strongSelf->_shazamRunID ?: @"-";
            //            if (strongSelf->_debugScoring) {
            //                NSLog(@"[ShazamRaw] run:%@ slice:%@ frame:%llu artist:%@
            //                title:%@ score:0.000 confidence:1",
            //                      runID,
            //                      sliceHash,
            //                      offset.unsignedLongLongValue,
            //                      track.meta.artist ?: @"",
            //                      track.meta.title ?: @"");
            //            }
            [[ActivityManager shared] updateActivity:strongSelf->_token detail:[NSString stringWithFormat:PECLocalizedString(@"activity.tracklist_detection.maybe_format", @"Format for tentative track match detail"), track.meta.title]];

            NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
            BOOL excludeUnknown = [defaults boolForKey:@"ExcludeUnknownInputs"];
            if (!excludeUnknown) {
                [strongSelf->_identifieds addObject:track];
            }
            unsigned long long next = strongSelf->_matchResponseCount + 1;
            strongSelf->_matchResponseCount = MIN(next, strongSelf->_matchRequestCount);
            [strongSelf checkForCompletion];
            return;
        }

        NSMutableArray<TimedMediaMetaData*>* tracks = [NSMutableArray arrayWithCapacity:items.count];
        for (SHMatchedMediaItem* item in items) {
            TimedMediaMetaData* track = [[TimedMediaMetaData alloc] initWithMatchedMediaItem:item frame:offset];
            [tracks addObject:track];
            [[ActivityManager shared] updateActivity:strongSelf->_token detail:[NSString stringWithFormat:PECLocalizedString(@"activity.tracklist_detection.maybe_format", @"Format for tentative track match detail"), track.meta.title]];
        }
        //        if (strongSelf->_debugScoring) {
        //            for (TimedMediaMetaData* track in tracks) {
        //                NSLog(@"[ShazamRaw] run:%@ slice:%@ frame:%llu artist:%@
        //                title:%@ score:0.000 confidence:1",
        //                      runID,
        //                      sliceHash,
        //                      offset.unsignedLongLongValue,
        //                      track.meta.artist ?: @"",
        //                      track.meta.title ?: @"");
        //            }
        //        }
        if (strongSelf->_firstMatchFrame == ULLONG_MAX) {
            strongSelf->_firstMatchFrame = offset.unsignedLongLongValue;
        }
        [strongSelf->_matchFrames addObject:offset];

        dispatch_group_t artworkGroup = dispatch_group_create();
        for (TimedMediaMetaData* track in tracks) {
            if (track.meta.artworkLocation != nil) {
                dispatch_group_enter(artworkGroup);
                [[ImageController shared] resolveDataForURL:track.meta.artworkLocation
                                                   callback:^(NSData* data) {
                                                       track.meta.artwork = data;
                                                       dispatch_group_leave(artworkGroup);
                                                   }];
            }
        }

        dispatch_group_notify(artworkGroup, strongSelf->_identifyQueue, ^{
            TotalIdentificationController* strongSelf = weakSelf;
            if (strongSelf == nil) {
                return;
            }
            [strongSelf->_identifieds addObjectsFromArray:tracks];
            unsigned long long next = strongSelf->_matchResponseCount + 1;
            strongSelf->_matchResponseCount = MIN(next, strongSelf->_matchRequestCount);
            [strongSelf checkForCompletion];
        });
    });
}

- (void)session:(SHSession*)session didNotFindMatchForSignature:(SHSignature*)signature error:(nullable NSError*)error
{
    __weak TotalIdentificationController* weakSelf = self;

    if (error != nil) {
        NSLog(@"[Detect] didNotFindMatch error=%@", error);
    }

    dispatch_async(_identifyQueue, ^{
        TotalIdentificationController* strongSelf = weakSelf;
        if (strongSelf != nil) {
            NSNumber* offset = nil;
            if (strongSelf->_pendingMatchOffsets.count > 0) {
                offset = strongSelf->_pendingMatchOffsets.firstObject;
                [strongSelf->_pendingMatchOffsets removeObjectAtIndex:0];
            }
            if (offset == nil) {
                offset = [NSNumber numberWithUnsignedLongLong:strongSelf->_sessionFrameOffset];
            }
            NSNumber* startTime = strongSelf->_requestStartTimeByOffset[offset];
            if (startTime != nil) {
                double latency = CFAbsoluteTimeGetCurrent() - startTime.doubleValue;
                strongSelf->_responseLatencySum += latency;
                strongSelf->_responseLatencyMin = MIN(strongSelf->_responseLatencyMin, latency);
                strongSelf->_responseLatencyMax = MAX(strongSelf->_responseLatencyMax, latency);
                [strongSelf->_requestStartTimeByOffset removeObjectForKey:offset];
            }
            NSString* sliceHash = strongSelf->_requestSliceHashByOffset[offset];
            if (sliceHash != nil) {
                [strongSelf->_requestSliceHashByOffset removeObjectForKey:offset];
            } else {
                sliceHash = @"-";
            }
            if (strongSelf->_inFlightCount > 0) {
                strongSelf->_inFlightCount -= 1;
            }
            if (!strongSelf.useStreamingMatch) {
                dispatch_semaphore_signal(strongSelf->_matchInFlightSemaphore);
            }
            TimedMediaMetaData* track = [TimedMediaMetaData unknownTrackAtFrame:offset];
            //            NSString* runID = strongSelf->_shazamRunID ?: @"-";
            //            if (strongSelf->_debugScoring) {
            //                NSLog(@"[ShazamRaw] run:%@ slice:%@ frame:%llu artist:%@
            //                title:%@ score:0.000 confidence:1",
            //                      runID,
            //                      sliceHash,
            //                      offset.unsignedLongLongValue,
            //                      track.meta.artist ?: @"",
            //                      track.meta.title ?: @"");
            //            }

            [[ActivityManager shared] updateActivity:strongSelf->_token detail:[NSString stringWithFormat:PECLocalizedString(@"activity.tracklist_detection.maybe_format", @"Format for tentative track match detail"), track.meta.title]];

            NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
            BOOL excludeUnknown = [defaults boolForKey:@"ExcludeUnknownInputs"];
            if (!excludeUnknown) {
                [strongSelf->_identifieds addObject:track];
            }
            unsigned long long next = strongSelf->_matchResponseCount + 1;
            strongSelf->_matchResponseCount = MIN(next, strongSelf->_matchRequestCount);
            [strongSelf checkForCompletion];
        }
    });
}

@end

NS_ASSUME_NONNULL_END
