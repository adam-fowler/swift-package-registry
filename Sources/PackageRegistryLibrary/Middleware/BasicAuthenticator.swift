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

import Hummingbird
import HummingbirdAuth
import HummingbirdBcrypt
import NIOPosix

struct BasicAuthenticator<Context: PackageRegistryRequestContext, Repository: UserRepository>: AuthenticatorMiddleware {
    let repository: Repository

    func authenticate(request: Request, context: Context) async throws -> User? {
        // does request have basic authentication info in the "Authorization" header
        guard let basic = request.headers.basic else { return nil }

        // check if user exists in the database and then verify the entered password
        // against the one stored in the database. If it is correct then login in user
        guard let user = try await repository.get(username: basic.username, logger: context.logger) else { return nil }
        guard try await NIOThreadPool.singleton.runIfActive({ Bcrypt.verify(basic.password, hash: user.passwordHash) }) else { return nil }
        return user
    }
}
