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

+ (NSString*)BeautifulSize:(NSNumber*)size
{
    NSString* beauty = nil;
    unsigned long long int base = 1024;
    unsigned long long int kilobyte = base;
    unsigned long long int megabyte = kilobyte * base;
    unsigned long long int gigabyte = megabyte * base;
    unsigned long long int terrabyte = gigabyte * base;
    unsigned long long int petabyte = terrabyte * base;
    
    NSString* const formatByte = @"%.0f %@";
    NSString* const formatRest = @"%.1f %@";

    float multiplier = 1.0;
    NSString* unit = @"Byte";
    NSString* format = formatByte;

    if (size.longLongValue >= petabyte) {
        multiplier = size.longLongValue / petabyte;
        unit = @"PB";
        format = formatRest;
    } else if (size.longLongValue >= terrabyte) {
        multiplier = size.longLongValue / terrabyte;
        unit = @"TB";
        format = formatRest;
    } else if (size.longLongValue >= gigabyte) {
        multiplier = size.longLongValue / gigabyte;
        unit = @"GB";
        format = formatRest;
    } else if (size.longLongValue >= megabyte) {
        multiplier = size.longLongValue / megabyte;
        unit = @"MB";
        format = formatRest;
    } else if (size.longLongValue >= kilobyte) {
        multiplier = size.longLongValue / kilobyte;
        unit = @"KB";
        format = formatRest;
    }
    beauty = [NSString stringWithFormat:format, multiplier, unit];

    return beauty;
}

@end
