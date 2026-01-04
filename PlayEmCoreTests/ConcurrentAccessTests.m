//
//  ConcurrentAccessTests.m
//  PlayEmCoreTests
//
//  Created by Till Toenshoff on 12/31/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "ConcurrentAccessDictionary.h"

@interface ConcurrentAccessTests : XCTestCase
@end

@implementation ConcurrentAccessTests

- (void)testWriteBeforeReadOrdering
{
    ConcurrentAccessDictionary *dict = [ConcurrentAccessDictionary new];
    [dict setObject:@1 forKey:@"k"];
    NSNumber *n = [dict objectForKey:@"k"];
    XCTAssertEqualObjects(n, @1);
}

- (void)testConcurrentReads
{
    ConcurrentAccessDictionary *dict = [ConcurrentAccessDictionary new];
    [dict setObject:@"v" forKey:@"k"];

    XCTestExpectation *expect = [self expectationWithDescription:@"concurrent reads"];
    expect.expectedFulfillmentCount = 10;

    dispatch_group_t group = dispatch_group_create();
    for (NSUInteger i = 0; i < 10; i++) {
        dispatch_group_async(group, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSString *v = [dict objectForKey:@"k"];
            XCTAssertEqualObjects(v, @"v");
            [expect fulfill];
        });
    }
    [self waitForExpectations:@[expect] timeout:2.0];
}

- (void)testRemoveAndClear
{
    ConcurrentAccessDictionary *dict = [ConcurrentAccessDictionary new];
    [dict setObject:@1 forKey:@"a"];
    [dict setObject:@2 forKey:@"b"];
    XCTAssertEqual([[dict allKeys] count], 2);

    [dict removeObjectForKey:@"a"];
    XCTAssertNil([dict objectForKey:@"a"]);
    XCTAssertEqual([[dict allKeys] count], 1);

    [dict removeAllObjects];
    XCTAssertEqual([[dict allKeys] count], 0);
}

@end
