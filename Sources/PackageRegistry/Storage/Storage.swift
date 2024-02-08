import Hummingbird

protocol Storage {
    func writeFile<AS: AsyncSequence>(
        _ filename: String,
        contents: AS,
        context: some HBBaseRequestContext
    ) async throws where AS.Element == ByteBuffer

    func writeFile(
        _ filename: String,
        buffer: ByteBuffer,
        context: some HBBaseRequestContext
    ) async throws

    func makeDirectory(
        _ path: String,
        context: some HBBaseRequestContext
    ) async throws

    func readFile(_ filename: String, context: some HBBaseRequestContext) async throws -> HBResponseBody
}
