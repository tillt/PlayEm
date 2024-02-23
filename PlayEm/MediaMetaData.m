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

#include "tag_c/tag_c.h"

///
/// MediaMetaData is lazily holding metadata for library entries to allow for extending iTunes provided data.
/// iTunes provided data are held in a shadow item until data is requested and thus copied in. iTunes metadata
/// is asynchronously requested through ITLibMediaItem on demand.
///

@implementation MediaMetaData

+ (MediaMetaData*)mediaMetaDataWithURL:(NSURL*)url error:(NSError**)error
{
    AVAsset* asset = [AVURLAsset URLAssetWithURL:url options:nil];
    NSLog(@"%@", asset);
    return [MediaMetaData mediaMetaDataWithURL:url asset:asset error:error];
}

+ (MediaMetaData*)mediaMetaDataWithURL:(NSURL*)url asset:(AVAsset *)asset error:(NSError**)error
{
    MediaMetaData* meta = [[MediaMetaData alloc] init];

    meta.location = url;

    for (NSString* format in [asset availableMetadataFormats]) {
        for (AVMetadataItem* item in [asset metadataForFormat:format]) {
            NSLog(@"%@ (%@): %@", [item commonKey], [item keyString], [item value]);
            if ([item commonKey] == nil) {
                if ([[item keyString] isEqualToString:@"TYER"] || [[item keyString] isEqualToString:@"@day"]  || [[item keyString] isEqualToString:@"TDRL"] ) {
                    meta.year = [NSNumber numberWithInt:[(NSString*)[item value] intValue]];
                } else if ([[item keyString] isEqualToString:@"@gen"]) {
                    meta.genre = (NSString*)[item value];
                } else {
                    continue;
                }
            }
            if ([[item commonKey] isEqualToString:@"title"]) {
                meta.title = (NSString*)[item value];
            } else if ([[item commonKey] isEqualToString:@"artist"]) {
                meta.artist = (NSString*)[item value];
            } else if ([[item commonKey] isEqualToString:@"albumName"]) {
                meta.album = (NSString*)[item value];
            } else if ([[item commonKey] isEqualToString:@"type"]) {
                meta.genre = (NSString*)[item value];
            } else if ([[item commonKey] isEqualToString:@"artwork"]) {
                if (item.dataValue != nil) {
                    NSLog(@"item.dataValue artwork");
                    meta.artwork = [[NSImage alloc] initWithData:item.dataValue];
                } else if (item.value != nil) {
                    NSLog(@"item.value artwork");
                    meta.artwork = [[NSImage alloc] initWithData:(id)item.value];
                } else {
                    NSLog(@"unknown artwork");
                }
            } else {
                NSLog(@"questionable metadata: %@ (%@): %@", [item commonKey], [item keyString], [item value]);
            }
        }
    }
    return meta;
}

+ (NSDictionary<NSString*, NSDictionary*>*)mediaMetaKeyMap
{
    return @{
                @"added": @{},
                @"album": @{
                    @"mp3": @{
                        @"key": @"ALBUM",
                        @"type": @"string",
                    },
                },
                @"albumArtist": @{
                    @"mp3": @{
                        @"key": @"ALBUMARTIST",
                        @"type": @"string",
                    },
                },
                @"artist": @{
                    @"mp3": @{
                        @"key": @"ARTIST",
                        @"type": @"string",
                    },
                },
                @"artwork": @{
                    @"mp3": @{
                        @"key": @"PICTURE",
                        @"type": @"image",
                    },
                },
                @"comment": @{
                    @"mp3": @{
                        @"key": @"COMMENTS",
                        @"type": @"string",
                    },
                },
                @"composer": @{
                    @"mp3": @{
                        @"key": @"COMPOSER",
                        @"type": @"string",
                    },
                },
                @"label": @{
                    @"mp3": @{
                        @"key": @"LABEL",
                        @"type": @"string",
                    },
                },
                @"disk": @{
                    @"mp3": @{
                        @"key": @"DISCNUMBER",
                        @"type": @"ofNumber",
                        @"mediaKey2": @"disks",
                    },
                },
                @"disks": @{},
                @"duration": @{
                    @"mp3": @{
                        @"key": @"LENGTH",
                        @"type": @"string",
                    },
                },
                @"genre": @{
                    @"mp3": @{
                        @"key": @"GENRE",
                        @"type": @"string",
                    },
                },
                @"key": @{
                    @"mp3": @{
                        @"key": @"INITIALKEY",
                        @"type": @"string",
                    },
                },
                @"location": @{},
                @"locationType": @{
                },
                @"tempo": @{
                    @"mp3": @{
                        @"key": @"BPM",
                        @"type": @"string",
                    },
                },
                @"title": @{
                    @"mp3": @{
                        @"key": @"TITLE",
                        @"type": @"string",
                    },
                },
                @"track": @{
                    @"mp3": @{
                        @"key": @"TRACKNUMBER",
                        @"type": @"ofNumber",
                        @"mediaKey2": @"tracks",
                    },
                },
                @"tracks": @{},
                @"year": @{
                    @"mp3": @{
                        @"key": @"DATE",
                        @"type": @"string",
                    },
                },
            };
}

