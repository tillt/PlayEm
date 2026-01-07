//
//  ActivityManagerTests.m
//  PlayEmCoreTests
//

#import <XCTest/XCTest.h>

#import "ActivityManager.h"

@interface ActivityManagerTests : XCTestCase
@end

@implementation ActivityManagerTests

- (void)waitForMainQueue
{
    XCTestExpectation* exp = [self expectationWithDescription:@"main sync"];
    dispatch_async(dispatch_get_main_queue(), ^{
        [exp fulfill];
    });
    [self waitForExpectations:@[ exp ] timeout:1.0];
}

- (void)waitForActivitiesAtLeast:(NSUInteger)count
{
    __block id token = nil;
    XCTestExpectation* exp = [self expectationWithDescription:@"activities updated"];
    void (^check)(void) = ^{
        if ([ActivityManager shared].activities.count >= count) {
            if (token) {
                [[NSNotificationCenter defaultCenter] removeObserver:token];
                token = nil;
            }
            [exp fulfill];
        }
    };
    token = [[NSNotificationCenter defaultCenter] addObserverForName:ActivityManagerDidUpdateNotification
                                                              object:nil
                                                               queue:[NSOperationQueue mainQueue]
                                                          usingBlock:^(__unused NSNotification* _Nonnull note) {
                                                              check();
                                                          }];
    dispatch_async(dispatch_get_main_queue(), check);
    [self waitForExpectations:@[ exp ] timeout:1.0];
}

- (void)testBeginAndCompleteMarksInactive
{
    ActivityToken* token = [[ActivityManager shared] beginActivityWithTitle:@"Test" detail:nil cancellable:NO cancelHandler:nil];
    [self waitForActivitiesAtLeast:1];
    XCTAssertTrue([[ActivityManager shared] isActive:token]);

    [[ActivityManager shared] completeActivity:token];
    [self waitForMainQueue];

    XCTAssertFalse([[ActivityManager shared] isActive:token]);
}

- (void)testCancelMarksCompleted
{
    __block BOOL handlerCalled = NO;
    ActivityToken* token = [[ActivityManager shared] beginActivityWithTitle:@"Cancelable"
                                                                     detail:nil
                                                                cancellable:YES
                                                              cancelHandler:^{
                                                                  handlerCalled = YES;
                                                              }];
    [self waitForActivitiesAtLeast:1];
    XCTAssertTrue([[ActivityManager shared] isActive:token]);

    [[ActivityManager shared] requestCancel:token];
    [self waitForMainQueue];

    XCTAssertTrue(handlerCalled);
    XCTAssertFalse([[ActivityManager shared] isActive:token]);
}

@end
