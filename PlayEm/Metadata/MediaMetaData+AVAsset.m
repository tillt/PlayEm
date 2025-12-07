//
//  MediaMetaData+AVAsset.m
//  PlayEm
//
//  Created by Till Toenshoff on 25.02.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>

#import <iTunesLibrary/ITLibMediaItem.h>

#import "MediaMetaData.h"
#import "MediaMetaData+AVAsset.h"
#import "AVMetadataItem+THAdditions.h"

#import "../NSError+BetterError.h"

@implementation MediaMetaData(AVAsset)

+ (NSDictionary*)id3GenreMap
{
    return @{
        @0: @"Blues",
        @1: @"Classic Rock",
        @2: @"Country",
        @3: @"Dance",
        @4: @"Disco",
        @5: @"Funk",
        @6: @"Grunge",
        @7: @"Hip-Hop",
        @8: @"Jazz",
        @9: @"Metal",
        @10: @"New Age",
        @11: @"Oldies",
        @12: @"Other",
        @13: @"Pop",
        @14: @"R&B",
        @15: @"Rap",
        @16: @"Reggae",
        @17: @"Rock",
        @18: @"Techno",
        @19: @"Industrial",
        @20: @"Alternative",
        @21: @"Ska",
        @22: @"Death Metal",
        @23: @"Pranks",
        @24: @"Soundtrack",
        @25: @"Euro-Techno",
        @26: @"Ambient",
        @27: @"Trip-Hop",
        @28: @"Vocal",
        @29: @"Jazz+Funk",
        @30: @"Fusion",
        @31: @"Trance",
        @32: @"Classical",
        @33: @"Instrumental",
        @34: @"Acid",
        @35: @"House",
        @36: @"Game",
        @37: @"Sound Clip",
        @38: @"Gospel",
        @39: @"Noise",
        @40: @"Alternative Rock",
        @41: @"Bass",
        @42: @"Soul",
        @43: @"Punk",
        @44: @"Space",
        @45: @"Meditative",
        @46: @"Instrumental Pop",
        @47: @"Instrumental Rock",
        @48: @"Ethnic",
        @49: @"Gothic",
        @50: @"Darkwave",
        @51: @"Techno-Industrial",
        @52: @"Electronic",
        @53: @"Pop-Folk",
        @54: @"Eurodance",
        @55: @"Dream",
        @56: @"Southern Rock",
        @57: @"Comedy",
        @58: @"Cult",
        @59: @"Gangsta Rap",
        @60: @"Top 40",
        @61: @"Christian Rap",
        @62: @"Pop/Funk",
        @63: @"Jungle",
        @64: @"Native American",
        @65: @"Cabaret",
        @66: @"New Wave",
        @67: @"Psychedelic",
        @68: @"Rave",
        @69: @"Showtunes",
        @70: @"Trailer",
        @71: @"Lo-Fi",
        @72: @"Tribal",
        @73: @"Acid Punk",
        @74: @"Acid Jazz",
        @75: @"Polka",
        @76: @"Retro",
        @77: @"Musical",
        @78: @"Rock & Roll",
        @79: @"Hard Rock",
    };
}

- (long)sampleRateForAsset:(AVAsset*)asset
{
    // Get the first audio track
    AVAssetTrack *audioTrack = [[asset tracksWithMediaType:AVMediaTypeAudio] firstObject];

    if (audioTrack == nil) {
        return 0;
    }

    // Each track has one or more CMAudioFormatDescriptions
    for (id desc in audioTrack.formatDescriptions) {
        CMAudioFormatDescriptionRef formatDesc = (__bridge CMAudioFormatDescriptionRef)desc;
        
        const AudioStreamBasicDescription* asbd =
            CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc);
        
        if (asbd != NULL) {
            return (long)(asbd->mSampleRate);
        }
    }

    return 0; // Could not read sample rate
}

- (void)readChapterMarks:(AVAsset*)asset
{
    NSArray<NSString*>* preferred = [NSBundle preferredLocalizationsFromArray:[[NSBundle mainBundle] localizations]
                                                               forPreferences:[NSLocale preferredLanguages]];
    long rate = [self sampleRateForAsset:asset];
    NSLog(@"Asset claims to have a rate of %ld", rate);

    [asset loadChapterMetadataGroupsBestMatchingPreferredLanguages:preferred
                                                 completionHandler:^(NSArray<AVTimedMetadataGroup*>* _Nullable chapterGroups,
                                                                     NSError * _Nullable error) {
        if (error) {
            NSLog(@"Error loading chapter metadata: %@", error.localizedDescription);
            return;
        }
        NSLog(@"Loaded %lu chapter groups", (unsigned long)chapterGroups.count);

        self.trackList = [[TrackList alloc] initWithTimedMetadataGroups:chapterGroups framerate:rate];
    }];
}

