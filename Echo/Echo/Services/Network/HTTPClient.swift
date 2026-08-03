//
//  HTTPClient.swift
//  Echo
//
//  Reusable provider-independent URLSession client.
//

import Foundation
import os

struct HTTPTimeouts: Sendable, Equatable {
    let connect: TimeInterval
    let read: TimeInterval
    let write: TimeInterval

    static let appDefaults = HTTPTimeouts(
        connect: AppConfig.Network.connectTimeout,
        read: AppConfig.Network.readTimeout,
        write: AppConfig.Network.writeTimeout
    )
}

final class HTTPClient {
    private let session: URLSession
    private let timeouts: HTTPTimeouts
    private let ownsSession: Bool

    /// Optional hook applied to every `URLRequest` before submission.
    /// Used exclusively by `makeTestClient` in tests to inject handler keys;
    /// always `nil` in production.
    var requestInterceptor: ((inout URLRequest) -> Void)?

    init(
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

    func execute(_ request: HTTPRequest) async throws -> HTTPResponse {
        try await execute(request.urlRequest)
    }

    func execute(_ originalRequest: URLRequest) async throws -> HTTPResponse {
        var request = originalRequest
        if request.timeoutInterval == URLRequest(url: request.url!).timeoutInterval {
            request.timeoutInterval = timeouts.read
        }
        requestInterceptor?(&request)

        logRequest(request)
        do {
            try Task.checkCancellation()
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()

            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.invalidResponse
            }

            let statusCode = httpResponse.statusCode
            let headers = httpResponse.allHeaderFields.reduce(into: [String: String]()) { result, item in
                result[String(describing: item.key)] = String(describing: item.value)
            }
            logResponse(statusCode: statusCode, url: request.url)

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
            throw NetworkError.from(urlError: error)
        } catch {
            if Task.isCancelled {
                throw NetworkError.cancelled
            }
            throw NetworkError.transportError(reason: error.localizedDescription)
        }
    }

    func send<Response: Decodable>(
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
            .joined(separator: "\n")
        let safeHeaders = EchoLog.redactingSensitiveHeaders(headerText)
        EchoLog.network.debug(
            "HTTP \(request.httpMethod ?? HTTPMethod.get.rawValue, privacy: .public) \(request.url?.absoluteString ?? "", privacy: .public) headers=\(safeHeaders, privacy: .private)"
        )
    }

    private func logResponse(statusCode: Int, url: URL?) {
        EchoLog.network.debug(
            "HTTP response \(statusCode, privacy: .public) \(url?.absoluteString ?? "", privacy: .public)"
        )
    }
}
