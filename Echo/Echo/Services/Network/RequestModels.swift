//
//  RequestModels.swift
//  Echo
//
//  Provider-independent request value types used by HTTPClient.
//

import Foundation

enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
    case head = "HEAD"
}

struct HTTPRequest: Sendable {
    let url: URL
    let method: HTTPMethod
    var headers: [String: String]
    var body: Data?
    var timeout: TimeInterval?

    init(
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

    var urlRequest: URLRequest {
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
