//
//  Sample.m
//  PlayEm
//
//  Created by Till Toenshoff on 11.04.20.
//  Copyright © 2020 Till Toenshoff. All rights reserved.
//

#import "Sample.h"

@interface Sample ()

@end



/*
   // Stick new data into inData, a (float*) array
   fetchFreshData(inData);

   // (You might want to window the signal here... )
   doSomeWindowing(inData);

   // Convert the data into a DSPSplitComplex
   // Pardon the C++ here. Also, you should pre-allocate this, and NOT
   // make a fresh one each time you do an FFT.
   mComplexData = new DSPSplitComplex;
   float *realpart = (float *)calloc(mNumFrequencies, sizeof(float));
   float *imagpart = (float *)calloc(mNumFrequencies, sizeof(float));
   mComplexData->realp = realpart;
   mComplexData->imagp = imagpart;

   vDSP_ctoz((DSPComplex *)inData, 2, mComplexData, 1, mNumFrequencies);

   // Calculate the FFT
   // ( I'm assuming here you've already called vDSP_create_fftsetup() )
   vDSP_fft_zrip(mFFTSetup, mComplexData, 1, log2f(mNumFrequencies), FFT_FORWARD);

   // Don't need that frequency
   mComplexData->imagp[0] = 0.0;

   // Scale the data
   float scale = (float) 1.0 / (2 * (float)mSignalLength);
   vDSP_vsmul(mComplexData->realp, 1, &scale, mComplexData->realp, 1, mNumFrequencies);
   vDSP_vsmul(mComplexData->imagp, 1, &scale, mComplexData->imagp, 1, mNumFrequencies);

   // Convert the complex data into something usable
   // spectrumData is also a (float*) of size mNumFrequencies
   vDSP_zvabs(mComplexData, 1, spectrumData, 1, mNumFrequencies);

   // All done!
   doSomethingWithYourSpectrumData(spectrumData);
*/

@implementation Sample

- (id)initWithChannels:(int)channels rate:(long)rate encoding:(int)encoding
{
    self = [super init];
    if (self) {
        _data = [[NSMutableData alloc] initWithCapacity:30 * 1024 * 1024];
        _channels = channels;
        _rate = rate;
        _encoding = encoding;
    }
    return self;
}

- (size_t)addSampleData:(unsigned char *)buffer size:(size_t)size
{
    [_data appendBytes:buffer length:size];
    return size;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"Channels: %d, Rate: %ld, Encoding: %d, Duration: %f seconds, Buffer: %@", _channels, _rate, _encoding, [self duration], _data];
}

- (NSTimeInterval)duration
{
    return (NSTimeInterval)((double)_data.length / (_rate * _channels * 2));
}

- (size_t)size
{
    return _data.length;
}

@end
