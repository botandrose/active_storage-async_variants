# ActiveStorage::AsyncVariants

Extends Active Storage with pluggable per-variant transformers, async-safe variant processing, and failure handling.

## The Problem

Active Storage's variant system assumes transformations are fast and reliable -- like generating an image thumbnail. But some transformations are slow (transcoding a 1GB video to 720p VP9) and fallible (the transcode may permanently fail). When you use `process: :later`, Active Storage enqueues a background job, but if the variant is requested before the job finishes, it falls through to synchronous processing -- blocking the request for minutes or timing out entirely. And if the transformation fails, the error bubbles up with no tracking or retry limits.

## Installation

```ruby
gem "active_storage-async_variants"
```

```bash
bin/rails active_storage_async_variants:install:migrations
bin/rails db:migrate
```

## Usage

Add `processing:` to any named variant to opt into the async pipeline. The value is what to serve while the variant is being processed:

```ruby
class User < ApplicationRecord
  has_one_attached :video do |attachable|
    attachable.variant :web,
      transformer: VideoTranscoder,
      codec: "vp9",
      resolution: "720p",
      processing: :original
  end
end
```

The presence of `processing:` is what opts a variant into async processing. Without it, variants behave exactly as they do in standard Active Storage. The `transformer:` option is independent -- you can use a custom transformer synchronously, or use the default transformer asynchronously:

```ruby
has_one_attached :video do |attachable|
  # Async with custom transformer (video transcode)
  attachable.variant :web,
    transformer: VideoTranscoder,
    codec: "vp9",
    processing: :original

  # Async with default transformer (large image resize that's too slow for inline)
  attachable.variant :thumbnail,
    resize_to_limit: [200, 200],
    processing: :original

  # Sync with custom transformer (fast custom processing, no opt-in needed)
  attachable.variant :watermarked,
    transformer: WatermarkStamper
end
```

In views, use the same Active Storage helpers:

```erb
<%= video_tag user.video.variant(:web).url %>
```

If the variant is still processing, this serves the original video. Once processing completes, it serves the transcoded variant.

## `image_tag` / `video_tag` with `async:` and `direct:`

For a polish layer that swaps in placeholder content while a variant is being processed, polls for completion in the background, and optionally serves the finished variant straight from your CDN, the gem adds two options to `image_tag` and `video_tag`:

```erb
<%# Variant URL with the async client wired up: spinner while pending,
    polls for completion, swaps to the real image when ready. %>
<%= image_tag user.avatar.variant(:web), async: true %>

<%# When the variant is ready, render its direct CDN/S3 URL instead of
    routing through Rails. While pending/failed, falls back to the
    Rails representation URL (which serves the placeholder). %>
<%= image_tag user.avatar.variant(:web), direct: true %>

<%# Both together: direct URL once processed, placeholder while pending,
    polling for completion. %>
<%= image_tag user.avatar.variant(:web), async: true, direct: true %>

<%# Same for videos. %>
<%= video_tag user.video.variant(:web), async: true, controls: true %>
```

The first argument must be a `VariantWithRecord` or `Preview` when either option is set; otherwise `image_tag` / `video_tag` behave exactly as in stock Rails.

### Configure the direct URL host

By default `direct:` uses the storage service's URL (presigned for private buckets, unsigned for public). To serve from a CDN, set the host in an initializer:

```ruby
# config/initializers/active_storage_async_variants.rb
ActiveStorage::AsyncVariants.cdn_host = "https://d1234abcd.cloudfront.net"
```

The resulting URL is `"#{cdn_host}/#{variant.key}"`.

### Wiring the JavaScript

The gem ships a dependency-free Stimulus-like controller at `app/assets/javascripts/active_storage_async_variants.js`. It is registered with the asset pipeline by the engine but not auto-imported. Wire it up the same way as `@rails/activestorage` -- pick whichever fits your bundler:

Using **importmap-rails**:

```ruby
# config/importmap.rb
pin "@active_storage/async_variants", to: "active_storage_async_variants.js", preload: true
```

```js
// app/javascript/application.js
import "@active_storage/async_variants"
```

Using **the asset pipeline** (sprockets/propshaft) with a classic `javascript_include_tag`:

```erb
<%= javascript_include_tag "active_storage_async_variants" %>
```

The module auto-starts on `DOMContentLoaded` and finds elements with `data-async-variant-state-value`. Opt out by setting `window.ActiveStorageAsyncVariants = null` before the script loads, then calling `start()` yourself from the exported module when ready.

## Writing a Transformer

Transformers come in two flavors: **inline** (the job blocks until processing completes) and **external** (the job kicks off remote work and a webhook signals completion).

### External Transformers (recommended for slow work)

An external transformer delegates to a remote service and returns immediately, freeing up the job worker. The remote service uploads the result directly to storage and hits a callback URL when done.

