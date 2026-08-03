//
//  MultipartFormData.swift
//  Echo
//
//  Provider-independent multipart/form-data builder.
//

import Foundation

public struct MultipartFormData: Sendable {
    public let boundary: String
    private var parts: [Part] = []

    public init(boundary: String = "EchoBoundary-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    public var contentType: String {
        "multipart/form-data; boundary=\(boundary)"
    }

    mutating func addTextField(name: String, value: String) {
        parts.append(
            Part(
                name: name,
                fileName: nil,
                mimeType: nil,
                data: Data(value.utf8)
            )
        )
    }

    /// Alias with terminology used by common multipart libraries.
    mutating func addField(name: String, value: String) {
        addTextField(name: name, value: value)
    }

    mutating func addFile(
        name: String,
        fileName: String,
        mimeType: String,
        data: Data
    ) {
        addBinaryData(name: name, fileName: fileName, mimeType: mimeType, data: data)
    }

    mutating func addBinaryData(
        name: String,
        fileName: String? = nil,
        mimeType: String,
        data: Data
    ) {
        parts.append(
            Part(
                name: name,
                fileName: fileName,
                mimeType: mimeType,
                data: data
            )
        )
    }

    public var encodedData: Data {
        var body = Data()
        let lineBreak = Data("\r\n".utf8)

        for part in parts {
            body.append(Data("--\(boundary)\r\n".utf8))
            var disposition = "Content-Disposition: form-data; name=\"\(escaped(part.name))\""
            if let fileName = part.fileName {
                disposition += "; filename=\"\(escaped(fileName))\""
            }
            body.append(Data("\(disposition)\r\n".utf8))
            if let mimeType = part.mimeType {
                body.append(Data("Content-Type: \(mimeType)\r\n".utf8))
            }
            body.append(lineBreak)
            body.append(part.data)
            body.append(lineBreak)
        }

        body.append(Data("--\(boundary)--\r\n".utf8))
        return body
    }

    /// Creates a provider-independent HTTP request carrying this body.
    public func makeRequest(
        url: URL,
        method: HTTPMethod = .post,
        headers: [String: String] = [:],
        timeout: TimeInterval? = nil
    ) -> HTTPRequest {
        var mergedHeaders = headers
        mergedHeaders["Content-Type"] = contentType
        return HTTPRequest(
            url: url,
            method: method,
            headers: mergedHeaders,
            body: encodedData,
            timeout: timeout
        )
    }

    private func escaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private struct Part: Sendable {
        let name: String
        let fileName: String?
        let mimeType: String?
        let data: Data
    }
}
