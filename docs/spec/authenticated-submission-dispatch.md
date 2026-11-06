# Authenticated local submission dispatch

`SubmissionService` and `RegisteredMaterialHandoffService` accept the optional
readonly named composition input `requiresAuthentication`, defaulting to `false`,
and an optional borrowed `SubmissionAuthenticationContext`. Construction retains
these inputs without observing the context or starting work. These inputs express
the local participant dispatch policy. They assert no server authorization.

## Admission matrix

Both drivers apply this matrix to the immutable request selected by their durable
claim. For a registered handoff, the request is `claim.sourceRequest`.

| Requires authentication | Saved binding | Context | Admission |
| --- | --- | --- | --- |
| `false` | absent | absent | Existing legacy processing |
| `true` | absent | absent | Deny |
| Either | absent | present | Deny; never adopt the context account |
| Either | present | absent | Deny |
| Either | present | different account, authority profile or canonical base URI | Deny |
| Either | present | exact binding, current predicate false or throwing | Deny |
| Either | present | exact binding, current predicate true | Admit under that context's run fence |

Binding equality includes the exact opaque account ID, authority profile ID and
canonical authority base URI. Context observation that throws is withdrawn. A
binding records local immutable intent; it contains no credential, login proof,
server ownership assertion or grant. Local binding fields are excluded from
ordinary and registered server packets. Successful submission retains the saved
request, connection identities, payload, original mappings and registered
association; the driver never replaces account A with account B.

Participant compositions must set `requiresAuthentication: true` even when no
authentication scope can be created. The resulting null-context composition
denies both bound and legacy unbound processing. Logging out does not require a
synthetic account or dummy context. The default remains compatible with existing
unbound custom compositions that omit a context.

## Claims, safe failures and run ownership

Ordinary processing preserves its existing offline and caller-current gates
before queue claim. Registered processing preserves caller-current, then offline,
then durable handoff claim. These early returns do not observe authentication or
touch originals, providers, transport or scheduling. No construction-time callback
or background actor is introduced.

After claim, an initial authentication denial precedes original reads, hashing,
reference-access policy, credential/provider resolution and adapter dispatch. The
ordinary queue persists its existing nonretryable configuration failure with code
`authenticationRequired`, without a next automatic attempt. A registered handoff
persists `failed` with configuration failure kind and that same code. Both use
the fixed message:

> Sign in to the account bound to this submission.

The failed registered result contains the exact persisted handoff row. A failed
save after handoff lease loss returns the existing `leaseLost` result. No denial
modifies the source queue, frozen target, packet, association or saved account.
Neither path sends, obtains originals, calls a provider or schedules another run
as a consequence of admission denial.

An admitted bound run captures the exact immutable binding, borrowed context and
original caller predicate in one local predicate. Existing ownership guards use
that combined predicate after asynchronous work, before dispatch, in classified
failure handling and before ACK acceptance/publication. Retirement or predicate
failure prevents a late result from becoming progress or an accepted ACK. No
global actor map or per-record lifetime registry is involved.

Ordinary cancellation retains its release and lease-loss behavior, including any
existing transport uncertainty checkpoint. Authentication denial on a later claim
cannot disprove an earlier possible remote effect or clear legacy uncertainty.
Explicit retry under a fresh exact context can continue the same intent. A
different context fails admission without rewriting the request or resending it.

A registered claim already persists the `sending` uncertainty boundary. Caller
retirement after claim, or bound-context retirement after admission but before
transport, therefore remains conservatively `outcomeUnknown` with `runRetired`.
Retirement after possible dispatch also preserves unknown acceptance, including
the existing `acceptanceUnknown` catch behavior. A late classified rejection
cannot override a retired run's uncertainty. Timeouts, mismatched ACKs, close,
lease expiry and lease loss keep their existing classifications. Unknown or
failed handoffs require explicit same-intent reconciliation before another send.
That reconciliation preserves the original packet, request key, target and
association; dispatch still needs the exact bound current context.

## Durable ACK transaction and publication

Registered ACK handling checks the combined predicate immediately before issuing
the existing `finishHandoff` acceptance save and after its await when selecting
the returned outcome. An acceptance save issued while valid remains the store's
existing durable transaction. Retirement during that await cancels publication;
it does not roll back or overwrite an ACK already durably saved. The result may
therefore be `cancelled` while carrying the genuinely accepted saved row. Local
ACK-save errors propagate and leave the existing sending uncertainty intact;
they do not trigger fallback ACK acceptance or an automatic resend. The store
contract, transactions and lease ownership are unchanged.

## Local intent and remaining gates

Commit, enqueue, find/list, retry, reconciliation and wake retain their existing
local durable-intent semantics. They do not observe authentication or perform
credential/server IO. Ordinary Commit still validates new original bytes as
before; equal existing intent avoids those reads. Registered enqueue and
reconciliation do not read originals or call TKL, storage or Studio transports.
An unbound legacy source remains unbound through these operations. Local
inspection and history survive logout. Close immediately fences processing,
drains accepted commands and reads according to the existing service contract,
and leaves borrowed handles and durable history under their original owners.

These local dispatch gates do not replace concrete credential authority in an
authentication scope, HTTP audience/target checks, server-side participant
authorization, or idempotent remote acceptance. App composition must separately
gate explicit participant commands and labels. Native/background lifetime and
platform entry gates remain responsibilities of their owning compositions. No
new native, App, server, provider, persistence-schema or store contract is defined
here.

The host executable specification is
`test/submission/authenticated_submission_dispatch_test.dart`. It uses real
SQLite queue/handoff stores and controlled context, transport and await
boundaries. Credential authority remains specified by the authentication-scope
suite.