+ (NSArray<NSString*>*)mediaMetaKeys
{
    return [[MediaMetaData mediaMetaKeyMap] allKeys];
}

+ (NSArray<NSString*>*)mp3SupportedKeys
{
    NSDictionary<NSString*, NSDictionary*>* mediaMetaKeyMap = [MediaMetaData mediaMetaKeyMap];
    NSMutableArray<NSString*>* supportedKeys = [NSMutableArray array];
    for (NSString* key in [MediaMetaData mediaMetaKeys]) {
        if ([mediaMetaKeyMap[key] objectForKey:@"mp3"]) {
            [supportedKeys addObject:key];
        }
    }
    return supportedKeys;
}

+ (NSDictionary<NSString*, NSDictionary<NSString*, NSString*>*>*)mp3TagMap
{
    NSDictionary<NSString*, NSDictionary*>* mediaMetaKeyMap = [MediaMetaData mediaMetaKeyMap];
    
    NSMutableDictionary<NSString*, NSDictionary<NSString*, NSString*>*>* tagMap = [NSMutableDictionary dictionary];
    
    for (NSString* mediaDataKey in [mediaMetaKeyMap allKeys]) {
        if ([mediaMetaKeyMap[mediaDataKey] objectForKey:@"mp3"] == nil) {
            continue;
        }

        NSString* mp3Key = mediaMetaKeyMap[mediaDataKey][@"mp3"][@"key"];
        NSString* type = mediaMetaKeyMap[mediaDataKey][@"mp3"][@"type"];

        NSMutableDictionary* mediaDataDictionary = [NSMutableDictionary dictionary];
        mediaDataDictionary[@"key"] = mediaDataKey;
        mediaDataDictionary[@"type"] = type;
        if ([type isEqualToString:@"ofNumber"]) {
            mediaDataDictionary[@"key2"] = mediaMetaKeyMap[mediaDataKey][@"mp3"][@"mediaKey2"];
        }
        
        tagMap[mp3Key] = mediaDataDictionary;
    }

    return tagMap;
}

- (NSString* _Nullable)title
{
    if (_shadow == nil) {
        return _title;
    }
    
    if (_title == nil) {
        _title = _shadow.title;
    }

    return _title;
}

- (NSString* _Nullable)artist
{
    if (_shadow == nil) {
        return _artist;
    }
    
    if (_artist == nil) {
        _artist = _shadow.artist.name;
    }

    return _artist;
}

- (NSString* _Nullable)album
{
    if (_shadow == nil) {
        return _album;
    }
    
    if (_album == nil) {
        _album = _shadow.album.title;
    }

    return _album;
}

- (NSString* _Nullable)albumArtist
{
    if (_shadow == nil) {
        return _albumArtist;
    }
    
    if (_albumArtist == nil) {
        _albumArtist = _shadow.album.albumArtist;
    }

    return _albumArtist;
}

- (NSString* _Nullable)genre
{
    if (_shadow == nil) {
        return _genre;
    }
    
    if (_genre == nil) {
        _genre = _shadow.genre;
    }

    return _genre;
}

- (NSString* _Nullable)composer
{
    if (_shadow == nil) {
        return _composer;
    }
    
    if (_composer == nil) {
        _composer = _shadow.composer;
    }

    return _composer;
}

- (NSString* _Nullable)comment
{
    if (_shadow == nil) {
        return _comment;
    }
    
    if (_comment == nil) {
        _comment = _shadow.comments;
    }

    return _comment;
}

