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

#import <iTunesLibrary/ITLibMediaItem.h>

#import "MediaMetaData.h"
#import "MediaMetaData+AVAsset.h"
#import "AVMetadataItem+THAdditions.h"

@implementation MediaMetaData(AVAsset)

+ (NSDictionary<NSString*, NSDictionary<NSString*, NSString*>*>*)mp4TagMap
{
    NSDictionary<NSString*, NSDictionary*>* mediaMetaKeyMap = [MediaMetaData mediaMetaKeyMap];
    
    NSMutableDictionary<NSString*, NSMutableDictionary<NSString*, id>*>* mp4TagMap = [NSMutableDictionary dictionary];
    
    for (NSString* mediaDataKey in [mediaMetaKeyMap allKeys]) {
        // Skip anything that isnt supported by MP4.
        if ([mediaMetaKeyMap[mediaDataKey] objectForKey:kMediaMetaDataMapKeyMP4] == nil) {
            continue;
        }

        NSString* mp4Key = mediaMetaKeyMap[mediaDataKey][kMediaMetaDataMapKeyMP4][kMediaMetaDataMapKeyKey];
        NSString* keyspace = mediaMetaKeyMap[mediaDataKey][kMediaMetaDataMapKeyMP4][kMediaMetaDataMapKeyKeySpace];
        NSString* type = kMediaMetaDataMapTypeString;
        NSString* t = [mediaMetaKeyMap[mediaDataKey][kMediaMetaDataMapKeyMP4] objectForKey:kMediaMetaDataMapKeyType];
        if (t != nil) {
            type = t;
        }
        NSMutableDictionary* mp4Dictionary = mp4TagMap[mp4Key];
        if (mp4TagMap[mp4Key] == nil) {
            mp4Dictionary = [NSMutableDictionary dictionary];
        }
        mp4Dictionary[kMediaMetaDataMapKeyKeySpace] = keyspace;
        mp4Dictionary[kMediaMetaDataMapKeyType] = type;
        
        NSMutableArray* mediaKeys = mp4Dictionary[kMediaMetaDataMapKeyKeys];
        if (mediaKeys == nil) {
            mediaKeys = [NSMutableArray array];
            if ([type isEqualToString:kMediaMetaDataMapTypeTuple] || [type isEqualToString:kMediaMetaDataMapTypeTuple48] || [type isEqualToString:kMediaMetaDataMapTypeTuple64]) {
                [mediaKeys addObjectsFromArray:@[@"", @""]];
            }
        }
        
        NSNumber* position = mediaMetaKeyMap[mediaDataKey][kMediaMetaDataMapKeyMP4][kMediaMetaDataMapKeyOrder];
        if (position != nil) {
            [mediaKeys replaceObjectAtIndex:[position intValue] withObject:mediaDataKey];
        } else {
            [mediaKeys addObject:mediaDataKey];
        }

        mp4Dictionary[kMediaMetaDataMapKeyKeys] = mediaKeys;

        mp4TagMap[mp4Key] = mp4Dictionary;
    }

    return mp4TagMap;
}

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

- (BOOL)readFromAVAsset:(AVAsset *)asset
{
    NSDictionary* id3Genres = [MediaMetaData id3GenreMap];
    NSLog(@"read metadata from AVAsset:%@", asset );
    // Note, this code uses a pre 10.10 compatible way of parsing the tags - newer versions
    // of macOS do support proper identifiers
    for (NSString* format in [asset availableMetadataFormats]) {
        for (AVMetadataItem* item in [asset metadataForFormat:format]) {
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
                    NSLog(@"questionable metadata: %@ (%@): %@", [item commonKey], [item keyString], [item value]);
                }
            } else if ([[item commonKey] isEqualToString:@"title"]) {
                self.title = (NSString*)[item value];
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
                    NSLog(@"item.dataValue artwork");
                    self.artwork = item.dataValue;
                } else if (item.value != nil) {
                    NSLog(@"item.value artwork");
                    self.artwork = (NSData*)item.value;
                } else {
                    NSLog(@"unknown artwork");
                }
            } else {
                NSLog(@"questionable metadata: %@ (%@): %@", [item commonKey], [item keyString], [item value]);
            }
        }
    }
    return YES;
}

- (BOOL)readFromMP4FileWithError:(NSError**)error
{
    AVAsset* asset = [AVURLAsset URLAssetWithURL:self.location options:nil];
    NSLog(@"%@", asset);
    return [self readFromAVAsset:asset];
}

