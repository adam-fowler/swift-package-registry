import Hummingbird
import HummingbirdAuth
import Logging
import NIOCore
import PackageRegistryLibrary

public struct AppRequestContext: PackageRegistryRequestContext {
    public var coreContext: CoreRequestContextStorage
    public var identity: User?

    public init(source: Source) {
        self.coreContext = .init(source: source)
        self.identity = nil
    }
}
