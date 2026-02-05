import Foundation

struct RaycastHTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    func headerValue(for name: String) -> String? {
        headers[name.lowercased()]
    }
}

struct RaycastHTTPResponse {
    let statusCode: Int
    let reasonPhrase: String
    let headers: [String: String]
    let body: Data

    func serialized() -> Data {
        var lines: [String] = [
            "HTTP/1.1 \(statusCode) \(reasonPhrase)",
        ]
        var headersWithLength = headers
        headersWithLength["Content-Length"] = "\(body.count)"
        for (key, value) in headersWithLength {
            lines.append("\(key): \(value)")
        }
        lines.append("")
        let headerData = lines.joined(separator: "\r\n").data(using: .utf8) ?? Data()
        return headerData + Data("\r\n".utf8) + body
    }

    static func json<T: Encodable>(statusCode: Int, reasonPhrase: String = "OK", payload: T) -> RaycastHTTPResponse {
        let body = (try? JSONEncoder().encode(payload)) ?? Data()
        return RaycastHTTPResponse(
            statusCode: statusCode,
            reasonPhrase: reasonPhrase,
            headers: ["Content-Type": "application/json; charset=utf-8"],
            body: body,
        )
    }
}

struct RaycastEnvelope<T: Encodable>: Encodable {
    let ok: Bool
    let data: T?
    let error: String?
    let message: String?
}

enum RaycastHTTPError {
    static func response(code: Int, error: String, message: String) -> RaycastHTTPResponse {
        let payload = RaycastEnvelope<RaycastEmptyPayload>(
            ok: false,
            data: nil,
            error: error,
            message: message,
        )
        return RaycastHTTPResponse.json(
            statusCode: code,
            reasonPhrase: "Error",
            payload: payload,
        )
    }
}

struct RaycastEmptyPayload: Encodable {}
