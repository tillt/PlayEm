//
//  MediaMetaData.m
//  PlayEm
//
//  Created by Till Toenshoff on 08.11.20.
//  Copyright © 2020 Till Toenshoff. All rights reserved.
//

#import "MediaMetaData.h"

#import <AVFoundation/AVFoundation.h>

#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>

#import <Foundation/Foundation.h>

#import <iTunesLibrary/ITLibMediaItem.h>
#import <iTunesLibrary/ITLibArtist.h>
#import <iTunesLibrary/ITLibAlbum.h>
#import <iTunesLibrary/ITLibArtwork.h>

#import "AVMetadataItem+THAdditions.h"
#import "ITLibMediaItem+TTAdditionsh.h"
#import "MediaMetaData+TagLib.h"

///
/// MediaMetaData is lazily holding metadata for library entries to allow for extending iTunes provided data.
/// iTunes provided data are held in a shadow item until data is requested and thus copied in. iTunes metadata
/// is asynchronously requested through ITLibMediaItem on demand.
///

NSString* const kMediaMetaDataMapKeyMP3 = @"mp3";
NSString* const kMediaMetaDataMapKeyType = @"type";
NSString* const kMediaMetaDataMapKeyKey = @"key";
NSString* const kMediaMetaDataMapKeyKeys = @"keys";
NSString* const kMediaMetaDataMapKeyOrder = @"order";
NSString* const kMediaMetaDataMapTypeString = @"string";
NSString* const kMediaMetaDataMapTypeDate = @"date";
NSString* const kMediaMetaDataMapTypeImage = @"image";
NSString* const kMediaMetaDataMapTypeNumbers = @"ofNumber";

@implementation MediaMetaData

+ (MediaMetaDataFileFormatType)fileTypeWithURL:(NSURL*)url error:(NSError**)error
{
    if (url == nil) {
        NSString* description = @"Cannot identify item as it lacks a location";
        if (error) {
            NSDictionary* userInfo = @{
                NSLocalizedDescriptionKey: description,
            };
            *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier]
                                         code:-1
                                     userInfo:userInfo];
        }
        NSLog(@"error: %@", description);
        return MediaMetaDataFileFormatTypeUnknown;
    }
    
    NSString* fileExtension = [url pathExtension];
    
    if ([fileExtension isEqualToString:@"mp4"] || [fileExtension isEqualToString:@"m4a"]) {
        return MediaMetaDataFileFormatTypeMP4;
    }
    if ([fileExtension isEqualToString:@"mp3"]) {
        return MediaMetaDataFileFormatTypeMP3;
    }
    
    NSString* description = [NSString stringWithFormat:@"Unknown file type (%@)", fileExtension];
    if (error) {
        NSDictionary* userInfo = @{
            NSLocalizedDescriptionKey: description,
        };
        *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier]
                                     code:-1
                                 userInfo:userInfo];
    }
    NSLog(@"error: %@", description);
    return MediaMetaDataFileFormatTypeUnknown;
}

+ (MediaMetaData*)mediaMetaDataWithURL:(NSURL*)url error:(NSError**)error
{
    MediaMetaData* meta = [[MediaMetaData alloc] init];
    meta.location = [url filePathURL];
    [meta readFromFileWithError:error];
    return meta;
}

- (BOOL)readFromFileWithError:(NSError**)error
{
    MediaMetaDataFileFormatType type = [MediaMetaData fileTypeWithURL:self.location error:error];
    if (type == MediaMetaDataFileFormatTypeMP3) {
        return [self readFromMP3FileWithError:error] == 0;
    }
    if (type == MediaMetaDataFileFormatTypeUnknown) {
        return NO;
    }
    
    AVAsset* asset = [AVURLAsset URLAssetWithURL:self.location options:nil];
    NSLog(@"%@", asset);
    return [self readFromAsset:asset];
}

