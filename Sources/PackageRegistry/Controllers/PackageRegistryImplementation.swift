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
        guard let version = Version(input.path.version) else {
            throw HTTPError(.badRequest)
        }

        let id = try PackageIdentifier(scope: input.path.scope, name: input.path.name)
        guard let manifests = try await self.manifestRepository.get(.init(packageId: id, version: version), logger: context.logger) else {
            throw HTTPError(.notFound)
        }
        let manifest: ByteBuffer
        var manifestVersion: String?
        if let swiftVersion = input.query.swift_hyphen_version {
            let foundManifest = manifests.versions.first { $0.swiftVersion == swiftVersion }
            manifest = foundManifest?.manifest ?? manifests.default
            manifestVersion = foundManifest?.swiftVersion
        } else {
            manifest = manifests.default
        }
        let filename = if let manifestVersion { "Package@swift-\(manifestVersion).swift" } else { "Package.swift" }
        let linkHeader = manifests.versions.map { "<\(self.urlRoot)\(input.path.scope)/\(input.path.name)/\(version)/Package.swift?swift-version=\($0.swiftVersion)>; rel=\"alternate\"; filename=\"Package@swift-\($0.swiftVersion).swift\"; swift-tools-version=\"\($0.swiftVersion)\"" }

        return .ok(
            .init(
                headers: .init(
                    Cache_hyphen_Control: "public, immutable", 
                    Content_hyphen_Disposition: "attachment; filename=\"\(filename)\"", 
                    Content_hyphen_Version: ._1, 
                    Link: linkHeader.joined(separator: ", ")
                ), 
                body: .text_x_hyphen_swift(.init(manifest.readableBytesView)))
        )
    }

    func downloadSourceArchive(_ input: PackageRegistryAPI.Operations.downloadSourceArchive.Input) async throws -> PackageRegistryAPI.Operations.downloadSourceArchive.Output {
        guard let context = PackageRegistryRequestContext.context else { 
            return .undocumented(statusCode: 500, .init())
        }
        guard let version = Version(input.path.version) else {
            throw HTTPError(.badRequest)
        }
        let filename = "\(input.path.scope).\(input.path.name)/\(version).zip"

        // get metadata
        let id = try PackageIdentifier(scope: input.path.scope, name: input.path.name)
        let release = try await self.packageRepository.get(id: id, version: version, logger: context.logger)
    
        guard let release else {
            throw HTTPError(.notFound)
        }
        let responseBody = try await self.storage.readFile(filename, context: context)
        var headers: HTTPFields = [
            .contentType: MediaType.applicationZip.description,
            .contentDisposition: "attachment; filename=\"\(input.path.name)-\(version).zip\"",
            .cacheControl: "public, immutable",
        ]
        var digest: String?
        if let resource = release.resources.first(where: { $0.name == "source-archive" }) {
            digest = "sha256=\(resource.checksum)"
            /* signing headers not supported
            if let signing = resource.signing {
                headers[.swiftPMSignature] = signing.signatureBase64Encoded
                headers[.swiftPMSignatureFormat] = signing.signatureFormat
            }
            */
        }
        return .ok(
            .init(
                headers: .init(
                    Accept_hyphen_Ranges: nil, 
                    Cache_hyphen_Control: "public, immutable", 
                    Content_hyphen_Disposition: "attachment; filename=\"\(input.path.name)-\(version).zip\"", 
                    Content_hyphen_Version: ._1, 
                    Digest: digest ?? "", 
                    Link: nil
                    // no SwiftPM signature headers
                ),
                body: .application_zip(
                    .init(
                        //  Not working at the moment, Use NIOFileSystem to provide a stream
                        responseBody.map { [UInt8](buffer: $0) },
                        length: .unknown,
                        iterationBehavior: .single
                    )
                )
            )
        )
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