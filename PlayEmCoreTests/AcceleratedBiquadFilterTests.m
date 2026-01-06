//  AcceleratedBiquadFilterTests.m
//  PlayEmCoreTests
//

#import <XCTest/XCTest.h>
#import "AcceleratedBiquadFilter.h"
#import "MockLazySample.h"

@interface AcceleratedBiquadFilterTests : XCTestCase
@end

@implementation AcceleratedBiquadFilterTests

- (void)testOneChannelImpulseProducesFiniteOutput
{
    MockLazySample* sample = [[MockLazySample alloc] initWithChannels:1];
    AcceleratedBiquadFilter* filter = [[AcceleratedBiquadFilter alloc] initWithSample:sample];
    [filter calculateParamsWithCutoff:1000 resonance:0.5 nyquistPeriod:1.0 / (sample.sampleFormat.rate * 0.5)];

    float inputBuf[4] = {1.0f, 0.0f, 0.0f, 0.0f};
    float outputBuf[4] = {0};
    float const* inputs[1] = { inputBuf };
    float* outputs[1] = { outputBuf };

    [filter applyToInputs:inputs outputs:outputs frames:4];

    for (int i = 0; i < 4; i++) {
        XCTAssertTrue(isfinite(outputBuf[i]), @"Output should be finite");
    }
}

- (void)testTwoChannelDoesNotCrashAndAllocatesCoeffs
{
    MockLazySample* sample = [[MockLazySample alloc] initWithChannels:2];
    AcceleratedBiquadFilter* filter = [[AcceleratedBiquadFilter alloc] initWithSample:sample];
    [filter calculateParamsWithCutoff:500 resonance:0.7 nyquistPeriod:1.0 / (sample.sampleFormat.rate * 0.5)];

    float inL[2] = {0.5f, 0.25f};
    float inR[2] = {0.1f, -0.1f};
    float outL[2] = {0};
    float outR[2] = {0};
    float const* inputs[2] = { inL, inR };
    float* outputs[2] = { outL, outR };

    [filter applyToInputs:inputs outputs:outputs frames:2];

    for (int i = 0; i < 2; i++) {
        XCTAssertTrue(isfinite(outL[i]) && isfinite(outR[i]), @"Outputs should be finite for both channels");
    }
}

@end
