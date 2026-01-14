//
//  LibraryStoreTests.m
//  PlayEmCoreTests
//
//  Created by Till Toenshoff on 09/03/26.
//  Copyright © 2026 Till Toenshoff. All rights reserved.
//

#import <XCTest/XCTest.h>

#import "LibraryStore.h"
#import "MediaMetaData.h"
#import "MediaMetaData+TagLib.h"

@interface LibraryStoreTests : XCTestCase
@end

@implementation LibraryStoreTests

- (NSURL*)temporaryDatabaseURL
{
    NSString* path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"playem_librarystore_test.sqlite"];
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    return [NSURL fileURLWithPath:path];
}

- (NSURL*)testMP3URL
{
    NSString* path = [[NSBundle bundleForClass:[self class]] pathForResource:@"taglib_sample" ofType:@"mp3" inDirectory:@"Fixtures"];
    return path ? [NSURL fileURLWithPath:path] : nil;
}

- (MediaMetaData*)sampleMeta
{
    MediaMetaData* meta = [MediaMetaData new];
    meta.location = [NSURL fileURLWithPath:@"/tmp/sample.mp3"];
    meta.title = @"Title";
    meta.artist = @"Artist";
    meta.album = @"Album";
    meta.albumArtist = @"AlbumArtist";
    meta.genre = @"Genre";
    meta.year = @2024;
    meta.track = @1;
    meta.tracks = @10;
    meta.disk = @1;
    meta.disks = @2;
    meta.duration = @123.45;
    meta.tempo = @128.0;
    meta.key = @"8A";
    meta.rating = @80;
    meta.comment = @"Comment";
    meta.tags = @"tag1,tag2";
    meta.compilation = @NO;
    meta.artworkLocation = [NSURL URLWithString:@"file:///tmp/art.png"];
    meta.locationType = @(MediaMetaDataLocationTypeFile);
    meta.appleLocation = [NSURL URLWithString:@"apple-music://abc"];
    return meta;
}

- (void)testImportAndLoadRoundTrip
{
    NSURL* dbURL = [self temporaryDatabaseURL];
    LibraryStore* store = [[LibraryStore alloc] initWithDatabaseURL:dbURL];

    MediaMetaData* meta = [self sampleMeta];
    NSError* error = nil;
    BOOL ok = [store importMediaItems:@[ meta ] error:&error];
    XCTAssertTrue(ok, @"import failed: %@", error);

    NSArray<MediaMetaData*>* loaded = [store loadAllMediaItems:&error];
    XCTAssertNotNil(loaded, @"load failed: %@", error);
    XCTAssertEqual(loaded.count, 1u);

    MediaMetaData* roundTrip = loaded.firstObject;
    XCTAssertEqualObjects(roundTrip.location, meta.location);
    XCTAssertEqualObjects(roundTrip.title, meta.title);
    XCTAssertEqualObjects(roundTrip.artist, meta.artist);
    XCTAssertEqualObjects(roundTrip.album, meta.album);
    XCTAssertEqualObjects(roundTrip.albumArtist, meta.albumArtist);
    XCTAssertEqualObjects(roundTrip.genre, meta.genre);
    XCTAssertEqualObjects(roundTrip.year, meta.year);
    XCTAssertEqualObjects(roundTrip.track, meta.track);
    XCTAssertEqualObjects(roundTrip.tracks, meta.tracks);
    XCTAssertEqualObjects(roundTrip.disk, meta.disk);
    XCTAssertEqualObjects(roundTrip.disks, meta.disks);
    XCTAssertEqualObjects(roundTrip.duration, meta.duration);
    XCTAssertEqualObjects(roundTrip.tempo, meta.tempo);
    XCTAssertEqualObjects(roundTrip.key, meta.key);
    XCTAssertEqualObjects(roundTrip.rating, meta.rating);
    XCTAssertEqualObjects(roundTrip.comment, meta.comment);
    XCTAssertEqualObjects(roundTrip.tags, meta.tags);
    XCTAssertEqualObjects(roundTrip.compilation, meta.compilation);
    XCTAssertEqualObjects(roundTrip.artworkLocation, meta.artworkLocation);
    XCTAssertEqualObjects(roundTrip.locationType, meta.locationType);
    XCTAssertEqualObjects(roundTrip.appleLocation, meta.appleLocation);
    XCTAssertNotNil(roundTrip.added);
}

- (void)testAddedAtPreservedOnUpsert
{
    NSURL* dbURL = [self temporaryDatabaseURL];
    LibraryStore* store = [[LibraryStore alloc] initWithDatabaseURL:dbURL];

    MediaMetaData* original = [self sampleMeta];
    original.added = [NSDate dateWithTimeIntervalSince1970:12345];
    NSError* error = nil;
    XCTAssertTrue([store importMediaItems:@[ original ] error:&error], @"import failed: %@", error);

    // Re-import same URL with different title and no added set.
    MediaMetaData* updated = [self sampleMeta];
    updated.title = @"New Title";
    updated.added = nil;
    XCTAssertTrue([store importMediaItems:@[ updated ] error:&error], @"second import failed: %@", error);

    NSArray<MediaMetaData*>* loaded = [store loadAllMediaItems:&error];
    XCTAssertNotNil(loaded, @"load failed: %@", error);
    MediaMetaData* roundTrip = loaded.firstObject;

    XCTAssertEqualObjects(roundTrip.title, updated.title);
    XCTAssertEqualWithAccuracy(roundTrip.added.timeIntervalSince1970, original.added.timeIntervalSince1970, 0.1, @"addedAt should be preserved");
}

