## [Unreleased]

- Touch attached records when a variant transitions to processed, so consumer caches keyed on `cache_key_with_version` invalidate without needing manual cascading. Multi-hop cascades remain the consumer's responsibility via standard Rails `touch:` or `after_touch`.
- Dedupe concurrent `.processed` calls so they enqueue at most one `ProcessJob` per blob+variation. Previously, every call before the first job flipped state to "processing" enqueued another job; each job created a fresh variant blob, leaving the others as orphans. The record is now created as `pending` at enqueue time, using the unique index on `active_storage_variant_records (blob_id, variation_digest)` (already shipped by the standard Active Storage migration) as the dedupe key. Once a record reaches `failed` (after `ProcessJob` exhausts its 3-attempt `retry_on` cycle), further `.processed` calls no longer re-enqueue — the variant is permanently failed.
- Renamed the `fallback:` variant option to `processing:` to better describe what it represents — the placeholder served while the variant is being processed.
- New `failed:` variant option that specifies a distinct placeholder to render when the variant has permanently failed, separate from the `processing:` placeholder. Accepts `:original`, `:blank`, a String URL, or a Proc that receives the blob. Defaults to `processing:` when unspecified. Also extends `processing:` to accept a String URL directly (previously you had to wrap a static URL in a Proc).

## [0.1.0] - 2026-03-03

- Initial release