- (NSArray<AVMetadataItem*>*)renderAVAssetMetaData
{
    NSMutableArray<AVMutableMetadataItem*>* list = [NSMutableArray new];
    NSDictionary* mp4TagMap = [MediaMetaData mp4TagMap];

    for (NSString* mp4Key in [mp4TagMap allKeys]) {
        NSString* mediaKey = mp4TagMap[mp4Key][kMediaMetaDataMapKeyKeys][0];
        // Anything we dont have a value for shall be skipped as we must not produce empty
        // metadata records as that seems invalid for MP4.
        if ([self valueForKey:mediaKey] == nil) {
            continue;
        }

        AVMutableMetadataItem* item = [AVMutableMetadataItem metadataItem];
        NSString* keyspace = mp4TagMap[mp4Key][kMediaMetaDataMapKeyKeySpace];
        NSString* type = kMediaMetaDataMapTypeString;
        NSString* t = [mp4TagMap[mp4Key] objectForKey:kMediaMetaDataMapKeyType];
        if (t != nil) {
            type = t;
        }
        item.keySpace = keyspace;
        item.key = mp4Key;

        NSString* value = [self stringForKey:mediaKey];
        if ([type isEqualToString:kMediaMetaDataMapTypeTuple] || [type isEqualToString:kMediaMetaDataMapTypeTuple48] || [type isEqualToString:kMediaMetaDataMapTypeTuple64]) {
            size_t length = 8;
            if ([type isEqualToString:kMediaMetaDataMapTypeTuple48]) {
                length = 6;
            } else {
                length = 8;
            }
            NSMutableData* data = [NSMutableData dataWithLength:length];
            uint16_t* tuple = (uint16_t*)data.bytes;
            tuple[1] = ntohs([value intValue]);
            
            mediaKey = mp4TagMap[mp4Key][kMediaMetaDataMapKeyKeys][1];
            value = [self stringForKey:mediaKey];
            if ([value length] > 0) {
                tuple[2] = ntohs([value intValue]);
            }
            item.dataType = (__bridge NSString*)kCMMetadataBaseDataType_RawData;
            item.value = data;
        } else if ([type isEqualToString:kMediaMetaDataMapTypeNumber] || [type isEqualToString:kMediaMetaDataMapTypeNumber16] || [type isEqualToString:kMediaMetaDataMapTypeNumber8]) {
            size_t length = 1;
            if ([type isEqualToString:kMediaMetaDataMapTypeNumber8]) {
                length = 1;
            } else {
                length = 2;
            }
            if (length == 1) {
                item.dataType = (__bridge NSString*)kCMMetadataBaseDataType_SInt8;
            } else {
                item.dataType = (__bridge NSString*)kCMMetadataBaseDataType_SInt16;
            }
            item.value = [NSNumber numberWithInt:[value intValue]];
        } else if ([type isEqualToString:kMediaMetaDataMapTypeImage]) {
            item.dataType = (__bridge NSString*)kCMMetadataBaseDataType_RawData;
            item.value = self.artwork;
        } else {
            item.dataType = (__bridge NSString*)kCMMetadataBaseDataType_UTF8;
            item.value = value;
        }
        [list addObject:item];
    }
    
    return list;
}

- (BOOL)writeToMP4FileWithError:(NSError**)error
{
    NSString* fileExtension = [self.location pathExtension];
    NSString* fileName = [[self.location URLByDeletingPathExtension] lastPathComponent];
    
    AVURLAsset* asset = [AVURLAsset assetWithURL:self.location];
    AVAssetExportSession* session = [AVAssetExportSession exportSessionWithAsset:asset
                                                                      presetName:AVAssetExportPresetPassthrough];
    session.outputFileType = AVFileTypeAppleM4A;

    NSString* outputFolder = @"/tmp/";
    NSString* outputFile = [NSString stringWithFormat:@"%@%@.%@", outputFolder, fileName, fileExtension];
    session.outputURL = [NSURL fileURLWithPath:outputFile];

    NSArray* metaList = [self renderAVAssetMetaData];
    NSAssert(metaList != nil, @"no metadata rendered");
    
    session.metadataItemFilter = nil;
    NSLog(@"metadatalist %@", metaList);
    session.metadata = metaList;

    [session exportAsynchronouslyWithCompletionHandler:^(){
        NSLog(@"MP4 export session completed for %@", session.outputURL);
        if (session.status != AVAssetExportSessionStatusCompleted) {
            NSLog(@"session did not complete but %ld", session.status);
            return;
        }
        if (session.error != nil) {
            NSLog(@"error during export: %@", session.error);
            return;
        }
        // [NSFileManager replaceFile]
    }];
    
    return YES;
}

@end
