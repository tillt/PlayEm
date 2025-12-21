//
//  TrackList+ChapterForge.m
//  PlayEm
//
//  Created by Till Toenshoff on 12/11/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//
#import "TrackList+ChapterForge.hpp"

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <VideoToolbox/VideoToolbox.h>
#import <CoreImage/CoreImage.h>
#import <CoreGraphics/CoreGraphics.h>

#import "MediaMetaData.h"
#import "MediaMetaData+JPEGTool.h"
#import "TimedMediaMetaData.h"
#import "JPEGTool.h"

#include "ChapterForge/chapterforge.hpp"

static NSString* kTrackListTitleArtistGlue = @" - ";


// Glue Code.
void populateChapters(TrackList* tl,
                      std::vector<ChapterTextSample> &textChapters,
                      std::vector<ChapterTextSample> &urlChapters,
                      std::vector<ChapterImageSample> &imageChapters,
                      FrameToSeconds frameToSeconds)
{
    NSArray<NSNumber*>* frames = [[tl frames] sortedArrayUsingSelector:@selector(compare:)];

    for (NSNumber* value in frames) {
        unsigned long long frame = [value unsignedLongLongValue];
        // We get the absolute time from our injected block
        double seconds = frameToSeconds(frame);
        uint32_t start_ms = ceil(seconds * 1000.0);

        TimedMediaMetaData* tm = [tl trackAtFrame:frame];
        
        //
        // Title
        //
        // We encode the title and the artist into the first chapter text track to make
        // things look beautiful and informative in players like VLC, QuickTime and alike.
        NSString* text = nil;
        if (tm.meta.title.length > 0 && tm.meta.artist.length > 0) {
            text = [NSString stringWithFormat:@"%@ - %@", tm.meta.artist, tm.meta.title];
        } else if (tm.meta.artist.length > 0) {
            text = tm.meta.artist;
        } else if (tm.meta.title.length > 0) {
            text = tm.meta.title;
        } else {
            text = @"Unknown";
        }
        
        ChapterTextSample ts{};
        ts.start_ms = start_ms;
        ts.text = [text UTF8String];

        textChapters.push_back(std::move(ts));
        
        //
        // URL & Artist
        //
        // We encode artist here again so that we can later split it out from the title
        // track when parsing the file again. This is done to assert that even titles or
        // artists containing dashes would not confuse the parser when attemptng to split.
        //
        // The artist encoding is quirky to say it mildly. We are exploiting the fact that
        // the URL track, in the end is not parsed by any player we know of. AVFoundation
        // only ever surfaces the URL if it gets referenced by the title track, making the
        // entire existence of the URL track questionable. However, that is what Apple and
        // other players get along with and this is where we piggyback on to stay compatible.
        //
        // Note that this schema appears to scale further - if we ever needed to encode more
        // timed information, we could simply add another track - it appears sane players
        // will ignore.
        ChapterTextSample us{};
        if (tm.meta.artist.length > 0) {
            us.text = [tm.meta.artist UTF8String];
        }
        if ([[tm.meta.appleLocation absoluteString] length] > 0) {
            us.href = [[tm.meta.appleLocation absoluteString] UTF8String];
        }
        us.start_ms = start_ms;
        urlChapters.push_back(std::move(us));

        //
        // Image
        //
        // Note: If there is no artwork, we dont write a sample into our video track
        // this might be a bad idea as it results in the previous track image getting
        // shown again.
        ChapterImageSample is{};
        if (tm.meta.artwork != nil) {
            NSData* artwork420 = [tm.meta sizedJPEG420];
            
            uint8_t* buffer = (uint8_t*)[artwork420 bytes];
            size_t len = [artwork420 length];
            
            std::vector<uint8_t> v(buffer, buffer + len);
            is.data = v;
        }
        is.start_ms = start_ms;
        imageChapters.push_back(std::move(is));
    }
}

@implementation TrackList (ChapterForge)

- (void)updateWithChapteredMetdaData:(ChapteredMetaData*)chaptered
{
    NSArray<NSNumber*>* frames = [[chaptered allKeys] sortedArrayUsingSelector:@selector(compare:)];

    for (NSNumber* frame in frames) {
        // Get the structured meta entry;
        StructuredMetaData* structured = [chaptered objectForKey:frame];
        // Try to find an existing timed meta.
        TimedMediaMetaData* track = [self trackAtFrameNumber:frame];
        if (track == nil) {
            track = [TimedMediaMetaData new];
        }
        // Path the timed meta data with our structured information.
        [track updateWithStructuredMeta:structured frame:frame];
        // Make sure it is added.
        [self addTrack:track];
    }
}

