//
//  PlayEmTests.m
//  PlayEmTests
//
//  Created by Till Toenshoff on 12/31/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import <XCTest/XCTest.h>

#import "Sample/LazySample.h"
#import "Audio/AudioController.h"
#import "TotalIdentificationController.h"
#import "TimedMediaMetaData.h"

@interface TotalIdentificationController (Testing)
- (double)estimatedDurationForTrack:(TimedMediaMetaData *)track nextTrack:(TimedMediaMetaData * _Nullable)next;
- (NSDictionary<NSString *, NSNumber *> *)testing_metrics;
@end

@interface PlayEmTests : XCTestCase

@end

@implementation PlayEmTests

// Golden reference list for the fixture (artist, title).
- (NSArray<NSDictionary<NSString*, NSString*> *> *)goldenTracks
{
    return @[
        @{@"artist": @"Yotto", @"title": @"Seat 11"},
        @{@"artist": @"Tigerskin & Alfa State", @"title": @"Slippery Roads (Pablo Bolivar Remix)"},
        @{@"artist": @"Saktu", @"title": @"Muted Glow (Extended Mix)"},
    ];
}

static NSString *NormalizedKey(NSString *artist, NSString *title)
{
    NSString *a = [[artist ?: @"" precomposedStringWithCanonicalMapping] lowercaseString];
    NSString *t = [[title ?: @"" precomposedStringWithCanonicalMapping] lowercaseString];
    a = [a stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    t = [t stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return [NSString stringWithFormat:@"%@ - %@", a, t];
}

static BOOL IsUnknownTrack(TimedMediaMetaData *track)
{
    NSString *artist = [[track.meta.artist ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    NSString *title = [[track.meta.title ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    BOOL artistUnknown = (artist.length == 0 || [artist isEqualToString:@"unknown"]);
    BOOL titleUnknown = (title.length == 0 || [title isEqualToString:@"unknown"]);
    return (artistUnknown && titleUnknown);
}

- (NSDictionary *)metricsBaseline
{
    NSString *sourcePath = [NSString stringWithUTF8String:__FILE__];
    NSString *testsDir = [sourcePath stringByDeletingLastPathComponent];
    NSString *projectRoot = [testsDir stringByDeletingLastPathComponent];
    NSString *baselinePath = [projectRoot stringByAppendingPathComponent:@"Training/metrics_baseline.md"];
    NSError *error = nil;
    NSString *text = [NSString stringWithContentsOfFile:baselinePath encoding:NSUTF8StringEncoding error:&error];
    if (!text) {
        NSLog(@"[PlayEmTests] Metrics baseline not found at %@ (%@). Using defaults.", baselinePath, error);
        return @{};
    }

    NSRange openRange = [text rangeOfString:@"{"];
    NSRange closeRange = [text rangeOfString:@"}" options:NSBackwardsSearch];
    if (openRange.location == NSNotFound || closeRange.location == NSNotFound || closeRange.location <= openRange.location) {
        NSLog(@"[PlayEmTests] Metrics baseline missing JSON block. Using defaults.");
        return @{};
    }

    NSString *jsonText = [text substringWithRange:NSMakeRange(openRange.location, closeRange.location - openRange.location + 1)];
    NSData *data = [jsonText dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) {
        return @{};
    }

    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (![json isKindOfClass:[NSDictionary class]] || error) {
        NSLog(@"[PlayEmTests] Metrics baseline JSON parse failed: %@", error);
        return @{};
    }
    return json;
}

// Compare detected tracks against the golden list and log precision/recall style info.
- (NSDictionary<NSString *, NSNumber *> *)reportDetection:(NSArray<TimedMediaMetaData *> *)results
                                                 duration:(NSTimeInterval)durationSeconds
                                            sampleDuration:(NSTimeInterval)sampleDurationSeconds
                                              enforceRules:(BOOL)enforceRules
{
    NSDictionary *baseline = [self metricsBaseline];
    NSUInteger goldenMinMatches = [baseline[@"golden_min_matches"] unsignedIntegerValue];
    NSUInteger totalHitsMin = baseline[@"total_hits_min"] != nil ? [baseline[@"total_hits_min"] unsignedIntegerValue] : 2;
    NSUInteger totalHitsMax = baseline[@"total_hits_max"] != nil ? [baseline[@"total_hits_max"] unsignedIntegerValue] : 6;
    NSUInteger unexpectedMax = baseline[@"unexpected_max"] != nil ? [baseline[@"unexpected_max"] unsignedIntegerValue] : 2;
    NSDictionary *goldenHitsMin = [baseline[@"golden_hits_min"] isKindOfClass:[NSDictionary class]] ? baseline[@"golden_hits_min"] : @{};

    NSArray *golden = [self goldenTracks];
    NSMutableDictionary<NSString *, NSDictionary *> *goldenMap = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *goldenKeys = [NSMutableArray arrayWithCapacity:golden.count];
    for (NSDictionary *g in golden) {
        NSString *k = NormalizedKey(g[@"artist"], g[@"title"]);
        goldenMap[k] = g;
        [goldenKeys addObject:k];
    }

    NSSet<NSString *> *goldenSet = [NSSet setWithArray:goldenKeys];
    NSMutableDictionary<NSString *, NSNumber *> *hitsByKey = [NSMutableDictionary dictionaryWithCapacity:golden.count];
    NSUInteger totalHits = 0;
    NSUInteger unexpectedCount = 0;
    NSUInteger unknownCount = 0;
    NSMutableSet<NSString *> *matchedInOrder = [NSMutableSet set];
    NSUInteger expectedIndex = 0;
    NSUInteger outOfOrderCount = 0;

    NSMutableSet<NSString *> *matchedGold = [NSMutableSet set];
    NSMutableArray<NSString *> *unexpected = [NSMutableArray array];

    for (TimedMediaMetaData *t in results) {
        NSString *k = NormalizedKey(t.meta.artist, t.meta.title);
        if (goldenMap[k]) {
            [matchedGold addObject:k];
            hitsByKey[k] = @([hitsByKey[k] unsignedIntegerValue] + 1);
            totalHits += 1;
            if (![matchedInOrder containsObject:k]) {
                if (expectedIndex < goldenKeys.count && [k isEqualToString:goldenKeys[expectedIndex]]) {
                    [matchedInOrder addObject:k];
                    expectedIndex += 1;
                } else if ([goldenSet containsObject:k]) {
                    outOfOrderCount += 1;
                    if (enforceRules) {
                        XCTFail(@"Out-of-order detection: expected %@ but saw %@",
                                expectedIndex < goldenKeys.count ? goldenKeys[expectedIndex] : @"<none>",
                                k);
                        // Keep collecting metrics for the summary.
                        break;
                    }
                }
            }
        } else {
            if (IsUnknownTrack(t)) {
                unknownCount += 1;
            } else {
                [unexpected addObject:[NSString stringWithFormat:@"%@ - %@", t.meta.artist ?: @"", t.meta.title ?: @""]];
                unexpectedCount += 1;
            }
        }
    }

    NSMutableArray<NSString *> *missing = [NSMutableArray array];
    for (NSString *k in goldenMap) {
        if (![matchedGold containsObject:k]) {
            NSDictionary *g = goldenMap[k];
            [missing addObject:[NSString stringWithFormat:@"%@ - %@", g[@"artist"], g[@"title"]]];
        }
    }

    NSLog(@"[PlayEmTests] Golden comparison: matched %lu / %lu", (unsigned long)matchedGold.count, (unsigned long)golden.count);
    if (missing.count > 0) {
        NSLog(@"[PlayEmTests] Missing (not detected): %@", [missing componentsJoinedByString:@", "]);
    }
    if (unexpected.count > 0) {
        NSLog(@"[PlayEmTests] Unexpected detections: %@", [unexpected componentsJoinedByString:@", "]);
    }
    NSUInteger nonUnknownHits = totalHits + unexpectedCount;
    double hitsPerMinute = 0.0;
    if (sampleDurationSeconds > 0.0) {
        hitsPerMinute = nonUnknownHits / (sampleDurationSeconds / 60.0);
    }
    NSLog(@"[PlayEmTests] Metrics: duration=%.2fs totalHits=%lu unexpected=%lu unknown=%lu hitsPerMin=%.2f",
          durationSeconds,
          (unsigned long)totalHits,
          (unsigned long)unexpectedCount,
          (unsigned long)unknownCount,
          hitsPerMinute);

    if (enforceRules) {
        for (NSString *k in goldenKeys) {
            NSUInteger count = [hitsByKey[k] unsignedIntegerValue];
            NSNumber *minValue = goldenHitsMin[k];
            NSUInteger minCount = minValue != nil ? minValue.unsignedIntegerValue : 0;
            XCTAssertGreaterThanOrEqual(count, minCount, @"Expected at least %lu hits for %@", (unsigned long)minCount, k);
        }
        XCTAssertGreaterThanOrEqual(totalHits, totalHitsMin, @"Unexpected total hit count (min)");
        XCTAssertLessThanOrEqual(totalHits, totalHitsMax, @"Unexpected total hit count (max)");
        XCTAssertLessThanOrEqual(unexpectedCount, unexpectedMax, @"Unexpected detection count too high");
        XCTAssertGreaterThanOrEqual(expectedIndex, goldenMinMatches, @"Missing golden tracks or ordering mismatch.");
    }

    return @{
        @"matched_goldens": @(matchedGold.count),
        @"ordered_matches": @(expectedIndex),
        @"out_of_order": @(outOfOrderCount),
        @"total_hits": @(totalHits),
        @"unexpected": @(unexpectedCount),
        @"unknown": @(unknownCount),
        @"hits_per_min": @(hitsPerMinute),
        @"duration": @(durationSeconds)
    };
}

- (LazySample *)loadFixtureSampleNamed:(NSString *)name extension:(NSString * _Nullable)ext
{
    NSURL *url = [[NSBundle bundleForClass:[self class]] URLForResource:name withExtension:ext];
    if (!url && [name hasPrefix:@"/"]) {
        url = [NSURL fileURLWithPath:name];
    }

    XCTAssertNotNil(url, @"Fixture %@.%@ not found (bundle or path)", name, ext);
    NSError *error = nil;
    LazySample *sample = [[LazySample alloc] initWithPath:url.path error:&error];
    XCTAssertNotNil(sample, @"Failed to load sample: %@", error);
    return sample;
}

- (void)setUp {
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
}

- (void)testDetectionRunsOnFixture
{
    LazySample *sample = [self loadFixtureSampleNamed:@"test_set_patrice" extension:@"mp3"];

    NSLog(@"[PlayEmTests] Loaded sample %@ (duration %.1fs)", sample.source.url.path, sample.duration);

    AudioController* audioController = [AudioController new];
    XCTestExpectation *expectDecodeFinish = [self expectationWithDescription:@"decoding finished"];

    [audioController decodeAsyncWithSample:sample callback:^(BOOL decodeFinished){
        if (decodeFinished) {
            [expectDecodeFinish fulfill];
        }
    }];
    NSLog(@"[PlayEmTests] Decoding sample %@", sample.source.url.path);

    [self waitForExpectations:@[expectDecodeFinish] timeout:30.0];

    NSLog(@"[PlayEmTests] Sample decoded");

    const char *jitterEnv = getenv("PLAYEM_JITTER_RUNS");
    NSUInteger runCount = 1;
    if (jitterEnv != NULL) {
        int value = atoi(jitterEnv);
        if (value > 0) {
            runCount = (NSUInteger)value;
        }
    }
    if (runCount > 5) {
        runCount = 5;
    }
    NSMutableArray<NSDictionary<NSString *, NSNumber *> *> *runMetrics = [NSMutableArray array];

    const char *windowEnv = getenv("PLAYEM_SIGNATURE_WINDOWS");
    NSMutableArray<NSNumber *> *signatureWindows = [NSMutableArray array];
    if (windowEnv != NULL && strlen(windowEnv) > 0) {
        NSString *raw = [NSString stringWithUTF8String:windowEnv];
        NSArray<NSString *> *parts = [raw componentsSeparatedByString:@","];
        for (NSString *part in parts) {
            double val = [part doubleValue];
            if (val > 0.0) {
                [signatureWindows addObject:@(val)];
            }
        }
    }
    if (signatureWindows.count == 0) {
        [signatureWindows addObject:@0.0];
    }

    const char *perWindowEnv = getenv("PLAYEM_SIGNATURE_RUNS");
    NSUInteger runsPerWindow = 1;
    if (perWindowEnv != NULL) {
        int value = atoi(perWindowEnv);
        if (value > 0) {
            runsPerWindow = (NSUInteger)value;
        }
    }
    const char *hopEnv = getenv("PLAYEM_HOP_SIZE_FRAMES");
    AVAudioFrameCount hopOverride = 0;
    if (hopEnv != NULL) {
        unsigned long long value = strtoull(hopEnv, NULL, 10);
        if (value > 0) {
            hopOverride = (AVAudioFrameCount)value;
        }
    }
    const char *streamingEnv = getenv("PLAYEM_USE_STREAMING_MATCH");
    BOOL useStreamingMatch = NO;
    if (streamingEnv != NULL) {
        int value = atoi(streamingEnv);
        if (value != 0) {
            useStreamingMatch = YES;
        }
    }
    const char *downmixEnv = getenv("PLAYEM_DOWNMIX_TO_MONO");
    BOOL downmixToMono = NO;
    if (downmixEnv != NULL) {
        int value = atoi(downmixEnv);
        if (value != 0) {
            downmixToMono = YES;
        }
    }
    const char *excludeUnknownEnv = getenv("PLAYEM_EXCLUDE_UNKNOWN_INPUTS");
    BOOL excludeUnknownInputs = NO;
    if (excludeUnknownEnv != NULL) {
        int value = atoi(excludeUnknownEnv);
        if (value != 0) {
            excludeUnknownInputs = YES;
        }
    }

    for (NSNumber *windowSeconds in signatureWindows) {
        NSUInteger windowRuns = (windowSeconds.doubleValue > 0.0) ? runsPerWindow : runCount;
        if (windowRuns > 5) {
            windowRuns = 5;
        }
        for (NSUInteger i = 0; i < windowRuns; i++) {
            @autoreleasepool {
                if (windowSeconds.doubleValue > 0.0) {
                    [[NSUserDefaults standardUserDefaults] setDouble:windowSeconds.doubleValue forKey:@"SignatureWindowSeconds"];
                    [[NSUserDefaults standardUserDefaults] setDouble:windowSeconds.doubleValue forKey:@"SignatureWindowMaxSeconds"];
                    NSLog(@"[PlayEmTests] signatureWindow=%.2fs run=%lu/%lu",
                          windowSeconds.doubleValue,
                          (unsigned long)(i + 1),
                          (unsigned long)windowRuns);
                }
                if (hopOverride > 0) {
                    [[NSUserDefaults standardUserDefaults] setDouble:(double)hopOverride forKey:@"HopSizeFrames"];
                    NSLog(@"[PlayEmTests] hopSizeFrames=%llu", (unsigned long long)hopOverride);
                }
                if (useStreamingMatch) {
                    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"UseStreamingMatch"];
                    NSLog(@"[PlayEmTests] useStreamingMatch=1");
                } else {
                    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"UseStreamingMatch"];
                }
                if (downmixToMono) {
                    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"DownmixToMono"];
                    NSLog(@"[PlayEmTests] downmixToMono=1");
                } else {
                    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"DownmixToMono"];
                }
                if (excludeUnknownInputs) {
                    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"ExcludeUnknownInputs"];
                    NSLog(@"[PlayEmTests] excludeUnknownInputs=1");
                } else {
                    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"ExcludeUnknownInputs"];
                }

                TotalIdentificationController *controller = [[TotalIdentificationController alloc] initWithSample:sample];
                controller.debugScoring = YES;
                controller.skipRefinement = YES;

                XCTestExpectation *expectation = [self expectationWithDescription:[NSString stringWithFormat:@"detection finished %lu", (unsigned long)i]];

                __block NSArray<TimedMediaMetaData *> *results = nil;
                __block NSTimeInterval detectionDuration = 0.0;
                CFAbsoluteTime detectionStart = CFAbsoluteTimeGetCurrent();
                [controller detectTracklistWithCallback:^(BOOL success, NSError *error, NSArray<TimedMediaMetaData *> *tracks) {
                    NSLog(@"[PlayEmTests] detection callback success=%d error=%@ tracks=%lu", success, error, (unsigned long)tracks.count);
                    results = tracks;
                    detectionDuration = CFAbsoluteTimeGetCurrent() - detectionStart;
                    [expectation fulfill];
                }];

                [self waitForExpectations:@[expectation] timeout:1200.0];

                XCTAssertNotNil(results);
                XCTAssertGreaterThan(results.count, 0, @"Expected at least one track detected in fixture");

                for (TimedMediaMetaData *t in results) {
                    double dur = [controller estimatedDurationForTrack:t nextTrack:nil];
                    XCTAssertLessThan(dur, 15 * 60, @"Duration too large for track %@ %@", t.meta.artist, t.meta.title);
                }

                NSDictionary<NSString *, NSNumber *> *metrics = [controller testing_metrics];
                if (controller.debugScoring) {
                    NSLog(@"[PlayEmTests] Request metrics: requests=%@ responses=%@ inFlightMax=%@ latency(avg/min/max)=%@/%@/%@",
                          metrics[@"match_requests"],
                          metrics[@"match_responses"],
                          metrics[@"in_flight_max"],
                          metrics[@"latency_avg"],
                          metrics[@"latency_min"],
                          metrics[@"latency_max"]);
                }

                NSDictionary<NSString *, NSNumber *> *summary = [self reportDetection:results
                                                                             duration:detectionDuration
                                                                        sampleDuration:sample.duration
                                                                          enforceRules:NO];
                NSMutableDictionary *merged = [summary mutableCopy];
                if (windowSeconds.doubleValue > 0.0) {
                    merged[@"signature_window"] = windowSeconds;
                }
                merged[@"requests"] = metrics[@"match_requests"] ?: @0;
                merged[@"responses"] = metrics[@"match_responses"] ?: @0;
                merged[@"in_flight_max"] = metrics[@"in_flight_max"] ?: @0;
                merged[@"latency_avg"] = metrics[@"latency_avg"] ?: @0;
                [runMetrics addObject:[merged copy]];
            }
        }
    }

    double durationMin = DBL_MAX, durationMax = 0.0, durationSum = 0.0;
    double hitsPerMinMin = DBL_MAX, hitsPerMinMax = 0.0, hitsPerMinSum = 0.0;
    NSUInteger matchedMin = NSUIntegerMax, matchedMax = 0, matchedSum = 0;
    NSUInteger unexpectedMin = NSUIntegerMax, unexpectedMax = 0, unexpectedSum = 0;
    double latencyAvgMin = DBL_MAX, latencyAvgMax = 0.0, latencyAvgSum = 0.0;
    NSMutableDictionary<NSNumber *, NSMutableArray<NSDictionary<NSString *, NSNumber *> *> *> *runsByWindow = [NSMutableDictionary dictionary];

    for (NSDictionary<NSString *, NSNumber *> *entry in runMetrics) {
        double duration = entry[@"duration"].doubleValue;
        durationMin = MIN(durationMin, duration);
        durationMax = MAX(durationMax, duration);
        durationSum += duration;

        double hitsPerMin = entry[@"hits_per_min"].doubleValue;
        hitsPerMinMin = MIN(hitsPerMinMin, hitsPerMin);
        hitsPerMinMax = MAX(hitsPerMinMax, hitsPerMin);
        hitsPerMinSum += hitsPerMin;

        NSUInteger matched = entry[@"matched_goldens"].unsignedIntegerValue;
        matchedMin = MIN(matchedMin, matched);
        matchedMax = MAX(matchedMax, matched);
        matchedSum += matched;

        NSUInteger unexpected = entry[@"unexpected"].unsignedIntegerValue;
        unexpectedMin = MIN(unexpectedMin, unexpected);
        unexpectedMax = MAX(unexpectedMax, unexpected);
        unexpectedSum += unexpected;

        double latencyAvg = entry[@"latency_avg"].doubleValue;
        latencyAvgMin = MIN(latencyAvgMin, latencyAvg);
        latencyAvgMax = MAX(latencyAvgMax, latencyAvg);
        latencyAvgSum += latencyAvg;

        NSNumber *window = entry[@"signature_window"];
        if (window != nil) {
            NSMutableArray *bucket = runsByWindow[window];
            if (bucket == nil) {
                bucket = [NSMutableArray array];
                runsByWindow[window] = bucket;
            }
            [bucket addObject:entry];
        }
    }

    double runs = (double)runMetrics.count;
    if (runMetrics.count > 1) {
        NSLog(@"[PlayEmTests] Summary over %lu runs:", (unsigned long)runMetrics.count);
        NSLog(@"[PlayEmTests] duration avg/min/max: %.2f / %.2f / %.2f", durationSum / runs, durationMin, durationMax);
        NSLog(@"[PlayEmTests] hitsPerMin avg/min/max: %.2f / %.2f / %.2f", hitsPerMinSum / runs, hitsPerMinMin, hitsPerMinMax);
        NSLog(@"[PlayEmTests] matchedGoldens avg/min/max: %.2f / %lu / %lu",
              (double)matchedSum / runs, (unsigned long)matchedMin, (unsigned long)matchedMax);
        NSLog(@"[PlayEmTests] unexpected avg/min/max: %.2f / %lu / %lu",
              (double)unexpectedSum / runs, (unsigned long)unexpectedMin, (unsigned long)unexpectedMax);
        NSLog(@"[PlayEmTests] latencyAvg avg/min/max: %.3f / %.3f / %.3f",
              latencyAvgSum / runs, latencyAvgMin, latencyAvgMax);
    }

    if (runsByWindow.count > 0) {
        NSArray<NSNumber *> *sortedWindows = [[runsByWindow allKeys] sortedArrayUsingSelector:@selector(compare:)];
        for (NSNumber *window in sortedWindows) {
            NSArray<NSDictionary<NSString *, NSNumber *> *> *entries = runsByWindow[window];
            if (entries.count == 0) {
                continue;
            }
            double wDurationMin = DBL_MAX, wDurationMax = 0.0, wDurationSum = 0.0;
            double wHitsMin = DBL_MAX, wHitsMax = 0.0, wHitsSum = 0.0;
            NSUInteger wMatchedMin = NSUIntegerMax, wMatchedMax = 0, wMatchedSum = 0;
            NSUInteger wUnexpectedMin = NSUIntegerMax, wUnexpectedMax = 0, wUnexpectedSum = 0;
            double wLatencyMin = DBL_MAX, wLatencyMax = 0.0, wLatencySum = 0.0;
            for (NSDictionary<NSString *, NSNumber *> *entry in entries) {
                double duration = entry[@"duration"].doubleValue;
                wDurationMin = MIN(wDurationMin, duration);
                wDurationMax = MAX(wDurationMax, duration);
                wDurationSum += duration;

                double hitsPerMin = entry[@"hits_per_min"].doubleValue;
                wHitsMin = MIN(wHitsMin, hitsPerMin);
                wHitsMax = MAX(wHitsMax, hitsPerMin);
                wHitsSum += hitsPerMin;

                NSUInteger matched = entry[@"matched_goldens"].unsignedIntegerValue;
                wMatchedMin = MIN(wMatchedMin, matched);
                wMatchedMax = MAX(wMatchedMax, matched);
                wMatchedSum += matched;

                NSUInteger unexpected = entry[@"unexpected"].unsignedIntegerValue;
                wUnexpectedMin = MIN(wUnexpectedMin, unexpected);
                wUnexpectedMax = MAX(wUnexpectedMax, unexpected);
                wUnexpectedSum += unexpected;

                double latencyAvg = entry[@"latency_avg"].doubleValue;
                wLatencyMin = MIN(wLatencyMin, latencyAvg);
                wLatencyMax = MAX(wLatencyMax, latencyAvg);
                wLatencySum += latencyAvg;
            }
            NSLog(@"[PlayEmTests] Window %.2fs summary over %lu runs:",
                  window.doubleValue,
                  (unsigned long)entries.count);
            NSLog(@"[PlayEmTests] duration avg/min/max: %.2f / %.2f / %.2f",
                  wDurationSum / entries.count,
                  wDurationMin,
                  wDurationMax);
            NSLog(@"[PlayEmTests] hitsPerMin avg/min/max: %.2f / %.2f / %.2f",
                  wHitsSum / entries.count,
                  wHitsMin,
                  wHitsMax);
            NSLog(@"[PlayEmTests] matchedGoldens avg/min/max: %.2f / %lu / %lu",
                  (double)wMatchedSum / entries.count, (unsigned long)wMatchedMin, (unsigned long)wMatchedMax);
            NSLog(@"[PlayEmTests] unexpected avg/min/max: %.2f / %lu / %lu",
                  (double)wUnexpectedSum / entries.count, (unsigned long)wUnexpectedMin, (unsigned long)wUnexpectedMax);
            NSLog(@"[PlayEmTests] latencyAvg avg/min/max: %.3f / %.3f / %.3f",
                  wLatencySum / entries.count,
                  wLatencyMin,
                  wLatencyMax);
        }
    }

    if (runMetrics.count > 0) {
        NSDateFormatter *formatter = [NSDateFormatter new];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.dateFormat = @"yyyyMMdd_HHmmss";
        NSString *stamp = [formatter stringFromDate:[NSDate date]];
        NSString *baseDir = @"/Users/till/Development/PlayEm/Training/test_summaries";
        [[NSFileManager defaultManager] createDirectoryAtPath:baseDir
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
        NSString *path = [baseDir stringByAppendingPathComponent:[NSString stringWithFormat:@"summary_%@.log", stamp]];
        NSMutableString *out = [NSMutableString string];
        [out appendFormat:@"sample=%@\n", sample.source.url.path];
        [out appendFormat:@"windows=%@\n", [signatureWindows componentsJoinedByString:@","]];
        [out appendFormat:@"runs_per_window=%lu\n", (unsigned long)runsPerWindow];
        [out appendFormat:@"hop_override_frames=%u\n", (unsigned int)hopOverride];
        [out appendFormat:@"use_streaming_match=%d\n", useStreamingMatch ? 1 : 0];
        [out appendFormat:@"downmix_to_mono=%d\n", downmixToMono ? 1 : 0];
        [out appendFormat:@"exclude_unknown_inputs=%d\n", excludeUnknownInputs ? 1 : 0];
        [out appendFormat:@"total_runs=%lu\n", (unsigned long)runMetrics.count];
        for (NSDictionary<NSString *, NSNumber *> *entry in runMetrics) {
            NSNumber *window = entry[@"signature_window"] ?: @0;
            [out appendFormat:@"run window=%.2f duration=%.2f hits_per_min=%.2f matched=%lu unexpected=%lu latency_avg=%.3f\n",
             window.doubleValue,
             entry[@"duration"].doubleValue,
             entry[@"hits_per_min"].doubleValue,
             (unsigned long)entry[@"matched_goldens"].unsignedIntegerValue,
             (unsigned long)entry[@"unexpected"].unsignedIntegerValue,
             entry[@"latency_avg"].doubleValue];
        }
        [out writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSLog(@"[PlayEmTests] Wrote summary to %@", path);
    }

    NSLog(@"[PlayEmTests] Loaded sample %@ (duration %.1fs)", sample.source.url.path, sample.duration);

    AudioController* audioController = [AudioController new];

    XCTestExpectation *expectDecodeFinish = [self expectationWithDescription:@"decoding finished"];

    [audioController decodeAsyncWithSample:sample callback:^(BOOL decodeFinished){
        if (decodeFinished) {
            [expectDecodeFinish fulfill];
        }
    }];

    [self waitForExpectations:@[expectDecodeFinish] timeout:30.0];

    NSLog(@"[PlayEmTests] Decoded sample %@", sample.source.url.path);

    const char *jitterEnv = getenv("PLAYEM_JITTER_RUNS");
    NSUInteger runCount = 1;
    if (jitterEnv != NULL) {
        int value = atoi(jitterEnv);
        if (value > 0) {
            runCount = (NSUInteger)value;
        }
    }
    if (runCount > 5) {
        runCount = 5;
    }
    NSMutableArray<NSDictionary<NSString *, NSNumber *> *> *runMetrics = [NSMutableArray array];

    const char *windowEnv = getenv("PLAYEM_SIGNATURE_WINDOWS");
    NSMutableArray<NSNumber *> *signatureWindows = [NSMutableArray array];
    if (windowEnv != NULL && strlen(windowEnv) > 0) {
        NSString *raw = [NSString stringWithUTF8String:windowEnv];
        NSArray<NSString *> *parts = [raw componentsSeparatedByString:@","];
        for (NSString *part in parts) {
            double val = [part doubleValue];
            if (val > 0.0) {
                [signatureWindows addObject:@(val)];
            }
        }
    }
    if (signatureWindows.count == 0) {
        [signatureWindows addObject:@0.0];
    }

    const char *perWindowEnv = getenv("PLAYEM_SIGNATURE_RUNS");
    NSUInteger runsPerWindow = 1;
    if (perWindowEnv != NULL) {
        int value = atoi(perWindowEnv);
        if (value > 0) {
            runsPerWindow = (NSUInteger)value;
        }
    }
    const char *hopEnv = getenv("PLAYEM_HOP_SIZE_FRAMES");
    AVAudioFrameCount hopOverride = 0;
    if (hopEnv != NULL) {
        unsigned long long value = strtoull(hopEnv, NULL, 10);
        if (value > 0) {
            hopOverride = (AVAudioFrameCount)value;
        }
    }
    const char *streamingEnv = getenv("PLAYEM_USE_STREAMING_MATCH");
    BOOL useStreamingMatch = NO;
    if (streamingEnv != NULL) {
        int value = atoi(streamingEnv);
        if (value != 0) {
            useStreamingMatch = YES;
        }
    }
    const char *downmixEnv = getenv("PLAYEM_DOWNMIX_TO_MONO");
    BOOL downmixToMono = NO;
    if (downmixEnv != NULL) {
        int value = atoi(downmixEnv);
        if (value != 0) {
            downmixToMono = YES;
        }
    }
    const char *excludeUnknownEnv = getenv("PLAYEM_EXCLUDE_UNKNOWN_INPUTS");
    BOOL excludeUnknownInputs = NO;
    if (excludeUnknownEnv != NULL) {
        int value = atoi(excludeUnknownEnv);
        if (value != 0) {
            excludeUnknownInputs = YES;
        }
    }

    for (NSNumber *windowSeconds in signatureWindows) {
        NSUInteger windowRuns = (windowSeconds.doubleValue > 0.0) ? runsPerWindow : runCount;
        if (windowRuns > 5) {
            windowRuns = 5;
        }
        for (NSUInteger i = 0; i < windowRuns; i++) {
            @autoreleasepool {
                if (windowSeconds.doubleValue > 0.0) {
                    [[NSUserDefaults standardUserDefaults] setDouble:windowSeconds.doubleValue forKey:@"SignatureWindowSeconds"];
                    [[NSUserDefaults standardUserDefaults] setDouble:windowSeconds.doubleValue forKey:@"SignatureWindowMaxSeconds"];
                    NSLog(@"[PlayEmTests] signatureWindow=%.2fs run=%lu/%lu",
                          windowSeconds.doubleValue,
                          (unsigned long)(i + 1),
                          (unsigned long)windowRuns);
                }
                if (hopOverride > 0) {
                    [[NSUserDefaults standardUserDefaults] setDouble:(double)hopOverride forKey:@"HopSizeFrames"];
                    NSLog(@"[PlayEmTests] hopSizeFrames=%llu", (unsigned long long)hopOverride);
                }
                if (useStreamingMatch) {
                    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"UseStreamingMatch"];
                    NSLog(@"[PlayEmTests] useStreamingMatch=1");
                } else {
                    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"UseStreamingMatch"];
                }
                if (downmixToMono) {
                    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"DownmixToMono"];
                    NSLog(@"[PlayEmTests] downmixToMono=1");
                } else {
                    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"DownmixToMono"];
                }
                if (excludeUnknownInputs) {
                    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"ExcludeUnknownInputs"];
                    NSLog(@"[PlayEmTests] excludeUnknownInputs=1");
                } else {
                    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"ExcludeUnknownInputs"];
                }

                TotalIdentificationController *controller = [[TotalIdentificationController alloc] initWithSample:sample];
                controller.debugScoring = YES;
                controller.skipRefinement = YES;

                XCTestExpectation *expectation = [self expectationWithDescription:[NSString stringWithFormat:@"detection finished %lu", (unsigned long)i]];

                __block NSArray<TimedMediaMetaData *> *results = nil;
                __block NSTimeInterval detectionDuration = 0.0;
                CFAbsoluteTime detectionStart = CFAbsoluteTimeGetCurrent();
                [controller detectTracklistWithCallback:^(BOOL success, NSError *error, NSArray<TimedMediaMetaData *> *tracks) {
                    NSLog(@"[PlayEmTests] detection callback success=%d error=%@ tracks=%lu", success, error, (unsigned long)tracks.count);
                    results = tracks;
                    detectionDuration = CFAbsoluteTimeGetCurrent() - detectionStart;
                    [expectation fulfill];
                }];

                [self waitForExpectations:@[expectation] timeout:1200.0];

                XCTAssertNotNil(results);
                XCTAssertGreaterThan(results.count, 0, @"Expected at least one track detected in fixture");

                for (TimedMediaMetaData *t in results) {
                    double dur = [controller estimatedDurationForTrack:t nextTrack:nil];
                    XCTAssertLessThan(dur, 15 * 60, @"Duration too large for track %@ %@", t.meta.artist, t.meta.title);
                }

                NSDictionary<NSString *, NSNumber *> *metrics = [controller testing_metrics];
                if (controller.debugScoring) {
                    NSLog(@"[PlayEmTests] Request metrics: requests=%@ responses=%@ inFlightMax=%@ latency(avg/min/max)=%@/%@/%@",
                          metrics[@"match_requests"],
                          metrics[@"match_responses"],
                          metrics[@"in_flight_max"],
                          metrics[@"latency_avg"],
                          metrics[@"latency_min"],
                          metrics[@"latency_max"]);
                }

                NSDictionary<NSString *, NSNumber *> *summary = [self reportDetection:results
                                                                             duration:detectionDuration
                                                                        sampleDuration:sample.duration
                                                                          enforceRules:NO];
                NSMutableDictionary *merged = [summary mutableCopy];
                if (windowSeconds.doubleValue > 0.0) {
                    merged[@"signature_window"] = windowSeconds;
                }
                merged[@"requests"] = metrics[@"match_requests"] ?: @0;
                merged[@"responses"] = metrics[@"match_responses"] ?: @0;
                merged[@"in_flight_max"] = metrics[@"in_flight_max"] ?: @0;
                merged[@"latency_avg"] = metrics[@"latency_avg"] ?: @0;
                [runMetrics addObject:[merged copy]];
            }
        }
    }

    double durationMin = DBL_MAX, durationMax = 0.0, durationSum = 0.0;
    double hitsPerMinMin = DBL_MAX, hitsPerMinMax = 0.0, hitsPerMinSum = 0.0;
    NSUInteger matchedMin = NSUIntegerMax, matchedMax = 0, matchedSum = 0;
    NSUInteger unexpectedMin = NSUIntegerMax, unexpectedMax = 0, unexpectedSum = 0;
    double latencyAvgMin = DBL_MAX, latencyAvgMax = 0.0, latencyAvgSum = 0.0;
    NSMutableDictionary<NSNumber *, NSMutableArray<NSDictionary<NSString *, NSNumber *> *> *> *runsByWindow = [NSMutableDictionary dictionary];

    for (NSDictionary<NSString *, NSNumber *> *entry in runMetrics) {
        double duration = entry[@"duration"].doubleValue;
        durationMin = MIN(durationMin, duration);
        durationMax = MAX(durationMax, duration);
        durationSum += duration;

        double hitsPerMin = entry[@"hits_per_min"].doubleValue;
        hitsPerMinMin = MIN(hitsPerMinMin, hitsPerMin);
        hitsPerMinMax = MAX(hitsPerMinMax, hitsPerMin);
        hitsPerMinSum += hitsPerMin;

        NSUInteger matched = entry[@"matched_goldens"].unsignedIntegerValue;
        matchedMin = MIN(matchedMin, matched);
        matchedMax = MAX(matchedMax, matched);
        matchedSum += matched;

        NSUInteger unexpected = entry[@"unexpected"].unsignedIntegerValue;
        unexpectedMin = MIN(unexpectedMin, unexpected);
        unexpectedMax = MAX(unexpectedMax, unexpected);
        unexpectedSum += unexpected;

        double latencyAvg = entry[@"latency_avg"].doubleValue;
        latencyAvgMin = MIN(latencyAvgMin, latencyAvg);
        latencyAvgMax = MAX(latencyAvgMax, latencyAvg);
        latencyAvgSum += latencyAvg;

        NSNumber *window = entry[@"signature_window"];
        if (window != nil) {
            NSMutableArray *bucket = runsByWindow[window];
            if (bucket == nil) {
                bucket = [NSMutableArray array];
                runsByWindow[window] = bucket;
            }
            [bucket addObject:entry];
        }
    }

    double runs = (double)runMetrics.count;
    if (runMetrics.count > 1) {
        NSLog(@"[PlayEmTests] Summary over %lu runs:", (unsigned long)runMetrics.count);
        NSLog(@"[PlayEmTests] duration avg/min/max: %.2f / %.2f / %.2f", durationSum / runs, durationMin, durationMax);
        NSLog(@"[PlayEmTests] hitsPerMin avg/min/max: %.2f / %.2f / %.2f", hitsPerMinSum / runs, hitsPerMinMin, hitsPerMinMax);
        NSLog(@"[PlayEmTests] matchedGoldens avg/min/max: %.2f / %lu / %lu",
              (double)matchedSum / runs, (unsigned long)matchedMin, (unsigned long)matchedMax);
        NSLog(@"[PlayEmTests] unexpected avg/min/max: %.2f / %lu / %lu",
              (double)unexpectedSum / runs, (unsigned long)unexpectedMin, (unsigned long)unexpectedMax);
        NSLog(@"[PlayEmTests] latencyAvg avg/min/max: %.3f / %.3f / %.3f",
              latencyAvgSum / runs, latencyAvgMin, latencyAvgMax);
    }

    if (runsByWindow.count > 0) {
        NSArray<NSNumber *> *sortedWindows = [[runsByWindow allKeys] sortedArrayUsingSelector:@selector(compare:)];
        for (NSNumber *window in sortedWindows) {
            NSArray<NSDictionary<NSString *, NSNumber *> *> *entries = runsByWindow[window];
            if (entries.count == 0) {
                continue;
            }
            double wDurationMin = DBL_MAX, wDurationMax = 0.0, wDurationSum = 0.0;
            double wHitsMin = DBL_MAX, wHitsMax = 0.0, wHitsSum = 0.0;
            NSUInteger wMatchedMin = NSUIntegerMax, wMatchedMax = 0, wMatchedSum = 0;
            NSUInteger wUnexpectedMin = NSUIntegerMax, wUnexpectedMax = 0, wUnexpectedSum = 0;
            double wLatencyMin = DBL_MAX, wLatencyMax = 0.0, wLatencySum = 0.0;
            for (NSDictionary<NSString *, NSNumber *> *entry in entries) {
                double duration = entry[@"duration"].doubleValue;
                wDurationMin = MIN(wDurationMin, duration);
                wDurationMax = MAX(wDurationMax, duration);
                wDurationSum += duration;

                double hitsPerMin = entry[@"hits_per_min"].doubleValue;
                wHitsMin = MIN(wHitsMin, hitsPerMin);
                wHitsMax = MAX(wHitsMax, hitsPerMin);
                wHitsSum += hitsPerMin;

                NSUInteger matched = entry[@"matched_goldens"].unsignedIntegerValue;
                wMatchedMin = MIN(wMatchedMin, matched);
                wMatchedMax = MAX(wMatchedMax, matched);
                wMatchedSum += matched;

                NSUInteger unexpected = entry[@"unexpected"].unsignedIntegerValue;
                wUnexpectedMin = MIN(wUnexpectedMin, unexpected);
                wUnexpectedMax = MAX(wUnexpectedMax, unexpected);
                wUnexpectedSum += unexpected;

                double latencyAvg = entry[@"latency_avg"].doubleValue;
                wLatencyMin = MIN(wLatencyMin, latencyAvg);
                wLatencyMax = MAX(wLatencyMax, latencyAvg);
                wLatencySum += latencyAvg;
            }
            NSLog(@"[PlayEmTests] Window %.2fs summary over %lu runs:",
                  window.doubleValue,
                  (unsigned long)entries.count);
            NSLog(@"[PlayEmTests] duration avg/min/max: %.2f / %.2f / %.2f",
                  wDurationSum / entries.count,
                  wDurationMin,
                  wDurationMax);
            NSLog(@"[PlayEmTests] hitsPerMin avg/min/max: %.2f / %.2f / %.2f",
                  wHitsSum / entries.count,
                  wHitsMin,
                  wHitsMax);
            NSLog(@"[PlayEmTests] matchedGoldens avg/min/max: %.2f / %lu / %lu",
                  (double)wMatchedSum / entries.count, (unsigned long)wMatchedMin, (unsigned long)wMatchedMax);
            NSLog(@"[PlayEmTests] unexpected avg/min/max: %.2f / %lu / %lu",
                  (double)wUnexpectedSum / entries.count, (unsigned long)wUnexpectedMin, (unsigned long)wUnexpectedMax);
            NSLog(@"[PlayEmTests] latencyAvg avg/min/max: %.3f / %.3f / %.3f",
                  wLatencySum / entries.count,
                  wLatencyMin,
                  wLatencyMax);
        }
    }

    if (runMetrics.count > 0) {
        NSDateFormatter *formatter = [NSDateFormatter new];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.dateFormat = @"yyyyMMdd_HHmmss";
        NSString *stamp = [formatter stringFromDate:[NSDate date]];
        NSString *baseDir = @"/Users/till/Development/PlayEm/Training/test_summaries";
        [[NSFileManager defaultManager] createDirectoryAtPath:baseDir
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
        NSString *path = [baseDir stringByAppendingPathComponent:[NSString stringWithFormat:@"summary_%@.log", stamp]];
        NSMutableString *out = [NSMutableString string];
        [out appendFormat:@"sample=%@\n", sample.source.url.path];
        [out appendFormat:@"windows=%@\n", [signatureWindows componentsJoinedByString:@","]];
        [out appendFormat:@"runs_per_window=%lu\n", (unsigned long)runsPerWindow];
        [out appendFormat:@"hop_override_frames=%u\n", (unsigned int)hopOverride];
        [out appendFormat:@"use_streaming_match=%d\n", useStreamingMatch ? 1 : 0];
        [out appendFormat:@"downmix_to_mono=%d\n", downmixToMono ? 1 : 0];
        [out appendFormat:@"exclude_unknown_inputs=%d\n", excludeUnknownInputs ? 1 : 0];
        [out appendFormat:@"total_runs=%lu\n", (unsigned long)runMetrics.count];
        for (NSDictionary<NSString *, NSNumber *> *entry in runMetrics) {
            NSNumber *window = entry[@"signature_window"] ?: @0;
            [out appendFormat:@"run window=%.2f duration=%.2f hits_per_min=%.2f matched=%lu unexpected=%lu latency_avg=%.3f\n",
             window.doubleValue,
             entry[@"duration"].doubleValue,
             entry[@"hits_per_min"].doubleValue,
             (unsigned long)entry[@"matched_goldens"].unsignedIntegerValue,
             (unsigned long)entry[@"unexpected"].unsignedIntegerValue,
             entry[@"latency_avg"].doubleValue];
        }
        [out writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSLog(@"[PlayEmTests] Wrote summary to %@", path);
    }
}

@end
