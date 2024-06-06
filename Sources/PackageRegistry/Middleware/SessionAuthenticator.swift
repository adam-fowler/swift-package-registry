//===----------------------------------------------------------------------===//
//
// This source file is part of the Hummingbird server framework project
//
// Copyright (c) 2021-2021 the Hummingbird authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See hummingbird/CONTRIBUTORS.txt for the list of Hummingbird authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Foundation
import Hummingbird
import HummingbirdAuth

/// Session authentication. Get UUID attached to session id in request and return
/// the associated user
struct SessionAuthenticator<Context: AuthRequestContext, Repository: UserRepository>: SessionMiddleware {
    typealias Session = UUID
    typealias Value = User

    let repository: Repository
    let sessionStorage: SessionStorage

    func getValue(from id: UUID, request: Request, context: Context) async throws -> User? {
        // find user from userId
        return try await self.repository.get(id: id, logger: context.logger)
    }
}
