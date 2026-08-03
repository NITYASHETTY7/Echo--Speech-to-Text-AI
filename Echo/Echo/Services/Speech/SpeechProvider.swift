//
//  SpeechProvider.swift
//  Echo
//
//  Provider contract only. Concrete network implementations arrive in Phase 4.
//

import Foundation

protocol SpeechProvider: AnyObject {
    var config: ProviderConfig { get }

    /// Transcribes a local audio file using the configured provider.
    /// Implementations must remain cancellable when networking is added later.
    func transcribe(
        audioFile: URL,
        model: String,
        language: String?
    ) async throws -> TranscriptionResult
}
