//
// Copyright (C) 2024 Marvin Häuser. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

@globalActor
public actor BTBackgroundActor: GlobalActor {
    public static let shared = BTBackgroundActor()
    public typealias ActorType = BTBackgroundActor
}
