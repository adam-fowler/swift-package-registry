import NIOCore

/// AsyncSequence that updates some state based on values it iterates
///
/// Once iteration has completed you can get the updated state from the AsyncSequence
final class ProcessingAsyncSequence<Base: AsyncSequence, State>: AsyncSequence {
    var base: Base.AsyncIterator
    var state: State
    let process: (Base.Element, inout State) -> Void

    init(_ base: Base, state: State, _ process: @escaping (Base.Element, inout State) -> Void) {
        self.base = base.makeAsyncIterator()
        self.state = state
        self.process = process
    }

    struct AsyncIterator: AsyncIteratorProtocol {
        let asyncSequence: ProcessingAsyncSequence<Base, State>

        func next() async throws -> Base.Element? {
            guard let buffer = try await self.asyncSequence.base.next() else { return nil }
            self.asyncSequence.process(buffer, &self.asyncSequence.state)
            return buffer
        }
    }

    func makeAsyncIterator() -> AsyncIterator {
        .init(asyncSequence: self)
    }
}