```ruby
class LambdaTranscoder < ActiveStorage::AsyncVariants::Transformer
  def initiate(source_url:, destination_url:, callback_url:, **options)
    Http.post("https://transcode.example.com/jobs",
      source_url: source_url,
      destination_url: destination_url,
      callback_url: callback_url,
      codec: options[:codec],
      resolution: options[:resolution],
    )
  end
end
```

The gem calls `initiate` with:
- `source_url` -- a presigned GET URL for the original file
- `destination_url` -- a presigned PUT URL where the result should be uploaded
- `callback_url` -- a signed webhook URL to POST to when done

The remote service does its work (which could take minutes or hours), uploads the result to `destination_url`, then POSTs to `callback_url`:

```
POST <callback_url>
Content-Type: application/json

{ "status": "success", "content_type": "video/webm", "byte_size": 52428800 }
```

Or on failure:

```
POST <callback_url>
Content-Type: application/json

{ "status": "failed", "error": "ffmpeg exited with status 1" }
```

The callback URL is signed -- no authentication is needed on the caller's side.

### Callback Endpoint

The gem mounts a callback endpoint at:

```
POST /active_storage/async_variants/callbacks/:token
```

The `:token` is a signed, single-use token that identifies the variant record. The gem generates this URL and passes it to `initiate` as `callback_url`. Your external service just POSTs to it -- no API keys or authentication headers required.

Expected request body:

```json
{ "status": "success", "content_type": "video/webm", "byte_size": 52428800 }
```

```json
{ "status": "failed", "error": "ffmpeg exited with status 1" }
```

### Inline Transformers (simpler, blocks the worker)

For cases where you're running the transformation locally (e.g., ffmpeg on the same machine), an inline transformer blocks until done:

```ruby
class LocalTranscoder < ActiveStorage::AsyncVariants::Transformer
  def process(file, **options)
    output = Tempfile.new(["output", ".webm"])
    system("ffmpeg", "-i", file.path,
      "-c:v", "libvpx-vp9",
      "-vf", "scale=-2:#{options[:resolution]&.delete("p") || 720}",
      "-c:a", "libopus",
      output.path,
      exception: true,
    )
    { io: output, content_type: "video/webm", filename: "video.webm" }
  end
end
```

The `process` method receives the source file and all non-reserved options from the variant definition. It returns a hash with `io:`, `content_type:`, and `filename:`.

The gem determines the mode by which method the transformer implements: `initiate` for external, `process` for inline.

## Checking Variant State

```ruby
variant = user.video.variant(:web)

variant.processed?   # => true if processed successfully
variant.processing?  # => true if job is running or external service is working
variant.pending?     # => true if job is enqueued
variant.failed?      # => true if permanently failed
variant.error        # => error message string, or nil
```

## Placeholder Options

The `processing:` option controls what gets served while a variant is being processed. The `failed:` option (optional) controls what gets served once the variant has permanently failed; if omitted, it defaults to the `processing:` value.

```ruby
# Serve the original unprocessed file while processing
attachable.variant :web, processing: :original

# Return nil -- let the view handle it
attachable.variant :web, processing: :blank

# Static URL while processing
attachable.variant :web, processing: "/placeholders/processing.svg"

# Dynamic placeholder via Proc
attachable.variant :web,
  processing: -> (blob) { "/placeholders/processing.svg" }

# Distinct placeholder when permanently failed
attachable.variant :web,
  processing: :original,
  failed: "/icons/broken.svg"
```

Both options accept the same set of values: `:original`, `:blank`, a String URL, or a Proc that receives the blob.

## Failure Handling

A variant is retried up to 3 times before being marked as permanently failed. Once permanently failed, `.processed` no longer re-enqueues the job — the variant stays failed until you delete the `ActiveStorage::VariantRecord` row manually (or re-attach a fresh blob).

Inspect failures:

```ruby
variant = user.video.variant(:web)
variant.failed? # => true
variant.error   # => "ffmpeg exited with status 1: ..."
```

## How It Works

### External transformer flow

1. User uploads a file to an attachment that has async variants defined
2. After attachment, a background job is enqueued for each async variant
3. `VariantRecord` is created with state `pending`
4. The job calls the transformer's `initiate` method with presigned source/destination URLs and a signed callback URL, then exits -- the worker is free
5. The external service processes the file, uploads the result to the destination URL
6. The external service POSTs to the callback URL with success/failure status
7. The gem's callback endpoint transitions the `VariantRecord` to `processed` or `failed`
8. When a view requests the variant URL, the gem checks state and serves the variant or the `processing:`/`failed:` placeholder

### Inline transformer flow

1-3. Same as above
4. The job calls the transformer's `process` method, blocking until complete
5. On success, the output is uploaded, the `VariantRecord` transitions to `processed`
6. On failure, the error is recorded and the job is re-enqueued (up to 3 attempts)
7. When a view requests the variant URL, the gem checks state and serves the variant or the `processing:`/`failed:` placeholder

## License

MIT
