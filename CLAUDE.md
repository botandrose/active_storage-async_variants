# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A Rails engine gem that extends Active Storage with async-safe variant processing. Solves the problem where slow transformations (e.g., video transcoding) block requests or fail silently. The `fallback:` option on a variant definition opts it into async processing.

## Commands

```bash
bundle exec rake          # Run full test suite (default task is :spec)
bundle exec rspec         # Run all specs
bundle exec rspec spec/active_storage/async_variants_spec.rb  # Run the main spec file
bundle exec rspec spec/active_storage/async_variants_spec.rb -e "description" # Run specific example
```

## Architecture

The gem works by prepending extension modules onto Active Storage classes:

- **`VariationExtension`** → `ActiveStorage::Variation` — extracts async options (`fallback:`, `transformer:`, `max_retries:`) from variant config before passing the rest to standard Active Storage
- **`AttachmentExtension`** → `ActiveStorage::Attachment` — hooks into `transform_variants_later` to enqueue `ProcessJob` for variants with `fallback:`
- **`VariantWithRecordExtension`** → `ActiveStorage::VariantWithRecord` — overrides URL generation to serve fallback while processing; adds state query methods (`ready?`, `processing?`, `pending?`, `failed?`)
- **`ProcessJob`** — background job that determines transformer type (inline vs external) and processes accordingly

### Transformer Types

- **Inline**: implements `process(file, **options)` → blocks worker, returns `{ io:, content_type:, filename: }`
- **External**: implements `initiate(source_url:, destination_url:, callback_url:, **options)` → frees worker immediately, external service POSTs to callback URL when done

The gem detects which type by checking if `process` is overridden on the transformer class.

### Callback Endpoint

`CallbacksController` mounted at `/active_storage/async_variants/callbacks/:token` receives webhook POSTs from external services. Tokens are signed with `ActiveStorage.verifier`.

### State Machine

`VariantRecord.state`: `pending` → `processing` → `processed` (success) or `failed` (with error message and attempt count)

## Testing

- Uses RSpec with a dummy Rails app in `spec/dummy/`
- SQLite in-memory database defined in `spec/support/active_record.rb`
- Jobs use `:test` queue adapter (not executed automatically — use `perform_enqueued_jobs` to run them)
- Test helpers `create_variant_record` and `simulate_processed_variant` are defined in `spec/support/active_record.rb`
- There is one main spec file: `spec/active_storage/async_variants_spec.rb`
