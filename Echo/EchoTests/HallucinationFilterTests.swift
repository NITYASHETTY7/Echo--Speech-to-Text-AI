//
//  HallucinationFilterTests.swift
//  EchoTests
//

import Testing
@testable import EchoCore

struct HallucinationFilterTests {
    @Test("Normal transcript passes the filter")
    func normalTranscript() {
        #expect(HallucinationFilter.passes(text: "Hello, world!", segments: nil))
    }

    @Test("High average no_speech_prob discards the transcript")
    func highAverageProbability() {
        let segs: [[String: Any]] = [
            ["no_speech_prob": 0.7],
            ["no_speech_prob": 0.6],
        ]
        #expect(!HallucinationFilter.passes(text: "Hello", segments: segs))
    }

    @Test("High max no_speech_prob discards the transcript")
    func highMaxProbability() {
        let segs: [[String: Any]] = [
            ["no_speech_prob": 0.1],
            ["no_speech_prob": 0.85],
        ]
        #expect(!HallucinationFilter.passes(text: "Hello", segments: segs))
    }

    @Test("Acceptable no_speech_prob passes the filter")
    func acceptableProbability() {
        let segs: [[String: Any]] = [
            ["no_speech_prob": 0.1],
            ["no_speech_prob": 0.2],
        ]
        #expect(HallucinationFilter.passes(text: "Acceptable text", segments: segs))
    }

    @Test("Known hallucination phrases are discarded")
    func knownPhrases() {
        let phrases = ["thank you.", "thank you", "you", "thanks.", "thanks", ".", "..", "...", "bye.", "bye"]
        for phrase in phrases {
            #expect(!HallucinationFilter.passes(text: phrase, segments: nil))
        }
    }

    @Test("Known phrase matching is case-insensitive")
    func caseInsensitiveMatch() {
        #expect(!HallucinationFilter.passes(text: "Thank You.", segments: nil))
        #expect(!HallucinationFilter.passes(text: "THANK YOU", segments: nil))
    }

    @Test("Empty segments array skips probability guard")
    func emptySegments() {
        #expect(HallucinationFilter.passes(text: "Real speech.", segments: []))
    }

    @Test("Nil segments skips probability guard")
    func nilSegments() {
        #expect(HallucinationFilter.passes(text: "Real speech.", segments: nil))
    }

    @Test("Missing no_speech_prob defaults to 0.0 and passes")
    func missingProbabilityKey() {
        let segs: [[String: Any]] = [[:]]
        #expect(HallucinationFilter.passes(text: "No prob key.", segments: segs))
    }
}
