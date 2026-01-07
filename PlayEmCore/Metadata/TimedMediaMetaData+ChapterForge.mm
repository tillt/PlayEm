//
//  TimedMediaMetaData+ChapterForge.mm
//  PlayEm
//
//  Created by Till Toenshoff on 12/16/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//
#import "TimedMediaMetaData+ChapterForge.hpp"
#import "TimedMediaMetaData.h"

//
NSString* const kStructuredMetaTitleKey = @"title";
NSString* const kStructuredMetaArtistKey = @"artist";
NSString* const kStructuredMetaURLKey = @"url";

@implementation TimedMediaMetaData (ChapterForge)

- (id)initWithChapteredMetaData:(StructuredMetaData*)structured frame:(NSNumber*)frame
{
    self = [super init];
    if (self) {
        self.meta = [MediaMetaData mediaMetaDataWithStructuredMeta:structured];
        self.frame = frame;
    }
    return self;
}

- (void)updateWithStructuredMeta:(StructuredMetaData*)structured frame:(NSNumber*)frame
{
    [self.meta updateWithStructuredMeta:structured];
    self.frame = frame;
}

@end
