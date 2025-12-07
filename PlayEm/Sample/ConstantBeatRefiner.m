//
//  ConstantBeatRefiner.m
//  PlayEm
//
//  Created by Till Toenshoff on 12/31/24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//
#import <Foundation/Foundation.h>
#import "ConstantBeatRefiner.h"
#import "LazySample.h"

/**
 Uses the given center BPM and tries to round it within the limits of
 the given minimum and maximum.
 
 Rounding strategies here are rather interesting;
 1st: try to round to nearest integer
 2nd: try to round to nearest half integer
 3rd; try to round to nearest 12th of an integer
 
 When all rounding strategies fail, return the center frequency as it
 appears to be super precise - or our given extrema were total bogus.
 */
double roundBpmWithinRange(double minBpm, double centerBpm, double maxBpm)
{
    //NSLog(@"rounding BPM - min: %.4f, center: %.4f, max: %.4f", minBpm, centerBpm, maxBpm);

    // First try to snap to a full integer BPM
    double snapBpm = (double)round(centerBpm);
    if (snapBpm > minBpm && snapBpm < maxBpm) {
        // Success
        return snapBpm;
    }

    // Probe the reasonable multipliers for 0.5.
    const double roundBpmWidth = maxBpm - minBpm;
    if (roundBpmWidth > 0.5) {
        // 0.5 BPM are only reasonable if the double value is not insane
        // or the 2/3 value is not too small.
        if (centerBpm < (double)(85.0)) {
            // This cane be actually up to 175 BPM allow halve BPM values.
            return (double)(round(centerBpm * 2) / 2);
        } else if (centerBpm > (double)(127.0)) {
            // Optimize for 2/3 going down to 85.
            return (double)(round(centerBpm/ 3 * 2) * 3 / 2);
        }
    }

    if (roundBpmWidth > 1.0 / 12) {
        // This covers all sorts of 1/2 2/3 and 3/4 multiplier.
        return (double)(round(centerBpm * 12) / 12);
    } else {
        // We are here if we have more than ~75 beats and ~30 s
        // try to snap to a 1/12 BPM.
        snapBpm = (double)(round(centerBpm * 12) / 12);
        if (snapBpm > minBpm && snapBpm < maxBpm) {
            // Success
            return snapBpm;
        }
        // else give up and use the original BPM value.
    }

    return centerBpm;
}

// When ironing the grid for long sequences of const tempo we use
// a 25 ms tolerance because this small of a difference is inaudible
// This is > 2 * 12 ms, the step width of the QM beat detector.
// We are actually using a smaller hop-size of 256 frames for the libaubio
// beat detector. However, the parameters seem good enough.
static const double kMaxSecsPhaseError = 0.025;
// This is set to avoid to use a constant region during an offset shift.
// That happens for instance when the beat instrument changes.
static const double kMaxSecsPhaseErrorSum = 0.1;
static const int kMaxOutliersCount = 1;
static const int kMinRegionBeatCount = 10;

@implementation BeatTrackedSample(ConstantBeatRefiner)

/**
 Locate and retrieve regions with a constant beat detection. Such region
 has a phase error that remains below a threshold. With the given detection method,
 we hardly ever get to 16 beats of stable detection - even with enabled lowpass filter.
 
 This is mostly a copy of code from MixxxDJ.
 from https://github.com/mixxxdj/mixxx/blob/8354c8e0f57a635acb7f4b3cc16b9745dc83312c/src/track/beatutils.cpp#L51
 */