- (void)updateWithMetadataItem:(AVMetadataItem*)item
{
    NSDictionary* id3Genres = [MediaMetaData id3GenreMap];

    NSLog(@"%@ (%@): %@ dataType: %@ extra:%@", [item commonKey], [item keyString], [item value], [item dataType], [item extraAttributes]);

    if ([item commonKey] == nil) {
        if ([[item keyString] isEqualToString:@"TYER"] || [[item keyString] isEqualToString:@"@day"]  || [[item keyString] isEqualToString:@"TDRL"] ) {
            self.year = [NSNumber numberWithInt:[(NSString*)[item value] intValue]];
        } else if ([[item keyString] isEqualToString:@"@gen"]) {
            self.genre = (NSString*)[item value];
        } else if ([[item keyString] isEqualToString:@"tmpo"]) {
            self.tempo = [NSNumber numberWithInt:[(NSString*)[item value] intValue]];
        } else if ([[item keyString] isEqualToString:@"aART"]) {
            self.albumArtist = (NSString*)[item value];
        } else if ([[item keyString] isEqualToString:@"@cmt"]) {
            self.comment = (NSString*)[item value];
        } else if ([[item keyString] isEqualToString:@"@wrt"]) {
            self.composer = (NSString*)[item value];
        } else if ([[item keyString] isEqualToString:@"@lyr"]) {
            self.lyrics = (NSString*)[item value];
        } else if ([[item keyString] isEqualToString:@"cpil"]) {
            self.compilation = [NSNumber numberWithBool:[(NSString*)[item value] boolValue]];
        } else if ([[item keyString] isEqualToString:@"trkn"]) {
            NSAssert([[item dataType] isEqualToString:(__bridge NSString*)kCMMetadataBaseDataType_RawData], @"item datatype isnt data");
            NSData* data = item.dataValue;
            NSAssert(data.length >= 8, @"unexpected tuple encoding");
            const uint16_t* tuple = data.bytes;
            self.track = [NSNumber numberWithShort:ntohs(tuple[1])];
            self.tracks = [NSNumber numberWithShort:ntohs(tuple[2])];
        } else if ([[item keyString] isEqualToString:@"disk"]) {
            NSAssert([[item dataType] isEqualToString:(__bridge NSString*)kCMMetadataBaseDataType_RawData], @"item datatype isnt data");
            NSData* data = item.dataValue;
            NSAssert(data.length >= 6, @"unexpected tuple encoding");
            const uint16_t* tuple = data.bytes;
            self.disk = [NSNumber numberWithShort:ntohs(tuple[1])];
            self.disks = [NSNumber numberWithShort:ntohs(tuple[2])];
        } else {
            //NSLog(@"ignoring unsupported metadata: %@ (%@): %@", [item commonKey], [item keyString], [item value]);
        }
    } else if ([[item commonKey] isEqualToString:@"title"]) {
        if (item.extraAttributes != nil && [item.extraAttributes objectForKey:@"dataType"] == nil) {
            NSLog(@"skip titles meant for extras - skipping \"%@\" for  %@", [item value], [item extraAttributes]);
        } else {
            self.title = (NSString*)[item value];
        }
    } else if ([[item commonKey] isEqualToString:@"artist"]) {
        self.artist = (NSString*)[item value];
    } else if ([[item commonKey] isEqualToString:@"albumName"]) {
        self.album = (NSString*)[item value];
    } else if ([[item commonKey] isEqualToString:@"type"]) {
        NSData* data = item.dataValue;
        NSAssert(data.length >= 2, @"unexpected genre encoding");
        const uint16_t* genre = data.bytes;
        const uint16_t index = ntohs(genre[0]);
        NSAssert(index >= 1 && index <= 80, @"unexpected genre index %d", index);
        // For some reason AVAsset serves a genre index +1 of the original id3 one.
        NSNumber* genreNumber = [NSNumber numberWithUnsignedShort:index - 1];
        self.genre = id3Genres[genreNumber];
    } else if ([[item commonKey] isEqualToString:@"artwork"]) {
        if (item.dataValue != nil) {
            //NSLog(@"item.dataValue artwork");
            self.artwork = item.dataValue;
        } else if (item.value != nil) {
            //NSLog(@"item.value artwork");
            self.artwork = (NSData*)item.value;
        } else {
            NSLog(@"unknown artwork");
        }
    } else {
        //NSLog(@"ignoring unsupported metadata: %@ (%@): %@", [item commonKey], [item keyString], [item value]);
    }
}

