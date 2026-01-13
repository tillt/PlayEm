//
//  MediaMetaData+ChapterForge.mm
//  PlayEm
//
//  Created by Till Toenshoff on 12/9/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//
#include <fstream>
#include <math.h>

#include "ChapterForge/chapterforge.hpp"
#include "ChapterForge/logging.hpp"

#import <Foundation/Foundation.h>

#import "MediaMetaData+ChapterForge.hpp"

#import <AVFoundation/AVFoundation.h>
#import <AppKit/AppKit.h>
#import <CoreMedia/CMFormatDescription.h>
#import <CoreMedia/CoreMedia.h>
#import <iTunesLibrary/ITLibMediaItem.h>

#import "NSError+BetterError.h"
#import "AVMetadataItem+THAdditions.h"
#import "MediaMetaData+AVAsset.h"
#import "MediaMetaData+JPEGTool.h"
#import "MediaMetaData.h"
#import "TemporaryFiles.h"
#import "TrackList+ChapterForge.hpp"

@implementation MediaMetaData (ChapterForge)

+ (MediaMetaData*)mediaMetaDataWithStructuredMeta:(StructuredMetaData*)structured
{
    MediaMetaData* meta = [[MediaMetaData alloc] init];

    [meta updateWithStructuredMeta:structured];

    return meta;
}

- (void)updateWithStructuredMeta:(StructuredMetaData*)structured
{
    NSString* title = [structured valueForKey:kStructuredMetaTitleKey];
    NSString* artist = [structured valueForKey:kStructuredMetaArtistKey];
    NSString* location = [structured valueForKey:kStructuredMetaURLKey];

    //    NSLog(@"text track: title: %@", title);
    //    NSLog(@"url track: artist: %@", artist);
    //    NSLog(@"url track: location: %@", location);

    // This should be old news -- the titles shall be identical. `title` was read
    // by AVFoundation via the track reader. `self.title` was read by AVFoundation
    // using the chapter loader.
    assert((title == nil && self.title == nil) || [title isEqualToString:self.title]);

    if (artist.length > 0 && title.length > artist.length + 3 && [[title substringToIndex:artist.length] isEqualToString:artist]) {
        self.artist = artist;
        // Remove artist and " - ".
        self.title = [title substringFromIndex:artist.length + 3];
    } else {
        if (title.length > 0) {
            self.title = title;
        }
        if (artist.length > 0) {
            self.artist = artist;
        }
    }

    if (location != nil) {
        self.appleLocation = [NSURL URLWithString:location];
    }
}

- (BOOL)writeChaperMarksToMP4FileWithError:(NSError**)error
{
    std::string input = [self.location.path UTF8String];

    NSString* outputPath = [TemporaryFiles pathForTemporaryFileWithPrefix:@"PlayEm"];
    NSURL* outputURL = [[NSURL URLWithString:outputPath] URLByAppendingPathExtension:@"m4a"];

    std::string output = [outputURL.path UTF8String];

    std::vector<ChapterTextSample> textChapters;
    std::vector<ChapterTextSample> urlChapters;
    std::vector<ChapterImageSample> imageChapters;

    // We need to assert a tracklist starting at the beginning of our sample to
    // keep everyone happy. Anything else will get snapped by AVFoundation when
    // parsing back, putting the first mark on zero. To avoid the inevitable, we
    // give in and create this "fake" jumpmark. As players like QuickTime will
    // display this, we need to come up with a nice image. For that we use the
    // cover art from the general metadata. If nothing is available, our default
    // placeholder will get used.
    NSArray* frames = [self.trackList.frames sortedArrayUsingSelector:@selector(compare:)];
    if (frames.count > 0) {
        if ([frames[0] unsignedLongLongValue] > 0) {
            NSLog(@"our first chapter has a non zero start time, inserting cover "
                  @"chapter");
            // Lets insert a blank dummy chapter at zero to satisfy players.
            ChapterTextSample ts{};
            ts.start_ms = 0;
            textChapters.push_back(std::move(ts));

            // To make sure everything gets neatly synced we insert a blank in the URL
            // track. Without we get mixups which I am not sure I fully understand atm
            // - in my mind, URL data is optional also for fully functioning results.
            // FIXME: Add a test to chapterforge on this and find out.
            ChapterTextSample us{};
            us.start_ms = 0;
            urlChapters.push_back(std::move(us));

            ChapterImageSample is{};
            // We will always get something back here as the default image gets
            // returned if nothing else was available.
            NSData* artwork420 = [self sizedJPEG420];
            assert(artwork420);
            uint8_t* buffer = (uint8_t*) [artwork420 bytes];
            size_t len = [artwork420 length];
            std::vector<uint8_t> v(buffer, buffer + len);
            is.start_ms = 0;
            is.data = v;
            imageChapters.push_back(std::move(is));
        }
    }

    // Glue code - writing our tracklist into the ChapterForge structures.
    populateChapters(self.trackList, textChapters, urlChapters, imageChapters, self.frameToSeconds);

    chapterforge::set_log_verbosity(chapterforge::LogVerbosity::Info);
    auto status = chapterforge::mux_file_to_m4a(input, textChapters, urlChapters, imageChapters, output);
    if (!status.ok) {
        NSLog(@"failed to create chaptered M4A file: %s", status.message.c_str());
        return NO;
    }

    NSFileManager* fileManager = [NSFileManager defaultManager];

    if (![fileManager removeItemAtPath:self.location.path error:error]) {
        NSLog(@"failed to remove the source file after re-creating it: %@", *error);
        return NO;
    }

    if (![fileManager moveItemAtPath:outputURL.path toPath:self.location.path error:error]) {
        NSLog(@"failed to move the output file after adding chapters to it: %@", *error);
        return NO;
    }

    return YES;
}

