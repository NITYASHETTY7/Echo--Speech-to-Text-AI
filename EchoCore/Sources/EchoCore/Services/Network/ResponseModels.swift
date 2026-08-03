//
//  ResponseModels.swift
//  Echo
//
//  Provider-independent response value types used by HTTPClient.
//

import Foundation

public struct HTTPResponse: Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let data: Data
    public let url: URL?

    public init(
        statusCode: Int,
        headers: [String: String] = [:],
        data: Data = Data(),
        url: URL? = nil
    ) {
        self.statusCode = statusCode
        self.headers = headers
        self.data = data
        self.url = url
    }
}