- (BOOL)readFromAVAsset:(AVAsset *)asset
{
    for (NSString* format in [asset availableMetadataFormats]) {
        NSLog(@"format: %@", format);
        for (AVMetadataItem* item in [asset metadataForFormat:format]) {
            [self updateWithMetadataItem:item];
        }
    }
    
    [self readChapterMarks:asset];
 
    return YES;
}

- (BOOL)readFromMP4FileWithError:(NSError**)error
{
    AVAsset* asset = [AVURLAsset URLAssetWithURL:self.location options:nil];
    //NSLog(@"%@", asset);
    return [self readFromAVAsset:asset];
}

+ (MediaMetaData*)mediaMetaDataWithMetadataItems:(NSArray<AVMetadataItem*>*)items error:(NSError**)error
{
    MediaMetaData* meta = [[MediaMetaData alloc] init];
    for (AVMetadataItem* item in items) {
        [meta updateWithMetadataItem:item];
    }
    return meta;
}


#pragma mark - EXPERIMENTAL: Chapter Handling 



/*
 !!! NONE OF THIS WORKS AS HOPED, SO FAR !!!
 
 The idea is getting AV Foundation to allow us to create MP4 files with chapter marks.
 This is somehow possible I bet, just there are plenty of traps and AV Foundation isnt
 too generous with its error handling.
 
 One challenge might be that chapter marks can only be stored in video files (that only
 have an audio track).
 */



/*
- (BOOL)addChapterMarksToMP4:(NSURL*)inputURL
                   outputURL:(NSURL*)outputURL
                    chapters:(NSArray<NSDictionary*>*)chapters
                       error:(NSError**)error
{
     chapters = @[
     @{@"title": @"Intro", @"time": @(0)},
     @{@"title": @"Scene 1", @"time": @(60)},
     @{@"title": @"Scene 2", @"time": @(120)}
     ];
     AVAsset* asset = [AVAsset assetWithURL:inputURL];
     if (!asset.isExportable) {
     NSLog(@"asset is not exportable");
     return NO;
     }
     AVAssetExportSession* exportSession = [[AVAssetExportSession alloc] initWithAsset:asset
     presetName:AVAssetExportPresetPassthrough];
     exportSession.outputURL = outputURL;
     exportSession.outputFileType = AVFileTypeAppleM4A;
     
     // Create chapter metadata
     NSMutableArray<AVMutableMetadataItem*> *metadataItems = [NSMutableArray array];
     
     for (NSDictionary *chapter in chapters) {
     NSString* title = chapter[@"title"];
     NSNumber* timeSeconds = chapter[@"time"];
     
     CMTime time = CMTimeMakeWithSeconds(timeSeconds.doubleValue, 600);
     
     AVMutableMetadataItem *chapterItem = [AVMutableMetadataItem metadataItem];
     chapterItem.keySpace = AVMetadataKeySpaceQuickTimeUserData;
     chapterItem.key = AVMetadataQuickTimeUserDataKeyChapter;
     chapterItem.value = title;
     chapterItem.extraAttributes = @{
     AVMetadataExtraAttributeInfoKey : @{
     AVMetadataExtraAttributeInfoKey : title
     }
     };
     
     // AVFoundation uses timed metadata groups for chapters
     AVMutableTimedMetadataGroup* sgroup = [[AVMutableTimedMetadataGroup alloc] initWithItems:@[chapterItem]
     timeRange:CMTimeRangeMake(time, CMTimeMakeWithSeconds(0.5, 600))];
     
     [metadataItems addObject:chapterItem];
     }
     
     // Set metadata on export session
     // exportSession.metadata = metadataItems;
     
     // Export asynchronously
     [exportSession exportAsynchronouslyWithCompletionHandler:^{
     switch (exportSession.status) {
     case AVAssetExportSessionStatusCompleted:
     NSLog(@"✅ Export completed: %@", outputURL);
     break;
     case AVAssetExportSessionStatusFailed:
     NSLog(@"❌ Export failed: %@", exportSession.error);
     break;
     case AVAssetExportSessionStatusCancelled:
     NSLog(@"⚠️ Export cancelled");
     break;
     default:
     break;
     }
     }];
     return YES;
}
     */

