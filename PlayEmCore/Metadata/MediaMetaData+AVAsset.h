//
//  MediaMetaData+AVAsset.h
//  PlayEm
//
//  Created by Till Toenshoff on 25.02.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#import "MediaMetaData.h"

NS_ASSUME_NONNULL_BEGIN

@class AVAsset;
@class AVMetadataItem;

@interface MediaMetaData (AVAsset)

+ (NSDictionary*)id3GenreMap;
+ (MediaMetaData*)mediaMetaDataWithMetadataItems:(NSArray<AVMetadataItem*>*)items;
+ (long)sampleRateForAsset:(AVAsset*)asset;

- (BOOL)readFromAVAsset:(AVAsset*)asset error:(NSError**)error;

//- (BOOL)readChapterMarksFromMP4FileWithError:(NSError**)error;
- (void)readChaperMarksFromMP4FileWithCallback:(void (^)(BOOL, NSError*))callback;
- (void)readChapterMarksFromAVAsset:(AVAsset*)asset callback:(void (^)(BOOL, NSError*))callback;

- (BOOL)readFromMP4FileWithError:(NSError**)error;
//- (BOOL)writeChaperMarksToMP4FileWithError:(NSError**)error;

//- (void)addChaptersToAudioFileAtURL:(NSURL *)inputURL
//                          outputURL:(NSURL *)outputURL;

- (void)updateWithMetadataItem:(AVMetadataItem*)item;
/*
- (void)addChapterMarksToMP4AtURL:(NSURL*)inputURL
                        outputURL:(NSURL*)outputURL
                       completion:(void (^)(BOOL success, NSError*
error))completion;

*/
@end

NS_ASSUME_NONNULL_END
