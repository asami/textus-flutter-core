# Flutter Core Untrusted Client Security Context

Status: initial projection
Updated: 2026-10-16
Canonical reference: asami/goldenport-cncf Textus Security Architecture / Entity Authorization / APK Untrusted Client note

Flutter Core may centralize client authentication/session token storage, refresh and transport, but it does not implement authoritative business authorization.

Client identity/session facts are sent through the standard application framework to server Operations. UI hiding, local role checks, APK integrity/attestation and local validation are defense-in-depth/UX signals only. They do not grant Entity, Material, Lake or source-resource access.

Secrets with server-wide or administrative authority must not be embedded in the client bundle.
