//
//  SampleFormat.h
//  PlayEm
//
//  Created by Till Toenshoff on 8/2/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//
#import <Foundation/Foundation.h>

#ifndef SampleFormat_h
#define SampleFormat_h

NS_ASSUME_NONNULL_BEGIN

typedef struct {
    int channels;
    long rate;
} SampleFormat;

NS_ASSUME_NONNULL_END

#endif
