//
//  AUPlaybackBackendTapTests.m
//  PlayEmCoreTests
//
//  Created for validating tap contiguity without real audio I/O.
//

#import <XCTest/XCTest.h>

#import <AudioToolbox/AudioToolbox.h>

#import "AUPlaybackBackend.h"
#import "MockLazySample.h"

OSStatus AUPlaybackTapNotify(void* inRefCon, AudioUnitRenderActionFlags* ioActionFlags, const AudioTimeStamp* inTimeStamp, UInt32 inBusNumber,
                             UInt32 inNumberFrames, AudioBufferList* ioData);

@interface AUPlaybackBackendTapTests : XCTestCase
@end

@implementation AUPlaybackBackendTapTests

- (void)testTapNotifyDeliversContiguousInterleavedFrames
{
    AUPlaybackBackend* backend = [AUPlaybackBackend new];
    MockLazySample* sample = [[MockLazySample alloc] initWithChannels:2];
    [backend setValue:sample forKey:@"sample"];

    __block unsigned long long receivedFrame = 0;
    __block NSUInteger receivedCount = 0;
    __block NSMutableArray<NSNumber*>* received = [NSMutableArray array];
    [backend setValue:[^(unsigned long long framePos, float* frameData, unsigned int frameCount) {
        receivedFrame = framePos;
        receivedCount = frameCount;
        for (unsigned int i = 0; i < frameCount * sample.sampleFormat.channels; i++) {
            [received addObject:@(frameData[i])];
        }
    } copy]
                  forKey:@"tapBlock"];

    [backend setValue:@(100ULL) forKey:@"tapFrame"];

    const UInt32 frames = 3;
    const UInt32 channels = (UInt32) sample.sampleFormat.channels;
    AudioBufferList list;
    list.mNumberBuffers = channels;
    AudioBuffer buffers[channels];
    float ch0[frames] = {1.0f, 2.0f, 3.0f};
    float ch1[frames] = {10.0f, 20.0f, 30.0f};
    buffers[0] = (AudioBuffer) {.mNumberChannels = 1, .mDataByteSize = sizeof(ch0), .mData = ch0};
    buffers[1] = (AudioBuffer) {.mNumberChannels = 1, .mDataByteSize = sizeof(ch1), .mData = ch1};
    list.mBuffers[0] = buffers[0];
    list.mBuffers[1] = buffers[1];

    AudioUnitRenderActionFlags flags = 0;
    OSStatus res = AUPlaybackTapNotify((__bridge void*) backend, &flags, NULL, 0, frames, &list);
    XCTAssertEqual(res, noErr);

    XCTAssertEqual(receivedFrame, 100ULL);
    XCTAssertEqual(receivedCount, (NSUInteger) frames);
    NSArray<NSNumber*>* expected = @[ @1.0f, @10.0f, @2.0f, @20.0f, @3.0f, @30.0f ];
    XCTAssertEqualObjects(received, expected);
    XCTAssertEqual([[backend valueForKey:@"tapFrame"] unsignedLongLongValue], 100 + frames);
}

@end
