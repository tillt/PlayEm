//
//  AudioQueuePlaybackBackendTests.m
//  PlayEmCoreTests
//
//  Created by Till Toenshoff on 01/05/26.
//  Copyright © 2026 Till Toenshoff. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "AudioQueuePlaybackBackend.h"

// Expose the helper for testing.
extern unsigned long long AQPlaybackAdjustedFrame(unsigned long long baseFrame,
                                                 double sampleTime,
                                                 signed long long latencyFrames,
                                                 unsigned long long totalFrames);

@interface AudioQueuePlaybackBackendTests : XCTestCase
@end

@implementation AudioQueuePlaybackBackendTests

- (void)testAdjustedFrameSubtractsLatency
{
    unsigned long long result = AQPlaybackAdjustedFrame(1000, 500.0, 50, 2000);
    XCTAssertEqual(result, 1450ULL);
}

- (void)testAdjustedFrameClampsToZero
{
    unsigned long long result = AQPlaybackAdjustedFrame(0, 10.0, 50, 2000);
    XCTAssertEqual(result, 0ULL);
}

- (void)testAdjustedFrameClampsToTotalFramesMinusOne
{
    unsigned long long result = AQPlaybackAdjustedFrame(1900, 200.0, 0, 2000);
    XCTAssertEqual(result, 1999ULL);
}

@end
