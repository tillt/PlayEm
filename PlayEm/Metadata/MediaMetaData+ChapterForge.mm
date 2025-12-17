//
//  MediaMetaData+ChapterForge.mm
//  PlayEm
//
//  Created by Till Toenshoff on 12/9/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//
#include <fstream>
#include <math.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreMedia/CMFormatDescription.h>

#import <iTunesLibrary/ITLibMediaItem.h>

#import "MediaMetaData.h"
#import "MediaMetaData+AVAsset.h"
#import "MediaMetaData+JPEGTool.h"
#import "AVMetadataItem+THAdditions.h"

#import "../NSError+BetterError.h"

#import "TemporaryFiles.h"
#import "TrackList+ChapterForge.hpp"

#include "logging.hpp"
#include "chapterforge.hpp"


@implementation MediaMetaData(ChapterForge)

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

    NSLog(@"title from text track: %@", title);
    NSLog(@"artist from text track: %@", artist);

    // This should be old news -- the titles shall be identical. `title` was read
    // by AVFoundation via the track reader. `self.title` was read by AVFoundation
    // using the chapter loader.
    assert([title isEqualToString:self.title]);

    if (artist.length > 0 &&
        title.length > artist.length + 3 &&
        [[title substringToIndex:artist.length] isEqualToString:artist]) {
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
    
    // We need to assert a tracklist starting at the beginning of our sample to keep
    // everyone happy. Anything else will get snapped by AVFoundation when parsing back,
    // putting the first mark on zero. To avoid the inevitable, we give in and create
    // this "fake" jumpmark.
    // As players like QuickTime will display this, we need to come up with a nice image.
    NSArray* frames = [self.trackList.frames sortedArrayUsingSelector:@selector(compare:)];
    if (frames.count > 0) {
        if ([frames[0] unsignedLongLongValue] > 0) {
            NSLog(@"our first chapter has a non zero start time, inserting cover chapter");
            // Lets insert a blank dummy chapter at zero to satisfy players.
            ChapterTextSample ts{};
            ts.start_ms = 0;
            textChapters.push_back(std::move(ts));

            ChapterTextSample us{};
            us.start_ms = 0;
            urlChapters.push_back(std::move(us));

            ChapterImageSample is{};
            NSData* artwork420 = [self sizedJPEG420];
            if (artwork420 == nil) {
                // We have no artwork for this tune, lets use our default.
                	
            }
            uint8_t* buffer = (uint8_t*)[artwork420 bytes];
            size_t len = [artwork420 length];
            std::vector<uint8_t> v(buffer, buffer + len);
            is.start_ms = 0;
            is.data = v;
            imageChapters.push_back(std::move(is));
        }
    }

    // Glue code - writing our tracklist into the ChapterForge structures.
    populateChapters(self.trackList, textChapters, urlChapters, imageChapters, self.frameToSeconds);

    chapterforge::set_log_verbosity(chapterforge::LogVerbosity::Debug);
    
    bool ret = chapterforge::mux_file_to_m4a(   input,
                                                textChapters,
                                                urlChapters,
                                                imageChapters,
                                                output);
    if (!ret) {
        NSLog(@"failed to create chaptered M4A file");
        return NO;
    }
    
    NSFileManager *fileManager = [NSFileManager defaultManager];

    if (![fileManager removeItemAtPath:self.location.path  error:error]) {
        NSLog(@"failed to remove the source file after re-creating it: %@", *error);
        return NO;
    }
    
    if (![fileManager moveItemAtPath:outputURL.path toPath:self.location.path error:error]) {
        NSLog(@"failed to move the output file after adding chapters to it: %@", *error);
        return NO;
    }

    NSLog(@"successfully updated chapters for: %@", outputURL);

    return YES;
}

/// FIXME: Consider using async functions instead - we are blocking the mainthread here.
- (BOOL)readChapterMarksFromAVAsset:(AVAsset*)asset error:(NSError*__autoreleasing  _Nullable* _Nullable)error
{
    NSArray<NSString*>* preferred =
        [NSBundle preferredLocalizationsFromArray:[[NSBundle mainBundle] localizations]
                                   forPreferences:[NSLocale preferredLanguages]];

    __block NSArray<AVTimedMetadataGroup*>* result = nil;
    __block NSError* loadError = nil;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);

    [asset loadChapterMetadataGroupsBestMatchingPreferredLanguages:preferred
                                                 completionHandler:^(NSArray<AVTimedMetadataGroup*>* _Nullable chapterGroups,
                                                                     NSError* _Nullable error) {
        if (error) {
            loadError = error;
        } else {
            result = chapterGroups;
        }
        dispatch_semaphore_signal(sema);
    }];

    // Wait until the completion handler fires.
    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);

    if (loadError) {
        NSLog(@"error loading chapter metadata: %@", loadError.localizedDescription);
        return NO;
    }
    
    long rate = [MediaMetaData sampleRateForAsset:asset];
    NSLog(@"asset claims to have a samplerate of %ld", rate);

    self.trackList = [[TrackList alloc] initWithTimedMetadataGroups:result  framerate:rate];

    // We now need to gather metadata that AVFoundation wont read the "normal" way.
    ChapteredMetaData* chaptered = [self.trackList readChapterTextTracksFromAVAsset:asset framerate:rate error:error];
    [self.trackList updateWithChapteredMetdaData:chaptered];

    return YES;
}

@end