- (NSNumber*)tempo
{
    if (_shadow == nil) {
        return _tempo;
    }
    
    if (_tempo == 0) {
        _tempo = [NSNumber numberWithUnsignedInteger:_shadow.beatsPerMinute];
    }

    return _tempo;
}

- (NSNumber*)year
{
    if (_shadow == nil) {
        return _year;
    }
    
    if (_year == 0) {
        _year = [NSNumber numberWithUnsignedInteger:_shadow.year];
    }

    return _year;
}

- (NSNumber*)track
{
    if (_shadow == nil) {
        return _track;
    }
    
    if (_track == 0) {
        _track = [NSNumber numberWithUnsignedInteger:_shadow.trackNumber];
    }

    return _track;
}

- (NSURL* _Nullable)location
{
    if (_shadow == nil) {
        return _location;
    }
    
    if (_location == 0) {
        _location = _shadow.location;
        _locationType = [NSNumber numberWithUnsignedInteger:_shadow.locationType];
    }

    return _location;
}

- (NSNumber*)locationType
{
    if (_shadow == nil) {
        return _locationType;
    }
    
    if (_locationType == 0) {
        _locationType = [NSNumber numberWithUnsignedInteger:_shadow.locationType];
    }

    return _locationType;
}

- (NSNumber*)duration
{
    if (_shadow == nil) {
        return _duration;
    }
    
    if (_duration == 0) {
        _duration = [NSNumber numberWithFloat:_shadow.totalTime];
    }

    return _duration;
}

- (NSImage* _Nullable)artwork
{
    if (_shadow == nil) {
        return _artwork;
    }
    
    if (_artwork == nil) {
        if (_shadow.hasArtworkAvailable) {
            _artwork = _shadow.artwork.image;
        } else {
            _artwork = [NSImage imageNamed:@"UnknownSong"];
        }
    }

    return _artwork;
}

- (NSDate* _Nullable)added
{
    if (_shadow == nil) {
        return _added;
    }
    
    if (_added == nil) {
        _added = _shadow.addedDate;
    }

    return _added;
}

+ (MediaMetaData*)mediaMetaDataWithITLibMediaItem:(ITLibMediaItem*)item error:(NSError**)error
{
    MediaMetaData* meta = [[MediaMetaData alloc] init];
    meta.shadow = item;
    meta.key = @"";
    return meta;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"Title: %@ -- Album: %@ -- Artist: %@ -- Location: %@", 
            self.title, self.album, self.artist, self.location];
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

