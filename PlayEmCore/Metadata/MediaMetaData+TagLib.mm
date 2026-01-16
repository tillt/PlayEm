//
//  MediaMetaData_TagLib.m
//  PlayEm
//
//  Created by Till Toenshoff on 24.02.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#include "mpegfile.h"
#include "id3v2tag.h"
#include "attachedpictureframe.h"
#include "apetag.h"
#include "apeitem.h"
#include "tpropertymap.h"
#include "tstringlist.h"
#include "tbytevector.h"
#include "tvariant.h"
#include "fileref.h"
#include "id3v2frame.h"
#include "id3v2header.h"
#include "id3v2framefactory.h"
#include "textidentificationframe.h"
#include "uniquefileidentifierframe.h"
#include "tag.h"

#import "MediaMetaData+TagLib.h"

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

#import "MediaMetaData.h"
#import "NSString+Sanitized.h"
#import "NSString+BeautifulPast.h"
#import "NSURL+WithoutParameters.h"

static NSString* cf_cleanUserText(NSString* s)
{
    if (s.length == 0) {
        return s;
    }

    NSMutableString* m = [s mutableCopy];
    NSCharacterSet* trimSet = [NSCharacterSet characterSetWithCharactersInString:@"\uFEFF\uFE00\uFE01\uFE0F\u00FF\r\n\t "];

    while (m.length > 0 && [trimSet characterIsMember:[m characterAtIndex:0]]) {
        [m deleteCharactersInRange:NSMakeRange(0, 1)];
    }
    while (m.length > 0 && [trimSet characterIsMember:[m characterAtIndex:m.length - 1]]) {
        [m deleteCharactersInRange:NSMakeRange(m.length - 1, 1)];
    }

    NSString* cleaned = [m sanitizedMetadataString];
    return cleaned;
}

static BOOL cf_isASCIIString(NSString* s)
{
    static NSCharacterSet* nonASCII = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        nonASCII = [[NSCharacterSet characterSetWithRange:NSMakeRange(0, 0x80)] invertedSet];
    });
    return ([s rangeOfCharacterFromSet:nonASCII].location == NSNotFound);
}

static NSString* cf_decodeUserText(const char* raw)
{
    if (raw == NULL) {
        return nil;
    }

    const unsigned char* bytes = (const unsigned char*) raw;
    size_t maxLen = 65536;
    NSString* result = nil;

    // Heuristic: attempt UTF-16 first by scanning until a 00 00 terminator.
    size_t utf16len = 0;
    while (utf16len + 1 < maxLen) {
        if (bytes[utf16len] == 0x00 && bytes[utf16len + 1] == 0x00) {
            utf16len += 2;
            break;
        }
        utf16len += 2;
    }
    if (utf16len >= 4) {
        NSData* data = [NSData dataWithBytes:bytes length:utf16len];
        result = [[NSString alloc] initWithData:data encoding:NSUTF16LittleEndianStringEncoding];
        if (!result) {
            result = [[NSString alloc] initWithData:data encoding:NSUTF16BigEndianStringEncoding];
        }
    }

    if (!result) {
        // Fallback to UTF-8/Latin-1 using a safe length.
        size_t utf8len = 0;
        while (utf8len < maxLen && raw[utf8len] != '\0') {
            utf8len++;
        }
        NSData* data = [NSData dataWithBytes:bytes length:utf8len];
        result = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!result) {
            result = [NSString stringWithCString:raw encoding:NSISOLatin1StringEncoding];
        }
    }

    if (result) {
        result = cf_cleanUserText(result);
        // Trim leading non-alphanumeric junk that sometimes prefixes TXXX values.
        NSCharacterSet* good = [NSCharacterSet alphanumericCharacterSet];
        while (result.length > 0 && ![good characterIsMember:[result characterAtIndex:0]]) {
            result = [result substringFromIndex:1];
        }
        // Treat any remaining non-ASCII text as invalid for these frames.
        BOOL hasNonASCII = !cf_isASCIIString(result);
        if (result.length == 0 || hasNonASCII || [result isLikelyMojibakeMetadata]) {
            result = nil;
        }
    }

    // Last resort: extract ASCII alphanumerics directly from raw bytes.
    if (!result) {
        NSMutableString* ascii = [NSMutableString string];
        for (size_t i = 0; i < maxLen && raw[i] != '\0'; i++) {
            unsigned char c = raw[i];
            if ((c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '#' || c == 'b') {
                [ascii appendFormat:@"%c", c];
            }
        }
        if (ascii.length > 0) {
            result = ascii;
        }
    }

    return result;
}

