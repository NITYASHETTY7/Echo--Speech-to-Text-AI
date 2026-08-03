//
//  TranscriptionResult.swift
//  Echo
//
//  Shared result returned by every SpeechProvider.
//

import Foundation

public struct TranscriptionResult: Equatable, Sendable {
    public let text: String
}
