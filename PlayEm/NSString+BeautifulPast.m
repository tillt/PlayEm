//
//  NSString+BeautifulPast.m
//  PlayEm
//
//  Created by Till Toenshoff on 15.10.23.
//  Copyright © 2023 Till Toenshoff. All rights reserved.
//

#import "NSString+BeautifulPast.h"

@implementation NSString (BeautifulPast)

+ (NSString*)BeautifulPast:(NSDate*)past
{
    NSDate* present = [NSDate now];

    NSDate* hourAgo = [present dateByAddingTimeInterval:-3600.0];
    NSDate* yesterday = [present dateByAddingTimeInterval:-86400.0];
    NSDate* thisWeek = [present dateByAddingTimeInterval:-604800.0];
    NSDate* lastWeek = [present dateByAddingTimeInterval:-1209600.0];
    NSDate* thisMonth = [present dateByAddingTimeInterval:-2629743.83];
    NSDate* lastMonth = [present dateByAddingTimeInterval:-5259487.66];

    NSString* beauty = nil;

    if ([lastMonth compare:past] == NSOrderedAscending) {
        if ([thisMonth compare:past] == NSOrderedAscending) {
            if ([lastWeek compare:past] == NSOrderedAscending) {
                if ([thisWeek compare:past] == NSOrderedAscending) {
                    if ([yesterday compare:past] == NSOrderedAscending) {
                        if ([hourAgo compare:past] == NSOrderedAscending) {
                            beauty = @"brandnew";
                        } else {
                            beauty = @"yesterday";
                        }
                    } else {
                        beauty = @"this week";
                    }
                } else {
                    beauty = @"last week";
                }
            } else {
                beauty = @"this month";
            }
        } else {
            beauty = @"last month";
        }
    } else {
        beauty = [NSDateFormatter localizedStringFromDate:past dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterNoStyle];
    }

    return beauty;
}

@end
