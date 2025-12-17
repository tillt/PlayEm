//
//  TrackList+ChapterForge.hpp
//  PlayEm
//
//  Created by Till Toenshoff on 12/11/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//
#import "TimedMediaMetaData+ChapterForge.hpp"
#import "TrackList.h"
#import "MediaMetaData+ChapterForge.hpp"
#import "TrackList+ChapterForge.hpp"

#include "chapterforge.hpp"

typedef NSDictionary<NSNumber*,StructuredMetaData*> ChapteredMetaData;

NS_ASSUME_NONNULL_BEGIN

void populateChapters(TrackList* tl,
                      std::vector<ChapterTextSample> &textChapters,
                      std::vector<ChapterTextSample> &urlChapters,
                      std::vector<ChapterImageSample> &imageChapters,
                      FrameToSeconds frameToSeconds);

@interface TrackList (ChapterForge)

- (void)updateWithChapteredMetdaData:(ChapteredMetaData*)chaptered;
- (ChapteredMetaData*)readChapterTextTracksFromAVAsset:(AVAsset*)asset framerate:(long)rate error:(NSError*__autoreleasing  _Nullable* _Nullable)error;

@end

NS_ASSUME_NONNULL_END
