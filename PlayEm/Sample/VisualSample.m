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
#import "VisualPairContext.h"
#import "ConcurrentAccessDictionary.h"
#import "ProfilingPointsOfInterest.h"
#import "EnergyDetector.h"
// TODO: Implement DynamicReducedVisualSample
// Implementation does two things at the same time - it immediately produces the requested
// tiles while additionally reducing the total amount of source samples towards something
// resembling a biggest possible visual representation width - ie 8192 pairs.

@interface VisualSample()
{
    // FIXME: losing the error from the previous window
}

@property (assign, nonatomic) size_t tileWidth;
@property (assign, nonatomic) size_t reducedTotalWidth;
@property (assign, nonatomic) double framesPerPixel;
@property (strong, nonatomic) ConcurrentAccessDictionary* operations;
@property (assign, nonatomic) size_t framesPerReducedValue;
@property (assign, nonatomic) size_t reductionWindowFrame;
@property (assign, nonatomic) VisualPairContext reductionPairContext;

@property (strong, nonatomic) NSMutableData* reducedSample;
@property (strong, nonatomic) NSMutableArray<NSMutableData*>* sampleBuffers;
@property (strong, nonatomic) EnergyDetector* energy;

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
        _energy = [EnergyDetector new];
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
        
        _reducedTotalWidth = 0;
        _reducedSample = nil;
        _framesPerReducedValue = 0;
        _reductionWindowFrame = 0.0;
    }
    return self;
}

- (id)initWithSample:(LazySample*)sample pixelPerSecond:(double)pixelPerSecond tileWidth:(size_t)tileWidth reducedWidth:(size_t)reducedMaxWidth
{
    self = [self initWithSample:sample pixelPerSecond:pixelPerSecond tileWidth:tileWidth];
    if (reducedMaxWidth > 0) {
        _framesPerReducedValue = _sample.frames / reducedMaxWidth;
        _reducedTotalWidth = _sample.frames / _framesPerReducedValue;
        NSLog(@"frames per reduced value: %ld (total %ld)", _framesPerReducedValue, _reducedTotalWidth);
        _reducedSample = [NSMutableData new];
        _reductionPairContext = (VisualPairContext){};
    }
    return self;
}

- (void)allAbort
{
    NSLog(@"aborting all operations...");
    NSArray* keys = [_operations allKeys];
    for (id key in keys) {
        IndexedBlockOperation* operation = [_operations objectForKey:key];
        if (!operation.isFinished) {
            [operation cancel];
        }
    }
    for (id key in keys) {
        IndexedBlockOperation* operation = [_operations objectForKey:key];
        if (!operation.isFinished) {
            [operation wait];
        }
    }
}

- (void)dealloc
{
    [self allAbort];
}

