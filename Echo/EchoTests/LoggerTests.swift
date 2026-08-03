//
//  LoggerTests.swift
//  EchoTests
//
//  Phase 0 unit tests: verifies EchoLog's header-redaction behavior, which
//  mirrors the Android HttpLoggingInterceptor regex redaction in AppModule.kt.
//  This is the only unit-testable business logic introduced in Phase 0;
//  AppConfig is pure constants and AppEnvironment is SwiftUI wiring with no
//  branching logic, so neither requires dedicated tests at this phase.
//

import Testing
@testable import EchoCore

struct LoggerTests {

    @Test("Authorization header value is redacted, case-insensitively")
    func redactsAuthorizationHeader() {
        let input = "Authorization: Bearer sk-super-secret-key-123"
        let result = EchoLog.redactingSensitiveHeaders(input)

        #expect(result == "Authorization: [REDACTED]")
        #expect(!result.contains("sk-super-secret-key-123"))
    }

    @Test("x-goog-api-key header value is redacted")
    func redactsGoogleApiKeyHeader() {
        let input = "x-goog-api-key: AIzaSyDsecretvalue"
        let result = EchoLog.redactingSensitiveHeaders(input)

        #expect(result == "x-goog-api-key: [REDACTED]")
        #expect(!result.contains("AIzaSyDsecretvalue"))
    }

    @Test("api-key header value is redacted")
    func redactsGenericApiKeyHeader() {
        let input = "api-key: my-azure-key-value"
        let result = EchoLog.redactingSensitiveHeaders(input)

        #expect(result == "api-key: [REDACTED]")
        #expect(!result.contains("my-azure-key-value"))
    }

    @Test("Header name casing does not prevent redaction")
    func redactsRegardlessOfCase() {
        let input = "AUTHORIZATION: Token abc123"
        let result = EchoLog.redactingSensitiveHeaders(input)

        #expect(result == "AUTHORIZATION: [REDACTED]")
    }

    @Test("Multi-line log blocks redact only sensitive lines")
    func redactsOnlyMatchingLinesInMultilineBlock() {
        let input = """
        POST /v2/transcript HTTP/1.1
        Authorization: my-secret-token
        Content-Type: application/json
        """
        let result = EchoLog.redactingSensitiveHeaders(input)

        #expect(result.contains("Content-Type: application/json"))
        #expect(result.contains("Authorization: [REDACTED]"))
        #expect(!result.contains("my-secret-token"))
    }

    @Test("Non-sensitive content passes through unchanged")
    func leavesNonSensitiveContentUntouched() {
        let input = "Content-Type: multipart/form-data; boundary=xyz"
        let result = EchoLog.redactingSensitiveHeaders(input)

        #expect(result == input)
    }
}
