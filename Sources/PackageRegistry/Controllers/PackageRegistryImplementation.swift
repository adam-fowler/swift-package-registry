import Hummingbird
import Logging
import PackageRegistryAPI

struct PackageRegistryImplementationl<PackageReleasesRepo: PackageReleaseRepository, ManifestsRepo: ManifestRepository>: APIProtocol {
    let storage: FileStorage
    let packageRepository: PackageReleasesRepo
    let manifestRepository: ManifestsRepo
    let urlRoot: String

    func listPackageReleases(_ input: PackageRegistryAPI.Operations.listPackageReleases.Input) async throws -> PackageRegistryAPI.Operations.listPackageReleases.Output {
        guard let context = PackageRegistryRequestContext.context else { 
            return .undocumented(statusCode: 500, .init())
        }
        let id = try PackageIdentifier(scope: input.path.scope, name: input.path.name)
        let releases = try await self.packageRepository.list(id: id, logger: context.logger)
        guard releases.count > 0 else { throw HTTPError(.notFound) }
        let releasesResponse = releases.compactMap {
            if $0.status.shoudBeListed {
                return (
                    $0.version.description,
                    ListReleaseResponse.Release(
                        url: "\(self.urlRoot)\(input.path.scope)/\(input.path.name)/\($0.version)",
                        problem: $0.status.problem
                    )
                )
            } else {
                return nil
            }
        }
        let response = ListReleaseResponse(releases: .init(releasesResponse) { first, _ in first })
        var headers: HTTPFields = .init()
        if let latestRelease = releases.max(by: { $0.version < $1.version }) {
            headers[values: .link].append("<\(self.urlRoot)\(input.path.scope)/\(input.path.name)/\(latestRelease.version)>; rel=\"latest-version\"")
        }
        return try .ok(
            .init(
                headers: .init(Content_hyphen_Version: ._1), 
                body: .json(.init(releases: .init(unvalidatedValue: response.releases)))
            )
        )
    }

    func fetchReleaseMetadata(_ input: PackageRegistryAPI.Operations.fetchReleaseMetadata.Input) async throws -> PackageRegistryAPI.Operations.fetchReleaseMetadata.Output {
        guard let context = PackageRegistryRequestContext.context else { 
            return .undocumented(statusCode: 500, .init())
        }
        guard let version = Version(input.path.version) else {
            throw HTTPError(.badRequest)
        }
        let id = try PackageIdentifier(scope: input.path.scope, name: input.path.name)
        guard let release = try await packageRepository.get(id: id, version: version, logger: context.logger) else {
            throw HTTPError(.notFound)
        }
        let releases = try await packageRepository.list(id: id, logger: context.logger)
        let sortedReleases = releases.sorted { $0.version < $1.version }

        // Construct Link header
        var headers: HTTPFields = .init()
        if let latestRelease = sortedReleases.last {
            headers[values: .link].append("<\(self.urlRoot)\(input.path.scope)/\(input.path.name)/\(latestRelease.version)>; rel=\"latest-version\"")
        }
        if let index = sortedReleases.firstIndex(where: { $0.version == version }) {
            if index != sortedReleases.startIndex {
                let prevIndex = sortedReleases.index(before: index)
                let prevVersion = sortedReleases[prevIndex].version
                headers[values: .link].append("<\(self.urlRoot)\(input.path.scope)/\(input.path.name)/\(prevVersion)>; rel=\"predecessor-version\"")
            }
            let nextIndex = sortedReleases.index(after: index)
            if nextIndex != sortedReleases.endIndex {
                let nextVersion = sortedReleases[nextIndex].version
                headers[values: .link].append("<\(self.urlRoot)\(input.path.scope)/\(input.path.name)/\(nextVersion)>; rel=\"successor-version\"")
            }
        }
        return .ok(.init(headers: .init(Content_hyphen_Version: ._1), body: .))
        return .init(headers: headers, response: release)
    }

    func publishPackageRelease(_ input: PackageRegistryAPI.Operations.publishPackageRelease.Input) async throws -> PackageRegistryAPI.Operations.publishPackageRelease.Output {
        guard let context = PackageRegistryRequestContext.context else { 
            return .undocumented(statusCode: 500, .init())
        }
        throw HTTPError(.serviceUnavailable)
    }

    func fetchManifestForPackageRelease(_ input: PackageRegistryAPI.Operations.fetchManifestForPackageRelease.Input) async throws -> PackageRegistryAPI.Operations.fetchManifestForPackageRelease.Output {
        guard let context = PackageRegistryRequestContext.context else { 
            return .undocumented(statusCode: 500, .init())
        }
        throw HTTPError(.serviceUnavailable)
    }

    func downloadSourceArchive(_ input: PackageRegistryAPI.Operations.downloadSourceArchive.Input) async throws -> PackageRegistryAPI.Operations.downloadSourceArchive.Output {
        guard let context = PackageRegistryRequestContext.context else { 
            return .undocumented(statusCode: 500, .init())
        }
        throw HTTPError(.serviceUnavailable)
    }

    func lookupPackageIdentifiersByURL(_ input: PackageRegistryAPI.Operations.lookupPackageIdentifiersByURL.Input) async throws -> PackageRegistryAPI.Operations.lookupPackageIdentifiersByURL.Output {
        guard let context = PackageRegistryRequestContext.context else { 
            return .undocumented(statusCode: 500, .init())
        }
        let url = input.query.url.standardizedGitURL()
        let identifiers = try await self.packageRepository.query(url: url, logger: context.logger)
        guard identifiers.count > 0 else {
            throw HTTPError(.notFound)
        }
        return .ok(.init(
            headers: .init(Content_hyphen_Version: ._1), 
            body: .json(.init(identifiers: identifiers.map { $0.description }))
        ))
    }
}