- (NSData*)retrieveConstantRegions
{
    NSLog(@"pass two: locate constant regions");
    
    // Original comment doesnt apply exactly -- we are not using the QM detector but the
    // libaubio one. Anyway, the rest applies equally.
    //---
    // The aubio detector has a step size of 256 frames @ 44100 Hz. This means that
    // Single beats have has a jitter of +- 6 ms around the actual position.
    // Expressed in BPM it means we have for instance steps of these BPM value around 120 BPM
    // 117.454 - 120.185 - 123.046 - 126.048
    // A pure electronic 120.000 BPM track will have many 120,185 BPM beats and a few
    // 117,454 BPM beats to adjust the collected offset.
    // This function irons these adjustment beats by adjusting every beat to the average of
    // a likely constant region.
    // Therefore we loop through the coarse beats and calculate the average beat
    // length from the first beat.
    // A inner loop checks for outliers using the momentary average as beat length.
    // Once we have found an average with only single outliers, we store the beats using the
    // current average to adjust them by up to +-6 ms.
    // Then we start with the region from the found beat to the end.
    //---
    
    const double maxPhaseError = kMaxSecsPhaseError * self.sample.sampleFormat.rate;
    const double maxPhaseErrorSum = kMaxSecsPhaseErrorSum * self.sample.sampleFormat.rate;
    const unsigned long long *coarseBeats = self.coarseBeats.bytes;
    const size_t coarseBeatCount = self.coarseBeats.length / sizeof(unsigned long long);
    if (coarseBeatCount == 0) {
        return nil;
    }
    size_t leftIndex = 0;
    size_t rightIndex = coarseBeatCount - 1;
    
    NSMutableData* constantRegions = [NSMutableData data];
    // Go through all the beats there are...
    while (leftIndex < coarseBeatCount - 1) {
        NSAssert(rightIndex > leftIndex, @"somehow we ended up with an invalid right index");
        
        // Calculate the frame count between the first and the last detected beat.
        double meanBeatLength = (double)(coarseBeats[rightIndex] - coarseBeats[leftIndex]) / (double)(rightIndex - leftIndex);
        
        int outliersCount = 0;
        unsigned long long ironedBeat = coarseBeats[leftIndex];
        double phaseErrorSum = 0;
        size_t i = leftIndex + 1;
        
        for (; i <= rightIndex; ++i) {
            ironedBeat += meanBeatLength;
            const double phaseError = (double)ironedBeat - coarseBeats[i];
            phaseErrorSum += phaseError;
            
            if (fabs(phaseError) > maxPhaseError) {
                outliersCount++;
                // The first beat must not be an outlier just like the number of outliers
                // overall must not be beyond
                if (outliersCount > kMaxOutliersCount || i == leftIndex + 1) {
                    break;
                }
            }
            if (fabs(phaseErrorSum) > maxPhaseErrorSum) {
                // we drift away in one direction, the meanBeatLength is not optimal.
                break;
            }
        }
        if (i > rightIndex) {
            double regionBorderError = 0;
            // Verify that the first and the last beat are not correction beats in the same direction
            // as this would bend meanBeatLength unfavorably away from the optimum.
            if (rightIndex > leftIndex + 2) {
                const double firstBeatLength = coarseBeats[leftIndex + 1] - coarseBeats[leftIndex];
                const double lastBeatLength = coarseBeats[rightIndex] - coarseBeats[rightIndex - 1];
                regionBorderError = fabs(firstBeatLength + lastBeatLength - (2.0 * meanBeatLength));
            }
            if (regionBorderError <= maxPhaseError / 2.0) {
                // We have found a constant enough region.
                const unsigned long long firstBeat = coarseBeats[leftIndex];
                // store the regions for the later stages
                BeatConstRegion region = { firstBeat, meanBeatLength };
                [constantRegions appendBytes:&region length:sizeof(BeatConstRegion)];
                // continue with the next region.
                leftIndex = rightIndex;
                rightIndex = coarseBeatCount - 1;
                continue;
            }
//            else {
//                NSLog(@"mean border error got too large for beat %ld to %ld = %f", leftIndex, rightIndex, regionBorderError);
//            }
        }
        // Try a by one beat smaller region.
        rightIndex--;
    }
    
    // Add a final region with zero length to mark the end.
    BeatConstRegion region = { coarseBeats[coarseBeatCount - 1], 0 };
    [constantRegions appendBytes:&region length:sizeof(BeatConstRegion)];
    
    return constantRegions;
}

/**
 This is mostly a copy of code from MixxxDJ.
 from https://github.com/mixxxdj/mixxx/blob/8354c8e0f57a635acb7f4b3cc16b9745dc83312c/src/track/beatutils.cpp#L140
 
 There is however a slight change that has rather dramatic consequences in my
 testing. Any functional modifications are highlighted by comments lead by `CHANGE:`.
 */
