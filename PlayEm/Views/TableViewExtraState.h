//
//  TableViewExtraState.h
//  PlayEm
//
//  Created by Till Toenshoff on 10.06.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#ifndef TableViewExtraState_h
#define TableViewExtraState_h

typedef enum : NSUInteger {
    kExtraStateNormal = 0,
    kExtraStateActive = 1,
    kExtraStatePlaying = 2,
    kExtraStateFocused = 3,
} ExtraState;

#endif /* TableViewExtraState_h */
