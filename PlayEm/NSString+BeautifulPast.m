//
//  NSString+BeautifulPast.m
//  PlayEm
//
//  Created by Till Toenshoff on 15.10.23.
//  Copyright © 2023 Till Toenshoff. All rights reserved.
//

#import "NSString+BeautifulPast.h"

@implementation NSString (BeautifulPast)

/// Describes an age in a human readable form, applying spoken patterns like
/// "yesterday" for anything older than 24 hours but younger than 48 hours.
///
/// - Parameter past: point of time in the past
///
/// - Returns: age decription
///
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
                            beauty = NSLocalizedString(@"date.beautiful.brandnew", @"Recent date description");
                        } else {
                            beauty = NSLocalizedString(@"date.beautiful.yesterday", @"Date description for yesterday");
                        }
                    } else {
                        beauty = NSLocalizedString(@"date.beautiful.this_week", @"Date description for this week");
                    }
                } else {
                    beauty = NSLocalizedString(@"date.beautiful.last_week", @"Date description for last week");
                }
            } else {
                beauty = NSLocalizedString(@"date.beautiful.this_month", @"Date description for this month");
            }
        } else {
            beauty = NSLocalizedString(@"date.beautiful.last_month", @"Date description for last month");
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
    NSString* unit = NSLocalizedString(@"unit.byte", @"Size unit: byte");
    NSString* format = formatByte;

    if (size.longLongValue >= petabyte) {
        multiplier = size.longLongValue / petabyte;
        unit = NSLocalizedString(@"unit.pb", @"Size unit: petabyte");
        format = formatRest;
    } else if (size.longLongValue >= terrabyte) {
        multiplier = size.longLongValue / terrabyte;
        unit = NSLocalizedString(@"unit.tb", @"Size unit: terabyte");
        format = formatRest;
    } else if (size.longLongValue >= gigabyte) {
        multiplier = size.longLongValue / gigabyte;
        unit = NSLocalizedString(@"unit.gb", @"Size unit: gigabyte");
        format = formatRest;
    } else if (size.longLongValue >= megabyte) {
        multiplier = size.longLongValue / megabyte;
        unit = NSLocalizedString(@"unit.mb", @"Size unit: megabyte");
        format = formatRest;
    } else if (size.longLongValue >= kilobyte) {
        multiplier = size.longLongValue / kilobyte;
        unit = NSLocalizedString(@"unit.kb", @"Size unit: kilobyte");
        format = formatRest;
    }
    beauty = [NSString stringWithFormat:format, multiplier, unit];

    return beauty;
}

@end
