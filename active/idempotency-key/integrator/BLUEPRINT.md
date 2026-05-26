# SPEC — Loading Resilience Pattern

> **Problem:** HTTP calls can fail (timeout, connection reset, server error). We need to track all requests and their outcomes, retry when appropriate, and give workers a simple way to decide what to do.

> **Solution:** Loader handles everything (HTTP call, error handling, response tracking) and returns LoadingResult. Worker decides based on LoadingResult.

---

## Solution Overview

### Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                           LOADER                                     │
├─────────────────────────────────────────────────────────────────────┤
│  1. Check if request already exists and is final                    │
│     └─ If final (success or user error): return LoadingResult       │
│                                                                      │
│  2. CREATE request (before HTTP call)                               │
│     └─ Request { url, http_method, body, timestamp }                │
│                                                                      │
│  3. Call HTTParty (inside begin/rescue)                             │
│     ├─ 2xx/4xx: Create Response with status + body                  │
│     ├─ 5xx: Create Response with status (server error)              │
│     └─ Exception: Mark Request with error_type + error_message      │
│                                                                      │
│  4. Return LoadingResult (always)                                   │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              │ LoadingResult
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                           WORKER                                     │
├─────────────────────────────────────────────────────────────────────┤
│  NO rescue blocks - just decision logic                             │
│                                                                      │
│  result = loader.create(params)                                     │
│                                                                      │
│  if result.retriable?                                               │
│    → Schedule retry (5 seconds)                                     │
│  elsif result.success?                                              │
│    → Update resource state, continue pipeline                       │
│  elsif result.failed?                                               │
│    → User error, skip retry, continue pipeline                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Key Benefits

1. **Loader is self-contained** - Handles all HTTP complexity internally
2. **Worker is simple** - Just checks LoadingResult and decides
3. **No exceptions crossing boundaries** - Cleaner architecture
4. **Clear error tracking** - Network errors on Request, HTTP errors on Response

---

## Technical Specification

### 1. Request Model

Add error fields for network failures (no HTTP response):

```ruby
# app/models/request.rb

field :error_type, type: String      # e.g., "Net::OpenTimeout"
field :error_message, type: String   # e.g., "execution expired"

def has_error?
  error_type.present?
end

def final?
  success? || user_error?
end
```

### 2. LoadingResult Value Object

```ruby
# app/models/loading_result.rb

class LoadingResult
  attr_reader :request

  def initialize(request)
    @request = request
  end

  def success?
    return false if request.nil? || request.response.nil?
    request.response.status.in?(Resource::API_SUCCESS_CODES)
  end

  def retriable?
    return true if request.nil?
    return true if request.has_error?                    # Network error
    return true if request.response.nil?                 # No response yet
    return true if request.response.status.nil?          # Unknown status
    request.response.status >= 500                       # Server error
  end

  def failed?
    return false if request.nil? || request.response.nil?
    return false if request.response.status.nil?
    request.response.status.between?(400, 499)           # User error
  end
end
```

### 3. ApplicationLoader

All logic directly in the loader, no service objects:

```ruby
# app/loaders/application_loader.rb

class ApplicationLoader
  RETRIABLE_EXCEPTIONS = [
    EOFError,
    Errno::ECONNRESET,
    JSON::ParserError,
    Net::OpenTimeout,
    OpenSSL::SSL::SSLError
  ].freeze

  def create_request(url:, http_method:, params: nil)
    request_data = {
      'job_id' => job_id.to_s,
      'url' => url,
      'http_method' => http_method,
      'timestamp' => DateTime.current,
      'body' => params.present? ? JSON.parse(params) : nil
    }

    Resource.collection.find_one_and_update(
      { '_id' => resource._id, 'imports._id' => BSON::ObjectId.from_string(import_id.to_s) },
      { '$push' => { 'imports.$.requests' => request_data } }
    )
  end

  def create_response(url:, http_method:, http_response:)
    response_data = {
      'status' => http_response.code.to_i,
      'body' => http_response.body.present? ? JSON.parse(http_response.body) : {}
    }

    update_request_response(url: url, http_method: http_method, response_data: response_data)
  end

  def mark_request_error(url:, http_method:, exception:)
    Resource.collection.update_one(
      {
        '_id' => resource._id,
        'imports._id' => BSON::ObjectId.from_string(import_id.to_s),
        'imports.requests' => {
          '$elemMatch' => {
            'job_id' => job_id.to_s,
            'url' => url,
            'http_method' => http_method,
            'response' => nil,
            'error_type' => nil
          }
        }
      },
      {
        '$set' => {
          'imports.$[i].requests.$[r].error_type' => exception.class.name,
          'imports.$[i].requests.$[r].error_message' => exception.message
        }
      },
      array_filters: [
        { 'i._id' => BSON::ObjectId.from_string(import_id.to_s) },
        { 'r.job_id' => job_id.to_s, 'r.url' => url, 'r.http_method' => http_method }
      ]
    )
  end

  private

  def update_request_response(url:, http_method:, response_data:)
    Resource.collection.update_one(
      {
        '_id' => resource._id,
        'imports._id' => BSON::ObjectId.from_string(import_id.to_s),
        'imports.requests' => {
          '$elemMatch' => {
            'job_id' => job_id.to_s,
            'url' => url,
            'http_method' => http_method,
            'response' => nil
          }
        }
      },
      { '$set' => { 'imports.$[i].requests.$[r].response' => response_data } },
      array_filters: [
        { 'i._id' => BSON::ObjectId.from_string(import_id.to_s) },
        { 'r.job_id' => job_id.to_s, 'r.url' => url, 'r.http_method' => http_method }
      ]
    )
  end
end
```

