//
//  MediaMetaData_TagLib.m
//  PlayEm
//
//  Created by Till Toenshoff on 24.02.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#include "tag_c/tag_c.h"

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

#import "MediaMetaData.h"
#import "MediaMetaData+TagLib.h"

#import "NSURL+WithoutParameters.h"

@implementation MediaMetaData(TagLib)

+ (void)setupTaglib
{
    taglib_set_strings_unicode(TRUE);
}

+ (NSDictionary<NSString*, NSDictionary<NSString*, NSString*>*>*)mp3TagMap
{
    NSDictionary<NSString*, NSDictionary*>* mediaMetaKeyMap = [MediaMetaData mediaMetaKeyMap];
    
    NSMutableDictionary<NSString*, NSMutableDictionary<NSString*, id>*>* mp3TagMap = [NSMutableDictionary dictionary];
    
    for (NSString* mediaDataKey in [mediaMetaKeyMap allKeys]) {
        // Skip anything that isnt supported by MP3 / ID3.
        if ([mediaMetaKeyMap[mediaDataKey] objectForKey:kMediaMetaDataMapKeyMP3] == nil) {
            continue;
        }

        NSString* mp3Key = mediaMetaKeyMap[mediaDataKey][kMediaMetaDataMapKeyMP3][kMediaMetaDataMapKey];
        NSString* type = kMediaMetaDataMapTypeString;
        NSString* t = mediaMetaKeyMap[mediaDataKey][kMediaMetaDataMapKeyMP3][kMediaMetaDataMapKeyType];
        if (t != nil) {
            type = t;
        }

        NSMutableDictionary* mp3Dictionary = mp3TagMap[mp3Key];
        if (mp3TagMap[mp3Key] == nil) {
            mp3Dictionary = [NSMutableDictionary dictionary];
        }

        mp3Dictionary[kMediaMetaDataMapKeyType] = type;
        
        NSMutableArray* mediaKeys = mp3Dictionary[kMediaMetaDataMapKeys];
        if (mediaKeys == nil) {
            mediaKeys = [NSMutableArray array];
            if ([type isEqualToString:kMediaMetaDataMapTypeTuple]) {
                [mediaKeys addObjectsFromArray:@[@"", @""]];
            }
        }
        
        NSNumber* position = mediaMetaKeyMap[mediaDataKey][kMediaMetaDataMapKeyMP3][kMediaMetaDataMapOrder];
        if (position != nil) {
            [mediaKeys replaceObjectAtIndex:[position intValue] withObject:mediaDataKey];
        } else {
            [mediaKeys addObject:mediaDataKey];
        }

        mp3Dictionary[kMediaMetaDataMapKeys] = mediaKeys;

        mp3TagMap[mp3Key] = mp3Dictionary;
    }

    return mp3TagMap;
}

+ (NSDictionary<NSString*, NSDictionary<NSString*, NSString*>*>*)mp4TagMap
{
    NSDictionary<NSString*, NSDictionary*>* mediaMetaKeyMap = [MediaMetaData mediaMetaKeyMap];
    
    NSMutableDictionary<NSString*, NSMutableDictionary<NSString*, id>*>* mp4TagMap = [NSMutableDictionary dictionary];
    
    for (NSString* mediaDataKey in [mediaMetaKeyMap allKeys]) {
        // Skip anything that isnt supported by MP4.
        if ([mediaMetaKeyMap[mediaDataKey] objectForKey:kMediaMetaDataMapKeyMP4] == nil) {
            continue;
        }

        NSString* mp4Key = mediaMetaKeyMap[mediaDataKey][kMediaMetaDataMapKeyMP4][kMediaMetaDataMapKey];
        NSString* type = kMediaMetaDataMapTypeString;
        NSString* t = [mediaMetaKeyMap[mediaDataKey][kMediaMetaDataMapKeyMP4] objectForKey:kMediaMetaDataMapKeyType];
        if (t != nil) {
            type = t;
        }

        NSMutableDictionary* mp4Dictionary = mp4TagMap[mp4Key];
        if (mp4TagMap[mp4Key] == nil) {
            mp4Dictionary = [NSMutableDictionary dictionary];
        }

        mp4Dictionary[kMediaMetaDataMapKeyType] = type;
        
        NSMutableArray* mediaKeys = mp4Dictionary[kMediaMetaDataMapKeys];
        if (mediaKeys == nil) {
            mediaKeys = [NSMutableArray array];
            if ([type isEqualToString:kMediaMetaDataMapTypeTuple]) {
                [mediaKeys addObjectsFromArray:@[@"", @""]];
            }
        }
        
        NSNumber* position = mediaMetaKeyMap[mediaDataKey][kMediaMetaDataMapKeyMP4][kMediaMetaDataMapOrder];
        if (position != nil) {
            [mediaKeys replaceObjectAtIndex:[position intValue] withObject:mediaDataKey];
        } else {
            [mediaKeys addObject:mediaDataKey];
        }

        mp4Dictionary[kMediaMetaDataMapKeys] = mediaKeys;

        mp4TagMap[mp4Key] = mp4Dictionary;
    }

    return mp4TagMap;
}

