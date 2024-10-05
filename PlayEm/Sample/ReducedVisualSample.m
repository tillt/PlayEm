//
//  ReducedVisualSample.m
//  PlayEm
//
//  Created by Till Toenshoff on 29.09.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#import "ReducedVisualSample.h"
#import "LazySample.h"
#import "IndexedBlockOperation.h"
#import "VisualPair.h"
#import "ConcurrentAccessDictionary.h"
#import "ProfilingPointsOfInterest.h"

@interface ReducedVisualSample()
{
    // FIXME: losing the error from the previous window
}

@property (strong, nonatomic) NSMutableArray<NSMutableData*>* sampleBuffers;
@property (strong, nonatomic) NSMutableData* precalcBuffer;

@end

const size_t kPrecalcPoolSize = 8192;
const size_t kSampleBufferFrameCount = 4 * 16384;

@implementation ReducedVisualSample
{
    dispatch_queue_t _calculations_queue;
}

- (id)initWithSample:(LazySample*)sample pixelPerSecond:(double)pixelPerSecond tileWidth:(size_t)tileWidth
{
    self = [super initWithSample:sample pixelPerSecond:pixelPerSecond tileWidth:tileWidth];
    if (self) {
        _sampleBuffers = [NSMutableArray array];

        //unsigned long long framesNeeded = tileWidth * _framesPerPixel;
        for (int channel = 0; channel < sample.channels; channel++) {
            NSMutableData* buffer = [NSMutableData dataWithCapacity:kSampleBufferFrameCount * sample.frameSize];
            [_sampleBuffers addObject:buffer];
        }
        
        _precalcBuffer = [NSMutableData dataWithCapacity:kPrecalcPoolSize * sizeof(VisualPair)];

        dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0);
        const char* queue_name = [@"ReducedVisualSample" cStringUsingEncoding:NSStringEncodingConversionAllowLossy];
        _calculations_queue = dispatch_queue_create(queue_name, attr);
    }
    return self;
}

- (void)dealloc
{
}

- (void)prepareWithCallback:(nonnull void (^)(void))callback
{
    [self runPrecalcWithCallback:callback];
}

