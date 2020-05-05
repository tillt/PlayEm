//
//  ITLibMediaItem+ITLibMediaItem_compare.m
//  PlayEm
//
//  Created by Till Toenshoff on 23.09.20.
//  Copyright © 2020 Till Toenshoff. All rights reserved.
//

#import "ITLibMediaItem+compare.h"

@implementation ITLibMediaItem (ITLibMediaItem_compare)

- (NSComparisonResult)compareGenre:(ITLibMediaItem*)otherObject
{
    return [self.genre compare:otherObject.genre];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"Title: '%@' --- Location: %@", self.title, self.location];
}

@end
