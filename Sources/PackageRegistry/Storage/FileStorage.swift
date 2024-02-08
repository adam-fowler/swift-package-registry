import Hummingbird

struct FileStorage: Storage {
    let rootFolder: String
    let fileIO = HBFileIO()

    init(rootFolder: String) {
        self.rootFolder = rootFolder.addSuffix("/")
    }

    func writeFile<AS: AsyncSequence>(
        _ filename: String,
        contents: AS,
        context: some HBBaseRequestContext
    ) async throws where AS.Element == ByteBuffer {
        let fullFilename = self.rootFolder + filename.dropPrefix("/")
        try await self.fileIO.writeFile(contents: contents, path: fullFilename, context: context)
    }

    func writeFile(
        _ filename: String,
        buffer: ByteBuffer,
        context: some HBBaseRequestContext
    ) async throws {
        let fullFilename = self.rootFolder + filename.dropPrefix("/")
        try await self.fileIO.writeFile(buffer: buffer, path: fullFilename, context: context)
    }

    func makeDirectory(
        _ path: String,
        context: some HBBaseRequestContext
    ) async throws {
        let fullPath = self.rootFolder + path.dropPrefix("/")
        try await self.fileIO.makeDirectory(path: fullPath, context: context)
    }

    func readFile(
        _ filename: String,
        context: some HBBaseRequestContext
    ) async throws -> HBResponseBody {
        let fullFilename = self.rootFolder + filename.dropPrefix("/")
        return try await self.fileIO.loadFile(path: fullFilename, context: context)
    }
}
