//
//  TrackList+ChapterForge.hpp
//  PlayEm
//
//  Created by Till Toenshoff on 12/11/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//
#include "ChapterForge/chapterforge.hpp"
#import "MediaMetaData+ChapterForge.hpp"
#import "TimedMediaMetaData+ChapterForge.hpp"
#import "TrackList+ChapterForge.hpp"
#import "TrackList.h"

typedef NSDictionary<NSNumber*, StructuredMetaData*> ChapteredMetaData;

NS_ASSUME_NONNULL_BEGIN

void populateChapters(TrackList* tl, std::vector<ChapterTextSample>& textChapters, std::vector<ChapterTextSample>& urlChapters,
                      std::vector<ChapterImageSample>& imageChapters, FrameToSeconds frameToSeconds);

@interface TrackList (ChapterForge)

- (void)updateWithChapteredMetdaData:(ChapteredMetaData*)chaptered;
- (ChapteredMetaData* _Nullable)readChapterTextTracksFromAVAsset:(AVAsset*)asset
                                                       framerate:(long)rate
                                                           error:(NSError* __autoreleasing _Nullable* _Nullable)error;

@end

NS_ASSUME_NONNULL_END