/*
   
- (void)addChapterMarksToMP4AtURL:(NSURL*)inputURL
                        outputURL:(NSURL*)outputURL
                       completion:(void (^)(BOOL success, NSError* error))completion
{
    // 1. Load the source asset
    AVURLAsset *sourceAsset = [AVURLAsset URLAssetWithURL:inputURL options:nil];

    // 2. Create a mutable composition
    AVMutableComposition *composition = [AVMutableComposition composition];

    // 3. Add the original audio track
    AVAssetTrack *sourceAudioTrack = [[sourceAsset tracksWithMediaType:AVMediaTypeAudio] firstObject];
    if (sourceAudioTrack) {
        AVMutableCompositionTrack *compositionAudioTrack =
            [composition addMutableTrackWithMediaType:AVMediaTypeAudio
                                       preferredTrackID:kCMPersistentTrackID_Invalid];
        NSError *insertError = nil;
        [compositionAudioTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, sourceAsset.duration)
                                       ofTrack:sourceAudioTrack
                                        atTime:kCMTimeZero
                                         error:&insertError];
        if (insertError) {
            NSLog(@"Error inserting audio track: %@", insertError);
            if (completion) completion(NO, insertError);
            return;
        }
    }

    // 4. Create a timed metadata track
    AVMutableCompositionTrack *metadataTrack =
        [composition addMutableTrackWithMediaType:AVMediaTypeMetadata
                                   preferredTrackID:kCMPersistentTrackID_Invalid];

    // 5. Create sample metadata items
    CMTime fiveSeconds = CMTimeMakeWithSeconds(5.0, 600);
    CMTime tenSeconds = CMTimeMakeWithSeconds(10.0, 600);

    AVMutableMetadataItem *item1 = [[AVMutableMetadataItem alloc] init];
    item1.identifier = AVMetadataIdentifierQuickTimeMetadataTitle;
    item1.value = @"Intro";
    item1.dataType = (__bridge NSString *)kCMMetadataBaseDataType_UTF8;
    item1.startDate = nil; // optional
    item1.time = fiveSeconds;
    item1.duration = CMTimeMakeWithSeconds(2.0, 600);

    AVMutableMetadataItem *item2 = [[AVMutableMetadataItem alloc] init];
    item2.identifier = AVMetadataIdentifierQuickTimeMetadataTitle;
    item2.value = @"Chorus";
    item2.dataType = (__bridge NSString *)kCMMetadataBaseDataType_UTF8;
    item2.time = tenSeconds;
    item2.duration = CMTimeMakeWithSeconds(2.0, 600);

    NSArray *metadataSamples = @[item1, item2];

    // 6. Add the metadata samples as timed metadata
    AVTimedMetadataGroup *group1 = [[AVTimedMetadataGroup alloc] initWithItems:@[item1]
                                                                   timeRange:CMTimeRangeMake(fiveSeconds, CMTimeMakeWithSeconds(2.0, 600))];

    AVTimedMetadataGroup *group2 = [[AVTimedMetadataGroup alloc] initWithItems:@[item2]
                                                                   timeRange:CMTimeRangeMake(tenSeconds, CMTimeMakeWithSeconds(2.0, 600))];

    // (Note: In AVFoundation, you don't insert metadata "samples" like audio/video.
    // Instead, adding them to the composition track defines their presence in the export.)

    NSError *metadataError = nil;
    if (![metadataTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, sourceAsset.duration)
                                ofTrack:nil
                                 atTime:kCMTimeZero
                                  error:&metadataError]) {
        NSLog(@"Error adding metadata track: %@", metadataError);
    }

    // 7. Create an export session
    AVAssetExportSession *exportSession =
        [[AVAssetExportSession alloc] initWithAsset:composition
                                          presetName:AVAssetExportPresetAppleM4A];
    exportSession.outputURL = outputURL;
    exportSession.outputFileType = AVFileTypeAppleM4A;
    exportSession.metadata = @[item1, item2]; // global metadata, optional

    // 8. Start export
    [exportSession exportAsynchronouslyWithCompletionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            if (exportSession.status == AVAssetExportSessionStatusCompleted) {
                NSLog(@"Export successful!");
                if (completion) completion(YES, nil);
            } else {
                NSLog(@"Export failed: %@", exportSession.error);
                if (completion) completion(NO, exportSession.error);
            }
        });
    }];
}
*/