- (double)makeConstBpm:(NSData*)constantRegions firstBeat:(signed long long*)pFirstBeat
{
    NSAssert(constantRegions.length > 0, @"no constant regions found");
    
    // We assume here the track was recorded with an unhear-able static metronome.
    // This metronome is likely at a full BPM.
    // The track may has intros, outros and bridges without detectable beats.
    // In these regions the detected beat might is floating around and is just wrong.
    // The track may also has regions with different rhythm giving instruments. They
    // have a different shape of onsets and introduce a static beat offset.
    // The track may also have break beats or other issues that makes the detector
    // hook onto a beat that is by an integer fraction off the original metronome.
    
    // This code aims to find the static metronome and a phase offset.
    
    // Find the longest region somewhere in the middle of the track to start with.
    // At least this region will be have finally correct annotated beats.
    
    int midRegionIndex = 0;
    double longestRegionLength = 0;
    double longestRegionBeatLength = 0;
    int longestRegionNumberOfBeats = 0;
    size_t regionsCount = constantRegions.length / sizeof(BeatConstRegion);
    
    const BeatConstRegion* regions = constantRegions.bytes;
    
    NSLog(@"pass three: identify longest constant region from out of %ld", regionsCount);
    
    for (int i = 0; i < regionsCount - 1; ++i) {
        double length = regions[i + 1].firstBeatFrame - regions[i].firstBeatFrame;
        // CHANGE: Calculate the number of beats right away instead of relying on the
        // region length for comparison. The observation was that the old code did
        // prefer long regions with long beat duration which in my opinion it should not.
        // The updated code shows a much better resultset in that we later have a higher
        // success rate in identifying additional constant regions that fit in phase.
        int beatCount = (int)((length / regions[i].beatLength) + 0.5);
        if (beatCount > longestRegionNumberOfBeats) {
            longestRegionLength = length;
            longestRegionBeatLength = regions[i].beatLength;
            longestRegionNumberOfBeats = beatCount;
            midRegionIndex = i;
            NSLog(@"%d: %.0f %.0f", i, length, regions[i].beatLength);
        }
    }
    
    if (longestRegionLength == 0) {
        // Could not infer a tempo.
        return 0.0;
    }
    
    NSLog(@"longest constant region: %.2f frames, %d beats", longestRegionLength, longestRegionNumberOfBeats);
    
    double longestRegionBeatLengthMin = longestRegionBeatLength - ((kMaxSecsPhaseError * self.sample.sampleFormat.rate) / longestRegionNumberOfBeats);
    double longestRegionBeatLengthMax = longestRegionBeatLength + ((kMaxSecsPhaseError * self.sample.sampleFormat.rate) / longestRegionNumberOfBeats);
    
    int startRegionIndex = midRegionIndex;
    
    NSLog(@"pass four: find a region at the beginning of the track with a similar tempo and phase");
    
    // Find a region at the beginning of the track with a similar tempo and phase.
    for (int i = 0; i < midRegionIndex; ++i) {
        const double length = regions[i + 1].firstBeatFrame - regions[i].firstBeatFrame;
        const int numberOfBeats = (int)((length / regions[i].beatLength) + 0.5);
        if (numberOfBeats < kMinRegionBeatCount) {
            // Request short regions, too unstable.
            continue;
        }
        const double thisRegionBeatLengthMin = regions[i].beatLength - ((kMaxSecsPhaseError * self.sample.sampleFormat.rate) / numberOfBeats);
        const double thisRegionBeatLengthMax = regions[i].beatLength + ((kMaxSecsPhaseError * self.sample.sampleFormat.rate) / numberOfBeats);
        // Check if the tempo of the longest region is part of the rounding range of this region.
        if (longestRegionBeatLength > thisRegionBeatLengthMin && longestRegionBeatLength < thisRegionBeatLengthMax) {
            // Now check if both regions are at the same phase.
            const double newLongestRegionLength = regions[midRegionIndex + 1].firstBeatFrame - regions[i].firstBeatFrame;
            
            double beatLengthMin = MAX(longestRegionBeatLengthMin, thisRegionBeatLengthMin);
            double beatLengthMax = MIN(longestRegionBeatLengthMax, thisRegionBeatLengthMax);
            
            const int maxNumberOfBeats = (int)(round(newLongestRegionLength / beatLengthMin));
            const int minNumberOfBeats = (int)(round(newLongestRegionLength / beatLengthMax));
            
            if (minNumberOfBeats != maxNumberOfBeats) {
                // Ambiguous number of beats, find a closer region.
                NSLog(@"ambiguous number of beats - %d != %d - find a closer region ...", minNumberOfBeats, maxNumberOfBeats);
                continue;
            }
            const int numberOfBeats = minNumberOfBeats;
            const double newBeatLength = newLongestRegionLength / numberOfBeats;
            if (newBeatLength > longestRegionBeatLengthMin && newBeatLength < longestRegionBeatLengthMax) {
                longestRegionLength = newLongestRegionLength;
                longestRegionBeatLength = newBeatLength;
                longestRegionNumberOfBeats = numberOfBeats;
                longestRegionBeatLengthMin = longestRegionBeatLength - ((kMaxSecsPhaseError * self.sample.sampleFormat.rate) / longestRegionNumberOfBeats);
                longestRegionBeatLengthMax = longestRegionBeatLength + ((kMaxSecsPhaseError * self.sample.sampleFormat.rate) / longestRegionNumberOfBeats);
                startRegionIndex = i;
                break;
            }
        }
    }
    
    NSLog(@"startRegionIndex: %d", startRegionIndex);
    
    NSLog(@"pass five: find a region at the end of the track with a similar tempo and phase");
    
    // Find a region at the end of the track with similar tempo and phase.
    for (size_t i = regionsCount - 2; i > midRegionIndex; --i) {
        const double length = regions[i + 1].firstBeatFrame - regions[i].firstBeatFrame;
        const int numberOfBeats = (int)((length / regions[i].beatLength) + 0.5);
        if (numberOfBeats < kMinRegionBeatCount) {
            continue;
        }
        const double thisRegionBeatLengthMin = regions[i].beatLength - ((kMaxSecsPhaseError * self.sample.sampleFormat.rate) / numberOfBeats);
        const double thisRegionBeatLengthMax = regions[i].beatLength + ((kMaxSecsPhaseError * self.sample.sampleFormat.rate) / numberOfBeats);
        if (longestRegionBeatLength > thisRegionBeatLengthMin && longestRegionBeatLength < thisRegionBeatLengthMax) {
            // Now check if both regions are at the same phase.
            const double newLongestRegionLength = regions[i + 1].firstBeatFrame - regions[startRegionIndex].firstBeatFrame;
            
            double minBeatLength = MAX(longestRegionBeatLengthMin, thisRegionBeatLengthMin);
            double maxBeatLength = MIN(longestRegionBeatLengthMax, thisRegionBeatLengthMax);
            
            const int maxNumberOfBeats = (int)(round(newLongestRegionLength / minBeatLength));
            const int minNumberOfBeats = (int)(round(newLongestRegionLength / maxBeatLength));
            
            if (minNumberOfBeats != maxNumberOfBeats) {
                // Ambiguous number of beats, find a closer region.
                NSLog(@"ambiguous number of beats - %d != %d - find a closer region ...", minNumberOfBeats, maxNumberOfBeats);
                continue;
            }
            const int numberOfBeats = minNumberOfBeats;
            double newBeatLength = newLongestRegionLength / numberOfBeats;
            if (newBeatLength > longestRegionBeatLengthMin && newBeatLength < longestRegionBeatLengthMax) {
                longestRegionLength = newLongestRegionLength;
                longestRegionBeatLength = newBeatLength;
                longestRegionNumberOfBeats = numberOfBeats;
                break;
            }
        }
    }
    
    NSLog(@"longestRegionNumberOfBeats: %d", longestRegionNumberOfBeats);
    
    longestRegionBeatLengthMin = longestRegionBeatLength - ((kMaxSecsPhaseError * self.sample.sampleFormat.rate) / longestRegionNumberOfBeats);
    longestRegionBeatLengthMax = longestRegionBeatLength + ((kMaxSecsPhaseError * self.sample.sampleFormat.rate) / longestRegionNumberOfBeats);
    
    NSLog(@"start: %d, mid: %d, count: %ld, longest: %.2f", startRegionIndex, midRegionIndex, regionsCount, longestRegionLength);
    NSLog(@"first beat: %lld, longest region length: %.2f, number of beats: %d", regions[startRegionIndex].firstBeatFrame, longestRegionLength, longestRegionNumberOfBeats);
    
    NSLog(@"pass six: create a const region from the first beat of the first region to the last beat of the last region");
    
    // Create a const region from the first beat of the first region to the last beat of the last region.
    
    const double minRoundBpm = (double)(60.0 * self.sample.sampleFormat.rate / longestRegionBeatLengthMax);
    const double maxRoundBpm = (double)(60.0 * self.sample.sampleFormat.rate / longestRegionBeatLengthMin);
    const double centerBpm = (double)(60.0 * self.sample.sampleFormat.rate / longestRegionBeatLength);
    const double roundBpm = roundBpmWithinRange(minRoundBpm, centerBpm, maxRoundBpm);
    
    NSLog(@"rounded BPM: %.4f", roundBpm);
    
    if (pFirstBeat) {
        // Move the first beat as close to the start of the track as we can. This is
        // a constant beatgrid so "first beat" only affects the anchor point where
        // bpm adjustments are made.
        // This is a temporary fix, ideally the anchor point for the BPM grid should
        // be the first proper downbeat, or perhaps the CUE point.
        
        // CHANGE: Extended intend is to determine the first beat of every bar.
        //
        // We calculate the frame for the very first beat according to the longest region
        // identified. Now this may not be optimal just yet. There may be cases with some
        // initial silence within the first beats. To account for such cases, we skip
        // numbering beats until the initial silence has passed.
        // Then there may be cases where the true first beat is slightly before the
        // beginning of the song -- weird but there are plenty of examples of such songs.
        // For catching such cases, we check if such misplaced first beat would be less
        // than a quarter beat before the recording.
        
        const double roundedBeatLength = 60.0 * self.sample.sampleFormat.rate / roundBpm;
        
        unsigned long long firstMeasuredGoodBeatFrame = regions[startRegionIndex].firstBeatFrame;
        
        signed long long possibleFirstBeatOffset = (signed long long)fmod(firstMeasuredGoodBeatFrame, roundedBeatLength);
        
        NSLog(@"first possible beat offset %lld", possibleFirstBeatOffset);
        
        // Evaluate if a possible first bar appears to be a bit beyond the beginning of the sample.
        unsigned long long delta = roundedBeatLength - possibleFirstBeatOffset;
        const double errorThreshold = roundedBeatLength / 4.0;
        if (delta < errorThreshold) {
            // We go negative for this initial beat.
            possibleFirstBeatOffset -= roundedBeatLength;
            NSLog(@"graciously adjusted possible beat offset towards frame %lld", possibleFirstBeatOffset);
        }
        
        NSLog(@"silence ends at frame %lld", self.initialSilenceEndsAtFrame);
        NSLog(@"rounded beat length is %lld frames", (unsigned long long)roundedBeatLength);
        
        // Skip as many beat-frames as we can fit into the initial silence.
        unsigned long long skipSilenceFrames = floor(self.initialSilenceEndsAtFrame / roundedBeatLength) * roundedBeatLength;
        if (skipSilenceFrames) {
            possibleFirstBeatOffset += skipSilenceFrames;
            NSLog(@"silently adjusted first beat offset = %lld", possibleFirstBeatOffset);
        }
        
        *pFirstBeat = possibleFirstBeatOffset;
    }
    return roundBpm;
}

