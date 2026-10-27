Unchanged producer-authored consumer goldens from
`KnowledgeHubProject/nict-editing-studio`,
`src/test/resources/display/protocol/v1` (ESS2-04 App handoff v1).
Their original LF, UTF16 escapes and supplied order are preserved.
The dated context is a codec input under the producer's fixed test clock;
it must not be provisioned as a current live flow. These files are normative
test inputs, not execution output. They are never regenerated from the decoder.

ESA5-03 additionally consumes the producer-authored `mutation-descriptor.json`
and `mutation-update-title.json` from the same directory in the selected
`server-esa5` checkout (Step base `ae214739872de8423033b75a66bb274101140d17`).
The descriptor orders title, intrinsically readonly stage, then description.
The title request carries no resource revision: its strong If-Match header is a
separate transport observation. These two files are copied byte for byte,
including the terminal LF; mutation result/error matrices are controlled test
inputs, not additional producer goldens or server execution evidence.
