import Hummingbird
import HummingbirdAuth
import Logging
import NIOCore

struct PackageRegistryRequestContext: AuthRequestContext, RequestContext {
    var coreContext: CoreRequestContext
    var auth: HummingbirdAuth.LoginCache

    init(channel: Channel, logger: Logger) {
        self.coreContext = .init(allocator: channel.allocator, logger: logger)
        self.auth = .init()
    }
}
