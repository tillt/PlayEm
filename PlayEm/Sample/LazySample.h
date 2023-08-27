//
//  LazySample.h
//  PlayEm
//
//  Created by Till Toenshoff on 01.01.21.
//  Copyright © 2021 Till Toenshoff. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class AVAudioFormat;

@interface LazySample : NSObject

@property (assign, nonatomic) int channels;
@property (assign, nonatomic) long rate;
@property (assign, nonatomic) int encoding;
@property (readonly, nonatomic) NSTimeInterval duration;
@property (readonly, assign, nonatomic) unsigned long long decodedFrames;

//@property (assign, nonatomic) unsigned long long size;
@property (assign, nonatomic, readonly) unsigned long long frames;
@property (assign, nonatomic, readonly) unsigned int frameSize;

@property (readonly, assign, nonatomic) AVAudioFormat* format;

- (id)initWithPath:(NSString*)path error:(NSError**)error;

- (unsigned long long)rawSampleFromFrameOffset:(unsigned long long)offset frames:(unsigned long long)frames outputs:(float * const _Nonnull * _Nullable)outputs;
- (unsigned long long)rawSampleFromFrameOffset:(unsigned long long)offset frames:(unsigned long long)frames data:(float *)data;

- (void)decodeAsyncWithCallback:(void (^)(void))callback;
- (void)abortDecode;

- (void)dumpToFile;

- (NSTimeInterval)timeForFrame:(unsigned long long)frame;


//TODO: NSEnumerator Support


@end

NS_ASSUME_NONNULL_END
