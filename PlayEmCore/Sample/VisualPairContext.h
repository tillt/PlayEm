//
//  VisualPairContext.h
//  PlayEm
//
//  Created by Till Toenshoff on 3/2/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#ifndef VisualPairContext_h
#define VisualPairContext_h

typedef struct {
    //    NSMutableData* reductionBuffer;
    double negativeSum;
    double positiveSum;
    unsigned int positiveCount;
    unsigned int negativeCount;
} VisualPairContext;

#endif /* VisualPairContext_h */
