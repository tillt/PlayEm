//
//  MediaMetaData+TrackList.h
//  PlayEmCore
//
//  Created by Till Toenshoff on 1/14/26.
//  Copyright © 2026 Till Toenshoff. All rights reserved.
//

#import "MediaMetaData.h"

NS_ASSUME_NONNULL_BEGIN

@interface MediaMetaData (TrackList)

- (void)recoverTracklistWithCallback:(void (^)(BOOL, NSError*))callback;
- (void)recoverSidecarWithCallback:(void (^)(BOOL, NSError*))callback;
- (BOOL)storeTracklistWithError:(NSError* __autoreleasing _Nullable*)error;
- (NSString*)readableTracklistWithFrameEncoder:(FrameToString)encoder;
- (BOOL)exportTracklistToFile:(NSURL*)url frameEncoder:(FrameToString)encoder error:(NSError* __autoreleasing _Nullable*)error;
- (NSURL*)trackListURL;

@end

NS_ASSUME_NONNULL_END
