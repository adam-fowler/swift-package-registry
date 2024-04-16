import CMinizip
import NIOCore
import NIOPosix

/// Zip error type
public struct ZipError: Error {
    enum _Internal {
        case fileNotFound
        case unzipFail
    }

    private let value: _Internal
    private init(_ value: _Internal) {
        self.value = value
    }

    /// File not found
    public static var fileNotFound: Self { self.init(.fileNotFound) }
    /// Unzip failed
    public static var unzipFail: Self { self.init(.unzipFail) }
}

public struct ZipFile {
    let file: unzFile
}

public struct ZipFilePosition {
    let position: unz64_file_pos
}

public struct ZipFileDesc {
    public let filename: String
    public let position: ZipFilePosition

    init(filename: String, position: unz64_file_pos) {
        self.filename = filename
        self.position = .init(position: position)
    }
}

public struct ZipFileManager: Sendable {
    let threadPool: NIOThreadPool

    public init(threadPool: NIOThreadPool = .singleton) {
        self.threadPool = threadPool
    }

    public func withZipFile<Value>(_ path: String, process: (ZipFile) async throws -> Value) async throws -> Value {
        guard let zip = try await self.open(path) else { throw ZipError.fileNotFound }
        let value: Value
        do {
            value = try await process(ZipFile(file: zip))
        } catch {
            try await self.close(zip)
            throw error
        }
        try await self.close(zip)
        return value
    }

    public func contents(of zip: ZipFile) -> ZipFileContentsAsyncSequence {
        return .init(manager: self, zip: zip.file)
    }

    public func loadFile(_ zipFile: ZipFile, at filePosition: ZipFilePosition) async throws -> ByteBuffer {
        let zip = zipFile.file
        return try await self.threadPool.runIfActive {
            var fp = filePosition.position
            guard unzGoToFilePos64(zip, &fp) == UNZ_OK else { throw ZipError.unzipFail }
            guard unzOpenCurrentFile(zip) == UNZ_OK else { throw ZipError.unzipFail }
            defer {
                unzCloseCurrentFile(zip)
            }
            let bufferSize: UInt32 = 4096
            var buffer = [CUnsignedChar](repeating: 0, count: numericCast(bufferSize))
            var output = ByteBuffer()
            while true {
                let readBytes = unzReadCurrentFile(zip, &buffer, bufferSize)
                if readBytes > 0 {
                    output.writeBytes(buffer[..<numericCast(readBytes)])
                } else {
                    break
                }
            }
            return output
        }
    }

    private func open(_ path: String) async throws -> unzFile? {
        try await self.threadPool.runIfActive { unzOpen(path) }
    }

    private func close(_ zipFile: unzFile) async throws {
        _ = try await self.threadPool.runIfActive { unzClose(zipFile) }
    }
}

/// AsyncSequence of zipfile contents
public struct ZipFileContentsAsyncSequence: AsyncSequence {
    public typealias Element = ZipFileDesc

    let manager: ZipFileManager
    let zip: unzFile

    public struct AsyncIterator: AsyncIteratorProtocol {
        var firstIteration = true
        let manager: ZipFileManager
        let zip: unzFile

        public mutating func next() async throws -> Element? {
            let element: Element? = try await self.manager.threadPool.runIfActive { [zip, firstIteration] in
                if firstIteration {
                    if unzGoToFirstFile(zip) != UNZ_OK {
                        throw ZipError.unzipFail
                    }
                } else {
                    let result = unzGoToNextFile(zip)
                    if result == UNZ_END_OF_LIST_OF_FILE {
                        return nil
                    } else if result != UNZ_OK {
                        throw ZipError.unzipFail
                    }
                }
                // get file name
                var fileInfo = unz_file_info64()
                memset(&fileInfo, 0, MemoryLayout<unz_file_info64>.size)
                guard unzGetCurrentFileInfo64(zip, &fileInfo, nil, 0, nil, 0, nil, 0) == UNZ_OK else {
                    throw ZipError.unzipFail
                }
                let filenameSize: Int = numericCast(fileInfo.size_filename)
                let filenameBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: filenameSize + 1)
                unzGetCurrentFileInfo64(zip, nil, filenameBuffer, fileInfo.size_filename, nil, 0, nil, 0)
                filenameBuffer[filenameSize] = 0
                let filename = String(cString: filenameBuffer)

                // get file position
                var filePosition = unz64_file_pos()
                memset(&filePosition, 0, MemoryLayout<unz64_file_pos>.size)
                guard unzGetFilePos64(zip, &filePosition) == UNZ_OK else {
                    throw ZipError.unzipFail
                }
                return .init(filename: filename, position: filePosition)
            }
            self.firstIteration = false
            return element
        }
    }

    public func makeAsyncIterator() -> AsyncIterator {
        return .init(manager: self.manager, zip: self.zip)
    }
}

extension unzFile: @unchecked Sendable {}