# Material Commit Transport

Status: initial projection
Updated: 2026-10-16

textus-flutter-core owns client-side Material identity allocation for the Editing Studio ingestion flow.

On Material commit, Flutter Core allocates one Material ID before transmission and applies it to both the Raw Material package and Material Data. It also assigns/records the Textus Knowledge Lake URN that Material Data uses to locate the Raw Material logically.

The commit has two independently retryable transport branches:

1. Raw Material (large files such as images, audio and video plus package metadata) is uploaded directly to the Google Drive-backed TKL Journal/Staging area.
2. Material Data (structured metadata, the same Material ID and Raw Material URN) is sent to the CNCF Material registration Operation.

The branches are not a distributed transaction. Flutter Core keeps enough durable client-side delivery state to retry either branch and converge idempotently around the same Material ID.

Security: direct Drive upload is only a bounded ingestion/data-plane capability. It does not authorize Knowledge Lake read/update/list or arbitrary Drive access. Server-wide/TKL management credentials are never embedded in the mobile client. Client-side UI/validation is not authoritative business authorization.
