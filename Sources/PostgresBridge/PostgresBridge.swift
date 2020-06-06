import NIO
import PostgresNIO
import AsyncKit
import Bridges
import Logging

public struct PostgresBridge: ContextBridgeable {
    public let context: BridgeWithContext<PBR>
    
    init (_ context: BridgeWithContext<PBR>) {
        self.context = context
    }
    
    /// Gives a connection to the database and releases it automatically in both success and error cases
    public func connection<T>(to db: DatabaseIdentifier,
                                            _ closure: @escaping (PostgresConnection) -> EventLoopFuture<T>) -> EventLoopFuture<T> {
        context.bridge.connection(to: db, on: context.eventLoop, closure)
    }
    
    /// Gives a connection to the database and you should close it by yourself
    func requestConnection(to db: DatabaseIdentifier) -> EventLoopFuture<PostgresConnection> {
        context.bridge.requestConnection(to: db, on: context.eventLoop)
    }
    
    public func transaction<T>(to db: DatabaseIdentifier,
                                            _ closure: @escaping (PostgresConnection) -> EventLoopFuture<T>) -> EventLoopFuture<T> {
        context.bridge.transaction(to: db, on: context.eventLoop, closure)
    }
    
    public func register(_ db: DatabaseIdentifier) {
        context.bridge.register(db)
    }
    
    public func migrator(for db: DatabaseIdentifier, dedicatedSchema: Bool = false) -> Migrator {
        BridgeDatabaseMigrations<PBR>(context.bridge, db: db, dedicatedSchema: dedicatedSchema)
    }
}

public final class PBR: Bridgeable {
    public typealias Source = PostgresConnectionSource
    public typealias Database = PostgresDatabase
    public typealias Connection = PostgresConnection
    
    public static var dialect: SQLDialect { .psql }
    
    public var pools: [String: GroupPool] = [:]
    
    public let logger: Logger
    public let eventLoopGroup: EventLoopGroup
    
    public required init (eventLoopGroup: EventLoopGroup, logger: Logger) {
        self.eventLoopGroup = eventLoopGroup
        self.logger = logger
    }
    
    /// Gives a connection to the database and releases it automatically in both success and error cases
    public func connection<T>(to db: DatabaseIdentifier,
                                  on eventLoop: EventLoop,
                                  _ closure: @escaping (PostgresConnection) -> EventLoopFuture<T>) -> EventLoopFuture<T> {
        self.db(db, on: eventLoop).withConnection { closure($0) }
    }
    
    /// Gives a connection to the database and you should close it by yourself
    public func requestConnection(to db: DatabaseIdentifier, on eventLoop: EventLoop) -> EventLoopFuture<PostgresConnection> {
        _db(db, on: eventLoop).requestConnection()
    }
    
    public func db(_ db: DatabaseIdentifier, on eventLoop: EventLoop) -> PostgresDatabase {
        _db(db, on: eventLoop)
    }
    
    private func _db(_ db: DatabaseIdentifier, on eventLoop: EventLoop) -> _ConnectionPoolPostgresDatabase {
        _ConnectionPoolPostgresDatabase(pool: pool(db, for: eventLoop), logger: logger)
    }
    
    deinit {
        shutdown()
    }
}

// MARK: Database on pool

private struct _ConnectionPoolPostgresDatabase {
    let pool: EventLoopConnectionPool<PostgresConnectionSource>
    let logger: Logger
}

extension _ConnectionPoolPostgresDatabase: PostgresDatabase {
    var eventLoop: EventLoop { self.pool.eventLoop }
    
    func send(_ request: PostgresRequest, logger: Logger) -> EventLoopFuture<Void> {
        pool.withConnection(logger: logger) {
            $0.send(request, logger: logger)
        }
    }
    
    func withConnection<T>(_ closure: @escaping (PostgresConnection) -> EventLoopFuture<T>) -> EventLoopFuture<T> {
        pool.withConnection(logger: self.logger, closure)
    }
    
    func requestConnection() -> EventLoopFuture<PostgresConnection> {
        pool.requestConnection(logger: logger)
    }
}
