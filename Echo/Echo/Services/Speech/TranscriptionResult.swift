//
//  TranscriptionResult.swift
//  Echo
//
//  Shared result returned by every SpeechProvider.
//

import Foundation

struct TranscriptionResult: Equatable, Sendable {
    let text: String
}
