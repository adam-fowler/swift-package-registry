import Hummingbird
import HummingbirdAuth
import Logging
import NIOCore

struct PackageRegistryRequestContext: AuthRequestContext, RequestContext {
    var coreContext: CoreRequestContextStorage
    var auth: HummingbirdAuth.LoginCache

    init(source: Source) {
        self.coreContext = .init(source: source)
        self.auth = .init()
    }
}
