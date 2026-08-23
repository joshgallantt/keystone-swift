import Foundation

public protocol HTTPClient: Sendable {
    func get(_ path: String) async throws -> Data
}

public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func get(_ path: String) async throws -> Data {
        guard let url = URL(string: path) else { return Data() }
        return try await session.data(from: url).0
    }
}
