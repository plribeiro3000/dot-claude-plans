# Tasks - Upload Abandonment and Attachment Expiring Refactoring

## Phase 1: Document Model Changes

- [ ] **1.1** Add `abandoned` status (value: 5) to Document enumerize
- [ ] **1.2** Add `abandoned` scope to Document model
- [ ] **1.3** Add `abandon` event to Document state machine
- [ ] **1.4** Create migration `add_abandoned_status_to_documents`

## Phase 2: DocumentAttachment Expirer Workers

- [ ] **2.1** Create `app/workers/document_attachment/expirer/producer.rb`
- [ ] **2.2** Create `app/workers/document_attachment/expirer/consumer.rb`
- [ ] **2.3** Create `spec/workers/document_attachment/expirer/producer_spec.rb`
- [ ] **2.4** Create `spec/workers/document_attachment/expirer/consumer_spec.rb`

## Phase 3: Attachment Expirer Refactoring

- [ ] **3.1** Create `app/workers/attachment/expirer/producer.rb`
- [ ] **3.2** Create `app/workers/attachment/expirer/consumer.rb`
- [ ] **3.3** Create `spec/workers/attachment/expirer/producer_spec.rb`
- [ ] **3.4** Create `spec/workers/attachment/expirer/consumer_spec.rb`
- [ ] **3.5** Delete `app/workers/attachment/expirator.rb`
- [ ] **3.6** Delete `app/workers/attachment/destroyer.rb`
- [ ] **3.7** Delete `spec/workers/attachment/expirator_spec.rb`
- [ ] **3.8** Delete `spec/workers/attachment/destroyer_spec.rb`

## Phase 4: Configuration

- [ ] **4.1** Add `document_attachment_expiring` queue to `config/sidekiq_system.yml`
- [ ] **4.2** Update `lib/tasks/cron.rake` to use `Attachment::Expirer::Producer` instead of `Attachment::Expirator`
- [ ] **4.3** Add `document_attachment:expirator` task to `lib/tasks/cron.rake`
- [ ] **4.4** Update `config/initializers/hire_fire.rb` to include `document_attachment_expiring` queue

## Phase 5: Documentation

- [ ] **5.1** Update `docs/state_machines/Document_status.png`
- [ ] **5.2** Update CHANGELOG.md

## Phase 6: Validation

- [ ] **6.1** Run all specs
- [ ] **6.2** Run rubocop
