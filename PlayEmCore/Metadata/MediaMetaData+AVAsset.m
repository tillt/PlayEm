//
//  MediaMetaData+AVAsset.m
//  PlayEm
//
//  Created by Till Toenshoff on 25.02.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#import <Foundation/Foundation.h>

#import <AVFoundation/AVFoundation.h>
#import <AppKit/AppKit.h>
#import <CoreMedia/CMTime.h>
#import <CoreMedia/CoreMedia.h>
#import <iTunesLibrary/ITLibMediaItem.h>

#import "AVMetadataItem+THAdditions.h"
#import "MediaMetaData+AVAsset.h"
#import "MediaMetaData.h"
// #import "../NSError+BetterError.h"

#import "NSString+Sanitized.h"
#import "TemporaryFiles.h"

@implementation MediaMetaData (AVAsset)

+ (NSDictionary*)id3GenreMap
{
    return @{
        @0 : @"Blues",
        @1 : @"Classic Rock",
        @2 : @"Country",
        @3 : @"Dance",
        @4 : @"Disco",
        @5 : @"Funk",
        @6 : @"Grunge",
        @7 : @"Hip-Hop",
        @8 : @"Jazz",
        @9 : @"Metal",
        @10 : @"New Age",
        @11 : @"Oldies",
        @12 : @"Other",
        @13 : @"Pop",
        @14 : @"R&B",
        @15 : @"Rap",
        @16 : @"Reggae",
        @17 : @"Rock",
        @18 : @"Techno",
        @19 : @"Industrial",
        @20 : @"Alternative",
        @21 : @"Ska",
        @22 : @"Death Metal",
        @23 : @"Pranks",
        @24 : @"Soundtrack",
        @25 : @"Euro-Techno",
        @26 : @"Ambient",
        @27 : @"Trip-Hop",
        @28 : @"Vocal",
        @29 : @"Jazz+Funk",
        @30 : @"Fusion",
        @31 : @"Trance",
        @32 : @"Classical",
        @33 : @"Instrumental",
        @34 : @"Acid",
        @35 : @"House",
        @36 : @"Game",
        @37 : @"Sound Clip",
        @38 : @"Gospel",
        @39 : @"Noise",
        @40 : @"Alternative Rock",
        @41 : @"Bass",
        @42 : @"Soul",
        @43 : @"Punk",
        @44 : @"Space",
        @45 : @"Meditative",
        @46 : @"Instrumental Pop",
        @47 : @"Instrumental Rock",
        @48 : @"Ethnic",
        @49 : @"Gothic",
        @50 : @"Darkwave",
        @51 : @"Techno-Industrial",
        @52 : @"Electronic",
        @53 : @"Pop-Folk",
        @54 : @"Eurodance",
        @55 : @"Dream",
        @56 : @"Southern Rock",
        @57 : @"Comedy",
        @58 : @"Cult",
        @59 : @"Gangsta Rap",
        @60 : @"Top 40",
        @61 : @"Christian Rap",
        @62 : @"Pop/Funk",
        @63 : @"Jungle",
        @64 : @"Native American",
        @65 : @"Cabaret",
        @66 : @"New Wave",
        @67 : @"Psychedelic",
        @68 : @"Rave",
        @69 : @"Showtunes",
        @70 : @"Trailer",
        @71 : @"Lo-Fi",
        @72 : @"Tribal",
        @73 : @"Acid Punk",
        @74 : @"Acid Jazz",
        @75 : @"Polka",
        @76 : @"Retro",
        @77 : @"Musical",
        @78 : @"Rock & Roll",
        @79 : @"Hard Rock",
    };
}

+ (long)sampleRateForAsset:(AVAsset*)asset
{
    // Get the first audio track
    AVAssetTrack* audioTrack = [[asset tracksWithMediaType:AVMediaTypeAudio] firstObject];

    if (audioTrack == nil) {
        return 0;
    }

    // Each track has one or more CMAudioFormatDescriptions
    for (id desc in audioTrack.formatDescriptions) {
        CMAudioFormatDescriptionRef formatDesc = (__bridge CMAudioFormatDescriptionRef) desc;

        const AudioStreamBasicDescription* asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc);

        if (asbd != NULL) {
            return (long) (asbd->mSampleRate);
        }
    }

    return 0;  // Could not read sample rate
}