- (BOOL)readFromAsset:(AVAsset *)asset
{
    for (NSString* format in [asset availableMetadataFormats]) {
        for (AVMetadataItem* item in [asset metadataForFormat:format]) {
            NSLog(@"%@ (%@): %@", [item commonKey], [item keyString], [item value]);
            if ([item commonKey] == nil) {
                if ([[item keyString] isEqualToString:@"TYER"] || [[item keyString] isEqualToString:@"@day"]  || [[item keyString] isEqualToString:@"TDRL"] ) {
                    self.year = [NSNumber numberWithInt:[(NSString*)[item value] intValue]];
                } else if ([[item keyString] isEqualToString:@"@gen"]) {
                    self.genre = (NSString*)[item value];
                } else {
                    continue;
                }
            }
            if ([[item commonKey] isEqualToString:@"title"]) {
                self.title = (NSString*)[item value];
            } else if ([[item commonKey] isEqualToString:@"artist"]) {
                self.artist = (NSString*)[item value];
            } else if ([[item commonKey] isEqualToString:@"albumName"]) {
                self.album = (NSString*)[item value];
            } else if ([[item commonKey] isEqualToString:@"type"]) {
                self.genre = (NSString*)[item value];
            } else if ([[item commonKey] isEqualToString:@"artwork"]) {
                if (item.dataValue != nil) {
                    NSLog(@"item.dataValue artwork");
                    self.artwork = [[NSImage alloc] initWithData:item.dataValue];
                } else if (item.value != nil) {
                    NSLog(@"item.value artwork");
                    self.artwork = [[NSImage alloc] initWithData:(id)item.value];
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

+ (MediaMetaData*)mediaMetaDataWithURL:(NSURL*)url asset:(AVAsset *)asset error:(NSError**)error
{
    MediaMetaData* meta = [[MediaMetaData alloc] init];
    
    meta.location = url;
    
    [meta readFromAsset:asset];
    
    return meta;
}

+ (MediaMetaData*)mediaMetaDataWithITLibMediaItem:(ITLibMediaItem*)item error:(NSError**)error
{
    MediaMetaData* meta = [[MediaMetaData alloc] init];
    meta.shadow = item;
    meta.key = @"";
    return meta;
}

+ (NSDictionary<NSString*, NSDictionary*>*)mediaMetaKeyMap
{
    return @{
        @"added": @{},
        @"location": @{},
        @"locationType": @{},
        
        @"album": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKeyKey: @"ALBUM",
                kMediaMetaDataMapKeyType: kMediaMetaDataMapTypeString,
            },
        },
        @"albumArtist": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKeyKey: @"ALBUMARTIST",
                kMediaMetaDataMapKeyType: kMediaMetaDataMapTypeString,
            },
        },
        @"artist": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKeyKey: @"ARTIST",
                kMediaMetaDataMapKeyType: kMediaMetaDataMapTypeString,
            },
        },
        @"artwork": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKeyKey: @"PICTURE",
                kMediaMetaDataMapKeyType: kMediaMetaDataMapTypeImage,
            },
        },
        @"comment": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKeyKey: @"COMMENTS",
                kMediaMetaDataMapKeyType: kMediaMetaDataMapTypeString,
            },
        },
        @"composer": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKeyKey: @"COMPOSER",
                kMediaMetaDataMapKeyType: kMediaMetaDataMapTypeString,
            },
        },
        @"label": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKeyKey: @"LABEL",
                kMediaMetaDataMapKeyType: kMediaMetaDataMapTypeString,
            },
        },
        @"disk": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKeyKey: @"DISCNUMBER",
                kMediaMetaDataMapKeyType: kMediaMetaDataMapTypeNumbers,
                kMediaMetaDataMapKeyOrder: @0,
            },
        },
        @"disks": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKeyKey: @"DISCNUMBER",
                kMediaMetaDataMapKeyType: kMediaMetaDataMapTypeNumbers,
                kMediaMetaDataMapKeyOrder: @1,
            },
        },
        @"duration": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKeyKey: @"LENGTH",
                kMediaMetaDataMapKeyType: kMediaMetaDataMapTypeString,
            },
        },
        @"genre": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKeyKey: @"GENRE",
                kMediaMetaDataMapKeyType: kMediaMetaDataMapTypeString,
            },
        },
        @"key": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKeyKey: @"INITIALKEY",
                kMediaMetaDataMapKeyType: kMediaMetaDataMapTypeString,
            },
        },
        @"tempo": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKeyKey: @"BPM",
                kMediaMetaDataMapKeyType: kMediaMetaDataMapTypeString,
            },
        },
        @"title": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKeyKey: @"TITLE",
                kMediaMetaDataMapKeyType: kMediaMetaDataMapTypeString,
            },
        },
        @"track": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKeyKey: @"TRACKNUMBER",
                kMediaMetaDataMapKeyType: kMediaMetaDataMapTypeNumbers,
                kMediaMetaDataMapKeyOrder: @0,
            },
        },
        @"tracks": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKeyKey: @"TRACKNUMBER",
                kMediaMetaDataMapKeyType: kMediaMetaDataMapTypeNumbers,
                kMediaMetaDataMapKeyOrder: @1,
            },
        },
        @"year": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKeyKey: @"DATE",
                kMediaMetaDataMapKeyType: kMediaMetaDataMapTypeDate,
            },
        },
    };
}

