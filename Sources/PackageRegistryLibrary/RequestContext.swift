import Hummingbird
import HummingbirdAuth

/// Requirements for PackageRegistry Request context
public protocol PackageRegistryRequestContext: AuthRequestContext, RequestContext where Identity == User {}
