//
//  NetworkError.swift
//  Echo
//
//  Provider-independent networking failures. Provider/API-specific decoding
//  belongs to later phases.
//

import Foundation

enum NetworkError: Error, LocalizedError, Equatable, Sendable {
    case badRequest
    case unauthorized
    case forbidden
    case notFound
    case requestTimeout
    case conflict
    case payloadTooLarge
    case unprocessableEntity
    case tooManyRequests
    case internalServerError
    case badGateway
    case serviceUnavailable
    case gatewayTimeout
    case unexpectedStatus(code: Int)
    case timeout
    case noInternet
    case sslError
    case decodingFailed(reason: String)
    case cancelled
    case invalidResponse
    case transportError(reason: String)

    static func from(statusCode: Int) -> NetworkError? {
        switch statusCode {
        case 400: return .badRequest
        case 401: return .unauthorized
        case 403: return .forbidden
        case 404: return .notFound
        case 408: return .requestTimeout
        case 409: return .conflict
        case 413: return .payloadTooLarge
        case 422: return .unprocessableEntity
        case 429: return .tooManyRequests
        case 500: return .internalServerError
        case 502: return .badGateway
        case 503: return .serviceUnavailable
        case 504: return .gatewayTimeout
        default: return nil
        }
    }

    static func from(urlError: URLError) -> NetworkError {
        switch urlError.code {
        case .timedOut:
            return .timeout
        case .cancelled:
            return .cancelled
        case .notConnectedToInternet,
             .networkConnectionLost,
             .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed:
            return .noInternet
        case .secureConnectionFailed,
             .serverCertificateUntrusted,
             .serverCertificateHasBadDate,
             .serverCertificateHasUnknownRoot,
             .clientCertificateRejected,
             .clientCertificateRequired:
            return .sslError
        default:
            return .transportError(reason: urlError.localizedDescription)
        }
    }

    var errorDescription: String? {
        switch self {
        case .badRequest:
            return "The request was invalid."
        case .unauthorized:
            return "Authentication failed. Check the API key."
        case .forbidden:
            return "Access was forbidden. Check the API key permissions."
        case .notFound:
            return "The requested endpoint was not found."
        case .requestTimeout, .timeout:
            return "The network request timed out."
        case .conflict:
            return "The request conflicted with the current server state."
        case .payloadTooLarge:
            return "The uploaded payload is too large."
        case .unprocessableEntity:
            return "The server could not process the request."
        case .tooManyRequests:
            return "Too many requests. Please try again later."
        case .internalServerError:
            return "The server encountered an internal error."
        case .badGateway:
            return "The upstream server returned an invalid response."
        case .serviceUnavailable:
            return "The service is temporarily unavailable."
        case .gatewayTimeout:
            return "The upstream server timed out."
        case let .unexpectedStatus(code):
            return "The server returned HTTP status \(code)."
        case .noInternet:
            return "No internet connection."
        case .sslError:
            return "A secure connection could not be established."
        case let .decodingFailed(reason):
            return "The server response could not be decoded: \(reason)"
        case .cancelled:
            return "The request was cancelled."
        case .invalidResponse:
            return "The server returned an invalid response."
        case let .transportError(reason):
            return "A network error occurred: \(reason)"
        }
    }
}
