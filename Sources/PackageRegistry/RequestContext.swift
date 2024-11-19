import Hummingbird
import HummingbirdAuth
import Logging
import NIOCore

struct PackageRegistryRequestContext: AuthRequestContext, RequestContext {
    var coreContext: CoreRequestContextStorage
    var identity: User?

    init(source: Source) {
        self.coreContext = .init(source: source)
        self.identity = nil
    }
}
