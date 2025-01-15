import Hummingbird

struct PublishStatusManager<KeyValueStore: PersistDriver> {
    enum PublishStatus: Codable {
        struct Problem: Codable {
            internal init(status: Int, url: String? = nil, detail: String? = nil) {
                self.status = status
                self.url = url
                self.detail = detail
            }

            let status: Int
            let url: String?
            let detail: String?
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