- (void)updateWithMetadataItem:(AVMetadataItem*)item
{
    NSDictionary* id3Genres = [MediaMetaData id3GenreMap];

    NSLog(@"%@ (%@): %@ dataType: %@ extra:%@", [item commonKey], [item keyString], [item value], [item dataType], [item extraAttributes]);

    if ([item commonKey] == nil) {
        if ([[item keyString] isEqualToString:@"TYER"] || [[item keyString] isEqualToString:@"@day"] || [[item keyString] isEqualToString:@"TDRL"]) {
            self.year = [NSNumber numberWithInt:[(NSString*) [item value] intValue]];
        } else if ([[item keyString] isEqualToString:@"@gen"]) {
            self.genre = [(NSString*) [item value] sanitizedMetadataString];
        } else if ([[item keyString] isEqualToString:@"tmpo"]) {
            self.tempo = [NSNumber numberWithInt:[(NSString*) [item value] intValue]];
        } else if ([[item keyString] isEqualToString:@"aART"]) {
            self.albumArtist = [(NSString*) [item value] sanitizedMetadataString];
        } else if ([[item keyString] isEqualToString:@"@cmt"]) {
            self.comment = [(NSString*) [item value] sanitizedMetadataString];
        } else if ([[item keyString] isEqualToString:@"@wrt"]) {
            self.composer = [(NSString*) [item value] sanitizedMetadataString];
        } else if ([[item keyString] isEqualToString:@"@lyr"]) {
            self.lyrics = [(NSString*) [item value] sanitizedMetadataString];
        } else if ([[item keyString] isEqualToString:@"cpil"]) {
            self.compilation = [NSNumber numberWithBool:[(NSString*) [item value] boolValue]];
        } else if ([[item keyString] isEqualToString:@"trkn"]) {
            NSAssert([[item dataType] isEqualToString:(__bridge NSString*) kCMMetadataBaseDataType_RawData], @"item datatype isnt data");
            NSData* data = item.dataValue;
            NSAssert(data.length >= 8, @"unexpected tuple encoding");
            const uint16_t* tuple = data.bytes;
            self.track = [NSNumber numberWithShort:ntohs(tuple[1])];
            self.tracks = [NSNumber numberWithShort:ntohs(tuple[2])];
        } else if ([[item keyString] isEqualToString:@"disk"]) {
            NSAssert([[item dataType] isEqualToString:(__bridge NSString*) kCMMetadataBaseDataType_RawData], @"item datatype isnt data");
            NSData* data = item.dataValue;
            NSAssert(data.length >= 6, @"unexpected tuple encoding");
            const uint16_t* tuple = data.bytes;
            self.disk = [NSNumber numberWithShort:ntohs(tuple[1])];
            self.disks = [NSNumber numberWithShort:ntohs(tuple[2])];
        } else {
            // NSLog(@"ignoring unsupported metadata: %@ (%@): %@", [item commonKey],
            // [item keyString], [item value]);
        }
    } else if ([[item commonKey] isEqualToString:@"title"]) {
        if (item.extraAttributes != nil && [item.extraAttributes objectForKey:@"dataType"] == nil) {
            if ([item.extraAttributes objectForKey:@"HREF"]) {
                self.appleLocation = [NSURL URLWithString:[item.extraAttributes objectForKey:@"HREF"]];
                self.title = [(NSString*) [item value] sanitizedMetadataString];
            } else {
                NSLog(@"skip titles meant for extras - skipping \"%@\" for  %@", [item value], [item extraAttributes]);
            }
        } else {
            self.title = (NSString*) [item value];
        }
    } else if ([[item commonKey] isEqualToString:@"artist"]) {
        self.artist = [(NSString*) [item value] sanitizedMetadataString];
    } else if ([[item commonKey] isEqualToString:@"albumName"]) {
        self.album = [(NSString*) [item value] sanitizedMetadataString];
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
            // NSLog(@"item.dataValue artwork");
            self.artwork = item.dataValue;
        } else if (item.value != nil) {
            // NSLog(@"item.value artwork");
            self.artwork = (NSData*) item.value;
        } else {
            NSLog(@"unknown artwork");
        }
    } else {
        // NSLog(@"ignoring unsupported metadata: %@ (%@): %@", [item commonKey],
        // [item keyString], [item value]);
    }
}

- (BOOL)readFromAVAsset:(AVAsset*)asset error:(NSError* __autoreleasing _Nullable* _Nullable)error
{
    for (NSString* format in [asset availableMetadataFormats]) {
        NSLog(@"format: %@", format);
        // TODO: We could neatly weave this into async AVAsset processing.
        for (AVMetadataItem* item in [asset metadataForFormat:format]) {
            [self updateWithMetadataItem:item];
        }
    }
    return YES;
}

- (void)readChaperMarksFromMP4FileWithCallback:(void (^)(BOOL, NSError*))callback
{
    NSLog(@"readChaperMarksFromMP4FileWithCallback");
    AVAsset* asset = [AVURLAsset URLAssetWithURL:self.location options:nil];
    [self readChapterMarksFromAVAsset:asset callback:callback];
}

- (BOOL)readFromMP4FileWithError:(NSError**)error
{
    NSLog(@"readFromMP4FileWithError");
    AVAsset* asset = [AVURLAsset URLAssetWithURL:self.location options:nil];
    return [self readFromAVAsset:asset error:error];
}

+ (MediaMetaData*)mediaMetaDataWithMetadataItems:(NSArray<AVMetadataItem*>*)items
{
    MediaMetaData* meta = [[MediaMetaData alloc] init];
    for (AVMetadataItem* item in items) {
        [meta updateWithMetadataItem:item];
    }
    return meta;
}

#pragma mark - Chapter Handling

@end
