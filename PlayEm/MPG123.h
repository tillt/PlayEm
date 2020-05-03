//
//  MPG123.h
//  PlayEm
//
//  Created by Till Toenshoff on 10.04.20.
//  Copyright © 2020 Till Toenshoff. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MPG123 : NSObject

- (BOOL)open:(NSString *)path error:(NSError **)error;
- (void)close;
- (BOOL)decode:(size_t (^) (unsigned char *buffer, size_t size))outputHandler;
- (BOOL)decodeToFile:(NSString *)path;

@property (assign, nonatomic) int framesize;
@property (assign, nonatomic) int channels;
@property (assign, nonatomic) int encoding;
@property (assign, nonatomic) long rate;

@end

NS_ASSUME_NONNULL_END
