import MultipartKit
import NIOCore

/// AsyncSequence that is initialized with a multipart iterator and returns a body as a stream
///
/// Once iteration has completed it is possible to continue parsing the multipart file by copying
/// the iterator stored in the class
final class MultipartBodyAsyncSequence<BackingSequence: AsyncSequence>: AsyncSequence
where BackingSequence.Element == ByteBufferView {
    var multipartIterator: StreamingMultipartParserAsyncSequence<BackingSequence>.AsyncIterator

    init(multipartIterator: StreamingMultipartParserAsyncSequence<BackingSequence>.AsyncIterator) {
        self.multipartIterator = multipartIterator
    }

    struct AsyncIterator: AsyncIteratorProtocol {
        let asyncSequence: MultipartBodyAsyncSequence<BackingSequence>
        var done: Bool = false

        mutating func next() async throws -> ByteBuffer? {
            guard done == false else { return nil }
            let next = try await self.asyncSequence.multipartIterator.next()
            switch next {
            case .bodyChunk(let bufferView):
                return ByteBuffer(bufferView)
            default:
                self.done = true
                return nil
            }
        }
    }

    func makeAsyncIterator() -> AsyncIterator {
        .init(asyncSequence: self)
    }
}
