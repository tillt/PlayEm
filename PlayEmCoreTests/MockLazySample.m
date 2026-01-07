//  MockLazySample.m
//  PlayEmCoreTests
//
//  Created for unit testing without real audio I/O.
//

#import "MockLazySample.h"

@implementation MockLazySample

- (instancetype)initWithChannels:(NSUInteger)channels
{
    self = [super init];
    if (self) {
        self.sampleFormat = (SampleFormat) {.rate = 44100.0, .channels = (int) channels};
    }
    return self;
}

// Override required designated initializer to satisfy superclass contract, but
// unused in tests.
- (id)initWithPath:(NSString*)path error:(NSError**)error
{
    return [self initWithChannels:1];
}

@end
