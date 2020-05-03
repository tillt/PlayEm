//
//  VisualSample.h
//  PlayEm
//
//  Created by Till Toenshoff on 19.04.20.
//  Copyright © 2020 Till Toenshoff. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef struct {
    double negativeMax;
    double positiveMax;
} VisualPair;

@class Sample;

@interface VisualSample : NSObject

@property (strong, nonatomic) Sample *sample;
@property (strong, nonatomic) NSMutableData *buffer;

- (id)initWithSample:(Sample *)sample;

@end

NS_ASSUME_NONNULL_END