### 4. Loader Pattern (Example: ClientLoader)

```ruby
# app/loaders/client_loader.rb

class ClientLoader < ApplicationLoader
  def create(params)
    url = "https://#{account.api_endpoint}/api/v3/clients"

    # Check for existing final request (idempotency)
    request = import.find_request('post', url, job_id)
    return LoadingResult.new(request) if request.present? && request.final?

    # Create request before HTTP call
    create_request(url: url, http_method: 'post', params: params)

    # Make HTTP call (capture all outcomes)
    begin
      idempotency_key = Digest::MD5.hexdigest("#{job_id}-#{import.source_id}-post-#{url}")
      http_response = HTTParty.post(url, body: params, headers: account.api_headers.merge('X-Idempotency-Key' => idempotency_key))

      create_response(url: url, http_method: 'post', http_response: http_response)
    rescue *RETRIABLE_EXCEPTIONS => e
      mark_request_error(url: url, http_method: 'post', exception: e)
    end

    # Always return LoadingResult
    LoadingResult.new(import.find_request('post', url, job_id))
  end
end
```

### 5. Worker Pattern (Example: Client::LoaderConsumer)

```ruby
# app/workers/client/loader_consumer.rb

class Client < Resource
  class LoaderConsumer < ApplicationWorker
    sidekiq_options queue: :api_loader_consumer

    def perform(job_id, client_id)
      job = Job.find(job_id)
      client = Client.find(client_id)
      import = client.imports.find_by(job_id: job_id)
      loader = ClientLoader.new(id: client_id, job_id: job_id, import_id: import.id)

      result = load_client(client, import, loader)
      return retry_later(job_id, client_id) if result.retriable?

      job.computation.increment_executions
      Product::LoaderProducer.perform_async(job_id) if job.computation.done?
    end

    private

    def load_client(client, import, loader)
      case client.integration_status
      when 'pending'
        result = loader.create(import.request_body)
        client.integrate! if result.success?
        result
      when 'integrated', 'disabled'
        result = loader.update(import.source_id, import.request_body)
        return result if result.retriable?
        # ... activity handling
        result
      else
        LoadingResult.new(nil)
      end
    end

    def retry_later(job_id, client_id)
      Client::LoaderConsumer.perform_in(5.seconds, job_id, client_id)
    end
  end
end
```

---

## Request States

| State | Response | Error | Meaning |
|-------|----------|-------|---------|
| Pending | nil | nil | HTTP call in progress or not started |
| Success | 2xx | nil | API accepted the request |
| User Error | 4xx | nil | Validation/business error (don't retry) |
| Server Error | 5xx | nil | API failed (retry) |
| Network Error | nil | present | Connection/timeout failed (retry) |

---

## Files to Modify

| File | Changes |
|------|---------|
| `app/models/request.rb` | Add `error_type`, `error_message` fields; add `has_error?` method |
| `app/models/loading_result.rb` | New file - value object |
| `app/loaders/application_loader.rb` | Add `create_request`, `create_response`, `mark_request_error` |
| `app/loaders/*.rb` (all) | Use new pattern, return LoadingResult |
| `app/workers/*/loader_consumer.rb` (all) | Remove rescue blocks, use LoadingResult |

## Files to Remove

| File | Reason |
|------|--------|
| `app/models/request/creator.rb` | Logic moved to ApplicationLoader |
| `app/models/request/error_creator.rb` | Logic moved to ApplicationLoader |
| `app/models/response/creator.rb` | Logic moved to ApplicationLoader |
| `app/models/response/server_error_creator.rb` | Logic moved to ApplicationLoader |

---

## Success Criteria

1. ✅ Loader handles all HTTP outcomes (success, error, exception)
2. ✅ Loader always returns LoadingResult
3. ✅ Worker has no rescue blocks for HTTP exceptions
4. ✅ Worker decides based on LoadingResult methods
5. ✅ Network errors stored on Request (not fake Response)
6. ✅ No service objects for request/response creation
