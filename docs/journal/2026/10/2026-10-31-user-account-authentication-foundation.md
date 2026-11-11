# User-account authentication foundation and successor binding

Date: 2026-10-31
Scope: PHASE-6.10 / ESA610-08A, shared Core authentication state and lifecycle
Status: foundation implemented; real-provider/native/queue acceptance pending

## Authority evidence and limits

The authorized Studio server-owner handoff identifies Studio source `5ca141b`
in `/Users/asami/.codex/worktrees/ess12-workbench-admission/nict-editing-studio`
and `textus-user-account` source `fab35a1`. This is source evidence, not an
accepted participant HTTP deployment. The user-account source inventory covers
identifier/password login, email challenge with `challengeId`/code, refresh,
current-session logout and `getMyAccount`. Successful authentication supplies
the authoritative `userAccountId`; refresh rotates access/refresh pairs.
UserAccount, principal and session identities are separate. Token material is
private to the eventual protected backend and must not enter presentation,
settings, queues or journals.

Existing Studio Material intake/editor has a fixed development Service guard.
It does not establish participant Material ownership. ESS5-01/02 participant
endpoint acceptance, runnable endpoint and real request/response envelope and
EntityId/ownership specimens remain absent. No guessed REST route is promoted
to an accepted URL here. Expiry, JSON shape and client TTL are not inferred from
the state foundation.

## Safe common consumer contract

Core now exports the normalized authentication values, backend port and
`UserAccountAuthenticationClient` through its normal public entrypoint. The
[client specification](../../../spec/user-account-authentication-client.md)
defines the complete safe public state and lifetime contract.

Framework's shared login UI can observe status, safe authoritative account,
email challenge channel, safe failure, revision and separate logout facts. It
can request sign-in, challenge verification, refresh, cancellation, logout and
close. An unavailable client is an honest no-IO state while the real adapter is
unconfigured. Labels and successful UI actions never establish server authority.
App/Framework must not supply a substitute credential verifier or session issuer.

Core owns action serialization before callbacks, synchronous state withdrawal,
retirement of stale operations and joining accepted backend work before admitting
new sign-in. Refresh can only preserve the exact previous account. Cancellation
and late completion cannot restore retired authentication. Logout distinguishes
local credential clearance from remote current-session revocation. Owned-backend
close drains and closes once; borrowed handles remain open. Close/dispose never
implicitly log out or delete retained work.

The controlled backend in executable specifications is test-only. These tests
exercise client observables and ordering; they do not establish a real provider,
protected credential persistence, participant HTTP authorization or successful
Material submission.

## Required successor work and acceptance inputs

Current work remains open for all of the following:

- Obtain accepted participant HTTP endpoint and real login/challenge/refresh/
  logout/account specimens, including envelope, opaque identity and ownership
  semantics, from the authority owners. Bind those specimens without inventing
  URLs, response formats, expiry or permission conditions.
- Implement the Core real authority adapter and Android native protected
  credential store. Honor operation retirement before credential commit and
  prove bounded drain under cancelled, stale and closing operations. Validate
  normalized account/challenge results without exposing response bodies or
  raw tokens to consumer state.
- Bind authenticated transport to the existing submission credential port and
  account-safe queue ownership. Preserve offline capture and retained work;
  logout/account changes must not silently reassign pending uploads or drafts.
  Obtain participant Material ownership acceptance beyond the fixed development
  Service guard.
- Connect Framework's shared login UI and App consumption to the genuine Core
  backend while retaining explicit unavailable/failure states when unconfigured.
- Complete real-provider login, refresh/refusal, correct-owner submission and
  logout acceptance on both Android and iPhone. Android-first foundation work
  does not reduce the remaining both-platform acceptance requirements.

Full ESA610-01..08 and TFC-UA01/02 acceptance remain pending. This successor
contract records the foundation and integration inputs; it does not claim those
gates closed.
