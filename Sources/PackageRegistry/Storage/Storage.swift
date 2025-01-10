import Hummingbird

protocol Storage: Sendable {
    func writeFile<AS: AsyncSequence>(
        _ filename: String,
        contents: AS,
        context: some RequestContext
    ) async throws where AS.Element == ByteBuffer

    func writeFile(
        _ filename: String,
        buffer: ByteBuffer,
        context: some RequestContext
    ) async throws

    func makeDirectory(
        _ path: String,
        context: some RequestContext
    ) async throws

    func readFile(
        _ filename: String,
        context: some RequestContext,
        process: (ByteBuffer) async throws -> Void
    ) async throws
}
