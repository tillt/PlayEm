//
//  VisualSample.m
//  PlayEm
//
//  Created by Till Toenshoff on 19.04.20.
//  Copyright © 2020 Till Toenshoff. All rights reserved.
//

#import "VisualSample.h"
#import "Sample.h"

@interface Sample ()

@end

const size_t kVisualBufferSize = 512000;

@implementation VisualSample

- (id)initWithSample:(Sample *)sample
{
    self = [super init];
    if (self) {
        _sample = sample;
        
        if (sample != nil) {
            NSLog(@"Creating visual sample\n");

            _buffer = [NSMutableData dataWithLength:kVisualBufferSize * sizeof(VisualPair)];
            assert(_buffer);
            VisualPair *storage = (VisualPair *)_buffer.mutableBytes;
            assert(storage);
            
            int channels = sample.channels;
            int bytesPerSample = 2;
            
            double start = 0.0;
            double duration = sample.duration;
           
            unsigned long int totalSamples = sample.size / bytesPerSample;
           
            unsigned long int displaySampleOffset = (totalSamples * start) / duration;
            displaySampleOffset = (displaySampleOffset / channels) * channels;

            unsigned long int displaySampleCount = totalSamples;
           
            double samplesPerPixel = displaySampleCount / (double)kVisualBufferSize;
            assert(samplesPerPixel >= 1.0);

            // FIXME: Hardcoding 16 bit sample width here.
            const signed short int *data = (const signed short int *)sample.data.bytes;
            double counter = 0.0f;
            unsigned long int sampleIndex = displaySampleOffset;
            unsigned long int maxSampleIndex = (displaySampleOffset + displaySampleCount) - 1;

            double smallest = 0.0, biggest = 0.0;
            double s = 0.0;
           
            while(sampleIndex < maxSampleIndex) {
                smallest = 0.0f;
                biggest = 0.0f;
                do {
                   if (sampleIndex > maxSampleIndex) {
                       break;
                   }

                   s = (double)data[sampleIndex];
                   
                   sampleIndex++;
                   counter += 1.0f;

                   if (channels > 1) {
                       assert(sampleIndex <= maxSampleIndex);

                       s += (double)data[sampleIndex];

                       sampleIndex++;
                       counter += 1.0f;

                       s /= 2.0f;
                   }
                   
                   smallest = MIN(s, smallest);
                   biggest = MAX(s, biggest);

                } while (counter < samplesPerPixel);

                // Distributing the fractional sample error by leaving a sub-sample or fraction -
                // causing the next round to possibly be shorter than `samplesPerPixel`.
                counter -= samplesPerPixel;

                storage->negativeMax = smallest;
                storage->positiveMax = biggest;
                
                ++storage;
           };
           NSLog(@"Visual sample created\n");
        }
    }
    return self;
}

@end
