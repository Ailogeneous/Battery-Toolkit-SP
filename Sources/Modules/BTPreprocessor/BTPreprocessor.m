/*@file
  Copyright (C) 2022 Marvin Häuser. All rights reserved.
  SPDX-License-Identifier: BSD-3-Clause
*/

#import <Foundation/NSString.h>
#import <Foundation/NSUserDefaults.h>
#import <Foundation/NSException.h>

#include "BTPreprocessor.h"

static NSString *BTPreprocessorSuiteName = nil;

void BTPreprocessorConfigure(NSString * _Nonnull suiteName) {
    BTPreprocessorSuiteName = [suiteName copy];
}

static NSString *BTPreprocessorValue(NSString * _Nonnull key) {
    if (!BTPreprocessorSuiteName) {
        [NSException raise:NSInternalInconsistencyException
                    format:@"BTPreprocessor not configured. Call BTPreprocessorConfigure() before use."];
    }

    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:BTPreprocessorSuiteName];
    if (!defaults) {
        [NSException raise:NSInternalInconsistencyException
                    format:@"Unable to access UserDefaults suite: %@", BTPreprocessorSuiteName];
    }

    NSString *value = [defaults stringForKey:key];
    if (!value || value.length == 0) {
        [NSException raise:NSInternalInconsistencyException
                    format:@"Missing UserDefaults key: %@", key];
    }

    return value;
}

NSString * _Nonnull BTPreprocessorAppID(void) {
    return BTPreprocessorValue(@"BT_APP_ID");
}

NSString * _Nonnull BTPreprocessorDaemonID(void) {
    return BTPreprocessorValue(@"BT_DAEMON_ID");
}

NSString * _Nonnull BTPreprocessorDaemonConn(void) {
    return BTPreprocessorValue(@"BT_DAEMON_CONN");
}

NSString * _Nonnull BTPreprocessorCodesignCN(void) {
    return BTPreprocessorValue(@"BT_CODESIGN_CN");
}
