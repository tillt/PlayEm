//
//  TrackList.h
//  PlayEm
//
//  Created by Till Toenshoff on 9/27/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class IdentifiedTrack;

typedef NSString* _Nonnull (^FrameToString)(unsigned long long frame);

@interface TrackListIterator : NSObject

@property (strong, nonatomic) NSArray<NSNumber*>* keys;
@property (assign, nonatomic) size_t index;
@property (readonly, nonatomic) unsigned long long frame;

@end


@interface TrackList : NSObject


- (BOOL)writeToFile:(NSURL*)url error:(NSError**)error;
- (BOOL)readFromFile:(NSURL*)url error:(NSError**)error;

- (NSString*)cueTracksWithFrameEncoder:(FrameToString)encoder;

- (void)addTrack:(IdentifiedTrack*)track;
- (void)removeTrackAtFrame:(unsigned long long)frame;
- (IdentifiedTrack*)trackAtFrame:(unsigned long long)frame;
- (NSArray<IdentifiedTrack*>*)tracks;
- (NSArray<NSNumber*>*)frames;

- (unsigned long long)firstTrackFrame:(TrackListIterator *_Nonnull*_Nullable)iterator;
- (unsigned long long)nextTrackFrame:(nonnull TrackListIterator *)iterator;

@end

NS_ASSUME_NONNULL_END