- (void)setPixelPerSecond:(double)pixelPerSecond
{
    if (_pixelPerSecond == pixelPerSecond) {
        return;
    }

    [self allAbort];

    NSLog(@"removing all operations...");
    [_operations removeAllObjects];
    NSLog(@"removed all operations - clear start!");

    _pixelPerSecond = pixelPerSecond;
    assert(_pixelPerSecond > 0.0f);

    _framesPerPixel = (double)_sample.rate / pixelPerSecond;
    assert(_framesPerPixel >= 1.0);
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
            [operation cancel];
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

// TODO(tillt): Generalize this to reuse for both, the quick-render as well as the
// initial render.
- (void)appendToReducedSampleWithValue:(double)s context:(VisualPairContext*)context
{
    // Store once we get a complete window done.
    if (_reductionWindowFrame >= _framesPerReducedValue) {
        VisualPair pair = {
            .negativeAverage = context->negativeCount > 0 ? context->negativeSum / context->negativeCount : 0.0,
            .positiveAverage = context->positiveSum > 0 ? context->positiveSum / context->positiveCount : 0.0
        };

        [_reducedSample appendBytes:&pair length:sizeof(VisualPair)];

        *context = (VisualPairContext){
            .negativeSum = 0.0,
            .positiveSum = 0.0,
            .negativeCount = 0,
            .positiveCount = 0
        };

        _reductionWindowFrame = 0;
    }

    // Put value into either positive or negative bin.
    if (s >= 0) {
        context->positiveSum += s;
        context->positiveCount++;
    } else {
        context->negativeSum += s;
        context->negativeCount++;
    }

    _reductionWindowFrame++;
}

- (IndexedBlockOperation*)runOperationWithOrigin:(size_t)origin width:(size_t)width callback:(nonnull void (^)(void))callback
{
    assert(origin < self.width);
    
    size_t pageIndex = origin / _tileWidth;
    
    NSNumber* pageNumber = [NSNumber numberWithLong:pageIndex];
    IndexedBlockOperation* blockOperation = [_operations objectForKey:pageNumber];
    if (blockOperation != nil) {
        // While in theory this should not happen, it does for example when
        NSLog(@"asking for the same operation again on page %ld", pageIndex);
        return blockOperation;
    }
    blockOperation = [[IndexedBlockOperation alloc] initWithIndex:pageIndex];
    IndexedBlockOperation* __weak weakOperation = blockOperation;
    VisualSample* __weak weakSelf = self;
    
    VisualPairContext* reductionPairContext = &_reductionPairContext;
    BOOL reduce = NO;
    BOOL fromReduced = NO;
    if (_reducedTotalWidth > 0) {
        if (_reducedSample.length < _reducedTotalWidth) {
            reduce = YES;
        } else {
            NSLog(@"from reduced!");
            fromReduced = YES;
        }
        reduce = _reducedSample.length < _reducedTotalWidth;
    }

    [_operations setObject:blockOperation forKey:[NSNumber numberWithLong:pageIndex]];
    
    [blockOperation run:^(void){
        const int channels = weakSelf.sample.channels;

        if (weakOperation.isCancelled || channels == 0) {
            return;
        }
        assert(!weakOperation.isFinished);
        
        double counter = 0.0;
        const unsigned long int framesNeeded = width * weakSelf.framesPerPixel;

        float* data[channels];
        
        for (int channel = 0; channel < channels; channel++) {
            data[channel] = (float*)((NSMutableData*)weakSelf.sampleBuffers[channel]).bytes;
        }
     
        //NSLog(@"we got room for %ld bytes", width * sizeof(VisualPair));
        NSMutableData* buffer = [NSMutableData dataWithLength:width * sizeof(VisualPair)];
        assert(buffer);

        VisualPair* storage = (VisualPair*)buffer.mutableBytes;
        assert(storage);

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
        
        VisualPairContext context;

        while(frameIndex < displayFrameCount) {
            context = (VisualPairContext){
                .negativeSum = 0.0,
                .positiveSum = 0.0,
                .negativeCount = 0,
                .positiveCount = 0
            };

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
                
                if (s >= 0) {
                    context.positiveSum += s;
                    context.positiveCount++;
                } else {
                    context.negativeSum += s;
                    context.negativeCount++;
                }

                if (reduce) {
                    [weakSelf appendToReducedSampleWithValue:s context:reductionPairContext];
                }

                frameIndex++;
                counter += 1.0;
            } while (counter < weakSelf.framesPerPixel);

            if (weakOperation.isCancelled) {
                break;
            }

            counter -= weakSelf.framesPerPixel;

            *storage = (VisualPair) {
                .negativeAverage = context.negativeCount > 0 ? context.negativeSum / context.negativeCount : 0.0,
                .positiveAverage = context.positiveSum > 0 ? context.positiveSum / context.positiveCount : 0.0
            };
            ++storage;
        };
        
        weakOperation.isFinished = !weakOperation.isCancelled;
        callback();
    }];

    dispatch_async(_calculations_queue, blockOperation.dispatchBlock);

    return blockOperation;
}

@end
