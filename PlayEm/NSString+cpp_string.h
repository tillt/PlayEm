//
//  NSString+cpp_string.h
//  PlayEm
//
//  Created by Till Toenshoff on 12/10/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//
#include <string>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSString (cpp_string)
+(NSString*) stringWithwstring:(const std::wstring&)string;
+(NSString*) stringWithstring:(const std::string&)string;
-(std::wstring) getwstring;
-(std::string) getstring;
@end

NS_ASSUME_NONNULL_END
