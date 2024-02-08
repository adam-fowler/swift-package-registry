import Hummingbird

protocol Storage {
    func writeFile<AS: AsyncSequence>(_ filename: String, contents: AS, context: some HBBaseRequestContext) async throws where AS.Element == ByteBuffer
    func readFile(_ filename: String, context: some HBBaseRequestContext) async throws -> HBResponseBody
}