import NIOCore
import Synchronization

final class MemoryFileStorage: FileStorage {
    public init() {
        self.files = .init([:])
    }

    public func writeFile<AS: AsyncSequence>(
        _ filename: String,
        contents: AS
    ) async throws where AS.Element == ByteBuffer {
        let buffer = try await contents.collect(upTo: .max)
        self.files.withLock { $0[filename] = buffer }
    }

    public func writeFile(
        _ filename: String,
        buffer: ByteBuffer
    ) async throws {
        self.files.withLock { $0[filename] = buffer }
    }

    public func makeDirectory(
        _ path: String
    ) async throws {
    }

    public func readFile<Value>(
        _ filename: String,
        process: (ByteBuffer) async throws -> Value
    ) async throws -> Value {
        guard let buffer = self.files.withLock({ $0[filename] }) else { throw FileStorageError.failedToReadFile }
        return try await process(buffer)
    }

    public func readFile(
        _ filename: String
    ) async throws -> ByteBuffer {
        guard let buffer = self.files.withLock({ $0[filename] }) else { throw FileStorageError.failedToReadFile }
        return buffer
    }

    let files: Mutex<[String: ByteBuffer]>
}
