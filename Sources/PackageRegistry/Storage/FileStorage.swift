import Hummingbird
import NIOPosix

struct FileStorage: Storage {
    let rootFolder: String
    let fileIO = FileIO()

    init(rootFolder: String) {
        self.rootFolder = rootFolder.addSuffix("/")
    }

    func writeFile<AS: AsyncSequence>(
        _ filename: String,
        contents: AS,
        context: some RequestContext
    ) async throws where AS.Element == ByteBuffer {
        let fullFilename = self.rootFolder + filename.dropPrefix("/")
        try await self.fileIO.writeFile(contents: contents, path: fullFilename, context: context)
    }

    func writeFile(
        _ filename: String,
        buffer: ByteBuffer,
        context: some RequestContext
    ) async throws {
        let fullFilename = self.rootFolder + filename.dropPrefix("/")
        try await self.fileIO.writeFile(buffer: buffer, path: fullFilename, context: context)
    }

    func makeDirectory(
        _ path: String,
        context: some RequestContext
    ) async throws {
        let fullPath = self.rootFolder + path.dropPrefix("/")
        let nonBlockingFileIO = NonBlockingFileIO(threadPool: .singleton)
        try await nonBlockingFileIO.createDirectory(path: fullPath, withIntermediateDirectories: true, mode: S_IRWXU)
    }

    func readFile(
        _ filename: String,
        context: some RequestContext
    ) async throws -> ResponseBody {
        let fullFilename = self.rootFolder + filename.dropPrefix("/")
        return try await self.fileIO.loadFile(path: fullFilename, context: context)
    }
}