- (IndexedBlockOperation*)runPrecalcWithCallback:(nonnull void (^)(void))callback
{
    IndexedBlockOperation* blockOperation = [[IndexedBlockOperation alloc] initWithIndex:0];
    //NSLog(@"adding %ld", pageIndex);
    IndexedBlockOperation* __weak weakOperation = blockOperation;
    //ConcurrentAccessDictionary* __weak weakOperations = _operations;
    ReducedVisualSample* __weak weakSelf = self;

    //[_operations setObject:blockOperation forKey:[NSNumber numberWithLong:pageIndex]];
    
    [blockOperation run:^(void){
        if (weakOperation.isCancelled) {
            return;
        }
        assert(!weakOperation.isFinished);
        
        double counter = 0.0;
        unsigned long int framesPerEntry = (weakSelf.sample.frames + (kPrecalcPoolSize - 1)) / kPrecalcPoolSize;

        unsigned long long framesLeftInBufferCount = 0;

        //   2 000 000 / 8000 = 250
        //  20 000 000 / 8000 = 2500
        // 158 760 000 / 8000 = 19845
        //unsigned long int framesNeeded = kSampleBufferFrameCount;

        float* data[weakSelf.sample.channels];
        
        for (int channel = 0; channel < weakSelf.sample.channels; channel++) {
            data[channel] = (float*)((NSMutableData*)weakSelf.sampleBuffers[channel]).bytes;
        }
     
        //NSLog(@"we got room for %ld bytes", width * sizeof(VisualPair));
        VisualPair* storage = (VisualPair*)self->_precalcBuffer.mutableBytes;
        assert(storage);

        const int channels = weakSelf.sample.channels;
        
        unsigned long long displaySampleFrameIndexOffset = 0;

        unsigned long int frameIndex = 0;

        double negativeSum = 0.0;
        double positiveSum = 0.0;
        unsigned int positiveCount = 0;
        unsigned int negativeCount = 0;
        unsigned long long offset = 0;

        while(frameIndex < weakSelf.sample.frames) {
            //NSLog(@"This block of %lld frames is used to create visuals for %ld pixels", displayFrameCount, width);
            negativeSum = 0.0;
            positiveSum = 0.0;
            positiveCount = 0;
            negativeCount = 0;
            do {
                if (weakOperation.isCancelled) {
                    break;
                }

                if (framesLeftInBufferCount == 0) {
                    unsigned long long framesRequiredCount = MIN(kSampleBufferFrameCount, weakSelf.sample.frames - frameIndex);
                    // This may block for a loooooong time!
                    [weakSelf.sample rawSampleFromFrameOffset:displaySampleFrameIndexOffset
                                                       frames:framesRequiredCount
                                                      outputs:data];

                    framesLeftInBufferCount = framesRequiredCount;
                    offset = frameIndex;
                }
                
                double s = 0.0;
                for (int channel = 0; channel < channels; channel++) {
                    s += data[channel][frameIndex - offset];
                }
                s /= channels;

                frameIndex++;
                counter += 1.0;
                framesLeftInBufferCount -= 1.0;
                
                if (s >= 0) {
                    positiveSum += s;
                    positiveCount++;
                } else {
                    negativeSum += s;
                    negativeCount++;
                }
            } while (counter < framesPerEntry);

            if (weakOperation.isCancelled) {
                break;
            }

            counter -= framesPerEntry;
            displaySampleFrameIndexOffset += framesPerEntry;

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

- (IndexedBlockOperation*)runOperationWithOrigin:(size_t)origin width:(size_t)width callback:(nonnull void (^)(void))callback
{
    assert(origin < self.width);

    size_t pageIndex = origin / self.tileWidth;

    NSNumber* pageNumber = [NSNumber numberWithLong:pageIndex];
    IndexedBlockOperation* blockOperation = [self.operations objectForKey:pageNumber];
    if (blockOperation != nil) {
        NSLog(@"asking for the same operation again on page %ld", pageIndex);
        return blockOperation;
    }

    blockOperation = [[IndexedBlockOperation alloc] initWithIndex:pageIndex];
    //NSLog(@"adding %ld", pageIndex);
    IndexedBlockOperation* __weak weakOperation = blockOperation;
    //ConcurrentAccessDictionary* __weak weakOperations = _operations;
    ReducedVisualSample* __weak weakSelf = self;

    [self.operations setObject:blockOperation forKey:[NSNumber numberWithLong:pageIndex]];
    
    [blockOperation run:^(void){
        if (weakOperation.isCancelled) {
            return;
        }
        assert(!weakOperation.isFinished);
        
        double pairsPerPixel = (double)kPrecalcPoolSize / (double)weakSelf.width;
        unsigned long int pairsNeeded = width * pairsPerPixel;

        //NSLog(@"we got room for %ld bytes", width * sizeof(VisualPair));
        NSMutableData* buffer = [NSMutableData dataWithLength:width * sizeof(VisualPair)];
        assert(buffer);
        VisualPair* storage = (VisualPair*)buffer.mutableBytes;
        assert(storage);

        unsigned long long displaySampleFrameIndexOffset = origin * pairsPerPixel;
        assert(displaySampleFrameIndexOffset < kPrecalcPoolSize);
        unsigned long long displayPairsCount = MIN(pairsNeeded, kPrecalcPoolSize - displaySampleFrameIndexOffset);

        VisualPair* source = (VisualPair*)self->_precalcBuffer.bytes +  displaySampleFrameIndexOffset;

        unsigned long int frameIndex = 0;

        double negativeSum = 0.0;
        double positiveSum = 0.0;
        unsigned int positiveCount = 0;
        unsigned int negativeCount = 0;

        while(frameIndex < displayPairsCount) {
            negativeSum = 0.0;
            positiveSum = 0.0;
            positiveCount = 0;
            negativeCount = 0;
            double counter = 0.0;
            do {
                if (weakOperation.isCancelled) {
                    break;
                }
                
                if (frameIndex >= displayPairsCount) {
                   break;
                }
                
                positiveSum += source->positiveAverage;
                positiveCount++;

                negativeSum += source->negativeAverage;
                negativeCount++;

                frameIndex++;
                counter += 1.0;

                source++;

            } while (counter < pairsPerPixel);

            if (weakOperation.isCancelled) {
                break;
            }

            storage->negativeAverage = negativeCount > 0 ? negativeSum / negativeCount : 0.0;
            storage->positiveAverage = positiveSum > 0 ? positiveSum / positiveCount : 0.0;
            
            ++storage;
        };
        weakOperation.index = pageIndex;
        weakOperation.data = buffer;
        weakOperation.isFinished = !weakOperation.isCancelled;
        callback();
    }];

    dispatch_async(_calculations_queue, blockOperation.dispatchBlock);

    return blockOperation;
}

@end
