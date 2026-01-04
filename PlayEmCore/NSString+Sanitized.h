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
 @discussion Processing pipeline:
             - Normalize (precompose, collapse whitespace/NBSP, trim, bound length).
             - Generate candidate recodes via CP1252/MacRoman (single/double/triple mis-decodes)
               and pick the lowest mojibake-score candidate; non-Latin scripts pass through.
             - Replace mojibake sequences using a generated Latin-1 map (no hand-coded literals).
             - Strip lingering mojibake markers if present, then re-normalize.
             Irreversible mangles (e.g. where bytes map to multiple accents) return the
             mechanically derived character; we do not inject bias. Optional verbose logging
             is gated at compile time with DEBUG_SANITIZER.
 @return A sanitized string suitable for display or comparison.
 */
- (NSString*)sanitizedMetadataString;

@end
NS_ASSUME_NONNULL_END
