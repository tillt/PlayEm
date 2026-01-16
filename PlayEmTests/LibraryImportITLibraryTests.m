//
//  LibraryImportITLibraryTests.m
//  PlayEmTests
//
//  Created by Till Toenshoff on 09/03/26.
//  Copyright © 2026 Till Toenshoff. All rights reserved.
//

#import <XCTest/XCTest.h>

#if __has_include(<iTunesLibrary/ITLibrary.h>)
#import <iTunesLibrary/ITLibrary.h>

#import "LibraryStore.h"
#import "MediaMetaData.h"

@interface LibraryImportITLibraryTests : XCTestCase
@end

@implementation LibraryImportITLibraryTests

- (NSURL*)temporaryDatabaseURL
{
    NSString* path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"playem_itunes_import_test.sqlite"];
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    return [NSURL fileURLWithPath:path];
}

- (void)testImportAndReloadFromITLibrary
{
    NSError* libError = nil;
    ITLibrary* lib = [ITLibrary libraryWithAPIVersion:@"1.0" options:ITLibInitOptionLazyLoadData error:&libError];
    if (!lib || lib.allMediaItems.count == 0) {
        XCTSkip(@"No Music library available or accessible: %@", libError);
    }

    NSMutableArray<MediaMetaData*>* metas = [NSMutableArray array];
    for (ITLibMediaItem* item in lib.allMediaItems) {
        if (item.cloud) {
            continue;  // skip cloud-only items
        }
        if (!item.location.fileURL) {
            continue;  // skip non-file items
        }
        NSError* metaErr = nil;
        MediaMetaData* meta = [MediaMetaData mediaMetaDataWithITLibMediaItem:item error:&metaErr];
        if (meta) {
            [metas addObject:meta];
        }
        if (metas.count >= 3) {
            break;
        }
    }
    if (metas.count == 0) {
        XCTSkip(@"No suitable media items for test import");
    }

    NSURL* dbURL = [self temporaryDatabaseURL];
    LibraryStore* store = [[LibraryStore alloc] initWithDatabaseURL:dbURL];

    NSError* err = nil;
    XCTAssertTrue([store importMediaItems:metas error:&err], @"Import failed: %@", err);

    NSArray<MediaMetaData*>* loaded = [store loadAllMediaItems:&err];
    XCTAssertNotNil(loaded, @"Load failed: %@", err);
    XCTAssertEqual(loaded.count, metas.count);

    // Ensure URLs round-trip.
    NSSet* originalURLs = [NSSet setWithArray:[metas valueForKeyPath:@"location"]];
    NSSet* loadedURLs = [NSSet setWithArray:[loaded valueForKeyPath:@"location"]];
    XCTAssertEqualObjects(originalURLs, loadedURLs);
}

@end

#endif
