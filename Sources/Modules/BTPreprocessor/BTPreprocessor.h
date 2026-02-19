/*@file
  Copyright (C) 2022 Marvin Häuser. All rights reserved.
  SPDX-License-Identifier: BSD-3-Clause
*/

#ifndef _BTPreprocessor_h_
#define _BTPreprocessor_h_

#include <Foundation/NSString.h>

__BEGIN_DECLS

/// Legacy no-op retained for API compatibility.
void BTPreprocessorConfigure(NSString * _Nonnull suiteName);

/// The Battery Toolkit bundle identifier.
NSString * _Nonnull BTPreprocessorAppID(void);

/// The Battery Toolkit daemon identifier.
NSString * _Nonnull BTPreprocessorDaemonID(void);

/// The Battery Toolkit daemon connection name.
NSString * _Nonnull BTPreprocessorDaemonConn(void);

/// The Battery Toolkit codesign Common Name.
NSString * _Nonnull BTPreprocessorCodesignCN(void);

__END_DECLS

#endif