/**
 This is mostly a copy of code from MixxxDJ.
 from https://github.com/mixxxdj/mixxx/blob/8354c8e0f57a635acb7f4b3cc16b9745dc83312c/src/track/beatutils.cpp#L386
 */
- (unsigned long long)adjustPhase:(unsigned long long)firstBeat bpm:(double)bpm
{
    const double beatLength = 60 * self.sample.sampleFormat.rate / bpm;
    const unsigned long long startOffset = (unsigned long long)(fmod(firstBeat, beatLength));
    double offsetAdjust = 0;
    double offsetAdjustCount = 0;
    
    const unsigned long long *coarseBeats = self.coarseBeats.bytes;
    const size_t coarseBeatCount = self.coarseBeats.length / sizeof(unsigned long long);
    
    for (int i = 0;i < coarseBeatCount; i++) {\
        double offset = fmod(coarseBeats[i] - startOffset, beatLength);
        if (offset > beatLength / 2) {
            offset -= beatLength;
        }
        if (fabs(offset) < (kMaxSecsPhaseError * self.sample.sampleFormat.rate)) {
            offsetAdjust += offset;
            offsetAdjustCount++;
        }
    }
    offsetAdjust /= offsetAdjustCount;
    NSLog(@"adjusting phase by: %.2f", offsetAdjust);
    //NSAssert(fabs(offsetAdjust) < (kMaxSecsPhaseError * _sample.rate), @"unexpexted phase adjustment");
    
    return firstBeat + offsetAdjust;
}

