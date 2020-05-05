//
//  ITLibMediaItem+ITLibMediaItem_compare.h
//  PlayEm
//
//  Created by Till Toenshoff on 23.09.20.
//  Copyright © 2020 Till Toenshoff. All rights reserved.
//

#import <iTunesLibrary/iTunesLibrary.h>
#import <iTunesLibrary/ITLibMediaItem.h>

NS_ASSUME_NONNULL_BEGIN

@interface ITLibMediaItem (ITLibMediaItem_compare)

- (NSComparisonResult)compareGenre:(ITLibMediaItem*)otherObject;

@end

NS_ASSUME_NONNULL_END
