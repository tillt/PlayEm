@import XCTest;

#import "Sample/LazySample.h"
#import "Audio/AudioController.h"
#import "TotalIdentificationController.h"
#import "TimedMediaMetaData.h"


@interface TotalIdentificationController (Testing)
- (double)estimatedDurationForTrack:(TimedMediaMetaData *)track nextTrack:(TimedMediaMetaData * _Nullable)next;
@end

// Test-only API declared here and implemented in TotalIdentificationController.m (Debug builds).
@interface TotalIdentificationController (TestingAccess)
- (void)testing_setIdentifieds:(NSArray<TimedMediaMetaData *> *)hits;
- (NSArray<TimedMediaMetaData *> *)refineTracklist;
@end

// Minimal stub sample to drive refinement without decoding.
@interface TestLazySample : LazySample
@property (nonatomic, assign) SampleFormat stubFormat;
@property (nonatomic, assign) unsigned long long stubFrames;
@property (nonatomic, assign) unsigned int stubFrameSize;
@end

@implementation TestLazySample
- (SampleFormat)sampleFormat { return _stubFormat; }
- (void)setSampleFormat:(SampleFormat)sampleFormat { _stubFormat = sampleFormat; }
- (unsigned long long)frames { return _stubFrames; }
- (unsigned int)frameSize { return _stubFrameSize; }
- (unsigned long long)rawSampleFromFrameOffset:(unsigned long long)offset frames:(unsigned long long)frames outputs:(float * const _Nonnull * _Nullable)outputs { return 0; }
- (unsigned long long)rawSampleFromFrameOffset:(unsigned long long)offset frames:(unsigned long long)frames data:(float *)data { return 0; }
@end

@interface TotalIdentificationControllerTests : XCTestCase
@end

@implementation TotalIdentificationControllerTests

- (void)testDetectionRunsOnFixture
{
    XCTSkip(@"Moved to hosted PlayEmTests.");
}

- (void)testRefinementWithHardcodedDetections
{
    // Use the recent detection output as hardcoded raw Shazam-style hits (two per track for support≥2).
    SampleFormat fmt = { .channels = 2, .rate = 44100 };
    TestLazySample *sample = [TestLazySample new];
    sample.stubFormat = fmt;
    sample.stubFrameSize = sizeof(float) * fmt.channels;
    // Ensure the sample length covers the last frame we feed.
    sample.stubFrames = 400000000ULL;

    TotalIdentificationController *controller = [[TotalIdentificationController alloc] initWithSample:sample];
    controller.debugScoring = YES;

    // Helper to add two hits for a track.
    NSMutableArray<TimedMediaMetaData *> *hits = [NSMutableArray array];
    void (^addTrack)(NSString*,NSString*,unsigned long long, NSTimeInterval, double) = ^(NSString *artist, NSString *title, unsigned long long frame, NSTimeInterval duration, double confidence) {
        MediaMetaData *meta = [MediaMetaData new];
        meta.artist = artist;
        meta.title = title;
        if (duration > 0) { meta.duration = @(duration); }
        for (int i = 0; i < 2; i++) { // two hits to reach support >= 2
            TimedMediaMetaData *t = [TimedMediaMetaData new];
            t.meta = meta;
            t.frame = @(frame + i * 1000); // slightly offset
            t.confidence = @(confidence);
            // approximate endFrame if duration available
            if (duration > 0) {
                unsigned long long end = frame + (unsigned long long)(duration * fmt.rate);
                t.endFrame = @(end);
            }
            [hits addObject:t];
        }
    };

    // Frames and approximate durations from the recent detection log.
    addTrack(@"Slove & David Shaw and the Beat", @"Special Places (Damon Jee Remix)", 140509184ULL, 285.33, 24.0);
    addTrack(@"Vincent Casanova", @"Hold Me", 154140672ULL, 261.55, 12.8);
    addTrack(@"Nick Curly", @"Go", 167772160ULL, 166.44, 2.31);
    addTrack(@"Alex O'Rion", @"Blackout", 178257920ULL, 665.76, 70.4);
    addTrack(@"Mike Griego", @"Back In Trance", 209715200ULL, 451.77, 19.2);
    addTrack(@"Eli & Fur", @"Parfume (Dosem Remix)", 239075328ULL, 95.11, 0.88);
    addTrack(@"Eitan Reiter", @"Eat You (Patrice Bäumel Remix)", 244318208ULL, 261.55, 24.0);
    addTrack(@"Wa Wu We", @"What's Left? (Ambient Mix)", 270532608ULL, 190.22, 7.5);
    // Unknown placeholder: two hits with empty meta.
    for (int i = 0; i < 2; i++) {
        TimedMediaMetaData *u = [TimedMediaMetaData unknownTrackAtFrame:@(255852544ULL + i * 1000)];
        [hits addObject:u];
    }

    XCTSkip(@"Synthetic hardcoded hit test is diagnostic only; golden-list validation covers correctness.");
}

// Simulate raw Shazam input: single hits (support==1) with confidences,
// and let refinement decide what to keep/merge.
- (void)testRefinementWithRawShazamHits
{
    XCTSkip(@"Raw single-hit diagnostic skipped; golden-list validation is authoritative.");
}

