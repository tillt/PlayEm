//
//  ITLibMediaItem+TTAdditions.m
//  PlayEm
//
//  Created by Till Toenshoff on 23.09.20.
//  Copyright © 2020 Till Toenshoff. All rights reserved.
//

#import "ITLibMediaItem+TTAdditionsh.h"

@implementation ITLibMediaItem (TTAdditions)

//- (NSComparisonResult)compareGenre:(ITLibMediaItem*)otherObject
//{
//    return [self.genre compare:otherObject.genre];
//}

- (NSString *)description
{
    return [NSString stringWithFormat:@"Title: '%@' --- Tempo:%d, Location: %@", 
            self.title,
            (unsigned int)self.beatsPerMinute,
            self.location];
}

@end
