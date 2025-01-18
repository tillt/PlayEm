//
//  VisualSample.m
//  PlayEm
//
//  Created by Till Toenshoff on 19.04.20.
//  Copyright © 2020 Till Toenshoff. All rights reserved.
//

#import "VisualSample.h"
#import "LazySample.h"
#import "IndexedBlockOperation.h"
#import "VisualPair.h"
#import "ConcurrentAccessDictionary.h"
#import "ProfilingPointsOfInterest.h"

// TODO: Implement DynamicReducedVisualSample
// Implementation does two things at the same time - it immediately produces the requested
// tiles while additionally reducing the total amount of source samples towards something
// resembling a biggest possible visual representation width - ie 8192 pairs.

@interface VisualSample()
{
    // FIXME: losing the error from the previous window
}

@property (assign, nonatomic) size_t tileWidth;
@property (assign, nonatomic) double framesPerPixel;
@property (strong, nonatomic) ConcurrentAccessDictionary* operations;
@property (strong, nonatomic) NSMutableArray<NSMutableData*>* sampleBuffers;

@end

@implementation VisualSample
{
    dispatch_queue_t _calculations_queue;
}

- (id)initWithSample:(LazySample*)sample pixelPerSecond:(double)pixelPerSecond tileWidth:(size_t)tileWidth
{
    self = [super init];
    if (self) {
        _sample = sample;
        assert(pixelPerSecond);
        _pixelPerSecond = pixelPerSecond;
        _operations = [ConcurrentAccessDictionary new];
        _framesPerPixel = (double)sample.rate / pixelPerSecond;
        _tileWidth = tileWidth;
        assert(_framesPerPixel >= 1.0);
        _sampleBuffers = [NSMutableArray array];

        unsigned long long framesNeeded = tileWidth * _framesPerPixel;
        for (int channel = 0; channel < sample.channels; channel++) {
            NSMutableData* buffer = [NSMutableData dataWithCapacity:framesNeeded * _sample.frameSize];
            [_sampleBuffers addObject:buffer];
        }

        dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0);
        const char* queue_name = [[NSString stringWithFormat:@"VisualSample%fPPS", pixelPerSecond] cStringUsingEncoding:NSStringEncodingConversionAllowLossy];
        _calculations_queue = dispatch_queue_create(queue_name, attr);
    }
    return self;
}

- (void)dealloc
{
    NSArray* keys = [_operations allKeys];
    for (id key in keys) {
        IndexedBlockOperation* operation = [_operations objectForKey:key];
        [operation cancelAndWait];
    }
}

- (void)setPixelPerSecond:(double)pixelPerSecond
{
    if (_pixelPerSecond == pixelPerSecond) {
        return;
    }

    NSArray* keys = [_operations allKeys];
    for (id key in keys) {
        IndexedBlockOperation* operation = [_operations objectForKey:key];
        [operation cancelAndWait];
    }

    _pixelPerSecond = pixelPerSecond;
    assert(_pixelPerSecond > 0.0f);

    _framesPerPixel = (double)_sample.rate / pixelPerSecond;
    assert(_framesPerPixel >= 1.0);
    
    [_operations removeAllObjects];
    
    NSLog(@"removed all operations - clear start...");
}

- (size_t)width
{
    return ceil((float)_sample.frames / _framesPerPixel);
}

- (NSData* _Nullable)visualsFromOrigin:(size_t)origin
{
    os_signpost_interval_begin(pointsOfInterest, POIVisualsFromOrigin, "VisualsFromOrigin");
    
    size_t pageIndex = origin / _tileWidth;

    NSNumber* pageNumber = [NSNumber numberWithLong:pageIndex];

    IndexedBlockOperation* operation = [_operations objectForKey:pageNumber];

    if (operation == nil) {
        os_signpost_interval_end(pointsOfInterest, POIVisualsFromOrigin, "VisualsFromOrigin", "unknown");
        return nil;
    }

    if (!operation.isFinished) {
        os_signpost_interval_end(pointsOfInterest, POIVisualsFromOrigin, "VisualsFromOrigin", "unfinished");
        return nil;
    }

    [_operations removeObjectForKey:pageNumber];

    os_signpost_interval_end(pointsOfInterest, POIVisualsFromOrigin, "VisualsFromOrigin", "normal");

    return operation.data;
}

- (double)framesPerPixel
{
    return _framesPerPixel;
}

- (void)garbageCollectOperationsOutsideOfWindow:(size_t)window width:(size_t)width
{
    const size_t prerenderTileDistance = 2;

    size_t left = 0;
    if ((window / _tileWidth) >= prerenderTileDistance) {
        left = (window / _tileWidth) - prerenderTileDistance;
    }
    size_t right = prerenderTileDistance + ((window + width) / _tileWidth);
    
    NSArray* keys = [_operations allKeys];
    for (NSNumber* pageNumber in keys) {
        if (pageNumber.integerValue < left || pageNumber.integerValue > right) {
            IndexedBlockOperation* operation = [_operations objectForKey:pageNumber];
            [operation cancelAndWait];
            [_operations removeObjectForKey:pageNumber];
            NSLog(@"garbage collecting tile %@", pageNumber);
        }
    }
}

