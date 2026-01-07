//
//  ImageControllerTests.m
//  PlayEmCoreTests
//
//  Created by Till Toenshoff on 12/31/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import <XCTest/XCTest.h>

@import AppKit;
#import "ImageController.h"

@interface ImageControllerTests : XCTestCase
@end

@implementation ImageControllerTests

- (NSData*)samplePNGDataWithSize:(CGFloat)edge
{
    NSImage* img = [[NSImage alloc] initWithSize:NSMakeSize(edge, edge)];
    [img lockFocus];
    [[NSColor colorWithCalibratedRed:0.2 green:0.4 blue:0.8 alpha:1.0] setFill];
    NSRectFill(NSMakeRect(0, 0, edge, edge));
    [img unlockFocus];

    NSBitmapImageRep* rep = [[NSBitmapImageRep alloc] initWithData:[img TIFFRepresentation]];
    NSData* png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    return png;
}

- (void)testImageCacheHitsAndClear
{
    NSData* png = [self samplePNGDataWithSize:20.0];
    XCTAssertNotNil(png);

    __block NSImage* first = nil;
    XCTestExpectation* firstExpect = [self expectationWithDescription:@"first image"];
    [[ImageController shared] imageForData:png
                                       key:@"test-key"
                                      size:20.0
                                completion:^(NSImage* img) {
                                    first = img;
                                    XCTAssertNotNil(img);
                                    XCTAssertEqualWithAccuracy(img.size.width, 20.0, 0.1);
                                    XCTAssertEqualWithAccuracy(img.size.height, 20.0, 0.1);
                                    [firstExpect fulfill];
                                }];
    [self waitForExpectations:@[ firstExpect ] timeout:2.0];

    __block NSImage* second = nil;
    XCTestExpectation* secondExpect = [self expectationWithDescription:@"cache hit"];
    [[ImageController shared] imageForData:png
                                       key:@"test-key"
                                      size:20.0
                                completion:^(NSImage* img) {
                                    second = img;
                                    XCTAssertNotNil(img);
                                    [secondExpect fulfill];
                                }];
    [self waitForExpectations:@[ secondExpect ] timeout:2.0];
    XCTAssertEqual(first, second, @"Expected cache hit to return the same NSImage instance");

    [[ImageController shared] clearCache];

    __block NSImage* third = nil;
    XCTestExpectation* thirdExpect = [self expectationWithDescription:@"post-clear miss"];
    [[ImageController shared] imageForData:png
                                       key:@"test-key"
                                      size:20.0
                                completion:^(NSImage* img) {
                                    third = img;
                                    XCTAssertNotNil(img);
                                    [thirdExpect fulfill];
                                }];
    [self waitForExpectations:@[ thirdExpect ] timeout:2.0];
    XCTAssertNotEqual(first, third, @"After clearCache a new image instance should be produced");
}

- (void)testResolveDataForURL
{
    NSData* payload = [@"hello-image" dataUsingEncoding:NSUTF8StringEncoding];
    NSString* tmpPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID].UUIDString stringByAppendingString:@".bin"]];
    XCTAssertTrue([payload writeToFile:tmpPath atomically:YES]);

    XCTestExpectation* expect = [self expectationWithDescription:@"download"];
    NSURL* url = [NSURL fileURLWithPath:tmpPath];
    [[ImageController shared] resolveDataForURL:url
                                       callback:^(NSData* data) {
                                           XCTAssertNotNil(data);
                                           XCTAssertEqualObjects(data, payload);
                                           [expect fulfill];
                                       }];
    [self waitForExpectations:@[ expect ] timeout:2.0];
}

- (NSImage*)syncImageForData:(NSData*)data key:(NSString*)key size:(CGFloat)size timeout:(NSTimeInterval)timeout
{
    __block NSImage* result = nil;
    XCTestExpectation* expect = [self expectationWithDescription:[NSString stringWithFormat:@"image-%@", key]];
    [[ImageController shared] imageForData:data
                                       key:key
                                      size:size
                                completion:^(NSImage* img) {
                                    result = img;
                                    [expect fulfill];
                                }];
    [self waitForExpectations:@[ expect ] timeout:timeout];
    return result;
}

- (void)testCacheEvictionWhenCostLimitExceeded
{
    NSCache* cache = [[ImageController shared] valueForKey:@"cache"];
    XCTAssertNotNil(cache);
    NSUInteger originalLimit = cache.totalCostLimit;

    // Use a small limit so we can force eviction quickly.
    cache.totalCostLimit = 200000;  // ~200 KB

    NSData* png = [self samplePNGDataWithSize:256.0];  // ~262 KB cost
    NSImage* first = [self syncImageForData:png key:@"evict-1" size:256.0 timeout:2.0];
    XCTAssertNotNil(first);

    // Insert a couple more unique entries to exceed the limit and trigger
    // eviction.
    NSImage* second = [self syncImageForData:png key:@"evict-2" size:256.0 timeout:2.0];
    XCTAssertNotNil(second);
    NSImage* third = [self syncImageForData:png key:@"evict-3" size:256.0 timeout:2.0];
    XCTAssertNotNil(third);

    // Re-request the first key; after eviction we should get a new instance.
    NSImage* reloaded = [self syncImageForData:png key:@"evict-1" size:256.0 timeout:2.0];
    XCTAssertNotNil(reloaded);
    XCTAssertNotEqual(first, reloaded,
                      @"Expected first entry to be evicted and reloaded after "
                      @"cost limit breach");

    cache.totalCostLimit = originalLimit;
    [[ImageController shared] clearCache];
}

@end
