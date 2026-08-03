//
//  RequestModels.swift
//  Echo
//
//  Provider-independent request value types used by HTTPClient.
//

import Foundation

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
    case head = "HEAD"
}

public struct HTTPRequest: Sendable {
    public let url: URL
    public let method: HTTPMethod
    public var headers: [String: String]
    public var body: Data?
    public var timeout: TimeInterval?

    public init(
        url: URL,
        method: HTTPMethod = .get,
        headers: [String: String] = [:],
        body: Data? = nil,
        timeout: TimeInterval? = nil
    ) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
        self.timeout = timeout
    }

    public var urlRequest: URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.allHTTPHeaderFields = headers
        request.httpBody = body
        if let timeout {
            request.timeoutInterval = timeout
        }
        return request
    }
}
