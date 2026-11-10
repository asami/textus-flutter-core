# Web response normal completion

Status: focused regression verified; independent review and actual paired
Phase7.1 observation remain pending. This is no Phase closure.

The retained App/server BMFT observation005 received HTTP200 and rendered the
preview controls/rows, while the browser observer's unchanged response.json()
failed with request-cancelled. No new registration, create or admission occurred.
The observer classification alone did not identify the cancelling party.

The selected Core browser transport unconditionally aborted Fetch and cancelled
the response reader even after normal EOF. Its abort-trigger listener also
aborted completed requests. package:http1.6's existing Abortable contract says
that completing the trigger after the response is fully complete has no effect.
This is the confirmed local contract defect; its causal effect on the retained
real browser/DevTools symptom still requires the same paired observation.

The limited correction retires normal EOF/null-body responses from the pending
set without aborting or cancelling a finished reader. Late triggers act only
while their controller is pending. Unfinished/error/early-cancel paths retain
abort and guarded reader cancellation; close still aborts outstanding requests.
The higher-level HTTP session, timeout, response-size, credential and account
retirement logic are unchanged. Same-origin/path validation, capability host and
header restrictions, omitted credentials, redirect refusal and cache/referrer
settings remain unchanged. No retries, refetches or observer bypass are added.

A test-first Chrome run against the original implementation finished exit1:
four normal-completion/late-trigger cases failed with an aborted signal; the
three active cancellation cases and two existing security cases passed.
After correction, the exact Chrome transport test passed all9 cases, exit0.
The nearest existing session/authentication-backend regressions passed128 cases,
exit0, including retirement, uncertain mutation, response limits and deadlines.
Analysis of the exact two Dart paths found no issues; Dart formatting and the
owned whitespace check passed. These are focused host checks, not a repository
full gate or real BMFT/Book acceptance.

The repair worker was /root/core_web_eof_fix_20261111, registered
cncf_fix_worker_luna_xhigh, configured GPT-6.1 Sol/high: one start plus one
same-manifest resume. It edited only the adapter and existing browser transport
test, without tests, self-review or commit. The parent selected the boundary,
confirmed the expected red case, inspected the diff and executed validation.
Existing failed runs, source material, counters, two-user fixture and workflow
Session remain retained by the server owner. No additional Drive operation,
Goal binding, public API, dependency or server implementation change is implied.

Independent focused read-only review by /root/core_web_eof_review_20261111,
GPT-6.1 Sol/high, returned PASS with no Current Boundary Blocker, Hygiene or
Development Candidate. It inspected both complete Dart programs, this journal,
the direct Session/backend edges and installed http1.6 sources without editing
or executing. The parent admitted that exact source and actual focused evidence
and notified the existing server owner to resume the same joined observation.
This review does not establish real browser symptom closure or Phase acceptance.

## Actual joined observation006

The owner rebuilt Web from the selected Core and retained App source. The
parent also inspected the generated main.dart.js: its response EOF branch has
the completed guard, and its late-trigger callback checks pending membership.
Thus the corrected code is present in the actual generated artifact.
Nevertheless, observation006 still failed at the same reply.json boundary with
request-cancelled. The App preview rows rendered, create/admit counts stayed0/0,
no recovery key or page error appeared, and readiness/cleanup succeeded. No
registration or cloud creation occurred. The normal-EOF contract defect is
fixed and regression-tested, but it is NOT the established cause/repair of this
real observer symptom. Retain both facts without rewriting old failures.

The parent is preparing a separate transparent harness observation to determine
whether the actual page Fetch AbortSignal fires before cleanup. No additional
Core production correction is selected from the still-ambiguous symptom.
