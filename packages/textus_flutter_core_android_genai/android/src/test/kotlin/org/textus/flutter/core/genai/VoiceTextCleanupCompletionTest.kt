package org.textus.flutter.core.genai

import com.google.mlkit.genai.prompt.Candidate
import org.junit.Assert.assertEquals
import org.junit.Assert.fail
import org.junit.Test

class VoiceTextCleanupCompletionTest {
    @Test fun onlyNormalStopCanBecomeAnEditableCleanupSuggestion() {
        // Given the real selected SDK's finish-reason domain.
        requireCompleteVoiceCleanup(Candidate.FinishReason.STOP)
        for (reason in listOf(null, Candidate.FinishReason.MAX_TOKENS, Candidate.FinishReason.OTHER, -1)) {
            // When a truncated or unqualified completion reaches the native boundary.
            try {
                requireCompleteVoiceCleanup(reason)
                fail("Incomplete cleanup was accepted")
            } catch (failure: GeminiNanoFailure) {
                // Then caller text remains recoverable and no successful suggestion is returned.
                assertEquals("incompleteResponse", failure.code)
            }
        }
    }
}