+ (NSArray<NSString*>*)mediaMetaKeys
{
    return [[MediaMetaData mediaMetaKeyMap] allKeys];
}

- (NSString*)description
{
    return [NSString stringWithFormat:@"Title: %@ -- Album: %@ -- Artist: %@ -- Location: %@",
            self.title, self.album, self.artist, self.location];
}

- (id)copyWithZone:(NSZone *)zone
{
    MediaMetaData* copy = [[[self class] allocWithZone:zone] init];
    if (copy != nil) {
        copy.title = [_title copyWithZone:zone];
        copy.album = [_album copyWithZone:zone];
        copy.artist = [_artist copyWithZone:zone];
        copy.genre = [_genre copyWithZone:zone];
        copy.year = [_year copyWithZone:zone];
        copy.comment = [_comment copyWithZone:zone];
        copy.composer = [_composer copyWithZone:zone];
        copy.albumArtist = [_albumArtist copyWithZone:zone];
        copy.label = [_label copyWithZone:zone];
        copy.tempo = [_tempo copyWithZone:zone];
        copy.albumArtist = [_albumArtist copyWithZone:zone];
        copy.key = [_key copyWithZone:zone];
        copy.track = [_track copyWithZone:zone];
        copy.tracks = [_tracks copyWithZone:zone];
        copy.disk = [_disk copyWithZone:zone];
        copy.disks = [_disks copyWithZone:zone];
        copy.locationType = [_locationType copyWithZone:zone];
        copy.artwork = [_artwork copyWithZone:zone];
        copy.location = [_location copyWithZone:zone];
        copy.added = [_added copyWithZone:zone];
        copy.duration = [_duration copyWithZone:zone];
        
        copy.shadow = _shadow;
    }
    return copy;
}

- (NSString* _Nullable)stringForKey:(NSString*)key
{
    id valueObject = [self valueForKey:key];
    
    if ([valueObject isKindOfClass:[NSString class]]) {
        return valueObject;
    }
    
    if ([valueObject isKindOfClass:[NSNumber class]] && [valueObject intValue] > 0) {
        return [valueObject stringValue];
    }
    
    if ([valueObject isKindOfClass:[NSURL class]]) {
        return [[valueObject absoluteString] stringByRemovingPercentEncoding];
    }
    
    if ([valueObject isKindOfClass:[NSDate class]]) {
        return [NSDateFormatter localizedStringFromDate:valueObject
                                              dateStyle:NSDateFormatterShortStyle
                                              timeStyle:NSDateFormatterNoStyle];
    }
    
    return @"";
}

- (BOOL)isEqualToMediaMetaData:(MediaMetaData*)other forKeys:(NSArray<NSString*>*)keys
{
    if (other == nil) {
        return NO;
    }
    
    for (NSString* key in keys) {
        // Special treatment for `artwork`.
        if ([key isEqualToString:@"artwork"]) {
            NSData* thisData = [self.artwork TIFFRepresentation];
            NSData* otherData = [other.artwork TIFFRepresentation];
            
            if (![thisData isEqualToData:otherData]) {
                NSLog(@"metadata is not equal for artwork");
                return NO;
            }
        } else {
            NSString* thisValue = [self stringForKey:key];
            NSString* otherValue = [other stringForKey:key];
            
            if (![thisValue isEqualToString:otherValue]) {
                NSLog(@"metadata is not equal for key %@ (\"%@\" != \"%@\")", key, thisValue, otherValue);
                return NO;
            }
        }
    }
    
    return YES;
}

- (BOOL)isEqualToMediaMetaData:(MediaMetaData*)other
{
    MediaMetaDataFileFormatType thisType = [MediaMetaData fileTypeWithURL:self.location
                                                                    error:nil];
    MediaMetaDataFileFormatType otherType = [MediaMetaData fileTypeWithURL:other.location
                                                                     error:nil];
    if (thisType != otherType) {
        NSLog(@"file types differ");
        return NO;
    }
    
    NSArray<NSString*>* supportedKeys = nil;
    
    if (thisType == MediaMetaDataFileFormatTypeMP3) {
        supportedKeys = [MediaMetaData mp3SupportedMediaDataKeys];
    } else if (thisType == MediaMetaDataFileFormatTypeMP4) {
        NSAssert(NO, @"not yet implemented");
    }
    
    return [self isEqualToMediaMetaData:other forKeys:supportedKeys];
}

