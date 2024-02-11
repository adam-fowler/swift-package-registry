@_spi(ConnectionPool) import PostgresNIO

struct PostgresContext {
    let connection: PostgresConnection
    let logger: Logger
}