- (void)prepareVisualsFromOrigin:(size_t)origin width:(size_t)width window:(size_t)window total:(size_t)totalWidth callback:(nonnull void (^)(void))callback
{
    os_signpost_interval_begin(pointsOfInterest, POIPrepareVisualsFromOrigin, "PrepareVisualsFromOrigin");
    
    [self garbageCollectOperationsOutsideOfWindow:window width:totalWidth];
    [self runOperationWithOrigin:origin width:width callback:callback];
    
    os_signpost_interval_end(pointsOfInterest, POIPrepareVisualsFromOrigin, "PrepareVisualsFromOrigin");
}

- (IndexedBlockOperation*)runOperationWithOrigin:(size_t)origin width:(size_t)width callback:(nonnull void (^)(void))callback
{
    assert(origin < self.width);

    size_t pageIndex = origin / _tileWidth;

    NSNumber* pageNumber = [NSNumber numberWithLong:pageIndex];
    IndexedBlockOperation* blockOperation = [_operations objectForKey:pageNumber];
    if (blockOperation != nil) {
        NSLog(@"asking for the same operation again on page %ld", pageIndex);
        return blockOperation;
    }
    blockOperation = [[IndexedBlockOperation alloc] initWithIndex:pageIndex];
    //NSLog(@"adding %ld", pageIndex);
    IndexedBlockOperation* __weak weakOperation = blockOperation;
    //ConcurrentAccessDictionary* __weak weakOperations = _operations;
    VisualSample* __weak weakSelf = self;

    [_operations setObject:blockOperation forKey:[NSNumber numberWithLong:pageIndex]];
    
    [blockOperation run:^(void){
        if (weakOperation.isCancelled || weakSelf.sample.channels == 0) {
            return;
        }
        assert(!weakOperation.isFinished);
        
        double counter = 0.0;
        unsigned long int framesNeeded = width * weakSelf.framesPerPixel;

        float* data[weakSelf.sample.channels];
        
        for (int channel = 0; channel < weakSelf.sample.channels; channel++) {
            data[channel] = (float*)((NSMutableData*)weakSelf.sampleBuffers[channel]).bytes;
        }
     
        //NSLog(@"we got room for %ld bytes", width * sizeof(VisualPair));
        NSMutableData* buffer = [NSMutableData dataWithLength:width * sizeof(VisualPair)];
        assert(buffer);

        VisualPair* storage = (VisualPair*)buffer.mutableBytes;
        assert(storage);

        const int channels = weakSelf.sample.channels;
        
        unsigned long long displaySampleFrameIndexOffset = origin * weakSelf.framesPerPixel;
        if (displaySampleFrameIndexOffset >= weakSelf.sample.frames) {
            return;
        }
        unsigned long long displayFrameCount = MIN(framesNeeded, weakSelf.sample.frames - displaySampleFrameIndexOffset);

        // This may block for a loooooong time!
        [weakSelf.sample rawSampleFromFrameOffset:displaySampleFrameIndexOffset
                                           frames:displayFrameCount
                                          outputs:data];

        //NSLog(@"This block of %lld frames is used to create visuals for %ld pixels", displayFrameCount, width);
        weakOperation.index = pageIndex;
        weakOperation.data = buffer;

        unsigned long int frameIndex = 0;

        double negativeSum = 0.0;
        double positiveSum = 0.0;
        unsigned int positiveCount = 0;
        unsigned int negativeCount = 0;

        while(frameIndex < displayFrameCount) {
            negativeSum = 0.0;
            positiveSum = 0.0;
            positiveCount = 0;
            negativeCount = 0;
            do {
                if (weakOperation.isCancelled) {
                    break;
                }
                
                if (frameIndex >= displayFrameCount) {
                   break;
                }
                   
                double s = 0.0;
                for (int channel = 0; channel < channels; channel++) {
                    s += data[channel][frameIndex];
                }
                s /= channels;

                frameIndex++;
                counter += 1.0;
                
                if (s >= 0) {
                    positiveSum += s;
                    positiveCount++;
                } else {
                    negativeSum += s;
                    negativeCount++;
                }
            } while (counter < weakSelf.framesPerPixel);

            if (weakOperation.isCancelled) {
                break;
            }

            counter -= weakSelf.framesPerPixel;

            storage->negativeAverage = negativeCount > 0 ? negativeSum / negativeCount : 0.0;
            storage->positiveAverage = positiveSum > 0 ? positiveSum / positiveCount : 0.0;
            
            ++storage;
        };
        weakOperation.isFinished = !weakOperation.isCancelled;
        callback();
    }];

    dispatch_async(_calculations_queue, blockOperation.dispatchBlock);

    return blockOperation;
}

@end
