## [0.4.0]

- **Breaking:** Replaced the polling-`<img>` architecture with a `<turbo-frame>` for unprocessed variants. `image_tag`/`video_tag` with `async: true` now emits a normal `<img>`/`<video>` when the variant is already processed, and a `<turbo-frame src="…">` otherwise. The frame hits a new gem-shipped endpoint (`GET /active_storage/async_variants/states/:signed_blob_id/:variation_key`) that renders one of `_processing`/`_failed`/`_processed` partials. Non-terminal renders include an inline `<script>` that schedules the frame's next reload, so the state polls itself until it terminates.
- New `app/views/active_storage/async_variants/states/` partial set — apps can override any partial by creating a same-named file in their own `app/views/active_storage/async_variants/states/`. The processing state defaults to a bare `<img>`/`<video>` pointing at the variant's URL, which the gem redirects to the app's configured `processing:` SVG.
- All CSS and JavaScript ship inline in the per-response state partials — no asset-pipeline footprint. Apps don't need to include any stylesheet or script.
- **Breaking:** `Variant#processed` and `Preview#processed` are now no-ops on bucket-backed services (they previously also lazy-enqueued `ProcessJob` for any record that wasn't already processed). Enqueue now happens only at attachment time (via `AttachmentExtension#transform_variants_later`). Pre-existing blobs that missed the auto-enqueue won't self-heal on first view; backfill via a rake task.
- New public `#enqueue!` method on both `Variant` and `Preview` with the same signature — no `respond_to?` dance. Creates a pending `VariantRecord` (RecordNotUnique guards dedupe) and dispatches `ProcessJob`. Replaces the previously private `enqueue_processing` / `enqueue_async_preview`.
- The named-variant lookup now walks one level back through `preview_image` attachments, so a request for a Variant of a video's extracted preview frame can recover the named-variant declaration from the parent record's source-video field. Fixes nil-URL 500s in dev where the cold Registry can't resolve a redirect-controller request.
- Added `turbo-rails >= 2.0` as a runtime dependency.
- Removed `RepresentationsRedirectControllerExtension`, the `[data-async-variant-*]` polling JS, the bundled `app/assets/stylesheets/active_storage_async_variants.css`, the engine's asset precompile initializer, and the `apply_async_data!` helper machinery. Consumers depending on those data attributes must migrate to targeting the new `.async-variant-state` classes or override the partials.

## [0.3.1]

- Bound the stored variant `error` to 16k chars at both write sites (the failed-status callback and `ProcessJob`'s rescue). An external transformer reporting a >64KB error payload was overflowing the `TEXT` column and 500ing the callback, leaving the variant stuck instead of marked failed.

## [0.3.0]

- Touch attached records when a variant transitions to processed, so consumer caches keyed on `cache_key_with_version` invalidate without needing manual cascading. Multi-hop cascades remain the consumer's responsibility via standard Rails `touch:` or `after_touch`.
- Dedupe concurrent `.processed` calls so they enqueue at most one `ProcessJob` per blob+variation. Previously, every call before the first job flipped state to "processing" enqueued another job; each job created a fresh variant blob, leaving the others as orphans. The record is now created as `pending` at enqueue time, using the unique index on `active_storage_variant_records (blob_id, variation_digest)` (already shipped by the standard Active Storage migration) as the dedupe key. Once a record reaches `failed` (after `ProcessJob` exhausts its 3-attempt `retry_on` cycle), further `.processed` calls no longer re-enqueue — the variant is permanently failed.
- Renamed the `fallback:` variant option to `processing:` to better describe what it represents — the placeholder served while the variant is being processed.
- New `failed:` variant option that specifies a distinct placeholder to render when the variant has permanently failed, separate from the `processing:` placeholder. Accepts `:original`, `:blank`, a String URL, or a Proc that receives the blob. Defaults to `processing:` when unspecified. Also extends `processing:` to accept a String URL directly (previously you had to wrap a static URL in a Proc).

## [0.1.0] - 2026-03-03

- Initial release
