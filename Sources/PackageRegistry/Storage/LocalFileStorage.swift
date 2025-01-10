import Hummingbird
import NIOFileSystem
import NIOPosix

struct LocalFileStorage: Storage {
    let rootFolder: String
    let fileSystem: FileSystem

    init(rootFolder: String) {
        self.rootFolder = rootFolder.addSuffix("/")
        self.fileSystem = .init(threadPool: .singleton)
    }

    func writeFile<AS: AsyncSequence>(
        _ filename: String,
        contents: AS,
        context: some RequestContext
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

    func writeFile(
        _ filename: String,
        buffer: ByteBuffer,
        context: some RequestContext
    ) async throws {
        let fullFilename = self.rootFolder + filename.dropPrefix("/")
        try await self.fileSystem.withFileHandle(
            forWritingAt: .init(fullFilename),
            options: .newFile(replaceExisting: true)
        ) { fileHandle in
            _ = try await fileHandle.write(contentsOf: buffer, toAbsoluteOffset: 0)
        }
    }

    func makeDirectory(
        _ path: String,
        context: some RequestContext
    ) async throws {
        let fullPath = self.rootFolder + path.dropPrefix("/")
        do {
            try await self.fileSystem.createDirectory(at: .init(fullPath), withIntermediateDirectories: true)
        } catch let error as FileSystemError where error.code == .fileAlreadyExists {
            // don't throw error on directory that already exists
        }
    }

    func readFile(
        _ filename: String,
        context: some RequestContext,
        process: (ByteBuffer) async throws -> Void
    ) async throws {
        let fullFilename = self.rootFolder + filename.dropPrefix("/")
        try await self.fileSystem.withFileHandle(forReadingAt: .init(fullFilename)) { fileHandle in
            for try await chunk in fileHandle.readChunks() {
                try await process(chunk)
            }
        }
    }
}
