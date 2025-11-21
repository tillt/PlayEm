//
//  LazySample.h
//  PlayEm
//
//  Created by Till Toenshoff on 01.01.21.
//  Copyright © 2021 Till Toenshoff. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SampleFormat.h"
NS_ASSUME_NONNULL_BEGIN

@class AVAudioFormat;
@class AVAudioFile;

@interface LazySample : NSObject

@property (assign, nonatomic) SampleFormat sampleFormat;
@property (readonly, nonatomic) NSTimeInterval duration;
@property (readonly, assign, nonatomic) unsigned long long decodedFrames;

@property (strong, nonatomic) AVAudioFile* source;

@property (assign, nonatomic, readonly) unsigned long long frames;
@property (assign, nonatomic, readonly) unsigned int frameSize;

- (id)initWithPath:(NSString*)path error:(NSError**)error;

- (unsigned long long)rawSampleFromFrameOffset:(unsigned long long)offset
                                        frames:(unsigned long long)frames
                                       outputs:(float * const _Nonnull * _Nullable)outputs;
- (unsigned long long)rawSampleFromFrameOffset:(unsigned long long)offset
                                        frames:(unsigned long long)frames
                                          data:(float *)data;

- (void)dumpToFile;

- (NSTimeInterval)timeForFrame:(unsigned long long)frame;
- (NSString*)beautifulTimeWithFrame:(unsigned long long)frame;
- (NSString*)cueTimeWithFrame:(unsigned long long)frame;

- (void)addLazyPageIndex:(unsigned long long)pageIndex
                channels:(NSArray<NSData*>*)channels;

@end

NS_ASSUME_NONNULL_END
