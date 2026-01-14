//
//  MediaMetaData+TrackList.m
//  PlayEmCore
//
//  Created by Till Toenshoff on 1/14/26.
//  Copyright © 2026 Till Toenshoff. All rights reserved.
//

#import "MediaMetaData+TrackList.h"
#import "MediaMetaData+AVAsset.h"
#import "MediaMetaData+ChapterForge.hpp"

@implementation MediaMetaData (TrackList)

/// Default tracklist location derived from the source file location.
///
/// - Returns: tracklist file location URL
///
- (NSURL*)trackListURL
{
    return [[self.location URLByDeletingPathExtension] URLByAppendingPathExtension:@"tracklist"];
}

- (void)recoverTracklistWithCallback:(void (^)(BOOL, NSError*))callback
{
    NSLog(@"attempting to recover tracklist");

    NSError* error = nil;
    MediaMetaDataFileFormatType type = [MediaMetaData fileTypeWithURL:self.location error:&error];
    if (error != nil) {
        NSLog(@"failed to determine file type: %@", error);
        callback(NO, error);
        return;
    }

    // We are using taglib for anything but MP4 for which we use the system
    // provided functions.
    if (type == MediaMetaDataFileFormatTypeMP4) {
        MediaMetaData* __weak weakSelf = self;

        [self readChaperMarksFromMP4FileWithCallback:^(BOOL done, NSError* error) {
            if (!done) {
                NSLog(@"failed to read chapter marks with error: %@", error);
            }
            NSLog(@"lets see if we can read chapters from our sidecar");
            // Did we get some tracks, so far?
            if (self.trackList.frames.count > 0) {
                callback(YES, nil);
                return;
            }
            [weakSelf recoverSidecarWithCallback:callback];
        }];
    } else {
        // Did we get some tracks, so far?
        if (self.trackList.frames.count > 0) {
            callback(YES, nil);
            return;
        }

        [self recoverSidecarWithCallback:callback];
    }
}

- (void)recoverSidecarWithCallback:(void (^)(BOOL, NSError*))callback
{
    NSError* error = nil;

    // Try a tracklist sidecar file as a source.
    NSURL* url = [self trackListURL];
    if (![self.trackList readFromFile:url error:&error]) {
        callback(NO, error);
        return;
    }

    // No matter if we received tracks or not, an empty list is just fine.
    callback(YES, nil);
}

- (BOOL)storeTracklistWithError:(NSError* __autoreleasing _Nullable*)error
{
    MediaMetaDataFileFormatType type = [MediaMetaData fileTypeWithURL:self.location error:error];

    // We are using taglib for anything but MP4 for which we use the system
    // provided functions.
    // BOOL ret = NO;
    if (type == MediaMetaDataFileFormatTypeMP4) {
        return [self writeChaperMarksToMP4FileWithError:error];
    }

    NSURL* url = [self trackListURL];
    return [self.trackList writeToFile:url error:error];
}

- (NSString*)readableTracklistWithFrameEncoder:(FrameToString)encoder
{
    NSString* global = @"Tracklist: ";
    if (self.title.length > 0 && self.artist.length > 0) {
        global = [NSString stringWithFormat:@"%@%@ - %@", global, self.artist, self.title];
    } else if (self.title.length > 0) {
        global = [NSString stringWithFormat:@"%@%@", global, self.title];
    } else if (self.artist.length > 0) {
        global = [NSString stringWithFormat:@"%@%@", global, self.artist];
    }
    global = [NSString stringWithFormat:@"%@\n\n", global];
    NSString* tracks = [self.trackList beautifulTracksWithFrameEncoder:encoder];
    return [global stringByAppendingString:tracks];
}

- (BOOL)exportTracklistToFile:(NSURL*)url frameEncoder:(FrameToString)encoder error:(NSError* __autoreleasing _Nullable*)error
{
    NSString* title = self.title.length > 0 ? [NSString stringWithFormat:@"TITLE \"%@\"\n", self.title] : @"";
    NSString* performer = self.artist.length > 0 ? [NSString stringWithFormat:@"PERFORMER \"%@\"\n", self.artist] : @"";
    NSString* file = [NSString stringWithFormat:@"FILE \"%@\" MP3\n", self.location.path];

    NSString* global = @"";
    global = [global stringByAppendingString:title];
    global = [global stringByAppendingString:performer];
    global = [global stringByAppendingString:file];

    NSString* tracks = [self.trackList cueTracksWithFrameEncoder:encoder];

    NSString* sheet = [global stringByAppendingString:tracks];

    NSData* ascii = [sheet dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:YES];

    return [ascii writeToFile:url.path options:NSDataWritingFileProtectionNone error:error];
}

@end
