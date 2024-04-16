import Hummingbird
import Logging
import NIOCore

struct PackageRegistryRequestContext: RequestContext {
    init(channel: Channel, logger: Logger) {
        self.coreContext = .init(allocator: channel.allocator, logger: logger)
    }

    var coreContext: CoreRequestContext
}
