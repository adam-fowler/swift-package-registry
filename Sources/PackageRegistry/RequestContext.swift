import Hummingbird
import Logging

struct RequestContext: HBRequestContext {
    init(allocator: ByteBufferAllocator, logger: Logger) {
        self.coreContext = .init(allocator: allocator, logger: logger)
    }

    var coreContext: HBCoreRequestContext
}
