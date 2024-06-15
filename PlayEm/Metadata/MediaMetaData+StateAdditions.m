//
//  MediaMetaData+StateAdditions.m
//  PlayEm
//
//  Created by Till Toenshoff on 14.06.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#import "MediaMetaData+StateAdditions.h"

@implementation MediaMetaData (StateAdditions)

static NSURL* activeLocation = nil;

+ (void)setActiveLocation:(NSURL*)url
{
    activeLocation = url;
}

- (BOOL)active
{
    return [self.location.absoluteString isEqualToString:activeLocation.absoluteString];
}

@end