static TagLib::String cf_NSStringToTString(NSString* s)
{
    if (!s) {
        return TagLib::String();
    }
    NSData* data = [s dataUsingEncoding:NSUTF8StringEncoding];
    return TagLib::String((const char*) data.bytes, TagLib::String::UTF8);
}

static NSUInteger cf_synchsafeToSize(const unsigned char* bytes)
{
    return (bytes[0] << 21) | (bytes[1] << 14) | (bytes[2] << 7) | bytes[3];
}

// Raw ID3 parser for APIC/PIC frames to extract embedded artwork when TagLib fails.
static NSData* cf_extractArtworkFromRawID3(NSString* path)
{
    NSData* data = [NSData dataWithContentsOfFile:path];
    if (data.length < 10) {
        return nil;
    }
    const unsigned char* bytes = (const unsigned char*) data.bytes;
    if (memcmp(bytes, "ID3", 3) != 0) {
        return nil;
    }
    uint8_t version = bytes[3];
    BOOL v24 = (version >= 4);
    uint8_t flags = bytes[5];
    NSUInteger tagSize = cf_synchsafeToSize(bytes + 6) + 10;
    if (tagSize > data.length) {
        tagSize = data.length;
    }

    NSUInteger offset = 10;
    // Skip extended header if present.
    if (flags & 0x40) {
        if (offset + 4 <= tagSize) {
            if (v24) {
                NSUInteger extSize = cf_synchsafeToSize(bytes + offset);
                offset += extSize + 4;
            } else {
                NSUInteger extSize = (bytes[offset] << 24) | (bytes[offset + 1] << 16) | (bytes[offset + 2] << 8) | bytes[offset + 3];
                offset += extSize + 4;
            }
            if (offset > tagSize) return nil;
        }
    }

    while (offset + 10 <= tagSize) {
        const unsigned char* f = bytes + offset;
        if (f[0] == 0 && f[1] == 0 && f[2] == 0 && f[3] == 0) {
            break;
        }
        char frameId[5] = { (char)f[0], (char)f[1], (char)f[2], (char)f[3], 0 };
        NSUInteger frameSize = v24 ? cf_synchsafeToSize(f + 4)
                                   : (f[4] << 24 | f[5] << 16 | f[6] << 8 | f[7]);
        NSUInteger bodyStart = offset + 10;
        if (frameSize == 0 || bodyStart + frameSize > tagSize) {
            break;
        }
        const unsigned char* body = bytes + bodyStart;

        if (strcmp(frameId, "APIC") == 0 || strcmp(frameId, "PIC") == 0) {
            unsigned char enc = body[0];
            NSUInteger idx = 1;
            if (strcmp(frameId, "PIC") == 0) {
                idx += 3; // 3-byte image format
            } else {
                while (idx < frameSize && body[idx] != 0) { idx++; }
                if (idx < frameSize) { idx++; }
            }
            if (idx >= frameSize) { goto nextFrame; }
            idx++; // picture type
            if (idx >= frameSize) { goto nextFrame; }
            if (enc == 0 || enc == 3) {
                while (idx < frameSize && body[idx] != 0) { idx++; }
                if (idx < frameSize) { idx++; }
            } else {
                while (idx + 1 < frameSize) {
                    if (body[idx] == 0 && body[idx + 1] == 0) { idx += 2; break; }
                    idx += 2;
                }
            }
            if (idx >= frameSize) { goto nextFrame; }
            NSData* img = [NSData dataWithBytes:body + idx length:frameSize - idx];
            if (img.length > 0) {
                return img;
            }
        }

    nextFrame:
        offset = bodyStart + frameSize;
    }
    return nil;
}

