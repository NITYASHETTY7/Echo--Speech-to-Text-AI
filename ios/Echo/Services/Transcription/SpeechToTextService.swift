import Foundation

/// Protocol for Speech-To-Text Transcription engine.
public protocol SpeechToTextServiceProtocol {
    func transcribeAudio(url: URL) async throws -> String
}

/// Service simulating / executing Speech-to-Text transcription.
public class SpeechToTextService: SpeechToTextServiceProtocol {
    public init() {}
    
    public func transcribeAudio(url: URL) async throws -> String {
        // Simulates audio transcription step
        try await Task.sleep(nanoseconds: 100_000_000)
        return "This is the raw transcription produced by the speech to text engine."
    }
}
