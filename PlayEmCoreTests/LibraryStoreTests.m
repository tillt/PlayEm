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

@interface LibraryStoreTests : XCTestCase
@end

@implementation LibraryStoreTests

- (NSURL*)temporaryDatabaseURL
{
    NSString* path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"playem_librarystore_test.sqlite"];
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    return [NSURL fileURLWithPath:path];
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

@end
