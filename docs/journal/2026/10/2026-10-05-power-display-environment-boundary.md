# Power and Persistent Display Environment Boundary

Date: 2026-10-05
Status: architecture direction
Driver: persistent Control Center Flutter dashboard

Textus Flutter Core should expose domain-neutral runtime observations needed by higher-level presentation policy without deciding application presentation modes.

Candidate environment facts include power/charging state, display/orientation facts and platform capability needed to request persistent display/wake-lock behavior. These belong with DeviceEnvironment/platform services.

Core must not decide that charging implies Dashboard or Stand mode. It must not know Control Center, Ambient presentation semantics, burn-in policy or application inactivity policy. TFAF combines Core observations with application/user presentation policy.

If an existing maintained Flutter plugin supplies a capability, prefer a thin provider/adapter boundary over reimplementing native platform logic. This direction does not by itself select a package dependency or add implementation to the current release.
