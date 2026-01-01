//
//  EnergyDetector.m
//
//  Mostly copied from https://github.com/rapilodev/rms
//  Written by Milan Chrobok
//
#import "EnergyDetector.h"

@implementation EnergyDetector

- (id)init
{
    self = [super init];
    if (self) {
        _rms = 0.0;
        _peak = 0.0;
        _frames = 0.0;
    }
    return self;
}

- (void)reset
{
    _rms = 0.0;
    _peak = 0.0;
    _frames = 0;
}

- (void)addFrame:(double)s
{
    _rms += s * s;
    if (fabs(s) > _peak) {
        _peak = fabs(s);
    }
    _frames++;
}

- (double)rms
{
    double squaredValue = 0.0;
    if (_frames == 0) {
        squaredValue = _rms / 0.0000000001;
    } else {
        squaredValue = _rms / (double)_frames;
    }
    return sqrt(squaredValue);
}

@end
