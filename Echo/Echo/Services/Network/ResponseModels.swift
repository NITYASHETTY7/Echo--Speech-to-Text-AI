//
//  ResponseModels.swift
//  Echo
//
//  Provider-independent response value types used by HTTPClient.
//

import Foundation

struct HTTPResponse: Sendable {
    let statusCode: Int
    let headers: [String: String]
    let data: Data
    let url: URL?

    init(
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
