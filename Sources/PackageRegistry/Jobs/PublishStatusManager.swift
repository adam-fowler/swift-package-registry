import Hummingbird

struct PublishStatusManager<KeyValueStore: PersistDriver> {
    enum PublishStatus: Codable {
        struct Problem: Codable {
            internal init(status: Int, url: String? = nil, details: String? = nil) {
                self.status = status
                self.url = url
                self.details = details
            }

            let status: Int
            let url: String?
            let details: String?
        }
        case inProgress
        case failed(Problem)
        case success(String)
    }

    let keyValueStore: KeyValueStore

    func get(id: String) async throws -> PublishStatus? {
        try await keyValueStore.get(key: id, as: PublishStatus.self)
    }

    func set(id: String, status: PublishStatus) async throws {
        try await keyValueStore.set(key: id, value: status)
    }
}
