//
//  CancelableBlockOperationTests.m
//  PlayEmCoreTests
//

#import <XCTest/XCTest.h>

#import "CancelableBlockOperation.h"

@interface CancelableBlockOperationTests : XCTestCase
@end

@implementation CancelableBlockOperationTests

- (void)testCompletesAndSetsFlags
{
    CancelableBlockOperation* op = [[CancelableBlockOperation alloc] init];
    __block BOOL ran = NO;
    [op run:^{
        ran = YES;
    }];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), op.dispatchBlock);
    dispatch_block_wait(op.dispatchBlock, DISPATCH_TIME_FOREVER);

    XCTAssertTrue(ran);
    XCTAssertTrue(op.isCompleted);
    XCTAssertTrue(op.isDone);
    XCTAssertFalse(op.isCancelled);
}

- (void)testCancelSetsDoneAndCancelled
{
    CancelableBlockOperation* op = [[CancelableBlockOperation alloc] init];
    __block BOOL ran = NO;
    [op run:^{
        ran = YES;
    }];

    [op cancel];
    XCTAssertTrue(op.isCancelled);
    XCTAssertTrue(op.isDone);
    XCTAssertFalse(op.isCompleted);
    XCTAssertFalse(ran);
}

@end
