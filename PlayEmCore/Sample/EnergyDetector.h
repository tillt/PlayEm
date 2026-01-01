//
//  EnergyDetector.h
//
//  Mostly copied from https://github.com/rapilodev/rms
//  Written by Milan Chrobok
//
#import <Foundation/Foundation.h>

@interface EnergyDetector : NSObject

@property (assign, nonatomic) double rms;
@property (assign, nonatomic) double peak;
@property (assign, nonatomic) unsigned long long frames;

- (void)reset;
- (void)addFrame:(double)s;

@end

