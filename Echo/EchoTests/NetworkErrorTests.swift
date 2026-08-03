//
//  NetworkErrorTests.swift
//  EchoTests
//

import Foundation
import Testing
@testable import EchoCore

struct NetworkErrorTests {
    @Test("Every required HTTP status maps to a typed NetworkError")
    func statusMappings() {
        let expected: [Int: NetworkError] = [
            400: .badRequest,
            401: .unauthorized,
            403: .forbidden,
            404: .notFound,
            408: .requestTimeout,
            409: .conflict,
            413: .payloadTooLarge,
            422: .unprocessableEntity,
            429: .tooManyRequests,
            500: .internalServerError,
            502: .badGateway,
            503: .serviceUnavailable,
            504: .gatewayTimeout,
        ]

        for (statusCode, expectedError) in expected {
            #expect(NetworkError.from(statusCode: statusCode) == expectedError)
            #expect(expectedError.errorDescription?.isEmpty == false)
        }
        #expect(NetworkError.from(statusCode: 200) == nil)
        #expect(NetworkError.from(statusCode: 418) == nil)
    }

    @Test("URLSession transport errors map to network categories")
    func transportMappings() {
        #expect(NetworkError.from(urlError: URLError(.timedOut)) == .timeout)
        #expect(NetworkError.from(urlError: URLError(.cancelled)) == .cancelled)
        #expect(NetworkError.from(urlError: URLError(.notConnectedToInternet)) == .noInternet)
        #expect(NetworkError.from(urlError: URLError(.cannotFindHost)) == .noInternet)
        #expect(NetworkError.from(urlError: URLError(.secureConnectionFailed)) == .sslError)
    }

    @Test("All typed errors provide localized descriptions")
    func localizedDescriptions() {
        let errors: [NetworkError] = [
            .badRequest, .unauthorized, .forbidden, .notFound, .requestTimeout,
            .conflict, .payloadTooLarge, .unprocessableEntity, .tooManyRequests,
            .internalServerError, .badGateway, .serviceUnavailable, .gatewayTimeout,
            .unexpectedStatus(code: 418), .timeout, .noInternet, .sslError,
            .decodingFailed(reason: "invalid JSON"), .cancelled, .invalidResponse,
            .transportError(reason: "offline"),
        ]

        for error in errors {
            #expect(error.errorDescription?.isEmpty == false)
        }
    }
}
