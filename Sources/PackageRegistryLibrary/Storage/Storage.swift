import Hummingbird

public protocol FileStorage: Sendable {
    func writeFile<AS: AsyncSequence>(
        _ filename: String,
        contents: AS
    ) async throws where AS.Element == ByteBuffer

    func writeFile(
        _ filename: String,
        buffer: ByteBuffer
    ) async throws

    func makeDirectory(
        _ path: String
    ) async throws

    func readFile(
        _ filename: String,
        process: (ByteBuffer) async throws -> Void
    ) async throws

    func readFile(
        _ filename: String
    ) async throws -> ByteBuffer
}

// Error loading file
enum FileStorageError: Error {
    case failedToReadFile
}
