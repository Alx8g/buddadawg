import Foundation
import FoundationModels

/// Command Mode: rewrites the user's selected text via Apple's on-device Foundation
/// Models (~3B params). Fully local — the selection never leaves the Mac. Only exists
/// when Apple Intelligence is enabled and its assets are downloaded; every entry point
/// checks `isAvailable` first so the feature silently hides otherwise.
enum RewriteEngine {
    static var isAvailable: Bool {
        if #available(macOS 26.0, *) {
            return SystemLanguageModel.default.availability == .available
        }
        return false
    }

    /// Shared instruction text — also used as the prewarm prefix so the constant
    /// part of every prompt is already hot when the rewrite fires.
    static let instructions = """
        You rewrite the user's selected text according to their command.
        Output ONLY the rewritten text: no preamble, no quotes around it, no explanation.
        Keep the original language and meaning unless the command says otherwise.
        """

    /// Cleanup prompt for Smart Dictation (triple-tap fn): polish a raw transcript
    /// in place rather than rewriting selected text.
    static let cleanupInstructions = """
        You clean up text that was dictated aloud. Remove filler words and false starts
        (um, uh, er, like, you know), fix grammar, spelling and punctuation, and
        capitalize properly. Keep the speaker's meaning, language, tone and wording —
        do NOT rewrite, summarize, translate, sanitize or censor anything. Preserve
        profanity, slang, swearing and emphasis EXACTLY as spoken; never make the text
        more formal or polite. Output ONLY the cleaned text.
        """

    /// Warms the on-device model while the user is still speaking, so the cold
    /// penalty overlaps speech instead of landing after it. `prefix` selects which
    /// instruction set to prewarm (rewrite vs cleanup). Fire-and-forget; a no-op
    /// when Apple Intelligence is unavailable.
    static func prewarm(prefix: String = instructions) {
        guard #available(macOS 26.0, *), isAvailable else { return }
        if #available(macOS 26.0, *) {
            LanguageModelSession().prewarm(promptPrefix: Prompt(prefix))
        }
    }

    /// Cleans a raw transcript in place: fillers, false starts, grammar, punctuation.
    /// Returns nil on any failure so callers fall back to the unprocessed text.
    static func cleanup(_ text: String) async -> String? {
        guard #available(macOS 26.0, *), isAvailable, !text.isEmpty else { return nil }
        // Prefill scales with input length; 8000 chars covers very long dictations
        // while keeping prefill ~1-2 s. Output cap allows ~3x expansion headroom.
        let clipped = text.count > 8000 ? String(text.prefix(8000)) : text
        let prompt = """
        \(cleanupInstructions)

        Text:
        \(clipped)
        """
        do {
            if #available(macOS 26.0, *) {
                let session = LanguageModelSession()
                let options = GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 4096)
                let response = try await session.respond(to: prompt, options: options)
                let cleaned = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                return cleaned.isEmpty ? nil : cleaned
            }
        } catch { return nil }
        return nil
    }

    /// Rewrites `text` per the spoken `command` ("make this formal", "shorten this").
    /// Returns only the rewritten text — the model is instructed to emit nothing else.
    @available(macOS 26.0, *)
    static func rewrite(_ text: String, command: String) async throws -> String {
        // Prefill cost scales with input and decode cost with output — both are
        // token-priced on the Neural Engine. 3000 chars keeps prefill ~1 s; the
        // response cap below bounds generation so a "make it longer" command on a
        // huge selection can't run away for 15 s.
        let clipped = text.count > 3000 ? String(text.prefix(3000)) : text
        let session = LanguageModelSession()
        let prompt = """
        \(instructions)

        Command: \(command)

        Text:
        \(clipped)
        """
        // Greedy decoding: deterministic and a touch faster than sampling — right
        // trade for a rewrite task. 1024 tokens covers ~4k chars of output.
        let options = GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 1024)
        let response = try await session.respond(to: prompt, options: options)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Availability-checked wrapper for callers on any deployment target.
    static func rewriteChecked(_ text: String, command: String) async throws -> String {
        guard #available(macOS 26.0, *), isAvailable else {
            throw NSError(domain: "Buddadawg", code: 10,
                          userInfo: [NSLocalizedDescriptionKey: "Apple Intelligence is not available"])
        }
        return try await rewrite(text, command: command)
    }
}

