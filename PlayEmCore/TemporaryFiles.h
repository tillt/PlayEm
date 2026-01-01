//
//  TemporaryFiles.h
//  PlayEm
//
//  Created by Till Toenshoff on 11/22/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TemporaryFiles : NSObject

+ (NSString*)pathForTemporaryFileWithPrefix:(NSString*)prefix;

@end

NS_ASSUME_NONNULL_END
