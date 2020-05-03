//
//  Sample.h
//  PlayEm
//
//  Created by Till Toenshoff on 11.04.20.
//  Copyright © 2020 Till Toenshoff. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface Sample : NSObject

@property (strong, nonatomic) NSMutableData *data;
@property (strong, nonatomic) NSMutableArray *velocityMap;

@property (assign, nonatomic) int channels;
@property (assign, nonatomic) long rate;
@property (assign, nonatomic) int encoding;

- (id)initWithChannels:(int)channels rate:(long)rate encoding:(int)encoding;
- (size_t)addSampleData:(unsigned char *)buffer size:(size_t)size;
- (NSString *)description;
- (NSTimeInterval)duration;
- (size_t)size;


@end

NS_ASSUME_NONNULL_END
