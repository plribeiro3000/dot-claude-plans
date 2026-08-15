# SPIKE — Portable Exportation: scale limits (memory, disk, upload, concurrency)

**Date:** 2026-07-22
**Feature:** result-side portable exportation (PR #5253, merged to `develop`)
**Question:** at "thousands → millions of PDFs" scale, where does the current design hit a wall — worker memory, container disk, the S3 upload, or Sidekiq concurrency? Find the ceilings before production so we don't hit them by surprise.

**Context (versions, all from `app` Gemfile.lock on `develop`):** carrierwave 3.1.3, fog-aws 3.33.2, fog-core 2.6.0, rubyzip 2.4.1.

---

## Summary of the four axes

| Axis | Verdict | Ceiling / cause |
|---|---|---|
| ZIP build — memory | **SAFE** | Streamed to disk, one PDF at a time in RAM |
| S3 upload — memory | **SAFE** | Streamed to S3 in 1 MB chunks; file never fully buffered |
| S3 upload — object size | **HARD WALL** | Single `PUT` ≤ **5 GB**; no auto-multipart → a ZIP > 5 GB fails |
| Container disk | **WALL (provisioned)** | Full ZIP must fit ephemeral storage; Fargate 20 GiB default → 200 GiB max; EC2 EBS-bound. Exceed → `ENOSPC`, partial file |
| Sidekiq concurrency | **WALL (config)** | Queue inherits `SIDEKIQ_THREADS` (=10) → up to 10 Chromiums/process → OOM |

---

## 1. ZIP build — memory: SAFE

`StatementPortableBatch::Finalizer` builds the archive with `Zip::OutputStream.open(zip_path) do |zip| ... end`.

Verified against rubyzip 2.4.1 source (`lib/zip/output_stream.rb`):
- `initialize` with `stream: false` sets `@output_stream = ::File.new(@file_name, 'wb')` (line 39) — a **real file on disk**, not a `StringIO`.
- The `Deflater` writes compressed bytes straight to `@output_stream` (line 164, and `<<` at 196-198); `put_next_entry` writes each entry header to the file (line 155).
- The in-memory `write_buffer` variant (`StringIO`, line 65) is **not** the one used — we use `.open(zip_path)`.

**Consequence:** the whole ZIP is never in RAM. Peak per iteration = one `attachment.file.read` (one PDF) + its deflate buffer, released each loop. The only thing that grows with entry **count** is the central directory (`@entry_set`) held until `close` — metadata (name/offset/size/CRC) per entry, ~tens of bytes each, so ~tens of MB for millions of entries. Bounded and small vs the file bodies.

## 2. S3 upload — memory: SAFE (streamed)

The Finalizer uploads the finished ZIP with `File.open(zip_path, 'rb') { |file| attachment.file = file }` then `attachment.save` (CarrierWave `:fog`).

- CarrierWave hands the **File object** to Fog, not `.read`: `carrierwave-3.1.3/lib/carrierwave/storage/fog.rb:343,346` — `fog_file = new_file.to_file` then `:body => fog_file || new_file.read`. Since `to_file` returns the local File, `:body` is the File IO; the `.read` (whole file → String) is only the fallback.
- fog-aws 3.33.2 does **not** hash the whole body for SigV4 when the body responds to `:read`. `lib/fog/aws/storage.rb` `request`:
  > `if params[:body].respond_to?(:read)` → sets `x-amz-content-sha256` to `'UNSIGNED-PAYLOAD'` (default; streaming-signature off unless `enable_signature_v4_streaming`, which defaults `false`). The full-`SHA256.hexdigest(params[:body])` branch runs **only for String bodies**. — https://github.com/fog/fog-aws/blob/master/lib/fog/aws/storage.rb
- `Content-Length` comes from the file's stat, not by reading it (fog-core `parse_data` → `body.stat.size`). — https://github.com/fog/fog-core/blob/master/lib/fog/storage.rb
- Excon streams the body in 1 MB chunks: > "Excon.defaults[:chunk_size] defaults to 1048576, ie 1MB". — https://github.com/excon/excon/blob/master/README.md

**Consequence:** a multi-GB ZIP is uploaded without being buffered into a Ruby String. Memory is NOT the upload wall.

*(Partially UNVERIFIED, does not change the verdict: the exact Excon call-site that auto-chunks a bare `:body` File was not quoted verbatim; the chunked-not-buffered net effect is corroborated by Content-Length-from-stat + no fog buffering.)*

## 3. S3 upload — object size: HARD WALL at 5 GB

`directory.files.create` → `put_object` is a **single PUT**, no size check, no auto-multipart (`lib/fog/aws/requests/storage/put_object.rb`).

AWS single-PUT limit:
> "With a single `PUT` operation, you can upload a single object up to 5 GB in size." — https://docs.aws.amazon.com/AmazonS3/latest/userguide/upload-objects.html

**Consequence:** a ZIP **larger than 5 GB fails to upload** regardless of the streaming behaviour. fog-aws exposes multipart (`initiate_multipart_upload` / `upload_part` / `complete_multipart_upload`, up to 50 TB) but it is **manual** — the CarrierWave `:fog` path never calls it. So above 5 GB we would need either manual multipart or splitting the export into multiple sub-5 GB ZIPs.

## 4. Container disk: WALL (provisioned size)

The ZIP is written to `Rails.root.join('tmp', ...)` — the container's local/ephemeral disk. The individual PDFs are NOT on disk during zipping (each Consumer writes one PDF to tmp, uploads it, `FileUtils.rm_f`s it; the Finalizer reads each back from S3 into memory transiently). So the Finalizer box must hold **the full ZIP + the manifest** on disk.

ECS limits (verified against AWS docs):
- **Fargate:** > "receive a minimum of 20 GiB of ephemeral storage. The total amount of ephemeral storage can be increased, up to a maximum of 200 GiB" via `ephemeralStorage.sizeInGiB` (platform 1.4.0+) — https://docs.aws.amazon.com/AmazonECS/latest/developerguide/fargate-task-storage.html . Usable space = that minus the container image footprint (image lives on the same ephemeral storage).
- **EC2:** no per-task number; bounded by the instance's EBS/Docker volume (Amazon Linux 2 AMI ships a "single 30-GiB root volume" shared OS+Docker, resizable at launch) — https://raw.githubusercontent.com/awsdocs/amazon-ecs-developer-guide/master/doc_source/ecs-ami-storage-config.md
- Exceed mid-write → `ENOSPC` ("No space left on device", `write(2)`); no auto-grow; a partial ZIP is left behind.

**Consequence:** the max ZIP size the box can build is a **provisioning decision** — `ephemeralStorage.sizeInGiB` (Fargate, ≤200 GiB) or the EBS volume (EC2) in the not-yet-written terraform service.

## 5. Sidekiq concurrency: WALL (config)

`config/sidekiq_portable_exportation.yml` sets `:concurrency: <%= ApplicationConfiguration.sidekiq_threads %>`, which is `Integer(ENV.fetch('SIDEKIQ_THREADS', 25))` (`lib/application_configuration.rb:74`). The effective env value is **10** (25 is only the fallback-if-unset). So the queue would run **up to 10 Chromiums in one process** — hundreds of MB each → OOM.

migration/cleansing use the same `sidekiq_threads` and are fine, because those jobs are lightweight DB work. Chromium is not. The HireFire dyno `worker_portable_exportation` already scales by queue depth (`config/initializers/hire_fire.rb:143`), so parallelism should come from **dyno instances**, not threads.

**Consequence:** this queue needs a **low fixed concurrency** (1, maybe 2) instead of inheriting the shared `sidekiq_threads`.

---

## What this means NOW (RedeBrasil) vs LATER (large clients)

RedeBrasil is a cancelled mid-size client — likely thousands of statements. At ~100–500 KB per statement PDF, a few thousand PDFs ≈ 1–2 GB ZIP: under the 5 GB PUT ceiling, fits default disk, memory already safe. **RedeBrasil clears every wall as-is** except the concurrency config, which must be fixed regardless because it is an OOM risk on the very first run.

The 5 GB upload ceiling and the disk ceiling only bite a **large** client (hundreds of thousands / millions of PDFs). They are real and worth deciding on now so the design has a known, documented behaviour instead of a surprise `EntityTooLarge` / `ENOSPC` in production.

## Decisions made (engineer, 2026-07-22)

The initial recommendation here (concurrency=1; accept the 5 GB single-ZIP limit) was **overruled**. The engineer's decisions — authoritative version lives in `../signature-pdf-audit-trail/PLAN.md` § "2026-07-22 — Scale & delivery decisions":

1. **Concurrency — KEEP ≥10 threads (Sidekiq default); do NOT lower it.** One thread/process does not scale. Chromium memory is solved by a **bigger ECS instance** (≥8 GB vs the standard 4 GB), not fewer threads. The worker is ephemeral and runs occasionally, so a bigger box only while it runs is fine. Fix lives in terraform (instance memory), not the yml.
2. **5 GB ceiling — sidestepped by the delivery redesign.** The export produces **multiple ZIPs — one per plano** (rule + result declarations), in a navigable folder tree (year → month → plano) with a root Excel index pointing to each file's location. No single giant ZIP, so the 5 GB single-object PUT is not approached in normal operation (open question: could one plano's PDFs alone exceed 5 GB?). Supersedes the current one-ZIP-per-batch Finalizer.
3. **Disk — 40 GB ephemeral (4Shark standard);** increment later if needed. Worker boots → generates on the box → saves to S3 → dies.
4. **S3 location — DEFERRED, documented.** Currently saved with the project's normal uploads; not a product feature yet. Future fork: release internally for client self-download (keep as-is) OR move to a dedicated folder with an N-day delete policy (like `integration-debug`). Decide later.

None of these block the merged code; they are pre-production hardening + the terraform service + the delivery redesign phase.
