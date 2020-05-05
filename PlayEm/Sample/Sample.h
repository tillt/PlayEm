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

@property (assign, nonatomic) int channels;
@property (assign, nonatomic) long rate;
@property (assign, nonatomic) int encoding;
@property (assign, nonatomic, readonly) unsigned long long size;
@property (assign, nonatomic, readonly) unsigned long long frames;
@property (assign, nonatomic, readonly) size_t frameSize;
@property (assign, nonatomic, readonly) NSTimeInterval duration;
@property (copy, nonatomic, readonly) NSString* description;

- (id)initWithChannels:(int)channels rate:(long)rate encoding:(int)encoding;
- (unsigned long long)addSampleData:(void *)buffer size:(unsigned long long)size;

@end

NS_ASSUME_NONNULL_END
