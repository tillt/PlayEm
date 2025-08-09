//
//  Sample.m
//  PlayEm
//
//  Created by Till Toenshoff on 11.04.20.
//  Copyright © 2020 Till Toenshoff. All rights reserved.
//

#import "Sample.h"


// Our average and therefor default song sample data shall be of 30mb in size.
const size_t kAverageSampleSize = 30 * 1024 * 1024;

@interface Sample ()
@end


@implementation Sample

- (id)initWithChannels:(int)channels rate:(long)rate
{
    self = [super init];
    if (self) {
        _data = [[NSMutableData alloc] initWithCapacity:kAverageSampleSize];
        _frameSize = sizeof(float) * channels;  // Hardcoded float-sized samples.
    }
    return self;
}

- (unsigned long long)addSampleData:(void*)buffer size:(unsigned long long)size
{
    [_data appendBytes:buffer length:size];
    return size;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"Duration: %f seconds, Buffer: %@",
            self.duration,
            _data];
}

- (NSTimeInterval)duration
{
    return (NSTimeInterval)((double)_data.length / (_sampleFormat.rate * _frameSize));
}

- (unsigned long long)size
{
    return _data.length;
}

- (unsigned long long)frames
{
    return _data.length / _frameSize;
}

@end
