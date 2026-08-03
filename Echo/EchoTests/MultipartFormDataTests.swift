//
//  MultipartFormDataTests.swift
//  EchoTests
//

import Foundation
import Testing
@testable import EchoCore

struct MultipartFormDataTests {
    @Test("Multipart body contains the configured boundary and closing delimiter")
    func boundaries() {
        var form = MultipartFormData(boundary: "test-boundary")
        form.addField(name: "model", value: "test-model")

        let body = String(decoding: form.encodedData, as: UTF8.self)
        #expect(body.hasPrefix("--test-boundary\r\n"))
        #expect(body.contains("--test-boundary--\r\n"))
        #expect(form.contentType == "multipart/form-data; boundary=test-boundary")
    }

    @Test("Multipart body formats multiple text fields")
    func textFields() {
        var form = MultipartFormData(boundary: "fields")
        form.addTextField(name: "model", value: "whisper")
        form.addTextField(name: "language", value: "en")

        let body = String(decoding: form.encodedData, as: UTF8.self)
        #expect(body.contains("Content-Disposition: form-data; name=\"model\"\r\n\r\nwhisper\r\n"))
        #expect(body.contains("Content-Disposition: form-data; name=\"language\"\r\n\r\nen\r\n"))
    }

    @Test("Multipart body formats file Content-Disposition and Content-Type")
    func fileAttachment() {
        var form = MultipartFormData(boundary: "file")
        form.addFile(
            name: "audio",
            fileName: "recording.m4a",
            mimeType: "audio/mp4",
            data: Data([0x01, 0x02, 0x03])
        )

        let body = String(decoding: form.encodedData, as: UTF8.self)
        #expect(body.contains("name=\"audio\"; filename=\"recording.m4a\""))
        #expect(body.contains("Content-Type: audio/mp4\r\n\r\n"))
        #expect(form.encodedData.range(of: Data([0x01, 0x02, 0x03])) != nil)
    }

    @Test("Multipart request sets Content-Type and preserves additional headers")
    func requestConstruction() {
        var form = MultipartFormData(boundary: "request")
        form.addBinaryData(name: "payload", mimeType: "application/octet-stream", data: Data([0xFF]))
        let request = form.makeRequest(
            url: URL(string: "https://example.test/upload")!,
            headers: ["Authorization": "Bearer secret"]
        )

        #expect(request.method == .post)
        #expect(request.headers["Content-Type"] == "multipart/form-data; boundary=request")
        #expect(request.headers["Authorization"] == "Bearer secret")
        #expect(request.body == form.encodedData)
    }
}