/**
 This is mostly a copy of code from MixxxDJ.
 from https://github.com/mixxxdj/mixxx/blob/8354c8e0f57a635acb7f4b3cc16b9745dc83312c/src/track/beatfactory.cpp#L51
 */
- (NSMutableData*)makeConstantBeats:(NSData*)constantRegions
{
    if (!constantRegions.length) {
        return 0;
    }
    
    signed long long firstBeatFrame = 0;
    
    const double constBPM = [self makeConstBpm:constantRegions firstBeat:&firstBeatFrame];
    const double beatLength = 60.0 * self.sample.sampleFormat.rate / constBPM;
    
    firstBeatFrame = [self adjustPhase:firstBeatFrame bpm:constBPM];
    
    NSLog(@"first beat frame = %lld with %.2f", firstBeatFrame, constBPM);
    
    BeatEvent event;
    BOOL fakeFirst = firstBeatFrame < 0.0;
    unsigned long long nextBeatFrame = fakeFirst ? 0.0 : firstBeatFrame;
    
    unsigned long long beatIndex = 0;
    unsigned long long beatCountAssumption = (self.sample.frames + (beatLength - 1)) / beatLength;

    // Asert our total beat count is a factor of 4.
    beatCountAssumption = (beatCountAssumption >> 2) << 2;

    unsigned long introBeatCount = 32 << 2;
    unsigned long buildupBeatCount = 64 << 2;
    unsigned long teardownBeatCount;
    unsigned long outroBeatCount;

    // Songs with too few beats for a shakespear format get a shortened variant.
    if (beatCountAssumption < 3 * buildupBeatCount) {
        buildupBeatCount = ((buildupBeatCount >> 1) >> 2) << 2;
        introBeatCount = ((introBeatCount >> 1) >> 2) << 2;
    }

    outroBeatCount = introBeatCount;
    teardownBeatCount = buildupBeatCount;

    const unsigned long long introBeatsStartingAt = introBeatCount;
    const unsigned long long buildupBeatsStartingAt = buildupBeatCount;
    const unsigned long long teardownBeatsStartingAt = beatCountAssumption - teardownBeatCount;
    const unsigned long long outroBeatsStartingAt = beatCountAssumption - outroBeatCount;

    NSMutableData* constantBeats = [NSMutableData data];

    while (nextBeatFrame < self.sample.frames) {
        int index = beatIndex % 4;
        event.frame = nextBeatFrame;
        event.bpm = constBPM;
        event.style = BeatEventStyleBeat;
        event.index = beatIndex;
        if (index == 0) {
            event.style |= BeatEventStyleBar;
        }

        if (beatIndex == 0) {
            event.style |= BeatEventStyleMarkStart;
        } else if (beatIndex == beatCountAssumption) {
            event.style |= BeatEventStyleMarkEnd;
        } else if (beatIndex == introBeatsStartingAt) {
            event.style |= BeatEventStyleMarkIntro;
        } else if (beatIndex == buildupBeatsStartingAt) {
            event.style |= BeatEventStyleMarkBuildup;
        } else if (beatIndex == teardownBeatsStartingAt) {
            event.style |= BeatEventStyleMarkTeardown;
        } else if (beatIndex == outroBeatsStartingAt) {
            event.style |= BeatEventStyleMarkOutro;
        }
        
        if (beatIndex >= outroBeatsStartingAt) {
            event.style |= BeatEventStyleAlarmOutro;
        } else if (beatIndex >= teardownBeatsStartingAt) {
            event.style |= BeatEventStyleAlarmTeardown;
        } else if (beatIndex < introBeatsStartingAt) {
            event.style |= BeatEventStyleAlarmIntro;
        } else if (beatIndex < buildupBeatsStartingAt) {
            event.style |= BeatEventStyleAlarmBuildup;
        }

        const size_t page = event.frame / self.shardFrameCount;
        NSNumber* pageKey = [NSNumber numberWithLong:page];
        
        [constantBeats appendBytes:&event length:sizeof(BeatEvent)];
        
        if ([self.beats objectForKey:pageKey] == nil) {
            [self.beats setObject:@(beatIndex) forKey:pageKey];
        }
        
        if (fakeFirst) {
            nextBeatFrame = firstBeatFrame + beatLength;
            fakeFirst = NO;
        } else {
            nextBeatFrame += beatLength;
        }
        beatIndex++;
    };

    return constantBeats;
}

@end