+ (MediaMetaData*)mediaMetaDataFromMP3FileWithURL:(NSURL*)url error:(NSError**)error
{
    MediaMetaData* meta = [[MediaMetaData alloc] init];
    meta.location = [[url filePathURL] URLWithoutParameters];
    meta.locationType = [NSNumber numberWithUnsignedInteger:MediaMetaDataLocationTypeFile];

    if ([meta readFromMP3FileWithError:error] != 0) {
        return nil;
    }
    
    return meta;
}

- (int)readFromMP3FileWithError:(NSError**)error
{
    NSString* path = [self.location path];
    
    const char* _Nullable fileName = [path cStringUsingEncoding:NSUTF8StringEncoding];
    NSAssert(fileName != NULL, @"failed to convert filename");
    
    TagLib_File* file = taglib_file_new(fileName);
    if (file == NULL) {
        NSString* description = @"Cannot load file using tagLib";
        if (error) {
            NSDictionary* userInfo = @{
                NSLocalizedDescriptionKey: description,
            };
            *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier]
                                         code:-1
                                     userInfo:userInfo];
        }
        NSLog(@"error: %@", description);
        
        return -1;
    }
    
    TagLib_Tag* tag = taglib_file_tag(file);

    if(tag != NULL) {
        // Process the taglib standard stuff - a ID3 v1 data subset by its selection.
        [self updateWithKey:@"title" string:[NSString stringWithCString:taglib_tag_title(tag)
                                                               encoding:NSUTF8StringEncoding]];
        [self updateWithKey:@"artist" string:[NSString stringWithCString:taglib_tag_artist(tag)
                                                                encoding:NSUTF8StringEncoding]];
        [self updateWithKey:@"album" string:[NSString stringWithCString:taglib_tag_album(tag)
                                                               encoding:NSUTF8StringEncoding]];
        [self updateWithKey:@"year" string:[[NSNumber numberWithUnsignedInt:taglib_tag_year(tag)] stringValue]];
        [self updateWithKey:@"comment" string:[NSString stringWithCString:taglib_tag_comment(tag)
                                                                 encoding:NSUTF8StringEncoding]];
        [self updateWithKey:@"track" string:[[NSNumber numberWithUnsignedInt:taglib_tag_track(tag)] stringValue]];
        [self updateWithKey:@"genre" string:[NSString stringWithCString:taglib_tag_genre(tag)
                                                               encoding:NSUTF8StringEncoding]];
    }
    
    NSDictionary* mp3TagMap = [MediaMetaData mp3TagMap];

    // Process dates, tuples and non standard string values.
    char** propertiesMap = taglib_property_keys(file);
    if (propertiesMap != NULL) {
        char** keyPtr = propertiesMap;
        keyPtr = propertiesMap;
        
        while (*keyPtr) {
            char** propertyValues = taglib_property_get(file, *keyPtr);
            char** valPtr = propertyValues;
            
            while (valPtr && *valPtr) {
                NSString* key = [NSString stringWithCString:*keyPtr
                                                   encoding:NSUTF8StringEncoding];
                NSString* values = [NSString stringWithCString:*valPtr
                                                      encoding:NSUTF8StringEncoding];
                NSDictionary* map = mp3TagMap[key];
                if (map != nil) {
                    NSString* type = map[kMediaMetaDataMapKeyType];
                    
                    if ([type isEqualToString:kMediaMetaDataMapTypeNumber]) {
                        [self updateWithKey:map[kMediaMetaDataMapKeys][0] string:values];
                    } else if ([type isEqualToString:kMediaMetaDataMapTypeString]) {
                        [self updateWithKey:map[kMediaMetaDataMapKeys][0] string:values];
                    } else if ([type isEqualToString:kMediaMetaDataMapTypeTuple]) {
                        NSArray<NSString*>* components = [values componentsSeparatedByString:@"/"];
                        [self updateWithKey:map[kMediaMetaDataMapKeys][0] string:components[0]];
                        if ([components count] > 1) {
                            [self updateWithKey:map[kMediaMetaDataMapKeys][1] string:components[1]];
                        }
                    } else if ([type isEqualToString:kMediaMetaDataMapTypeDate]) {
                        if (![values containsString:@"-"]) {
                            [self updateWithKey:map[kMediaMetaDataMapKeys][0] string:values];
                        } else {
                            NSArray<NSString*>* components = [values componentsSeparatedByString:@"-"];
                            [self updateWithKey:map[kMediaMetaDataMapKeys][0] string:components[0]];
                        }
                    } else if ([type isEqualToString:kMediaMetaDataMapTypeImage]) {
                        NSLog(@"skipping complex image type in simple parser");
                    } else {
                        NSAssert(NO, @"unknown type %@", type);
                    }
                }
                ++valPtr;
            };
            taglib_property_free(propertyValues);
            ++keyPtr;
        };
        taglib_property_free(propertiesMap);
    }
    
    // Process artwork.
    char** complexKeys = taglib_complex_property_keys(file);
    if (complexKeys != NULL) {
        char** keyPtr = complexKeys;

        while (*keyPtr) {
            TagLib_Complex_Property_Attribute*** props = taglib_complex_property_get(file, *keyPtr);
            if (props != NULL) {
                TagLib_Complex_Property_Attribute*** propPtr = props;

                while (*propPtr) {
                    TagLib_Complex_Property_Attribute** attrPtr = *propPtr;
                    NSString* key = [NSString stringWithCString:*keyPtr
                                                       encoding:NSUTF8StringEncoding];
                    // NOTE: We only use the first PICTURE gathered.
                    if ([key isEqualToString:@"PICTURE"] && self.artwork == nil) {

                        while (*attrPtr) {
                            TagLib_Complex_Property_Attribute* attr = *attrPtr;
                            TagLib_Variant_Type type = attr->value.type;
                            if (type == TagLib_Variant_ByteVector) {
                                NSData* data = [NSData dataWithBytes:attr->value.value.byteVectorValue
                                                              length:attr->value.size];
                                NSLog(@"updated artwork with %ld bytes of image data", [data length]);
                                self.artwork = data;
                                ITLibArtworkFormat format = [MediaMetaData artworkFormatForData:data];
                                self.artworkFormat = [NSNumber numberWithInteger:format];

                            }
                            ++attrPtr;
                        };
                    }
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
    
    return 0;
}

// Note that we are avoiding using `BOOL` in the signature here as that gets defined as `int`
// by "taglib_c.h". Trouble is, Objective C typedefs BOOL to various types, depending on the
// platform and processor architecture. See
// https://www.jviotti.com/2024/01/05/is-objective-c-bool-a-boolean-type-it-depends.html
- (int)writeToTagLibFileWithError:(NSError**)error tagMap:(NSDictionary*)tagMap
{
    NSString* path = [self.location path];
    
    TagLib_File* file = taglib_file_new([path cStringUsingEncoding:NSUTF8StringEncoding]);
    
    if (file == NULL) {
        NSString* description = @"Cannot open file using tagLib";
        if (error) {
            NSDictionary* userInfo = @{
                NSLocalizedDescriptionKey: description,
            };
            *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier]
                                         code:-1
                                     userInfo:userInfo];
        }
        NSLog(@"error: %@", description);
        
        return -1;
    }

    for (NSString* key in [tagMap allKeys]) {
        // Lets not create records from data we dont need on the destination.
        NSString* mediaKey = tagMap[key][kMediaMetaDataMapKeys][0];

        NSString* type = tagMap[key][kMediaMetaDataMapKeyType];
        if ([type isEqualToString:kMediaMetaDataMapTypeImage]) {
            /*
             ITLibArtworkFormatNone = 0,
             ITLibArtworkFormatBitmap = 1,
             ITLibArtworkFormatJPEG = 2,
             ITLibArtworkFormatJPEG2000 = 3,
             ITLibArtworkFormatGIF = 4,
             ITLibArtworkFormatPNG = 5,
             ITLibArtworkFormatBMP = 6,
             ITLibArtworkFormatTIFF = 7,
             ITLibArtworkFormatPICT = 8
             */
            unsigned int imageFormat = [self.artworkFormat intValue];
            NSString* mimeType = [MediaMetaData mimeTypeForArtworkFormat:imageFormat];
            NSAssert(mimeType != nil, @"no mime type known for this picture format %d", imageFormat);
            const char* m = [mimeType cStringUsingEncoding:NSUTF8StringEncoding];
            TAGLIB_COMPLEX_PROPERTY_PICTURE(props,
                                            self.artwork.bytes,
                                            (unsigned int)self.artwork.length,
                                            "",
                                            m,
                                            "Front Cover");
            NSLog(@"setting complex tag: \"%@\" = %p", key, self.artwork);
            taglib_complex_property_set(file,
                                        [key cStringUsingEncoding:NSUTF8StringEncoding],
                                        props);
        } else {
            NSString* value = [self stringForKey:mediaKey];
            
            if ([type isEqualToString:kMediaMetaDataMapTypeTuple]) {
                NSMutableArray* components = [NSMutableArray array];
                [components addObject:value];
                
                mediaKey = tagMap[key][kMediaMetaDataMapKeys][1];
                value = [self stringForKey:mediaKey];
                if ([value length] > 0) {
                    [components addObject:value];
                }
                value = [components componentsJoinedByString:@"/"];
            }
            // NOTE: We are possible reducing the accuracy of a DATE as we will only store the year
            // while the original may have had day and month included.
            NSLog(@"setting tag: \"%@\" = \"%@\"", key, value);
            taglib_property_set(file,
                                [key cStringUsingEncoding:NSUTF8StringEncoding],
                                value.length > 0 ? [value cStringUsingEncoding:NSUTF8StringEncoding] : NULL);
        }
    }
    
    int ret = 0;
    
    if (!taglib_file_save(file)) {
        NSString* description = @"Cannot store file using tagLib";
        if (error) {
            NSDictionary* userInfo = @{
                NSLocalizedDescriptionKey: description,
            };
            *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier]
                                         code:-1
                                     userInfo:userInfo];
        }
        NSLog(@"error: %@", description);
        ret = -1;
    }
    
    taglib_tag_free_strings();
    taglib_file_free(file);
    
    return ret;
}

- (int)writeToMP3FileWithError:(NSError**)error
{
    NSDictionary* mp3TagMap = [MediaMetaData mp3TagMap];
    return [self writeToTagLibFileWithError:error tagMap:mp3TagMap];
}

- (int)writeToMP4FileWithError:(NSError**)error
{
    NSDictionary* mp3TagMap = [MediaMetaData mp3TagMap];
    return [self writeToTagLibFileWithError:error tagMap:mp3TagMap];
}
@end
