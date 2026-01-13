//
//  TagLibMetaTests.m
//  PlayEmCoreTests
//
//  Created by Codex on 2026-01-xx.
//

#import <XCTest/XCTest.h>

#import "MediaMetaData.h"
#import "MediaMetaData+TagLib.h"
#import "NSString+Sanitized.h"

@interface TagLibMetaTests : XCTestCase
@end

@implementation TagLibMetaTests

- (NSData*)smallTestArtwork
{
    // 1x1 PNG.
    static NSString* const b64 = @"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z/C/HwAFgwJ/lDRbugAAAABJRU5ErkJggg==";
    return [[NSData alloc] initWithBase64EncodedString:b64 options:0];
}

- (NSURL*)testFileURL
{
    NSDictionary<NSString*, NSString*>* env = [[NSProcessInfo processInfo] environment];
    NSString* path = env[@"PLAYEM_TAGLIB_TEST_FILE"];

    if (path.length == 0) {
        path = @"/Users/till/Music/Music2Go/Media.localized/Kaufmann (DE)/Ibu 3000/1-02 Ibu 3000 (Metodi Hristov Remix).mp3";
    }

    if (path.length == 0) {
        return nil;
    }
    return [NSURL fileURLWithPath:path];
}

- (void)testMP3TagsAreSanitizedAndNotMojibake
{
    NSURL* url = [self testFileURL];
    if (!url || ![[NSFileManager defaultManager] fileExistsAtPath:url.path]) {
        XCTSkip(@"TagLib test file missing; set PLAYEM_TAGLIB_TEST_FILE to a valid MP3 path.");
        return;
    }

    MediaMetaData* meta = [MediaMetaData emptyMediaDataWithURL:url];
    NSError* error = nil;
    XCTAssertTrue([meta readFromFileWithError:&error], @"Failed to read taglib meta: %@", error);

    NSArray<NSString*>* textKeys = @[ @"title", @"artist", @"album", @"albumArtist", @"genre", @"comment", @"tags", @"key" ];
    for (NSString* key in textKeys) {
        NSString* value = [meta valueForKey:key];
        if (value.length == 0) {
            continue;
        }
        NSString* sanitized = [value sanitizedMetadataString];
        XCTAssertEqualObjects(value, sanitized, @"%@ was not sanitized: %@", key, value);
        XCTAssertFalse([value isLikelyMojibakeMetadata], @"%@ contains mojibake: %@", key, value);
    }

    // Spot-check key normalization is readable (no mojibake artifacts).
    if (meta.key.length > 0) {
        XCTAssertFalse([meta.key isLikelyMojibakeMetadata], @"Key still looks mojibake: %@", meta.key);
    }
}

- (void)testMP3RoundTripWriteAndRemoval
{
    NSURL* srcURL = [self testFileURL];
    if (!srcURL || ![[NSFileManager defaultManager] fileExistsAtPath:srcURL.path]) {
        XCTSkip(@"TagLib test file missing; set PLAYEM_TAGLIB_TEST_FILE to a valid MP3 path.");
        return;
    }

    NSString* tmpDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:tmpDir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString* dstPath = [tmpDir stringByAppendingPathComponent:srcURL.lastPathComponent];
    XCTAssertTrue([[NSFileManager defaultManager] copyItemAtPath:srcURL.path toPath:dstPath error:nil]);
    NSURL* dstURL = [NSURL fileURLWithPath:dstPath];

    // Read, mutate, write.
    MediaMetaData* meta = [MediaMetaData emptyMediaDataWithURL:dstURL];
    NSError* error = nil;
    XCTAssertTrue([meta readFromFileWithError:&error], @"read failed: %@", error);

    NSString* newTitle = @"TagLib Write Test";
    NSString* newGenre = @"UnitTestGenre";
    NSString* newKey = @"12A";
    meta.title = newTitle;
    meta.genre = newGenre;
    meta.key = newKey;
    meta.comment = @"";  // remove comment

    XCTAssertEqual(0, [meta writeToMP3FileWithError:&error], @"write failed: %@", error);

    // Re-read and verify changes persisted.
    MediaMetaData* roundTrip = [MediaMetaData emptyMediaDataWithURL:dstURL];
    error = nil;
    XCTAssertTrue([roundTrip readFromFileWithError:&error], @"re-read failed: %@", error);

    XCTAssertEqualObjects(roundTrip.title, newTitle);
    XCTAssertEqualObjects(roundTrip.genre, newGenre);
    XCTAssertEqualObjects(roundTrip.key, newKey);
    XCTAssertTrue(roundTrip.comment.length == 0, @"Comment should be removed, got %@", roundTrip.comment);
}

- (void)testMP3ArtworkRoundTrip
{
    NSURL* srcURL = [self testFileURL];
    if (!srcURL || ![[NSFileManager defaultManager] fileExistsAtPath:srcURL.path]) {
        XCTSkip(@"TagLib test file missing; set PLAYEM_TAGLIB_TEST_FILE to a valid MP3 path.");
        return;
    }

    NSString* tmpDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:tmpDir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString* dstPath = [tmpDir stringByAppendingPathComponent:srcURL.lastPathComponent];
    XCTAssertTrue([[NSFileManager defaultManager] copyItemAtPath:srcURL.path toPath:dstPath error:nil]);
    NSURL* dstURL = [NSURL fileURLWithPath:dstPath];

    NSData* art = [self smallTestArtwork];
    XCTAssertTrue(art.length > 0);

    MediaMetaData* meta = [MediaMetaData emptyMediaDataWithURL:dstURL];
    NSError* error = nil;
    XCTAssertTrue([meta readFromFileWithError:&error], @"read failed: %@", error);
    meta.artwork = art;
    meta.artworkFormat = @(ITLibArtworkFormatPNG);
    XCTAssertEqual(0, [meta writeToMP3FileWithError:&error], @"write failed: %@", error);

    MediaMetaData* roundTrip = [MediaMetaData emptyMediaDataWithURL:dstURL];
    XCTAssertTrue([roundTrip readFromFileWithError:&error], @"re-read failed: %@", error);
    XCTAssertTrue([roundTrip.artwork isEqualToData:art], @"artwork not persisted");

    // Now remove artwork and ensure it clears.
    roundTrip.artwork = nil;
    roundTrip.artworkFormat = nil;
    XCTAssertEqual(0, [roundTrip writeToMP3FileWithError:&error], @"write failed clearing art: %@", error);

    MediaMetaData* cleared = [MediaMetaData emptyMediaDataWithURL:dstURL];
    XCTAssertTrue([cleared readFromFileWithError:&error], @"re-read after clear failed: %@", error);
    XCTAssertNil(cleared.artwork);
}

- (void)testExportArtworkToTempFile
{
    NSURL* url = [self testFileURL];
    if (!url || ![[NSFileManager defaultManager] fileExistsAtPath:url.path]) {
        XCTSkip(@"TagLib test file missing; set PLAYEM_TAGLIB_TEST_FILE to a valid MP3 path.");
        return;
    }

    NSError* error = nil;
    MediaMetaData* meta = [MediaMetaData emptyMediaDataWithURL:url];
    XCTAssertTrue([meta readFromFileWithError:&error], @"read failed: %@", error);

    XCTAssertTrue(meta.artwork.length > 0, @"Fixture artwork should be present but was empty");

    NSString* tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"taglib_artwork_%@.bin", [[NSUUID UUID] UUIDString]]];
    BOOL ok = [[NSFileManager defaultManager] createFileAtPath:tempPath contents:meta.artwork attributes:nil];
    XCTAssertTrue(ok, @"Failed to write artwork to %@", tempPath);
}

@end