//
//static AVTimedMetadataGroup *ChapterMetadataGroup(NSString *title, CMTime startTime, CMTime duration) {
//    // Create title metadata item
//    AVMutableMetadataItem *titleItem = [AVMutableMetadataItem metadataItem];
//    titleItem.identifier = AVMetadataIdentifierQuickTimeUserDataChapter;
//    titleItem.dataType = (__bridge NSString *)kCMMetadataBaseDataType_UTF8;
//    titleItem.value = title;
//    titleItem.extendedLanguageTag = @"und"; // undetermined language
//
//    // Create time range for chapter
//    CMTimeRange timeRange = CMTimeRangeMake(startTime, duration);
//
//    // Build timed metadata group
//    AVTimedMetadataGroup *group = [[AVTimedMetadataGroup alloc] initWithItems:@[titleItem]
//                                                                    timeRange:timeRange];
//    return group;
//}

- (void)addChaptersToAudioFileAtURL:(NSURL *)inputURL
                         outputURL:(NSURL *)outputURL
{
    AVURLAsset* asset = [AVURLAsset URLAssetWithURL:inputURL options:nil];
    
    // 1. Create a composition
    AVMutableComposition* composition = [AVMutableComposition composition];
    
    // 2. Add the original audio track
    AVAssetTrack *audioTrack = [[asset tracksWithMediaType:AVMediaTypeAudio] firstObject];
    AVMutableCompositionTrack *compositionAudioTrack = [composition addMutableTrackWithMediaType:AVMediaTypeAudio
                                                                                preferredTrackID:kCMPersistentTrackID_Invalid];
    
    NSError *error = nil;
    [compositionAudioTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, asset.duration)
                                   ofTrack:audioTrack
                                    atTime:kCMTimeZero
                                     error:&error];
    if (error) {
        NSLog(@"Error inserting audio track: %@", error);
        return;
    }
    
    // 3. Add a timed metadata track
//    AVMutableCompositionTrack *metadataTrack = [composition addMutableTrackWithMediaType:AVMediaTypeMetadata
//                                                                          preferredTrackID:kCMPersistentTrackID_Invalid];
//    
//    // 4. Create chapter marks
//    NSArray<NSDictionary *> *chapters = @[
//        @{@"title": @"Intro", @"time": @0},
//        @{@"title": @"Verse 1", @"time": @10},
//        @{@"title": @"Chorus", @"time": @30},
//        @{@"title": @"Outro", @"time": @50}
//    ];
//    
//    NSMutableArray<AVMutableMetadataItem *> *metadataItems = [NSMutableArray array];
//    
//    for (NSDictionary *chapter in chapters) {
//        AVMutableMetadataItem *item = [AVMutableMetadataItem metadataItem];
//        //item.identifier = AVMetadataiTunesMetadataKeyDescription; // Chapter title
//        item.identifier = AVMetadataCommonIdentifierTitle;
//        item.value = chapter[@"title"];
//        item.dataType = (__bridge NSString *)kCMMetadataBaseDataType_UTF8;
//        item.time = CMTimeMakeWithSeconds([chapter[@"time"] doubleValue], 600);
//        [metadataItems addObject:item];
//    }
//    
//    // 5. Insert metadata items into the track
//    for (AVMutableMetadataItem *item in metadataItems) {
//        [metadataTrack insertTimeRange:CMTimeRangeMake(item.time, CMTimeMake(1, 600))
//                                ofTrack:metadataTrack
//                                 atTime:item.time
//                                  error:&error];
//        if (error) {
//            NSLog(@"Error inserting metadata: %@", error);
//        }
//    }
    
    // 6. Export the composition
    AVAssetExportSession *exporter = [[AVAssetExportSession alloc] initWithAsset:composition
                                                                      presetName:AVAssetExportPresetPassthrough];
    exporter.outputURL = outputURL;
    exporter.outputFileType = AVFileTypeAppleM4A;
    //exporter.metadata = metadataItems; // ensure metadata is exported
    [exporter exportAsynchronouslyWithCompletionHandler:^{
        if (exporter.status == AVAssetExportSessionStatusCompleted) {
            NSLog(@"Export completed: %@", outputURL);
        } else {
            NSLog(@"Export failed: %@", exporter.error);
            NSError* better = [NSError betterErrorWithError:exporter.error];
            NSLog(@"Better failure: %@", better);
        }
    }];

}

@end
