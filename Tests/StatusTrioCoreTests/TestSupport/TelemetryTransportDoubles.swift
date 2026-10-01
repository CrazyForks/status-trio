import Foundation
@testable import StatusTrioCore

actor StubTelemetryTransport: TelemetryTransport {
    private(set) var requests: [URLRequest] = []
    private let statusCode: Int
    private let shouldThrow: Bool

    init(statusCode: Int = 204, shouldThrow: Bool = false) {
        self.statusCode = statusCode
        self.shouldThrow = shouldThrow
    }

    func send(request: URLRequest) async throws -> HTTPURLResponse {
        requests.append(request)
        if shouldThrow { throw URLError(.timedOut) }
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil) else {
            throw TelemetryTransportError.nonHTTPResponse
        }
        return response
    }

    func requestCount() -> Int { requests.count }
    func recordedRequests() -> [URLRequest] { requests }
}
