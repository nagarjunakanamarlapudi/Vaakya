// VaakyaApp/Sources/Services/AIPrompts.swift
import Foundation

enum AIPrompts {

    static func enhancePrompt(transcript: String, userNotes: String, template: String, language: String) -> String {
        let languageName = TranscriptionLanguage(rawValue: language)?.displayName ?? "English"
        return """
        You are a meeting notes assistant. Analyze this meeting transcript and produce structured notes.
        Produce all notes in \(languageName).

        IMPORTANT: You MUST respond with ONLY a valid JSON array. No code, no explanations, no markdown.

        Each element in the array must have these fields:
        - "type": "summary" or "decision" or "action" or "quote"
        - "content": a clear sentence describing what was said or decided (in \(languageName))
        - "speaker": the person's name (use null for summary)
        - "timestamp_seconds": null
        - "meta_text": null

        Example output for a short meeting:
        [
          {"type": "summary", "content": "The team discussed project deadlines and assigned tasks.", "speaker": null, "timestamp_seconds": null, "meta_text": null},
          {"type": "decision", "content": "Launch date set for April 15th.", "speaker": "Sarah", "timestamp_seconds": null, "meta_text": "Agreed by all"},
          {"type": "action", "content": "Prepare the launch presentation.", "speaker": "Mike", "timestamp_seconds": null, "meta_text": "Due next Monday"},
          {"type": "quote", "content": "We need to move fast on this.", "speaker": "Sarah", "timestamp_seconds": null, "meta_text": null}
        ]

        Now analyze this transcript and return ONLY a JSON array like the example above:

        <transcript>
        \(transcript)
        </transcript>

        <user_notes>
        \(userNotes.isEmpty ? "(none)" : userNotes)
        </user_notes>

        Template style: \(template)

        Respond with ONLY the JSON array in \(languageName). Nothing else.
        """
    }

    static func chatPrompt(transcript: String, message: String, language: String) -> String {
        let languageName = TranscriptionLanguage(rawValue: language)?.displayName ?? "English"
        return """
        You are a meeting notes assistant. The user is asking a question about a meeting transcript.
        Respond in \(languageName).

        <transcript>
        \(transcript)
        </transcript>

        <user_question>
        \(message)
        </user_question>

        Provide a clear, concise answer based only on the transcript. If the answer is not in the transcript, say so.
        Respond in \(languageName). Respond in plain text, not JSON.
        """
    }

    static func translatePrompt(transcript: String, language: String) -> String {
        let languageName = TranscriptionLanguage(rawValue: language)?.displayName ?? "English"
        return """
        Translate this meeting transcript to \(languageName).
        Preserve speaker labels and timestamps exactly as they appear.
        Do NOT summarize or modify content — translate each segment verbatim.

        IMPORTANT: You MUST respond with ONLY a valid JSON array. No explanations, no markdown.

        Each element must have these fields:
        - "start": the timestamp in seconds (number)
        - "end": the end timestamp in seconds (number)
        - "text": the translated text
        - "speaker": the speaker label (keep unchanged)

        <transcript>
        \(transcript)
        </transcript>

        Respond with ONLY the JSON array. Nothing else.
        """
    }
}