+ (MediaMetaData*)metaFromMP3FileWithURL:(NSURL*)url error:(NSError**)error
{
    NSString* path = [url path];
    
    typedef BOOL (^TagLibParseBlock)(NSDictionary*, char*, char*);
    
    TagLib_File* file = taglib_file_new([path cStringUsingEncoding:NSStringEncodingConversionAllowLossy]);
    if (file == NULL) {
        NSString* description = @"Cannot load file using tagLib";
        if (error) {
            NSDictionary* userInfo = @{
                NSLocalizedDescriptionKey : description,
            };
            *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier]
                                         code:-1
                                     userInfo:userInfo];
        }
        NSLog(@"error: %@", description);

        return nil;
    }

    __block MediaMetaData* meta = [[MediaMetaData alloc] init];
    
    TagLibParseBlock parse = ^ BOOL (NSDictionary* tagMaps, char* tagLibKey, char* tagLibValues){
        NSString* key = [NSString stringWithCString:tagLibKey 
                                           encoding:NSStringEncodingConversionAllowLossy];
        NSString* values = [NSString stringWithCString:tagLibValues 
                                              encoding:NSStringEncodingConversionAllowLossy];
        
        NSDictionary* map = tagMaps[key];
        if (map == nil) {
            NSLog(@"skipping key: %@ with value(s) \"%@\"", key, values);
            return NO;
        }

        NSString* type = map[@"type"];

        if ([type isEqualToString:@"string"]) {
            [meta updateWithKey:map[@"key"] string:values];
            return YES;
        }

        if ([type isEqualToString:@"ofNumber"]) {
            if (![values containsString:@"/"]) {
                [meta updateWithKey:map[@"key"] string:values];
                return YES;
            }
            NSArray<NSString*>* components = [values componentsSeparatedByString:@"/"];
            [meta updateWithKey:map[@"key"] string:components[0]];
            if ([components count] > 1) {
                [meta updateWithKey:map[@"key2"] string:components[1]];
            }
            return YES;
        }
        
        if ([type isEqualToString:@"date"]) {
            if (![values containsString:@"-"]) {
                [meta updateWithKey:map[@"key"] string:values];
                return YES;
            }
            NSArray<NSString*>* components = [values componentsSeparatedByString:@"-"];
            [meta updateWithKey:map[@"key"] string:components[0]];
            return YES;
        }

        if ([type isEqualToString:@"image"]) {
            NSLog(@"ignoring complex image type in simple parser");
            return YES;
        }

        NSAssert(NO, @"unknown type %@", type);

        return NO;
    };
    
    NSDictionary* tagMap = [MediaMetaData mp3TagMap];

    char **propertiesMap = propertiesMap = taglib_property_keys(file);
    if(propertiesMap != NULL) {
        char **keyPtr = propertiesMap;
        keyPtr = propertiesMap;

        while(*keyPtr) {
            char **valPtr;
            char **propertyValues = valPtr = taglib_property_get(file, *keyPtr);
            while(valPtr && *valPtr) {
                parse(tagMap, *keyPtr, *valPtr);
                ++valPtr;
            };
            taglib_property_free(propertyValues);
            ++keyPtr;
        }
        taglib_property_free(propertiesMap);
    }
    
    char **complexKeys = taglib_complex_property_keys(file);
    if(complexKeys != NULL) {
        NSLog(@"-- TAG (complex properties) --");

        char **keyPtr = complexKeys;
        while(*keyPtr) {
            TagLib_Complex_Property_Attribute*** props =
            taglib_complex_property_get(file, *keyPtr);
            if(props != NULL) {
                TagLib_Complex_Property_Attribute*** propPtr = props;
                while(*propPtr) {
                    TagLib_Complex_Property_Attribute** attrPtr = *propPtr;
                    // PICTURE
                    printf("%s:\n", *keyPtr);
                    while(*attrPtr) {
                        TagLib_Complex_Property_Attribute *attr = *attrPtr;
                        TagLib_Variant_Type type = attr->value.type;
                        printf("  %-11s - ", attr->key);
                        switch(type) {
                            case TagLib_Variant_Void:
                                printf("null\n");
                                break;
                            case TagLib_Variant_Bool:
                                printf("%s\n", attr->value.value.boolValue ? "true" : "false");
                                break;
                            case TagLib_Variant_Int:
                                printf("%d\n", attr->value.value.intValue);
                                break;
                            case TagLib_Variant_UInt:
                                printf("%u\n", attr->value.value.uIntValue);
                                break;
                            case TagLib_Variant_LongLong:
                                printf("%lld\n", attr->value.value.longLongValue);
                                break;
                            case TagLib_Variant_ULongLong:
                                printf("%llu\n", attr->value.value.uLongLongValue);
                                break;
                            case TagLib_Variant_Double:
                                printf("%f\n", attr->value.value.doubleValue);
                                break;
                            case TagLib_Variant_String:
                                printf("\"%s\"\n", attr->value.value.stringValue);
                                break;
                            case TagLib_Variant_StringList:
                                if(attr->value.value.stringListValue) {
                                    char **strs = attr->value.value.stringListValue;
                                    char **s = strs;
                                    while(*s) {
                                        if(s != strs) {
                                            printf(" ");
                                        }
                                        printf("%s", *s++);
                                    }
                                }
                                printf("\n");
                                break;
                            case TagLib_Variant_ByteVector:
                                printf("(%u bytes)\n", attr->value.size);
                                break;
                        }
                        ++attrPtr;
                    };
                    ++propPtr;
                };
                taglib_complex_property_free(props);
            }
            ++keyPtr;
        };
        taglib_complex_property_free_keys(complexKeys);
    }
    
    taglib_tag_free_strings();
    taglib_file_free(file);
    
    return meta;
}

