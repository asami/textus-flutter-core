# TKL-managed Material delivery in Flutter Core

Decision: 2026-10-24. Status: specification; implementation pending.
Authority: [TKL delivery contract](../../../textus-knowledge-lake/docs/spec/tkl-managed-mobile-material-delivery.md).

Core supplies a domain-independent TKL client and transfer runtime. It obtains
logical destination and delivery instructions from TKL; it does not ask users
for Google drive/folder IDs or define Lake layout. Support Workspace Shared Drive
folders and My Drive shared folders, with Workspace as the first live route.

## Runtime behavior

- Accept committed metadata and resource references from the consumer through
  public contracts. Keep Book-specific fields and editing decisions outside Core.
- Resolve TKL's permitted destination, prepare delivery, transfer originals and
  finalize registration using the returned delivery reference.
- A provider adapter can consume concrete upload instructions, including opaque
  provider references, without elevating them to editable application settings.
- Persist only the execution information required for queued/background work,
  recovery and progress. TKL remains the configuration authority.
- Preserve offline capture, originals, completed uploads and targeted retry.
  Reconcile uncertain outcomes with TKL before repeating remote effects.
- Keep resource upload, TKL registration and Editing Studio submission outcomes
  distinct. Publish registration success only from TKL's receipt.
- Resolve current configuration for new deliveries; resume existing ones through
  their TKL reference. Configuration changes cannot silently retarget pending work.
- Sign-in/consent and provider token renewal use platform facilities. Do not
  accept server service-account keys, invent fixed expiry gates or add integrity
  ledgers. Respect actual provider authorization and transfer-session outcomes.

## Migration

The existing Drive connection/HTTP adapters and durable queue are reusable
implementation inputs, not evidence that this TKL route already works. Replace
client-owned destination provisioning for this route. Do not re-create the queue
or copy TKL's account/folder/placement configuration to Android.

Existing queued direct-Drive requests are not silently converted or moved.
Preserve their state and local originals; define explicit reconciliation/adoption
with TKL for prior uploads before retiring their setup path. No destructive queue
reset or app uninstall is a migration step.

App currently consumes a Core worktree via pubspec_overrides.yaml. Main's older
Phase status is not evidence that delivered Core features are absent. At entry,
integrate the actual accepted producer work before implementing only this delta.

Plan: [delivery workstream](../phase/tkl-managed-material-delivery-plan.md).
