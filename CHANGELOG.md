## [Unreleased]

- Touch attached records when a variant transitions to processed, so consumer caches keyed on `cache_key_with_version` invalidate without needing manual cascading. Multi-hop cascades remain the consumer's responsibility via standard Rails `touch:` or `after_touch`.
- Dedupe concurrent `.processed` calls so they enqueue at most one `ProcessJob` per blob+variation. Previously, every call before the first job flipped state to "processing" enqueued another job; each job created a fresh variant blob, leaving the others as orphans. The record is now created as `pending` at enqueue time, using the unique index on `active_storage_variant_records (blob_id, variation_digest)` (already shipped by the standard Active Storage migration) as the dedupe key. Records stuck in `failed` are reset to `pending` on the next call so retries still work.

## [0.1.0] - 2026-03-03

- Initial release