- (BOOL)metaToMP3FileWithError:(NSError**)error
{
    NSString* path = [self.location path];
    
    TagLib_File* file = taglib_file_new([path cStringUsingEncoding:NSStringEncodingConversionAllowLossy]);

    if (file == NULL) {
        NSString* description = @"Cannot open file using tagLib";
        if (error) {
            NSDictionary* userInfo = @{
                NSLocalizedDescriptionKey : description,
            };
            *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier]
                                         code:-1
                                     userInfo:userInfo];
        }
        NSLog(@"error: %@", description);

        return NO;
    }
    
    NSDictionary* mediaMetaKeyMap = [MediaMetaData mediaMetaKeyMap];
    NSArray* mp3SupportedKeys = [MediaMetaData mp3SupportedKeys];

    for (NSString* mediaKey in mp3SupportedKeys) {
        NSString* type = mediaMetaKeyMap[mediaKey][@"mp3"][@"type"];
        NSString* mp3Key = mediaMetaKeyMap[mediaKey][@"mp3"][@"key"];

        if ([type isEqualToString:@"image"]) {
            NSLog(@"setting image data not yet supported");
        } else {
            NSString* value = [self stringForKey:mediaKey];

            if ([type isEqualToString:@"ofNumber"]) {
                NSMutableArray* components = [NSMutableArray array];
                [components addObject:value];

                NSString* secondKey = mediaMetaKeyMap[mediaKey][@"mp3"][@"mediaKey2"];
                NSString* value2 = [self stringForKey:secondKey];
                if ([value2 length] > 0) {
                    [components addObject:value2];
                }
                value = [components componentsJoinedByString:@"/"];
            }
            // NOTE: We are possible reducing the accuracy of a DATE as we will only store the year
            // while the original may have had day and month included.
            
            NSLog(@"setting ID3: \"%@\" = \"%@\"", mp3Key, value);
            taglib_property_set(file,
                                [mp3Key cStringUsingEncoding:NSStringEncodingConversionAllowLossy],
                                [value cStringUsingEncoding:NSStringEncodingConversionAllowLossy]);
        }
    }
    
    BOOL ret = YES;

    if (!taglib_file_save(file)) {
        NSString* description = @"Cannot store file using tagLib";
        if (error) {
            NSDictionary* userInfo = @{
                NSLocalizedDescriptionKey : description,
            };
            *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier]
                                         code:-1
                                     userInfo:userInfo];
        }
        NSLog(@"error: %@", description);
        ret = NO;
    }

    taglib_tag_free_strings();
    taglib_file_free(file);

    return ret;
}

- (BOOL)isEqual:(MediaMetaData*)other forKeys:(NSArray<NSString*>*)keys
{
    if (other == nil) {
        return NO;
    }
    
    for (NSString* key in keys) {
        NSString* thisValue = [self stringForKey:key];
        NSString* otherValue = [other stringForKey:key];

        if (![thisValue isEqualToString:otherValue]) {
            NSLog(@"metadata is not equal for key %@ (\"%@\" != \"%@\")", key, thisValue, otherValue);
            return NO;
        }
    }
    
    return YES;
}

- (BOOL)exportMP3WithError:(NSError**)error
{
    MediaMetaData* metaFromFile = [MediaMetaData metaFromMP3FileWithURL:self.location error:error];
    NSArray<NSString*>* mp3SupportedKeys = [MediaMetaData mp3SupportedKeys];

    BOOL ret = YES;

    if (![self isEqual:metaFromFile forKeys:mp3SupportedKeys]) {
        ret = [self metaToMP3FileWithError:error];
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

- (BOOL)syncToFileWithError:(NSError**)error
{
    if (self.location == nil) {
        NSString* description = @"Cannot sync item back as it lacks a location";
        if (error) {
            NSDictionary* userInfo = @{
                NSLocalizedDescriptionKey : description,
            };
            *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier]
                                         code:-1
                                     userInfo:userInfo];
        }
        NSLog(@"error: %@", description);

        return NO;
    }
    
    NSString* fileExtension = [self.location pathExtension];

    if ([fileExtension isEqualToString:@"mp4"] || [fileExtension isEqualToString:@"m4a"]) {
        return [self exportMP4WithError:error];
    }

    if ([fileExtension isEqualToString:@"mp3"]) {
        return [self exportMP3WithError:error];
    }

    NSString* description = [NSString stringWithFormat:@"Unsupport filetype (%@) for modifying metadata", fileExtension];
    if (error) {
        NSDictionary* userInfo = @{
            NSLocalizedDescriptionKey : description,
        };
        *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier]
                                     code:-1
                                 userInfo:userInfo];
    }
    NSLog(@"error: %@", description);

    return NO;
}

@end