- (ChapteredMetaData* _Nullable)readChapterTextTracksFromAVAsset:(AVAsset*)asset framerate:(long)rate error:(NSError*__autoreleasing  _Nullable* _Nullable)error
{
    NSMutableDictionary<NSNumber*, NSMutableDictionary<NSString*, NSString*>*>* chapteredMetadata = [NSMutableDictionary dictionary];

    NSArray<AVAssetTrack*>* textTracks = [asset tracksWithMediaType:AVMediaTypeText];
    
    if (textTracks.count > 0) {
        NSLog(@"titles trackID=%d", textTracks[0].trackID);
        if (![self populateTimedKeyedTextTrackInfoFromAVAsset:asset
                                                   track:textTracks[0]
                                                     key:kStructuredMetaTitleKey
                                       chapteredMetadata:chapteredMetadata
                                                    framerate:rate
                                                        error:error]) {
            return nil;
        }
    }
    if (textTracks.count > 1) {
        NSLog(@"url trackID=%d", textTracks[1].trackID);
        if (![self populateTimedKeyedTextTrackInfoFromAVAsset:asset
                                                   track:textTracks[1]
                                                     key:kStructuredMetaArtistKey
                                       chapteredMetadata:chapteredMetadata
                                                    framerate:rate
                                                        error:error]) {
            return nil;
        }
    }

    NSLog(@"lets see %@", chapteredMetadata);
    return chapteredMetadata;
}

- (void)poplateTimedKeyedTextTrackInfoFromTrackOutput:(AVAssetReaderTrackOutput*)trackOut
                                                  key:(NSString *)key
                                    chapteredMetadata:(NSMutableDictionary<NSNumber*,NSMutableDictionary<NSString*,NSString*>*>*)chapteredMetadata
                                            framerate:(long)rate
{
    CMSampleBufferRef sb = NULL;
    
    while ((sb = [trackOut copyNextSampleBuffer]) != NULL) {
        CMTime pts = CMSampleBufferGetPresentationTimeStamp(sb);
        CMTime dur = CMSampleBufferGetDuration(sb); // may be kCMTimeInvalid; derive from stts if needed
        Float64 ptsSec = 0;
        Float64 durSec = 0;
        
        if (CMTIME_IS_VALID(pts) && CMTIME_IS_NUMERIC(pts)) {
            ptsSec = CMTimeGetSeconds(pts);
            durSec = (CMTIME_IS_VALID(dur) && CMTIME_IS_NUMERIC(dur)) ? CMTimeGetSeconds(dur) : 0.0;
            if (durSec == 0.0f) {
                // padding/invalid sample
                CFRelease(sb);
                continue;
            }
        } else {
            // padding/invalid sample
            CFRelease(sb);
            continue;
        }
        
        CMBlockBufferRef bb = CMSampleBufferGetDataBuffer(sb);
        
        if (bb) {
            size_t len = CMBlockBufferGetDataLength(bb);
            // need at least 2 bytes for the tx3g length
            if (len > 2) {
                NSMutableData* data = [NSMutableData dataWithLength:len];
                CMBlockBufferCopyDataBytes(bb, 0, len, data.mutableBytes);
                
                // tx3g: first 2 bytes = big-endian text length, then UTF-8 text, then optional boxes (e.g., href)
                uint16_t beLen = 0;
                [data getBytes:&beLen length:2];
                uint16_t textLen = CFSwapInt16BigToHost(beLen);
                
                if (textLen > 0) {
                    if (len >= 2 + textLen) {
                        NSData* utf8 = [data subdataWithRange:NSMakeRange(2, textLen)];
                        NSString* s = [[NSString alloc] initWithData:utf8 encoding:NSUTF8StringEncoding];
                        if (s.length > 0) {
                            NSLog(@"sample pts=%.2f dur=%.2f %@ (tx3g len=%u): %@", ptsSec, durSec, key, textLen, s);
                            
                            NSMutableDictionary* item = nil;
                            NSNumber* start = @((unsigned long long)(ptsSec * rate));
                            if ([[chapteredMetadata allKeys] containsObject:start]) {
                                item = chapteredMetadata[start];
                            } else {
                                item = [NSMutableDictionary dictionary];
                            }
                            item[key] = s;
                            chapteredMetadata[start] = item;
                        }
                    } else {
                        NSLog(@"tx3g payload length %u exceeds buffer size %zu", textLen, len);
                    }
                }
            }
        }
        CFRelease(sb);
    }
}

- (BOOL)populateTimedKeyedTextTrackInfoFromAVAsset:(AVAsset*)asset
                                             track:(AVAssetTrack*)track
                                               key:(NSString*)key
                                 chapteredMetadata:(NSMutableDictionary<NSNumber*, NSMutableDictionary<NSString*, NSString*>*>*)chapteredMetadata
                                         framerate:(long)rate
                                             error:(NSError*__autoreleasing  _Nullable* _Nullable)outError
{
    NSError* readerErr = nil;
    AVAssetReader* reader = [[AVAssetReader alloc] initWithAsset:asset error:&readerErr];

    if (!reader) {
        if (outError) {
            *outError = readerErr;
            return NO;
        }
    }
    AVAssetReaderTrackOutput* trackOut = [[AVAssetReaderTrackOutput alloc] initWithTrack:track outputSettings:nil];
    [reader addOutput:trackOut];
    if (![reader startReading]) {
        if (outError) {
            *outError = reader.error;
            return NO;
        }
    }

    [self poplateTimedKeyedTextTrackInfoFromTrackOutput:trackOut key:key chapteredMetadata:chapteredMetadata framerate:rate];

    return YES;
}

@end
