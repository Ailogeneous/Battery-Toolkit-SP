/*@file
  Copyright (C) 2022 Marvin Häuser. All rights reserved.
  SPDX-License-Identifier: BSD-3-Clause
*/

#import <Foundation/NSBundle.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSString.h>
#import <Foundation/NSException.h>

#include "BTPreprocessor.h"

void BTPreprocessorConfigure(NSString * _Nonnull suiteName) {
    (void)suiteName;
}

static NSString *BTPreprocessorValue(NSString * _Nonnull key) {
    // Prefer Info.plist keys (app or helper bundle)
    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
    if (info) {
        NSString *plistValue = [info objectForKey:key];
        if (plistValue && plistValue.length > 0) {
            return plistValue;
        }
    }

    [NSException raise:NSInternalInconsistencyException
                format:@"Missing configuration value for key: %@", key];
    return @"";
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
