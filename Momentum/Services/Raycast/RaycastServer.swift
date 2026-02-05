import Foundation
import Network

@MainActor
final class RaycastServer {
    private let port: NWEndpoint.Port
    private let handler: @Sendable (RaycastHTTPRequest) async -> RaycastHTTPResponse
    private let queue = DispatchQueue(label: "Momentum.RaycastServer")
    private var listener: NWListener?
    private var startContinuation: CheckedContinuation<Void, Error>?
    private var didResumeStart = false

    init(port: UInt16, handler: @escaping @Sendable (RaycastHTTPRequest) async -> RaycastHTTPResponse) {
        self.port = NWEndpoint.Port(rawValue: port) ?? NWEndpoint.Port(rawValue: 51637)!
        self.handler = handler
    }

    func start() async throws {
        guard listener == nil else { return }
        let listener = try NWListener(using: .tcp, on: port)
        didResumeStart = false

        try await withCheckedThrowingContinuation { continuation in
            startContinuation = continuation
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    self?.handleStateUpdate(state)
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.handleConnection(connection)
                }
            }
            self.listener = listener
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        startContinuation = nil
        didResumeStart = false
    }

    @MainActor
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    @MainActor
    private func handleStateUpdate(_ state: NWListener.State) {
        guard let continuation = startContinuation, !didResumeStart else { return }
        switch state {
        case .ready:
            didResumeStart = true
            startContinuation = nil
            continuation.resume()
        case let .failed(error):
            didResumeStart = true
            startContinuation = nil
            continuation.resume(throwing: error)
        case .cancelled:
            didResumeStart = true
            startContinuation = nil
            continuation.resume(throwing: RaycastServerError.cancelled)
        default:
            break
        }
    }

    @MainActor
    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            var buffer = buffer
            if let data {
                buffer.append(data)
            }
            Task { @MainActor in
                guard let self else {
                    connection.cancel()
                    return
                }
                if let request = HTTPRequestParser.parse(buffer) {
                    let response = await self.handler(request)
                    connection.send(content: response.serialized(), completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                    return
                }
                if isComplete || error != nil {
                    connection.cancel()
                    return
                }
                self.receive(on: connection, buffer: buffer)
            }
        }
    }
}

enum RaycastServerError: Error {
    case cancelled
}

private enum HTTPRequestParser {
    private static let headerDelimiter = Data([13, 10, 13, 10])

    static func parse(_ data: Data) -> RaycastHTTPRequest? {
        guard let headerRange = data.range(of: headerDelimiter) else { return nil }
        let headerData = data[..<headerRange.lowerBound]
        guard let headerString = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let method = String(parts[0])
        let path = String(parts[1])

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            headers[key] = value
        }

        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerRange.upperBound
        guard data.count >= bodyStart + contentLength else { return nil }
        let body = Data(data[bodyStart..<bodyStart + contentLength])

        return RaycastHTTPRequest(method: method, path: path, headers: headers, body: body)
    }
}
