# Text revision proposals — ESA68-S1-A

Date: 2026-10-30. Authority: ESA68-S1-A@1, App PHASE-6.8.
Implementation authored in S1-A; the shared Core/TFAF route is accepted as
ESA68-S1 after focused validation and independent Step review/focused closure.

The [shared contract](../../../notes/text-revision-proposals.md) adds proofreading
and personal-comment readability operations to the existing generated-draft
request/provider/native path. Current prompts use v3; historical v2 evidence and
workspace schema1 stay readable without migration. Native parsing admits exactly
the two added operation names with null bytes and existing Japanese language and
six-key checks. The existing SDK text-only path remains the execution route.

The exported pure `TextRevisionComparison` supplies one Unicode-scalar replacement
window with exact reconstruction. Whole selected text is the adoption unit.
No TFAF interaction, App program integration or persistence fields are added.

Authored Flutter specifications cover exact source retention and rejection,
new-operation/schema1 round trips alongside retained v2 image/summary history,
operation-specific v3 JSON prompts and the real provider/service channel envelope.
Comparison cases include equal/empty strings, whole and interior replacement,
Japanese, astral and combining characters, whitespace and nonoverlap. Native JUnit
cases extend accepted operations and reject invalid text-byte/language/field
variants before model creation. Each new or modified scenario has adjacent
Given/When/Then evidence; no tests were executed by the implementation editor.

The initial parent-selected Core analysis, focused generated-draft/service/provider/
comparison checks and Android SDK/JUnit validation are complete. Independent
Step review and focused closure are accepted. Book integration and actual
Japanese device behavior, comprehensive Phase review, owning full validation
and final Phase completion remain pending. Existing unrelated formatting/header debt was
preserved; no separate follow-up debt was introduced by this slice.
