//
//  main.m
//  PlayEmRefineCLI
//
//  Created by Till Toenshoff on 1/1/26.
//  Copyright © 2026 Till Toenshoff. All rights reserved.
//

#import <Foundation/Foundation.h>
// Use direct relative imports so we don't depend on framework header exports.
#import "../PlayEmCore/Identification/TotalIdentificationController.h"
#import "../PlayEmCore/Sample/LazySample.h"
#import "../PlayEmCore/Sample/SampleFormat.h"
#import "../PlayEmCore/Metadata/TimedMediaMetaData.h"
#import "../PlayEmCore/Metadata/MediaMetaData.h"

// Simple stub sample so the refiner has timing context without decoding audio.
@interface CLITestLazySample : LazySample
@property (assign, nonatomic) SampleFormat stubFormat;
@property (assign, nonatomic) unsigned long long stubFrames;
@property (assign, nonatomic) unsigned int stubFrameSize;
@end

@implementation CLITestLazySample
- (SampleFormat)sampleFormat { return _stubFormat; }
- (unsigned long long)frames { return _stubFrames; }
- (unsigned int)frameSize { return _stubFrameSize; }
- (unsigned long long)rawSampleFromFrameOffset:(unsigned long long)offset
                                        frames:(unsigned long long)frames
                                       outputs:(float * const _Nonnull * _Nullable)outputs
{
    // No audio needed for refinement-only CLI.
    return 0;
}
- (unsigned long long)rawSampleFromFrameOffset:(unsigned long long)offset
                                        frames:(unsigned long long)frames
                                          data:(float *)data
{
    return 0;
}
@end

// Testing hook from TotalIdentificationController.m
@interface TotalIdentificationController (TestingAccess)
- (void)testing_setIdentifieds:(NSArray<TimedMediaMetaData *> *)hits;
- (NSArray<TimedMediaMetaData*>*)refineTracklist;
- (double)estimatedDurationForTrack:(TimedMediaMetaData*)track nextTrack:(TimedMediaMetaData* _Nullable)next;
@end

static NSArray<TimedMediaMetaData*>* ParseInputLog(NSString *path, unsigned long long *outMaxFrame) {
    NSError *error = nil;
    NSString *contents = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
    if (!contents) {
        fprintf(stderr, "Failed to read %s: %s\n", path.UTF8String, error.localizedDescription.UTF8String);
        return @[];
    }
    NSMutableArray<TimedMediaMetaData*> *hits = [NSMutableArray array];
    __block unsigned long long maxFrame = 0;

    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"\\[(Input|Shazam)\\]\\s*frame:(\\d+)\\s*artist:([^\\r\\n]*)\\s*title:([^\\r\\n]*)\\s*score:([0-9\\.]+)\\s*confidence:(null|[0-9\\.]+)" options:0 error:nil];

    NSArray<NSTextCheckingResult*> *matches = [re matchesInString:contents options:0 range:NSMakeRange(0, contents.length)];
    for (NSTextCheckingResult *m in matches) {
        if (m.numberOfRanges < 6) { continue; }
        NSString *frameStr = [contents substringWithRange:[m rangeAtIndex:2]];
        NSString *artist = [[contents substringWithRange:[m rangeAtIndex:3]] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSString *title = [[contents substringWithRange:[m rangeAtIndex:4]] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSString *scoreStr = [contents substringWithRange:[m rangeAtIndex:5]];
        NSString *confStr = [contents substringWithRange:[m rangeAtIndex:6]];

        unsigned long long frame = strtoull(frameStr.UTF8String, NULL, 10);
        maxFrame = MAX(maxFrame, frame);

        MediaMetaData *meta = [MediaMetaData new];
        meta.artist = artist.length ? artist : nil;
        meta.title = title.length ? title : nil;

        TimedMediaMetaData *t = [TimedMediaMetaData new];
        t.frame = @(frame);
        t.meta = meta;
        t.score = @([scoreStr doubleValue]);
        if (![confStr isEqualToString:@"null"] && confStr.length) {
            t.confidence = @([confStr doubleValue]);
        }
        [hits addObject:t];
    }

    if (outMaxFrame) { *outMaxFrame = maxFrame; }
    return hits;
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSString *inputPath = @"Training/output_latest_run.txt";
        if (argc > 1) {
            inputPath = [NSString stringWithUTF8String:argv[1]];
        }
        unsigned long long maxFrame = 0;
        NSArray<TimedMediaMetaData*> *hits = ParseInputLog(inputPath, &maxFrame);
        if (hits.count == 0) {
            fprintf(stderr, "No [Shazam] entries parsed from %s\n", inputPath.UTF8String);
            return EXIT_FAILURE;
        }

        // Build stub sample context (~10 minutes beyond last frame to keep duration math sane).
        CLITestLazySample *sample = [CLITestLazySample new];
        sample.stubFormat = (SampleFormat){ .channels = 2, .rate = 44100 };
        sample.stubFrameSize = sizeof(float) * sample.stubFormat.channels;
        sample.stubFrames = maxFrame + (unsigned long long)(sample.stubFormat.rate * 600); // pad 10 min

        TotalIdentificationController *controller = [[TotalIdentificationController alloc] initWithSample:sample];
        controller.debugScoring = YES;
        NSBundle *bundle = [NSBundle bundleForClass:[TotalIdentificationController class]];
        NSLog(@"[CLI] PlayEmCore bundle: %@", bundle.bundlePath ?: @"<nil>");

        // Inject hits and refine.
        [controller testing_setIdentifieds:hits];
        NSArray<TimedMediaMetaData*> *refined = [controller refineTracklist];

        NSLog(@"[CLI] Refined %lu tracks", (unsigned long)refined.count);
        for (NSUInteger i = 0; i < refined.count; i++) {
            TimedMediaMetaData *t = refined[i];
            TimedMediaMetaData *next = (i + 1 < refined.count) ? refined[i+1] : nil;
            double durationSeconds = [controller estimatedDurationForTrack:t nextTrack:next];
            NSLog(@"[Final] frame:%llu artist:%@ title:%@ duration:%.2fs score:%.3f confidence:%.3f",
                  t.frame.unsignedLongLongValue,
                  t.meta.artist ?: @"",
                  t.meta.title ?: @"",
                  durationSeconds,
                  t.score.doubleValue,
                  t.confidence ? t.confidence.doubleValue : 0.0);
        }
    }
    return EXIT_SUCCESS;
}
