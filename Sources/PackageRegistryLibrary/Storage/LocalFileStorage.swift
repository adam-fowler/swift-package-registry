import Hummingbird
import NIOFileSystem
import NIOPosix

public struct LocalFileStorage: FileStorage {
    let rootFolder: String
    let fileSystem: FileSystem

    public init(rootFolder: String) {
        self.rootFolder = rootFolder.addSuffix("/")
        self.fileSystem = .init(threadPool: .singleton)
    }

    public func writeFile<AS: AsyncSequence>(
        _ filename: String,
        contents: AS
    ) async throws where AS.Element == ByteBuffer {
        let fullFilename = self.rootFolder + filename.dropPrefix("/")
        try await self.fileSystem.withFileHandle(
            forWritingAt: .init(fullFilename),
            options: .newFile(replaceExisting: true)
        ) { fileHandle in
            try await fileHandle.withBufferedWriter { writer in
                _ = try await writer.write(contentsOf: contents)
            }
        }
    }

    public func writeFile(
        _ filename: String,
        buffer: ByteBuffer
    ) async throws {
        let fullFilename = self.rootFolder + filename.dropPrefix("/")
        try await self.fileSystem.withFileHandle(
            forWritingAt: .init(fullFilename),
            options: .newFile(replaceExisting: true)
        ) { fileHandle in
            _ = try await fileHandle.write(contentsOf: buffer, toAbsoluteOffset: 0)
        }
    }

    public func makeDirectory(
        _ path: String
    ) async throws {
        let fullPath = self.rootFolder + path.dropPrefix("/")
        do {
            try await self.fileSystem.createDirectory(at: .init(fullPath), withIntermediateDirectories: true)
        } catch let error as FileSystemError where error.code == .fileAlreadyExists {
            // don't throw error on directory that already exists
        }
    }

    public func readFile(
        _ filename: String,
        process: (ByteBuffer) async throws -> Void
    ) async throws {
        let fullFilename = self.rootFolder + filename.dropPrefix("/")
        try await self.fileSystem.withFileHandle(forReadingAt: .init(fullFilename)) { fileHandle in
            for try await chunk in fileHandle.readChunks() {
                try await process(chunk)
            }
        }
    }

    public func readFile(
        _ filename: String
    ) async throws -> ByteBuffer {
        let fullFilename = self.rootFolder + filename.dropPrefix("/")
        return try await self.fileSystem.withFileHandle(forReadingAt: .init(fullFilename)) { fileHandle in
            try await fileHandle.readChunks().collect(upTo: .max)
        }
    }
}
