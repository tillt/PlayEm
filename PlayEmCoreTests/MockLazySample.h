//  MockLazySample.h
//  PlayEmCoreTests
//
//  Lightweight stub for injecting channel count into filters without real I/O.
//

#import <Foundation/Foundation.h>

#import "LazySample.h"

@interface MockLazySample : LazySample

/// Convenience initializer to set just the channel count for tests.
- (instancetype)initWithChannels:(NSUInteger)channels;

@end
