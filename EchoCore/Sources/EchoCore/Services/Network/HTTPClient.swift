//
//  HTTPClient.swift
//  Echo
//
//  Reusable provider-independent URLSession client.
//

import Foundation
import os

public struct HTTPTimeouts: Sendable, Equatable {
    public let connect: TimeInterval
    public let read: TimeInterval
    public let write: TimeInterval

    public static let appDefaults = HTTPTimeouts(
        connect: AppConfig.Network.connectTimeout,
        read: AppConfig.Network.readTimeout,
        write: AppConfig.Network.writeTimeout
    )
}

public final class HTTPClient {
    private let session: URLSession
    private let timeouts: HTTPTimeouts
    private let ownsSession: Bool

    /// Optional hook applied to every `URLRequest` before submission.
    /// Used exclusively by `makeTestClient` in tests to inject handler keys;
    /// always `nil` in production.
    public var requestInterceptor: ((inout URLRequest) -> Void)?

    public init(
        session: URLSession? = nil,
        timeouts: HTTPTimeouts = .appDefaults
    ) {
        self.timeouts = timeouts
        if let session {
            self.session = session
            self.ownsSession = false
        } else {
            let configuration = URLSessionConfiguration.default
            // URLSession exposes request/resource timeouts rather than separate
            // connect/write knobs. Requests can still override the request timeout.
            configuration.timeoutIntervalForRequest = timeouts.read
            configuration.timeoutIntervalForResource = max(timeouts.read, timeouts.write)
            self.session = URLSession(configuration: configuration)
            self.ownsSession = true
        }
    }

    deinit {
        if ownsSession {
            session.invalidateAndCancel()
        }
    }

    public func execute(_ request: HTTPRequest) async throws -> HTTPResponse {
        try await execute(request.urlRequest)
    }

    public func execute(_ originalRequest: URLRequest) async throws -> HTTPResponse {
        var request = originalRequest
        if request.timeoutInterval == URLRequest(url: request.url!).timeoutInterval {
            request.timeoutInterval = timeouts.read
        }
        requestInterceptor?(&request)

        logRequest(request)
        let start = Date()
        do {
            try Task.checkCancellation()
            let (data, response) = try await session.data(for: request)
            let durationMs = Int(Date().timeIntervalSince(start) * 1_000)
            try Task.checkCancellation()

            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.invalidResponse
            }

            let statusCode = httpResponse.statusCode
            let headers = httpResponse.allHeaderFields.reduce(into: [String: String]()) { result, item in
                result[String(describing: item.key)] = String(describing: item.value)
            }
            logResponse(statusCode: statusCode, url: request.url, durationMs: durationMs, data: data)

            guard (200...299).contains(statusCode) else {
                throw NetworkError.from(statusCode: statusCode)
                    ?? .unexpectedStatus(code: statusCode)
            }

            return HTTPResponse(
                statusCode: statusCode,
                headers: headers,
                data: data,
                url: httpResponse.url
            )
        } catch let error as NetworkError {
            throw error
        } catch is CancellationError {
            throw NetworkError.cancelled
        } catch let error as URLError {
            let durationMs = Int(Date().timeIntervalSince(start) * 1_000)
            EchoLog.network.error(
                "HTTP request failed after \(durationMs, privacy: .public)ms: URLError \(error.code.rawValue, privacy: .public) — \(error.localizedDescription, privacy: .public)"
            )
            throw NetworkError.from(urlError: error)
        } catch {
            if Task.isCancelled {
                throw NetworkError.cancelled
            }
            EchoLog.network.error("HTTP request failed: \(error.localizedDescription, privacy: .public)")
            throw NetworkError.transportError(reason: error.localizedDescription)
        }
    }

    public func send<Response: Decodable>(
        _ request: HTTPRequest,
        decode type: Response.Type,
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> Response {
        let response = try await execute(request)
        do {
            return try decoder.decode(type, from: response.data)
        } catch {
            throw NetworkError.decodingFailed(reason: error.localizedDescription)
        }
    }

    private func logRequest(_ request: URLRequest) {
        let headers = request.allHTTPHeaderFields ?? [:]
        let headerText = headers
            .map { "\($0.key): \($0.value)" }
            .joined(separator: ", ")
        let safeHeaders = EchoLog.redactingSensitiveHeaders(headerText)
        let bodySize = request.httpBody?.count ?? 0
        EchoLog.network.debug(
            "→ \(request.httpMethod ?? HTTPMethod.get.rawValue, privacy: .public) \(request.url?.absoluteString ?? "", privacy: .public) body=\(bodySize, privacy: .public)B timeout=\(request.timeoutInterval, privacy: .public)s headers=[\(safeHeaders, privacy: .private)]"
        )
    }

    private func logResponse(statusCode: Int, url: URL?, durationMs: Int, data: Data) {
        let bodyPreview: String
        if data.count <= 512, let text = String(data: data, encoding: .utf8) {
            bodyPreview = text.prefix(200).description
        } else {
            bodyPreview = "\(data.count)B"
        }
        EchoLog.network.debug(
            "← \(statusCode, privacy: .public) \(url?.absoluteString ?? "", privacy: .public) [\(durationMs, privacy: .public)ms] \(bodyPreview, privacy: .private)"
        )
    }
}
