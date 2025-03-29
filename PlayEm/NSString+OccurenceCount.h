//
//  NSString+OccurenceCount.h
//  PlayEm
//
//  From https://stackoverflow.com/a/15947190/91282
//   and https://stackoverflow.com/a/5310084/91282
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSString (OccurenceCount)

- (NSUInteger)occurrenceCountOfCharacter:(UniChar)character;
- (NSUInteger)occurrenceCountOfString:(NSString*)string;

@end

NS_ASSUME_NONNULL_END
