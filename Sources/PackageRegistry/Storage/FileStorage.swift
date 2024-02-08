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
        try await fileIO.writeFile(contents: contents, path: fullFilename, context: context)
    }

    func readFile(
        _ filename: String, 
        context: some HBBaseRequestContext
    ) async throws -> HBResponseBody {
        let fullFilename = self.rootFolder + filename.dropPrefix("/")
        return try await fileIO.loadFile(path: fullFilename, context: context)
    }
}