- (void)updateWithKey:(NSString*)key string:(NSString*)string
{
    // Rather involved way to retrieve the Class from a member (that may be set to nil).
    objc_property_t property = class_getProperty(self.class, [key cStringUsingEncoding:NSStringEncodingConversionAllowLossy]);
    const char * const attrString = property_getAttributes(property);
    const char *typeString = attrString + 1;
    const char *next = NSGetSizeAndAlignment(typeString, NULL, NULL);
    const char *className = typeString + 2;
    next = strchr(className, '"');
    size_t classNameLength = next - className;
    char trimmedName[classNameLength + 1];
    strncpy(trimmedName, className, classNameLength);
    trimmedName[classNameLength] = '\0';
    Class objectClass = objc_getClass(trimmedName);
    
    if (objectClass == [NSString class]) {
        [self setValue:string forKey:key];
        NSLog(@"updated %@ with string \"%@\"", key, string);
        return;
    }
    
    if (objectClass == [NSNumber class]) {
        NSInteger integerValue = [string integerValue];
        NSNumber* numberValue = [NSNumber numberWithInteger:integerValue];
        [self setValue:numberValue forKey:key];
        NSLog(@"updated %@ with number \"%@\"", key, numberValue);
        return;
    }
    
    NSAssert(NO, @"should never get here");
}

// FIXME: This is BS as it does the comparison on the wrong level -- should go up.
- (BOOL)exportMP3WithError:(NSError**)error
{
    MediaMetaData* metaFromFile = [MediaMetaData mediaMetaDataFromMP3FileWithURL:self.location error:error];
    NSArray<NSString*>* mp3SupportedKeys = [MediaMetaData mp3SupportedMediaDataKeys];
    
    BOOL ret = YES;
    
    if (![self isEqualToMediaMetaData:metaFromFile forKeys:mp3SupportedKeys]) {
        ret = [self writeToMP3FileWithError:error] == 0;
    }
    
    return ret;
}

- (BOOL)exportMP4WithError:(NSError**)error
{
    NSString* fileExtension = [self.location pathExtension];
    NSString* fileName = [[self.location URLByDeletingPathExtension] lastPathComponent];
    
    AVURLAsset* asset = [AVURLAsset assetWithURL:self.location];
    AVAssetExportSession* session = [AVAssetExportSession exportSessionWithAsset:asset
                                                                      presetName:AVAssetExportPresetPassthrough];
    
    
    NSString* outputFolder = @"/tmp";
    NSString* outputFile = [NSString stringWithFormat:@"%@/%@.%@", outputFolder, fileName, fileExtension];
    
    session.outputURL = [NSURL fileURLWithPath:outputFile];
    session.outputFileType = AVFileTypeAppleM4A;
    
    [session exportAsynchronouslyWithCompletionHandler:^(){
        NSLog(@"MP4 export session completed");
    }];
    
    return YES;
}

- (BOOL)writeToFileWithError:(NSError**)error
{
    if (self.location == nil) {
        NSString* description = @"Cannot sync item back as it lacks a location";
        if (error) {
            NSDictionary* userInfo = @{
                NSLocalizedDescriptionKey: description,
            };
            *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier]
                                         code:-1
                                     userInfo:userInfo];
        }
        NSLog(@"error: %@", description);
        
        return NO;
    }
    
    MediaMetaDataFileFormatType type = [MediaMetaData fileTypeWithURL:self.location error:error];
    
    if (type == MediaMetaDataFileFormatTypeMP3) {
        return [self exportMP3WithError:error];
    }
    if (type == MediaMetaDataFileFormatTypeMP4) {
        return [self exportMP4WithError:error];
    }
    
    NSString* description = [NSString stringWithFormat:@"Unsupport filetype for modifying metadata"];
    if (error) {
        NSDictionary* userInfo = @{
            NSLocalizedDescriptionKey: description,
        };
        *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier]
                                     code:-1
                                 userInfo:userInfo];
    }
    NSLog(@"error: %@", description);
    
    return NO;
}

@end
