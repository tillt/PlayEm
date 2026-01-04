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

/*!
 @brief Returns a normalized metadata string with common mojibake repaired.
 @discussion Normalizes case, whitespace, non-breaking spaces, and fixes common Latin1/CP1252
             mojibake sequences while bounding work on pathological inputs. If the string already
             looks clean, it is returned with minimal changes. Heuristics focus on Latin/CP1252,
             with additional marker checks and a UTF-16 fallback; non-Latin scripts are left
             untouched unless obvious mojibake markers are detected.
 @return A sanitized string suitable for display or comparison.
 */
- (NSString*)sanitizedMetadataString;

@end
NS_ASSUME_NONNULL_END
