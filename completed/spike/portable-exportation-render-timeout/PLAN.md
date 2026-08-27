# Plan — Deliver a portable exportation at production volume

The spike beside this file answers why renders stalled. This plan is the wider work that had to ship
for a client-sized export to complete end to end, in the order the dependencies force, and it
describes the delivered end state rather than a proposal.

The reference run produced **197,865,728,799 bytes carrying 219,842 documents** on `shared-001`,
assembled in 2,912 multipart parts.

---

## Why the order is forced

Each phase is only observable once the previous one stops failing. That is what makes this a
sequence rather than a checklist: the packaging defects were invisible while renders were dying, and
the attachment defect was invisible while packaging was dying. A team attacking them in any other
order finds each bug hidden behind the one before it.

## Phase 1 — Produce correct documents

| Commit | What it settles |
|---|---|
| `364d4f727` | The coordinator that turns a request into an export |
| `90b796876` | Document locale and index columns |
| `48df2fc5b` | Closing month as the export reference |
| `7fc8c6f24` | Full file path on the index |

Correctness first, because every later phase multiplies whatever this produces by two hundred
thousand. A locale or reference-period defect found after the volume work costs a full regeneration.

## Phase 2 — Make one render survive, then survive repetition

| Commit | What it settles |
|---|---|
| `db362e870` | Analytics blocked; render timeout widened |
| `de6b04ad4` | The page is asserted before capture, so a redirect fails loudly |
| `e17581759` | Capture outlasts the API request budget |
| `7ccdd04a5` | The browser stays alive across documents |
| `0e60c5535` | Capture waits for **sustained** network idle |
| `d6ab17669` | A request Chrome left unanswered is abandoned past its own timeout |

The last two are the spike's finding turned into code. Ferrum's `wait_for_idle!` returns on the first
instant of zero in-flight requests, which a single-page app hits between bursts; and Chrome drops
some requests without ever sending `responseReceived`, `loadingFinished` or `loadingFailed`, which
Ferrum counts pending for the page's whole life. `Browser::Page#wait_until_settled`
(`app/app/models/browser/page.rb:14-33`) answers both — a sustained quiet window, and a per-request
deadline that abandons an exchange older than `BROWSER_REQUEST_TIMEOUT`.

Widening the global timeout is not a substitute and was measured not to be: it lengthens the time a
job holds a vCPU without removing a single request, and does nothing about a request that never
completes.

## Phase 3 — Make packaging survive the volume

| Commit | What it settles |
|---|---|
| `55c10a873` | Expected render failures retry before being reported |
| `53c483be0` | Each document is read once while packaging |
| `70334c43f` | Archives past four gigabytes (ZIP64) |
| `6fb3cc1eb` | Documents fetched in parallel while packaging |
| `09a075601` | Batch counters stay consistent across retries and redeliveries |

The counter fix is the one that is easy to skip and expensive to skip. The `Computation` completion
signal compares two Redis counters, so a retry or a redelivery that increments one without the other
leaves the chain unable to conclude — the run neither finishes nor reports a failure.

## Phase 4 — Move assembly onto object storage

| Commit | What it settles |
|---|---|
| `03db05734` | The archive is assembled in parallel via S3 multipart |
| `853be9782` | The multipart part listing is paginated |
| `2932c6bdc` | The archive is assembled in a binary buffer |
| `d42022bb2` | The attachment is persisted before anything fans out |

Assembling on object storage is what makes the volume tractable at all — no worker ever holds the
archive. Three constraints follow from that choice and each one produced a defect:

- **`ListParts` returns at most 1,000 parts per response.** The fog call does not paginate, so the
  Finalizer walks `NextPartNumberMarker` itself. At 2,912 parts, not paginating silently loses two
  thirds of the archive.
- **zip_kit builds each header's extra fields in a non-binary buffer**, which a String already
  holding document bytes refuses to concatenate. A `StringIO` absorbs it.
- **A validation the type can never satisfy fails silently through a non-bang call.**
  `PortableExportationAttachment` inherits `validates :file, presence: { unless: :file_optional? }`
  while carrying no upload by design, so `create_attachment` returned an unsaved record; the
  in-memory object still answered `.file.path`, so the multipart upload started and its identifier
  was saved while `attachments` stayed empty. Every consumer and the Finalizer then met `nil.file`.

The fix is the type added to `file_optional?` (`app/app/models/attachment.rb`) plus `save!` in
`PartProducer` (`app/app/workers/portable_exportation/part_producer.rb:15`). The bang is the
documented exception in `BANG-METHOD-WEB-FLOW.md` — nothing is enqueued at that point, so halting is
exactly what is wanted.

## Configuration surface

Everything below is an environment variable with a code default
(`app/lib/application_configuration.rb`), so a run can be tuned without a deploy.

| Setting | Default | Line |
|---|---|---|
| `BROWSER_REQUEST_TIMEOUT` | 15 s | 481 |
| `BROWSER_NETWORK_SETTLE_DURATION` | 0.5 s | 485 |
| `BROWSER_NETWORK_POLL_INTERVAL` | 0.05 s | 489 |
| `BROWSER_SESSION_TIMEOUT` | 60 s | 477 |
| `BROWSER_PAGE_LIMIT` | 200 pages/browser | 473 |
| `PORTABLE_EXPORTATION_PART_BYTE_SIZE` | 16 MiB | 501 |
| `PORTABLE_EXPORTATION_MAXIMUM_RETRIES` | 3 | 497 |

**`PORTABLE_EXPORTATION_PART_BYTE_SIZE` has a ceiling nothing enforces.** S3 caps a multipart upload
at 10,000 parts, so the part size has to exceed `total ÷ 10000`. At 16 MiB the reference archive
needs 11,793 parts and fails; it succeeded because the assembly path sizes its own parts. Any
re-copy of the finished object has to carry its own chunk size — see the runbook.

## What is deliberately not code

Generating the archive is a product feature and runs from the interface: the system scales the
worker fleet up, produces the archive, writes it to S3 and scales back down. **Delivering it is an
operational procedure**, and it does not belong in the application because the constraint it works
around is network geography rather than behaviour.

The short version, with the full procedure in
`~/.claude/docs/runbooks/services/PORTABLE-EXPORTATION.md`: a direct download from `us-east-1` to
Brazil sustains ~3,7 MB/s against ~20 MB/s from `sa-east-1`, so the archive is copied server-side to
a São Paulo bucket first and downloaded from there.

## Verifying a completed run

Three checks, in order, and the first two are cheap enough that skipping them is never justified.

**Size before anything else** — the object's `ContentLength` against what the download produced. A
truncated transfer is the failure most likely to survive unnoticed into a client's hands.

**Then the central directory** — `zipinfo -t` reads the index at the end of the file, so it costs a
seek rather than a full read, and a truncated archive cannot answer it at all.

**Extraction is the content check** — `unzip` validates every entry's CRC as it writes, so a separate
`unzip -t` pays for the same read twice and proves nothing extraction will not.

## Open risk

The favicon that produced the original stall is one instance of a mechanism that is indifferent to
which URL is involved: an exchange receiving `loadingFinished` without a prior `responseReceived`
satisfies none of Ferrum's `finished?` terms. The per-request abandon bounds the failure rather than
removing its cause, so a future asset can reproduce the shape. The spike carries the protocol-level
detail and the upstream references.
