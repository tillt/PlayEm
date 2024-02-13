//
//  WaveTile.h
//  PlayEm
//
//  Created by Till Toenshoff on 31.01.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <MetalKit/MetalKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface WaveTile : NSObject

@property (strong, nonatomic) id<MTLTexture> texture;
@property (assign, nonatomic) CGRect frame;
@property (assign, nonatomic) BOOL needsDisplay;

@property (strong, nonatomic) id<MTLBuffer> pairsBuffer;
@property (strong, nonatomic) id<MTLBuffer> verticesBuffer;

-(nonnull instancetype)initWithDevice:(id<MTLDevice>)device size:(NSSize)size;
-(void)copyFromData:(NSData*)source;

@end

NS_ASSUME_NONNULL_END
