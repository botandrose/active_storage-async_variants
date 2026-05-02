## [Unreleased]

- Touch attached records when a variant transitions to processed, so consumer caches keyed on `cache_key_with_version` invalidate without needing manual cascading. Multi-hop cascades remain the consumer's responsibility via standard Rails `touch:` or `after_touch`.

## [0.1.0] - 2026-03-03

- Initial release
