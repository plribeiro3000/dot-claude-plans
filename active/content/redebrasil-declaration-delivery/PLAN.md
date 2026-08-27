# RedeBrasil — Declaration Export Delivery

Contract-termination billing for RedeBrasil required delivering every declaration the platform
had generated for the client. The volume made both generation and validation impossible by hand,
so the export and its verification were automated. This document records what was delivered,
where each copy of it lives, and what still has to happen to the copies.

## The artifact

| Property | Value |
|---|---|
| File | `portable_exportation-2.zip` |
| Size | 197,865,728,799 bytes (184.28 GiB / ~198 GB decimal) |
| Contents | 219,843 files |
| Compression | 0.0% — PDFs do not compress, so the extracted content occupies the same ~198 GB |

The zero-percent compression is the load-bearing fact behind the disk-space guidance given to the
client: extracting requires as much space again as the archive itself, so ~400 GB is the working
minimum and 500 GB free was the recommendation sent.

## Delivery

Delivered to Clayton Reis on 2026-08-26 by email on the thread
"Faturamento Referente à Rescisão do Contrato de Prestação de Serviços - 4SHARK", with Roney,
Sergio, elisangela.fraga, Danilo and narjara.fagundes copied.

Access is a Google Drive link to folder `1UhkATccR4REKaAsNVqacaV1xUKxLlG7V`. The share was granted
on the parent folder "Rede Brasil", so the delivery folder and the file inherit it rather than
carrying their own permission entries — a permission listing on the child returns only the owner,
which is expected and is not evidence that the share is missing. Sharing at the parent also means
the recipient sees everything else that folder contains.

## Copies and retention

The archive carries personal data for ~220,000 declarations, so every surviving copy is a
retention decision rather than a convenience.

| Location | State |
|---|---|
| External drive `/Volumes/RafaePaulo/` | Deleted 2026-08-26, archive and extracted folder both |
| Google Drive, folder `1UhkATccR4REKaAsNVqacaV1xUKxLlG7V` | Live — to be deleted roughly a month after delivery |
| `s3://4shark-shared-001/uploads/portable_exportations/2/portable_exportation-2.zip` (us-east-1) | Expires on its own two days after the attachment record's last update |

## How the S3 copy expires

Retention of the S3 copy is enforced by the application, not by an S3 lifecycle rule — the bucket's
lifecycle configuration only covers the `integration-debug/` prefixes, so looking there answers
nothing about this object.

`PortableExportationAttachment` declares `ttl 2.days` (`app/models/portable_exportation_attachment.rb:5`).
The `cron:attachment:expirator` task runs daily at 04:00 UTC and enqueues `Attachment::Expirator`,
which selects records matching the `expired` scope — `updated_at` older than the type's TTL —
transitions each through `expire!`, and hands the id to `Attachment::Destroyer`. The destroyer calls
`Attachment.destroy`, and because the model mounts a CarrierWave uploader the destroy removes the
S3 object along with the row.

Which nightly run catches a given export therefore depends on the attachment record's `updated_at`,
not on the S3 object's upload timestamp. The two can differ by a day for an export whose assembly
spans one, so an export is best treated as leaving within roughly two to three nights rather than on
a specific one.