- (void)testMetaComparisonIgnoresAddedAt
{
    MediaMetaData* a = [self sampleMeta];
    a.added = [NSDate dateWithTimeIntervalSince1970:1000];
    MediaMetaData* b = [self sampleMeta];
    b.added = [NSDate dateWithTimeIntervalSince1970:2000];

    // Should be considered equal for reconciliation purposes.
    XCTAssertTrue([a isSemanticallyEqualToMeta:b]);
}

- (void)testReconcileDoesNotReportUnchangedMeta
{
    NSURL* dbURL = [self temporaryDatabaseURL];
    LibraryStore* store = [[LibraryStore alloc] initWithDatabaseURL:dbURL];

    NSURL* srcURL = [self testMP3URL];
    if (!srcURL || ![[NSFileManager defaultManager] fileExistsAtPath:srcURL.path]) {
        XCTSkip(@"TagLib test file missing; set PLAYEM_TAGLIB_TEST_FILE to a valid MP3 path.");
        return;
    }

    // Seed the DB with a temp copy of the MP3, preserving its ID3 metadata.
    NSString* tmpDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:tmpDir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString* dstPath = [tmpDir stringByAppendingPathComponent:srcURL.lastPathComponent];
    NSError* copyErr = nil;
    XCTAssertTrue([[NSFileManager defaultManager] copyItemAtPath:srcURL.path toPath:dstPath error:&copyErr], @"copy failed: %@", copyErr);
    NSURL* dstURL = [NSURL fileURLWithPath:dstPath];

    MediaMetaData* original = [MediaMetaData emptyMediaDataWithURL:dstURL];
    NSError* error = nil;
    XCTAssertTrue([original readFromFileWithError:&error], @"read failed: %@", error);
    XCTAssertTrue([store importMediaItems:@[ original ] error:&error], @"import failed: %@", error);

    // Reconcile against the same file list (no changes).
    XCTestExpectation* exp = [self expectationWithDescription:@"reconcile"];
    [store reconcileLibraryWithCompletion:^(NSArray<MediaMetaData*>* _Nullable refreshedMetas,
                                            NSArray<MediaMetaData*>* _Nullable changedMetas,
                                            NSArray<NSURL*>* missingFiles,
                                            NSError* _Nullable error) {
        XCTAssertNil(error, @"reconcile error: %@", error);
        XCTAssertNotNil(refreshedMetas);
        XCTAssertEqual(changedMetas.count, 0u, @"No diffs expected for identical meta");
        XCTAssertEqual(missingFiles.count, 0u);
        [exp fulfill];
    }];

    [self waitForExpectationsWithTimeout:5 handler:nil];
}

- (void)testReconcileIgnoresWhitespaceAndUmlautStability
{
    NSURL* dbURL = [self temporaryDatabaseURL];
    LibraryStore* store = [[LibraryStore alloc] initWithDatabaseURL:dbURL];

    NSURL* srcURL = [self testMP3URL];
    if (!srcURL || ![[NSFileManager defaultManager] fileExistsAtPath:srcURL.path]) {
        XCTSkip(@"TagLib test file missing; set PLAYEM_TAGLIB_TEST_FILE to a valid MP3 path.");
        return;
    }

    // Work on a temp copy and embed metadata with umlauts/double spaces.
    NSString* tmpDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:tmpDir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString* dstPath = [tmpDir stringByAppendingPathComponent:srcURL.lastPathComponent];
    NSError* copyErr = nil;
    XCTAssertTrue([[NSFileManager defaultManager] copyItemAtPath:srcURL.path toPath:dstPath error:&copyErr], @"copy failed: %@", copyErr);
    NSURL* dstURL = [NSURL fileURLWithPath:dstPath];

    MediaMetaData* meta = [MediaMetaData emptyMediaDataWithURL:dstURL];
    NSError* error = nil;
    XCTAssertTrue([meta readFromFileWithError:&error], @"read failed: %@", error);
    meta.title = @"Faust  Hörspiel  Übergröße";  // double spaces + umlauts
    meta.artist = @"Müller  & Söhne";
    meta.album = @"Über  Album";
    meta.comment = @"Kommentar  mit  Doppel  Leerzeichen";
    XCTAssertEqual(0, [meta writeToMP3FileWithError:&error], @"write failed: %@", error);

    // Re-read to get exactly what the file stores.
    MediaMetaData* storedMeta = [MediaMetaData emptyMediaDataWithURL:dstURL];
    XCTAssertTrue([storedMeta readFromFileWithError:&error], @"re-read failed: %@", error);

    XCTAssertTrue([store importMediaItems:@[ storedMeta ] error:&error], @"import failed: %@", error);

    XCTestExpectation* exp = [self expectationWithDescription:@"reconcile2"];
    [store reconcileLibraryWithCompletion:^(NSArray<MediaMetaData*>* _Nullable refreshedMetas,
                                            NSArray<MediaMetaData*>* _Nullable changedMetas,
                                            NSArray<NSURL*>* missingFiles,
                                            NSError* _Nullable error) {
        XCTAssertNil(error, @"reconcile error: %@", error);
        XCTAssertEqual(changedMetas.count, 0u, @"Whitespace/umlaut stability should not produce diffs");
        XCTAssertEqual(missingFiles.count, 0u);
        [exp fulfill];
    }];

    [self waitForExpectationsWithTimeout:5 handler:nil];
}

@end