// Parse “[Score] frame:… artist:… title:… duration:… score:… confidence:…” lines from a log file.
- (NSArray<TimedMediaMetaData *> *)hitsFromScoreLogAtPath:(NSString *)path
{
    NSError *err = nil;
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&err];
    if (!text) {
        XCTFail(@"Unable to read log at %@: %@", path, err);
        return @[];
    }
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"\\[Score\\] frame:(\\d+) artist:([^\\n]*?) title:([^\\n]*?) duration:([0-9\\.]+)s score:([0-9\\.]+) confidence:([0-9\\.]+)"
                                                                        options:0
                                                                          error:&err];
    if (!re) {
        XCTFail(@"Regex build failed: %@", err);
        return @[];
    }

    NSMutableArray<TimedMediaMetaData *> *hits = [NSMutableArray array];
    NSArray<NSTextCheckingResult *> *matches = [re matchesInString:text options:0 range:NSMakeRange(0, text.length)];
    for (NSTextCheckingResult *m in matches) {
        if (m.numberOfRanges < 7) { continue; }
        NSString *(^group)(NSInteger) = ^NSString *(NSInteger idx) {
            NSRange r = [m rangeAtIndex:idx];
            if (r.location == NSNotFound) return @"";
            return [text substringWithRange:r];
        };
        unsigned long long frame = strtoull([group(1) UTF8String], NULL, 10);
        NSString *artist = [group(2) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSString *title  = [group(3) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        double duration  = [[group(4) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] doubleValue];
        double confidence = [[group(6) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] doubleValue];

        MediaMetaData *meta = [MediaMetaData new];
        meta.artist = artist.length ? artist : nil;
        meta.title = title.length ? title : nil;
        if (duration > 0) { meta.duration = @(duration); }

        TimedMediaMetaData *t = [TimedMediaMetaData new];
        t.meta = meta;
        t.frame = @(frame);
        t.confidence = @(confidence);
        if (duration > 0) {
            t.endFrame = @(frame + (unsigned long long)(duration * 44100.0));
        }
        [hits addObject:t];
    }
    return hits;
}

// Full refinement on the complete raw Shazam log.
- (void)testRefinementWithFullShazamLog
{
    NSString *logPath = @"/Users/till/Development/PlayEm/Training/output_latest_run.txt";
    if (![[NSFileManager defaultManager] fileExistsAtPath:logPath]) {
        XCTSkip(@"Log file not found at %@", logPath);
    }

    SampleFormat fmt = { .channels = 2, .rate = 44100 };
    TestLazySample *sample = [TestLazySample new];
    sample.stubFormat = fmt;
    sample.stubFrameSize = sizeof(float) * fmt.channels;
    sample.stubFrames = 800000000ULL;

    TotalIdentificationController *controller = [[TotalIdentificationController alloc] initWithSample:sample];
    controller.debugScoring = YES;

    NSArray<TimedMediaMetaData *> *hits = [self hitsFromScoreLogAtPath:logPath];
    XCTAssertGreaterThan(hits.count, 0, @"Expected hits parsed from log");

    [controller testing_setIdentifieds:hits];
    NSArray<TimedMediaMetaData *> *refined = [controller refineTracklist];
    NSLog(@"[PlayEmTests] Full-log refinement: %lu hits -> %lu refined", (unsigned long)hits.count, (unsigned long)refined.count);

    XCTAssertGreaterThan(refined.count, 0, @"Refinement should yield tracks");

    // Check that core golden tracks are present.
    BOOL hasSeat11 = NO, hasBlackout = NO, hasEatYou = NO;
    NSInteger unknownCount = 0;
    for (TimedMediaMetaData *t in refined) {
        NSString *title = t.meta.title ?: @"";
        NSString *artist = t.meta.artist ?: @"";
        if ([title containsString:@"Seat 11"]) { hasSeat11 = YES; }
        if ([title containsString:@"Blackout"]) { hasBlackout = YES; }
        if ([title containsString:@"Eat You"] || [artist containsString:@"Eitan Reiter"]) { hasEatYou = YES; }
        if (title.length == 0 && artist.length == 0) { unknownCount += 1; }
    }
    XCTAssertTrue(hasSeat11, @"Expected Seat 11 from golden list");
    XCTAssertTrue(hasBlackout, @"Expected Blackout from golden list");
    // We are missing 4 golden tracks in the raw input; allow up to that many unknown placeholders.
    XCTAssertLessThanOrEqual(unknownCount, 4, @"Too many unknown placeholders compared to missing golden tracks");
    XCTAssertTrue(hasEatYou, @"Expected Eat You (Patrice Bäumel Remix) from golden list");

    // Emit a quick diff vs. golden (excluding truly missing tracks) to guide scoring tweaks.
    NSSet<NSString *> *presentAvailables = [NSSet setWithObjects:
        @"Seat 11",
        @"Slippery Road",
        @"Muted Glow",
        @"End of the Line",
        @"The Arboretum",
        @"Cosmo Acids",
        @"Masquerade",
        @"Special Places",
        @"Hold Me",
        @"Go",
        @"Blackout",
        @"Calypso",
        @"Back In Trance",
        @"Eat You",
        @"What's Left",
        nil];
    NSMutableSet<NSString *> *seenTitles = [NSMutableSet set];
    for (TimedMediaMetaData *t in refined) {
        NSString *title = t.meta.title ?: @"";
        if (title.length) {
            [seenTitles addObject:title];
        }
    }
    NSMutableSet<NSString *> *missing = [presentAvailables mutableCopy];
    [missing minusSet:seenTitles];
    if (missing.count > 0) {
        NSLog(@"[PlayEmTests] Missing available golden titles in refined list: %@", missing);
    }
}

@end
