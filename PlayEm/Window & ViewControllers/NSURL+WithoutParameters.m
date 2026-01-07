//
//  NSURL+WithoutParameters.m
//  PlayEm
//
//  Created by Till Toenshoff on 14.06.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "NSURL+WithoutParameters.h"

@implementation NSURL (WithoutParameters)

- (NSURL*)URLWithoutParameters
{
    NSURLComponents* components = [NSURLComponents componentsWithURL:self resolvingAgainstBaseURL:NO];
    components.query = nil;
    return [components URL];
}

@end
