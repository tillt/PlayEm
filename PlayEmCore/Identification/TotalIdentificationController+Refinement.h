//
//  TotalIdentificationController+Refinement.h
//  PlayEm
//
//  Created by Till Toenshoff on 12/26/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import "TotalIdentificationController.h"

@class TimedMediaMetaData;

NS_ASSUME_NONNULL_BEGIN

@interface TotalIdentificationController (Refinement)
- (NSArray<TimedMediaMetaData*>*)refineTracklist;
@end

NS_ASSUME_NONNULL_END
