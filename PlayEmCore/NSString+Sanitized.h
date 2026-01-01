//
//  NSString+Sanitized.h
//  PlayEm
//
//  Created by Till Toenshoff on 12/27/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSString (CFSanitize)

- (NSString*)sanitizedMetadataString;
+ (NSString*)bestMetadataStringFromVariants:(NSArray<NSString*>*)variants;

@end
NS_ASSUME_NONNULL_END
