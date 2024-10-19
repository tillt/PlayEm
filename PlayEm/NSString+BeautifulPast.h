//
//  NSString+BeautifulPast.h
//  PlayEm
//
//  Created by Till Toenshoff on 15.10.23.
//  Copyright © 2023 Till Toenshoff. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSString (BeautifulPast)

+ (NSString*)BeautifulPast:(NSDate*)past;
+ (NSString*)BeautifulSize:(NSNumber*)size;


@end

NS_ASSUME_NONNULL_END
