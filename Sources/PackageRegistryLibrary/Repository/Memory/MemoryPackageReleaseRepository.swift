import Logging
import NIOConcurrencyHelpers

/// Memory implementation of package release repository
public actor MemoryPackageReleaseRepository: PackageReleaseRepository {
    struct PackageReleaseStorage {
        let release: PackageRelease
        var status: PackageStatus
    }

    typealias Context = Void

    let packages: NIOLockedValueBox<[String: PackageReleaseStorage]>

    public init() {
        self.packages = .init(.init())
    }

    public func add(_ release: PackageRelease, status: PackageStatus, logger: Logger) throws -> Bool {
        let releaseID = release.releaseID
        return self.packages.withLockedValue {
            if $0[releaseID.id] != nil {
                return false
            }
            $0[releaseID.id] = PackageReleaseStorage(release: release, status: status)
            return true
        }
    }

    public func get(id: PackageIdentifier, version: Version, logger: Logger) throws -> PackageRelease? {
        let releaseId = PackageReleaseIdentifier(packageId: id, version: version)
        return self.packages.withLockedValue {
            if let packageRelease = $0[releaseId.id], packageRelease.status == .ok {
                packageRelease.release
            } else {
                nil
            }
        }
    }

    public func delete(id: PackageIdentifier, version: Version, logger: Logger) async throws {
        let releaseId = PackageReleaseIdentifier(packageId: id, version: version)
        self.packages.withLockedValue {
            $0[releaseId.id] = nil
        }
    }

    public func list(id: PackageIdentifier, logger: Logger) throws -> [ListRelease] {
        self.packages.withLockedValue {
            var releases = [ListRelease].init()
            for release in $0.values {
                if release.release.id == id {
                    releases.append(.init(id: id, version: release.release.version, status: release.status))
                }
            }
            return releases
        }
    }

    public func setStatus(id: PackageIdentifier, version: Version, status: PackageStatus, logger: Logger) {
        let releaseId = PackageReleaseIdentifier(packageId: id, version: version)
        self.packages.withLockedValue { $0[releaseId.id]?.status = status }
    }

    public func query(url: String, logger: Logger) async throws -> [PackageIdentifier] {
        self.packages.withLockedValue {
            var identifierSet = Set<PackageIdentifier>()
            for package in $0.values {
                if package.release.metadata?.repositoryURLs?.first(where: { $0 == url }) != nil {
                    identifierSet.insert(package.release.id)
                }
            }
            return .init(identifierSet)
        }
    }
}
