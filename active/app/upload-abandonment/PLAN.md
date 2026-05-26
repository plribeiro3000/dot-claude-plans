# Upload Abandonment and Attachment Expiring Refactoring

## Overview

This feature implements automatic cleanup of abandoned document uploads and refactors the existing attachment expiration system to follow the producer/consumer pattern.

## Problem Statement

1. **Orphan files in S3**: Documents created but never processed (client uploaded file but never called the processing endpoint) leave orphan files in S3
2. **Inconsistent worker patterns**: `Attachment::Expirator` and `Attachment::Destroyer` don't follow the producer/consumer pattern used elsewhere in the codebase

## Solution

### Part 1: Document Upload Abandonment

Add `abandoned` status to Document model for uploads that were never processed within 24 hours.

**New files:**
- `app/workers/document_attachment/expirer/producer.rb`
- `app/workers/document_attachment/expirer/consumer.rb`

**Modified files:**
- `app/models/document.rb` - Add `abandoned` status (value: 5), `abandon` event, and `abandoned` scope

**Queue:** `document_attachment_expiring`

**Flow:**
1. Producer finds Documents with status `initial` older than 24 hours
2. Producer pushes document IDs to Consumer via `Sidekiq::Client.push_bulk`
3. Consumer receives document_id, transitions state to `abandoned`, and destroys the DocumentAttachment

### Part 2: Attachment Expiring Refactoring

Refactor existing workers to follow producer/consumer pattern.

**Files to delete:**
- `app/workers/attachment/expirator.rb`
- `app/workers/attachment/destroyer.rb`

**New files:**
- `app/workers/attachment/expirer/producer.rb`
- `app/workers/attachment/expirer/consumer.rb`

**Queue:** `attachment_expiring` (unchanged)

**Flow:**
1. Producer iterates `Attachment::TYPES`, finds expired attachments, pushes IDs to Consumer
2. Consumer receives attachment_id, transitions state to `expired`, and destroys the attachment

## Technical Details

### Document Model Changes

```ruby
# Status enumeration
enumerize :status,
          in: {
            initial: 0,
            processing: 1,
            erasing: 2,
            final: 3,
            failed: 4,
            abandoned: 5  # NEW
          }

# New scope
scope :abandoned, -> { with_status(:initial).where(created_at: ...24.hours.ago) }

# New event in state machine
event :abandon do
  transition initial: :abandoned
end
```

### DocumentAttachment::Expirer::Producer

```ruby
class DocumentAttachment < Attachment
  module Expirer
    class Producer < ApplicationWorker
      sidekiq_options queue: :document_attachment_expiring

      def perform
        document_ids = Document.with_uncached_connection { Document.abandoned.pluck(:id) }
        return if document_ids.empty?

        arguments = document_ids.zip
        Sidekiq::Client.push_bulk('class' => DocumentAttachment::Expirer::Consumer, 'args' => arguments)
      end
    end
  end
end
```

### DocumentAttachment::Expirer::Consumer

```ruby
class DocumentAttachment < Attachment
  module Expirer
    class Consumer < ApplicationWorker
      sidekiq_options queue: :document_attachment_expiring

      def perform(document_id)
        document = Document.with_uncached_connection { Document.find(document_id) }
        Document.with_uncached_connection { document.abandon! }

        attachment = Attachment.with_uncached_connection { document.attachment }
        Attachment.with_uncached_connection { attachment&.destroy }
      end
    end
  end
end
```

### Attachment::Expirer::Producer

```ruby
class Attachment < ApplicationRecord
  module Expirer
    class Producer < ApplicationWorker
      sidekiq_options queue: :attachment_expiring

      def perform
        Attachment::TYPES.each do |attachment_type|
          attachment_ids = Attachment.with_uncached_connection { attachment_type.constantize.expired.pluck(:id) }
          next if attachment_ids.empty?

          arguments = attachment_ids.zip
          Sidekiq::Client.push_bulk('class' => Attachment::Expirer::Consumer, 'args' => arguments)
        end
      end
    end
  end
end
```

### Attachment::Expirer::Consumer

```ruby
class Attachment < ApplicationRecord
  module Expirer
    class Consumer < ApplicationWorker
      sidekiq_options queue: :attachment_expiring

      def perform(attachment_id)
        attachment = Attachment.with_uncached_connection { Attachment.find(attachment_id) }
        Attachment.with_uncached_connection { attachment.expire! }
        Attachment.with_uncached_connection { attachment.destroy }
      end
    end
  end
end
```

## File Changes Summary

### New Files (6)
1. `app/workers/document_attachment/expirer/producer.rb`
2. `app/workers/document_attachment/expirer/consumer.rb`
3. `app/workers/attachment/expirer/producer.rb`
4. `app/workers/attachment/expirer/consumer.rb`
5. `db/migrate/2026/01/XXXXXX_add_abandoned_status_to_documents.rb`
6. `docs/state_machines/Document_status.png` (update)

### Files to Delete (2)
1. `app/workers/attachment/expirator.rb`
2. `app/workers/attachment/destroyer.rb`

### Modified Files (1)
1. `app/models/document.rb` - Add abandoned status, event, and scope

### Spec Files (4)
1. `spec/workers/document_attachment/expirer/producer_spec.rb`
2. `spec/workers/document_attachment/expirer/consumer_spec.rb`
3. `spec/workers/attachment/expirer/producer_spec.rb`
4. `spec/workers/attachment/expirer/consumer_spec.rb`

### Spec Files to Delete (2)
1. `spec/workers/attachment/expirator_spec.rb`
2. `spec/workers/attachment/destroyer_spec.rb`

## Sidekiq Configuration

Add `document_attachment_expiring` queue to `config/sidekiq_system.yml`:

```yaml
:queues:
  # ... existing queues ...
  - [document_attachment_expiring, 8]  # Same priority as attachment_expiring
```

## HireFire Configuration

Add `document_attachment_expiring` queue to `config/initializers/hire_fire.rb` in the `worker_system` dyno:

```ruby
config.dyno(:worker_system) do
  HireFire::Macro::Sidekiq.queue(
    # ... existing queues ...
    :document_attachment_expiring,  # Add this line
    # ... more queues ...
  )
end
```

## Cron Configuration

Update `lib/tasks/cron.rake`:

```ruby
# Change existing:
namespace :attachment do
  desc 'Expire old attachments, run once a day at 1 am'
  task expirator: :environment do
    Attachment::Expirer::Producer.perform_async  # Changed from Attachment::Expirator
  end
end

# Add new:
namespace :document_attachment do
  desc 'Abandon old document uploads, run once a day at 3 am'
  task expirator: :environment do
    DocumentAttachment::Expirer::Producer.perform_async
  end
end
```

## State Machine Diagram Update

Update `docs/state_machines/Document_status.png` to include:
- New `abandoned` state
- Transition: `initial` → `abandoned` (via `abandon` event)

## Risks and Mitigations

1. **Risk**: Existing scheduled jobs reference `Attachment::Expirator`
   **Mitigation**: Update scheduler configuration to use new producer class

2. **Risk**: Race condition between document processing and abandonment
   **Mitigation**: The `abandon` event only transitions from `initial` state; if document started processing, it won't be abandoned

## Acceptance Criteria

- [ ] Documents in `initial` status for more than 24 hours are marked as `abandoned`
- [ ] DocumentAttachment is destroyed when document is abandoned
- [ ] Existing attachment expiration continues to work with new producer/consumer pattern
- [ ] All specs pass
- [ ] State machine diagram is updated