// Directly parse the on-disk ID3v2 tag to recover the INITIALKEY frame.
// We go this crazy route as tagLib is unfortunately not allowing us to
// recover incorrectly marked UTF16LE TXXX fields.
//
// Assumption is this implementation is anything but stable against variations
// - doesnt really matter too much. It does cover a case I have seen A LOT
// in the wild. Tags incorrecly marked as UTF16 while being latin - some windows
// coder likely is to blame.
NSString* cf_extractKeyFromRawID3(NSString* path)
{
    NSData* data = [NSData dataWithContentsOfFile:path];
    if (data.length < 10) {
        return nil;
    }

    const unsigned char* bytes = (const unsigned char*) data.bytes;
    if (memcmp(bytes, "ID3", 3) != 0) {
        return nil;
    }

    uint8_t version = bytes[3];
    BOOL v24 = (version >= 4);
    NSUInteger tagSize = cf_synchsafeToSize(bytes + 6) + 10;  // header + body
    if (tagSize > data.length) {
        tagSize = data.length;
    }

    NSUInteger offset = 10;  // skip header
    while (offset + 10 <= tagSize) {
        const unsigned char* f = bytes + offset;
        if (f[0] == 0 && f[1] == 0 && f[2] == 0 && f[3] == 0) {
            break;  // padding reached
        }

        char frameId[5] = { (char)f[0], (char)f[1], (char)f[2], (char)f[3], 0 };
        NSUInteger frameSize = v24 ? cf_synchsafeToSize(f + 4)
                                   : (f[4] << 24 | f[5] << 16 | f[6] << 8 | f[7]);
        NSUInteger bodyStart = offset + 10;
        if (frameSize == 0 || bodyStart + frameSize > tagSize) {
            break;
        }

        const unsigned char* body = bytes + bodyStart;

        if ((strcmp(frameId, "TKEY") == 0) || (strcmp(frameId, "TXXX") == 0)) {
            if (frameSize > 0) {
                unsigned char enc = body[0];
                NSUInteger idx = 1;

                NSStringEncoding nsEnc = NSISOLatin1StringEncoding;
                if (enc == 1) {
                    nsEnc = NSUTF16StringEncoding;
                } else if (enc == 2) {
                    nsEnc = NSUTF16BigEndianStringEncoding;
                } else if (enc == 3) {
                    nsEnc = NSUTF8StringEncoding;
                }

                NSString* description = nil;

                if (strcmp(frameId, "TXXX") == 0) {
                    // Decode description first.
                    if (enc == 0 || enc == 3) {
                        NSUInteger descStart = idx;
                        while (idx < frameSize && body[idx] != 0) {
                            idx++;
                        };

                        description = [[NSString alloc] initWithBytes:body + descStart length:(idx - descStart) encoding:nsEnc];

                        if (idx < frameSize) {
                            idx++;
                        }
                    } else {
                        NSUInteger descStart = idx;

                        while (idx + 1 < frameSize) {
                            if (body[idx] == 0 && body[idx + 1] == 0) {
                                break;
                            }
                            idx += 2;
                        };
                        
                        description = [[NSString alloc] initWithBytes:body + descStart length:(idx - descStart) encoding:nsEnc];
                        if (idx + 1 < frameSize) {
                            idx += 2;
                        }
                    }

                    if (description.length > 0 && [[description uppercaseString] isEqualToString:@"INITIALKEY"] == NO) {
                        // Not our key frame; skip.
                        offset = bodyStart + frameSize;
                        continue;
                    }
                }

                NSData* valueData = (idx < frameSize) ? [NSData dataWithBytes:body + idx length:frameSize - idx] : [NSData data];
                NSString* decoded = [[NSString alloc] initWithData:valueData encoding:nsEnc];

                NSMutableString* ascii = [NSMutableString string];
                if (decoded.length > 0) {
                    for (NSUInteger i = 0; i < decoded.length; i++) {
                        unichar c = [decoded characterAtIndex:i];
                        if ((c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '#' || c == 'b' || c == '*') {
                            [ascii appendFormat:@"%c", (char) c];
                        }
                    }
                }
                if (ascii.length == 0) {
                    // Fallback: raw scan ignoring UTF-16 zero bytes.
                    for (NSUInteger i = idx; i < frameSize; i++) {
                        unsigned char c = body[i];
                        if (c == 0) {
                            continue;
                        }
                        if ((c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '#' || c == 'b' || c == '*') {
                            [ascii appendFormat:@"%c", c];
                        }
                    }
                }
                if (ascii.length > 0) {
                    return ascii;
                }
            }
        }

        offset = bodyStart + frameSize;
    }

    return nil;
}

@implementation MediaMetaData (TagLib)

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
                [mediaKeys addObjectsFromArray:@[ @"", @"" ]];
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
                [mediaKeys addObjectsFromArray:@[ @"", @"" ]];
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

static NSString* TStringToNSString(const TagLib::String& s)
{
    if (s.isEmpty()) {
        return @"";
    }
    std::string utf8 = s.to8Bit(true);
    return [[NSString alloc] initWithBytes:utf8.data() length:utf8.size() encoding:NSUTF8StringEncoding];
}

static NSString* SanitizeTagValue(const TagLib::String& s)
{
    NSString* value = TStringToNSString(s);
    value = [value sanitizedMetadataString];
    value = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    // Drop clearly invalid or mojibake-looking values.
    BOOL isClearlyBroken = NO;
    if (value.length > 0) {
        if (value.length >= 2) {
            unichar first = [value characterAtIndex:0];
            unichar second = [value characterAtIndex:1];
            if (first == 0x00FE && second >= 0xFF00 && second <= 0xFFEF) {
                isClearlyBroken = YES;
            }
        }
        __block NSUInteger highCount = 0;
        [value enumerateSubstringsInRange:NSMakeRange(0, value.length)
                                   options:NSStringEnumerationByComposedCharacterSequences
                                usingBlock:^(NSString* substring, NSRange __, NSRange ___, BOOL* stop) {
                                    unichar c = [substring characterAtIndex:0];
                                    // Allow basic/Latin‑1/extended Latin; flag heavy use of high codepoints.
                                    if (c > 0x024F) {
                                        highCount++;
                                        if (highCount > 3) {
                                            *stop = YES;
                                        }
                                    }
                                }];
        if (highCount > 3) {
            isClearlyBroken = YES;
        }
    }

    if (value.length == 0 || [value isLikelyMojibakeMetadata] || isClearlyBroken) {
        value = nil;
    }
    return value;
}

static void ApplyPropertyMap(const TagLib::PropertyMap& props, MediaMetaData* meta)
{
    auto setIfPresent = ^(const char* key, NSString* metaKey) {
        if (props.contains(TagLib::String(key))) {
            TagLib::String rawString = props[TagLib::String(key) ].toString();
            NSString* value = SanitizeTagValue(rawString);
            if (value.length > 0) {
                [meta setValue:value forKey:metaKey];
            }
        }
    };

    setIfPresent("TITLE", @"title");
    setIfPresent("ARTIST", @"artist");
    setIfPresent("ALBUM", @"album");
    setIfPresent("ALBUMARTIST", @"albumArtist");
    setIfPresent("GENRE", @"genre");
    setIfPresent("COMMENT", @"comment");
    setIfPresent("INITIALKEY", @"key");

    if (props.contains("DATE")) {
        NSString* date = SanitizeTagValue(props["DATE"].toString());
        if (date.length > 0) {
            [meta setValue:date forKey:@"year"];
        }
    }

    if (props.contains("BPM")) {
        NSString* bpm = SanitizeTagValue(props["BPM"].toString());
        if (bpm.length > 0) {
            [meta setValue:@(bpm.doubleValue) forKey:@"tempo"];
        }
    }

    if (props.contains("TRACKNUMBER")) {
        NSString* track = SanitizeTagValue(props["TRACKNUMBER"].toString());
        [meta setValue:@(track.intValue) forKey:@"track"];
    }
    if (props.contains("TRACKTOTAL")) {
        NSString* tracks = SanitizeTagValue(props["TRACKTOTAL"].toString());
        [meta setValue:@(tracks.intValue) forKey:@"tracks"];
    }
    if (props.contains("DISCNUMBER")) {
        NSString* disc = SanitizeTagValue(props["DISCNUMBER"].toString());
        [meta setValue:@(disc.intValue) forKey:@"disk"];
    }
    if (props.contains("DISCTOTAL")) {
        NSString* discs = SanitizeTagValue(props["DISCTOTAL"].toString());
        [meta setValue:@(discs.intValue) forKey:@"disks"];
    }
}

- (int)readFromMP3FileWithError:(NSError**)error
{
    NSString* path = [self.location path];

    if (path.length == 0) {
        return 0;
    }

    TagLib::MPEG::File file([path fileSystemRepresentation],
                            TagLib::ID3v2::FrameFactory::instance(),
                            true,
                            TagLib::AudioProperties::Average);
    if (!file.isValid()) {
        if (error) {
            *error = [NSError errorWithDomain:@"TagLibReader" code:-1 userInfo:@{NSLocalizedDescriptionKey : @"Invalid MPEG file"}];
        }
        return 0;
    }

    TagLib::PropertyMap props = file.properties();
    ApplyPropertyMap(props, self);

	// As a fallback, use the filename as title if nothing else was found.
	if (self.title.length == 0) {
		self.title = self.location.lastPathComponent.stringByDeletingPathExtension;
	}

    TagLib::StringList names = file.complexPropertyKeys();
    for (const auto& name : names) {
        if (self.artwork) {
            break;
        }

        if (!name.isEmpty() && name != "PICTURE") {
            continue;
        }

        const auto& properties = file.complexProperties(name);
        for (const auto& property : properties) {
            if (self.artwork) {
                break;
            }

            for (const auto& kv : property) {
                const TagLib::Variant& v = kv.second;
                if (v.type() == TagLib::Variant::ByteVector) {
                    TagLib::ByteVector bv = v.value<TagLib::ByteVector>();
                    if (!bv.isEmpty()) {
                        NSData* data = [NSData dataWithBytes:bv.data() length:bv.size()];
                        self.artwork = data;

                        ITLibArtworkFormat format = [MediaMetaData artworkFormatForData:data];
                        self.artworkFormat = [NSNumber numberWithInteger:format];

                        break;
                    }
                }
            }
        }
    }
    
    // Audio properties
    if (file.audioProperties()) {
        const TagLib::AudioProperties* ap = file.audioProperties();
        if (!self.duration) {
            self.duration = @((double) ap->length() * 1000.0);
        }
        self.channels = ap->channels() == 1 ? @"Mono" : @"Stereo";
        self.samplerate = [NSString stringWithFormat:@"%.1f kHz", ap->sampleRate() / 1000.0f];
        self.bitrate = [NSString stringWithFormat:@"%d kbps", ap->bitrate()];
    }
    
    if (self.key == nil || self.key.length == 0) {
        self.key = cf_extractKeyFromRawID3(path);
        if (self.key != nil && self.key.length > 0) {
            NSLog(@"we actually made the world a little better just now");
        }
    }

    return 0;
}

- (int)writeToTagLibFileWithError:(NSError**)error tagMap:(NSDictionary*)tagMap
{
    NSString* path = [self.location path];

    TagLib::MPEG::File file([path fileSystemRepresentation],
                            TagLib::ID3v2::FrameFactory::instance(),
                            true,
                            TagLib::AudioProperties::Average);
    if (!file.isValid()) {
        if (error) {
            *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier]
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey : @"Cannot open file using TagLib"}];
        }
        return -1;
    }

    TagLib::PropertyMap props = file.properties();

    BOOL shouldClearArt = NO;
    NSData* newArtwork = nil;
    NSString* newArtworkMime = nil;

    TagLib::ID3v2::Tag* id3 = file.ID3v2Tag(true);  // create if missing for artwork writes

    for (NSString* key in [tagMap allKeys]) {
        // Lets not create records from data we dont need on the destination.
        NSString* mediaKey = tagMap[key][kMediaMetaDataMapKeys][0];

        NSString* type = tagMap[key][kMediaMetaDataMapKeyType];
        if ([type isEqualToString:kMediaMetaDataMapTypeImage]) {
            if (self.artwork != nil) {
                ITLibArtworkFormat imageFormat = (ITLibArtworkFormat)[self.artworkFormat intValue];
                if (imageFormat == ITLibArtworkFormatNone) {
                    imageFormat = [MediaMetaData artworkFormatForData:self.artwork];
                }
                NSString* mimeType = [MediaMetaData mimeTypeForArtworkFormat:imageFormat];
                NSAssert(mimeType != nil, @"no mime type known for this picture format %d", imageFormat);
                newArtwork = self.artwork;
                newArtworkMime = mimeType;
            } else {
                shouldClearArt = YES;
            }
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
            TagLib::String tKey = cf_NSStringToTString(key);
            if (value.length > 0) {
                TagLib::StringList list;
                list.append(cf_NSStringToTString(value));
                props.replace(tKey, list);
            } else {
                props.erase(tKey);
            }
        }
    }

    file.setProperties(props);

    // Apply artwork changes after setting text properties so it doesn't get clobbered.
    if (id3) {
        id3->removeFrames("APIC");
        if (newArtwork && newArtworkMime.length > 0) {
            auto* pic = new TagLib::ID3v2::AttachedPictureFrame();
            pic->setType(TagLib::ID3v2::AttachedPictureFrame::FrontCover);
            pic->setMimeType([newArtworkMime UTF8String]);
            pic->setPicture(TagLib::ByteVector((const char*) newArtwork.bytes, (unsigned int)newArtwork.length));
            id3->addFrame(pic);
        }
    }

    // Also mirror artwork into APE tag to support readers that store art there.
    TagLib::APE::Tag* ape = file.APETag(true);
    if (ape) {
        ape->removeItem("COVER ART (FRONT)");
        if (newArtwork) {
            // APE cover art format: description\0<data>
            TagLib::ByteVector payload("cover", 5);
            payload.append(TagLib::ByteVector(1, '\0'));
            payload.append(TagLib::ByteVector((const char*) newArtwork.bytes, (unsigned int)newArtwork.length));
            TagLib::APE::Item artItem;
            artItem.setKey("COVER ART (FRONT)");
            artItem.setValue(payload);
            artItem.setType(TagLib::APE::Item::Binary);
            ape->setItem("COVER ART (FRONT)", artItem);
        }
    }

    if (!file.save()) {
        if (error) {
            *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier]
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey : @"Cannot store file using TagLib"}];
        }
        return -1;
    }

    return 0;
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
