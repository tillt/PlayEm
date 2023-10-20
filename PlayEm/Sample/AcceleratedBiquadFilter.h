//
//  AcceleratedBiquadFilter.h
//  PlayEm
//
//  Created by Till Toenshoff on 06.10.23.
//  Copyright © 2023 Till Toenshoff. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class LazySample;

@interface AcceleratedBiquadFilter : NSObject

@property (strong, nonatomic) LazySample* sample;

@end

NS_ASSUME_NONNULL_END