/// FIXME: Consider using async functions instead - we are blocking the
/// mainthread here.
- (void)readChapterMarksFromAVAsset:(AVAsset*)asset callback:(void (^)(BOOL, NSError*))callback
{
    NSLog(@"readChapterMarksFromAVAsset");

    NSArray<NSString*>* preferred = [NSBundle preferredLocalizationsFromArray:[[NSBundle mainBundle] localizations]
                                                               forPreferences:[NSLocale preferredLanguages]];

    __weak MediaMetaData* weakSelf = self;

    [asset loadValuesAsynchronouslyForKeys:@[ @"availableChapterLocales" ]
                         completionHandler:^{
                             dispatch_async(dispatch_get_main_queue(), ^{
                                 NSError* error = nil;
                                 AVKeyValueStatus status = [asset statusOfValueForKey:@"availableChapterLocales" error:&error];
                                 if (status != AVKeyValueStatusLoaded) {
                                     NSLog(@"not AVKeyValueStatusLoaded");
                                     callback(NO, error);
                                     return;
                                 }
                                 if (asset.availableChapterLocales.count == 0) {
                                     NSLog(@"none available");
                                     callback(NO, nil);
                                     return;
                                 }

                                 NSSet* offered = [NSSet setWithArray:[asset.availableChapterLocales valueForKey:@"identifier"]];
                                 NSString* match = nil;
                                 for (NSString* lang in preferred) {
                                     if ([offered containsObject:lang]) {
                                         match = lang;
                                         break;
                                     }
                                 }

                                 NSLocale* locale = asset.availableChapterLocales.firstObject;
                                 if (match != nil) {
                                     for (NSLocale* loc in asset.availableChapterLocales) {
                                         if ([loc.localeIdentifier isEqualToString:match]) {
                                             locale = loc;
                                             break;
                                         }
                                     }
                                 }

                                 NSArray<AVMetadataKey>* commonKeys = @[ AVMetadataCommonKeyTitle, AVMetadataCommonKeyArtwork ];

                                 [asset loadChapterMetadataGroupsWithTitleLocale:locale
                                                   containingItemsWithCommonKeys:commonKeys
                                                               completionHandler:^(NSArray<AVTimedMetadataGroup*>* groups, NSError* error) {
                                                                   if (groups.count == 0) {
                                                                       NSLog(@"group empty");
                                                                   } else {
                                                                       long rate = [MediaMetaData sampleRateForAsset:asset];
                                                                       NSLog(@"asset claims to "
                                                                             @"have a samplerate "
                                                                             @"of %ld",
                                                                             rate);

                                                                       // FIXME: REALLY? Find
                                                                       // out! First parse the
                                                                       // tracklist as received
                                                                       // by
                                                                       // `loadChapterMetadataGroupsBestMatchingPreferredLanguages`
                                                                       // - the high level
                                                                       // chapter parser of
                                                                       // AVFoundation. We
                                                                       // exploit its artwork
                                                                       // surfacing as parsing
                                                                       // the video track might
                                                                       // add considerable
                                                                       // effort. We do however
                                                                       // need to do some
                                                                       // patcheroo on the
                                                                       // received data as
                                                                       // tracks without a cover
                                                                       // will simply repeat the
                                                                       // last cover.
                                                                       weakSelf.trackList = [[TrackList alloc] initWithTimedMetadataGroups:groups
                                                                                                                                 framerate:rate];

                                                                       // We now need to gather
                                                                       // metadata that
                                                                       // AVFoundation wont read
                                                                       // the "normal" way.
                                                                       NSError* chapterForgeError = nil;
                                                                       ChapteredMetaData* chaptered =
                                                                           [weakSelf.trackList readChapterTextTracksFromAVAsset:asset
                                                                                                                      framerate:rate
                                                                                                                          error:&chapterForgeError];
                                                                       if (chaptered == nil) {
                                                                           NSLog(@"failed reading "
                                                                                 @"chaptered text "
                                                                                 @"tracks: %@",
                                                                                 chapterForgeError);
                                                                           callback(NO, chapterForgeError);
                                                                           return;
                                                                       }
                                                                       [weakSelf.trackList updateWithChapteredMetdaData:chaptered];
                                                                   }
                                                                   callback(YES, nil);
                                                               }];
                             });
                         }];
}

@end
