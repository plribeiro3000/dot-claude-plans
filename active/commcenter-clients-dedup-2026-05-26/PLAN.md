# Commcenter — Dedupe of Clients without CPF prefix (2026-05-26)

## Context

In May 2026, the commcenter-side Client registration script started creating records in the normalized database without the CPF prefix in the `name` field. Result: 58 affected Clients, some generating duplicates in the app because the customer re-registered people who already existed, and the app accepted both (CPF with different encoding + different name → passed the `external_id` and `name` uniqueness constraints).

- Total rows in normalized database: 13449
- With prefix (OK): 13391
- Without prefix (BUG): 58

## Categorization of the 58

| Bucket | Qty | State | Action |
|---|---|---|---|
| **B1** | 33 | Real duplicate (with + without prefix, both integrated, both in app) | 4Shark moves deals + disables bugged in app + disables in mongo + recommends customer delete bugged row from source |
| **C3** | 3 | Bugged pending in mongo, never reached the app (only the correct one made it) | 4Shark does NOT touch the app, disables in mongo, **and** sends list to customer to delete from source |
| **B5** | 2 | Same CPF for different people (probable CPF typo) | Customer confirms which name corresponds to the correct CPF |
| **B6** | 15 | Without prefix, no duplicate (just bugged name, integrated, in app) | Customer updates the name in the normalized source |
| **B7** | 1 | Felipe Granuzzio Fascirolli — special case (old hard-delete blocking) | Separate decision |

Total: 33 + 3 + 2 + 15 + 1 = 58.

> **Note:** an earlier version of this plan grouped 3 cases as "B2/B3" — that was a modeling error (the hypothetical C2 "bugged uploaded, correct did not" does NOT exist in the base; only C3 exists). Bucket renamed to C3 and treated as separate from B1, because even though the final recommendation to the customer is similar, the 4Shark action differs (B1 involves changing the app, C3 does not).

---

## Done — Bucket B1 (33 duplicates)

### What was done

1. **App `shared-001` (cpy 2077)** — for each pair:
   - Re-pointed all `Deal.client_id` from the bugged to the correct (39 deals moved in total — some pairs had more than 1 deal)
   - Also checked `accumulated_deals`, `collaborative_deals`, `deal_eligibilities`, `incentives`, `metrics` — all 0 across the 33 pairs
   - `bugged_client.update!(disabled_at: Time.current)` — no disabler_id

2. **Mongo `integrator-commcenter`** — for each of the 33 bugged ext_ids:
   - `resource.set(integration_status: 'disabled')` — atomic update without triggering state_machine event or Loader
   - No app-side effect (atomic Mongoid update)

### Post-mutation verification

- App: 33 Clients with `disabled_at` set, 0 active associations pointing to them
- Mongo: 33 Resources with `integration_status=disabled`

### The 33 pairs (correct KEPT / bugged DISABLED)

Notation: `norm_id_correct → app_id_correct || norm_id_bugged → app_id_bugged`

| CPF | Name | Correct (kept) | Bugged (disabled) |
|---|---|---|---|
| 52099222860 | Lucas Henrique Sales da Silva | norm 9891 / app 241134 | norm 13506 / app 244875 |
| 48861429823 | Josanaiane Nascimento da Silva | norm 9892 / app 241118 | norm 13507 / app 244874 |
| 16791288680 | Kethellyn Cristine Doscorgos | norm 9893 / app 241109 | norm 13496 / app 244864 |
| 41779176805 | Natane de Freitas da Silva | norm 9900 / app 241107 | norm 13517 / app 244877 |
| 47490665833 | Luis Miguel Silva Souza | norm 10064 / app 241289 | norm 13432 / app 244687 |
| 50110717821 | Marcos Vinicius Almeida Maria Felicio | norm 10439 / app 241645 | norm 13434 / app 244694 |
| 50938334875 | Joao Vitor Americo | norm 11234 / app 242447 | norm 13393 / app 244647 |
| 12582505862 | Arilson Duran da Silva | norm 11361 / app 242571 | norm 13518 / app 244876 |
| 12672546886 | Maria Lucia Bortoloto de Souza | norm 11376 / app 242592 | norm 13369 / app 244621 |
| 31928885802 | Moises de Carvalho Arandes | norm 11893 / app 243107 | norm 13399 / app 244664 |
| 40301513880 | Dora da Silva Andrade | norm 12056 / app 243279 | norm 9899 / app 241130 |
| 38873467857 | Matheus Henrique Boffi Goncalves | norm 12202 / app 243427 | norm 13453 / app 244703 |
| 26965073845 | Joaquim Bispo Rocha | norm 13370 / app 244607 | norm 13500 / app 244866 |
| 33492342833 | Silvana Alexandra de Paula | norm 13372 / app 244628 | norm 13499 / app 244867 |
| 48847552869 | Chirley Mireli Meneses de Lima | norm 13373 / app 244623 | norm 13509 / app 244883 |
| 31333676840 | Alexandre Lemos Santos Teodoro de Souza | norm 13383 / app 244633 | norm 13498 / app 244869 |
| 33522603893 | Adilson Nascimento dos Santos | norm 13387 / app 244649 | norm 13508 / app 244882 |
| 13120860840 | Veronica Goncalves Santos | norm 13400 / app 244650 | norm 13497 / app 244873 |
| 11750613875 | Marizete Alves dos Santos | norm 13411 / app 244651 | norm 13515 / app 244872 |
| 36590597812 | Adriano Pereira do Nascimento Rufino | norm 13412 / app 244652 | norm 13516 / app 244892 |
| 46268248899 | Amanda dos Santos | norm 13419 / app 244673 | norm 13510 / app 244878 |
| 37959995885 | Laiane Cristina Galati | norm 13420 / app 244674 | norm 13511 / app 244891 |
| 11319491537 | Rai Santos Silva | norm 13422 / app 244672 | norm 13512 / app 244889 |
| 35295202844 | Adao Barbosa dos Santos | norm 13427 / app 244677 | norm 13513 / app 244879 |
| 35784120824 | Elizane Carvalho Teles | norm 13429 / app 244680 | norm 13514 / app 244880 |
| 22591740860 | Eva Cristina de Oliveira | norm 13433 / app 244686 | norm 13493 / app 244886 |
| 21546930833 | Albertina Juliana Matielo da Fonseca | norm 13437 / app 244701 | norm 13494 / app 244865 |
| 23536389880 | Willa Pereira de Carvalho | norm 13443 / app 244695 | norm 13495 / app 244871 |
| 35478116866 | Rudinei Fernando Pereira dos Santos | norm 13449 / app 244709 | norm 13501 / app 244863 |
| 90198426844 | Pablo Henrique Dias da Silva | norm 13450 / app 244702 | norm 13502 / app 244868 |
| 49194581851 | Andresa Cristina do Carmo Ribeiro | norm 13452 / app 244699 | norm 13503 / app 244887 |
| 17123037839 | Aparecida de Fatima Almeida Nancio | norm 13454 / app 244706 | norm 13504 / app 244870 |
| 50296607800 | Aline Gabriela Ruivo Madureiro | norm 13455 / app 244708 | norm 13505 / app 244881 |

CSV: `~/Downloads/commcenter_B1_pares_para_corrigir_deals_20260526.csv`

---

## To deliver — Bucket B6 (15 bugged names)

### What to ask the customer

Update the `name` in the normalized source to include the CPF prefix (raw, no dots/dash). SQL ready at:

`~/Downloads/commcenter_B6_sql_updates_para_cliente_20260526.sql`

15 UPDATEs with `BEGIN; ... COMMIT;`.

### The 15 IDs to update

| norm.id | CPF | Current name (wrong) | Expected name (correct) |
|---|---|---|---|
| 9965 | 42871518874 | PAMELA DE ALMEIDA MORAES FONSECA | 42871518874-PAMELA DE ALMEIDA MORAES FONSECA |
| 10106 | 13277215890 | MARCIA APARECIDA BRITO | 13277215890-MARCIA APARECIDA BRITO |
| 10388 | 17693979816 | Luciana Rodrigues Da Silva | 17693979816-Luciana Rodrigues Da Silva |
| 10399 | 29752842844 | ISAIAS COSTA | 29752842844-ISAIAS COSTA |
| 10625 | 21833597818 | JOAO LUIZ DA SILVA | 21833597818-JOAO LUIZ DA SILVA |
| 10697 | 39613698876 | Catarina Aparecida do Santos | 39613698876-Catarina Aparecida do Santos |
| 10709 | 44945976864 | Mateus Wallace Alves da Silva | 44945976864-Mateus Wallace Alves da Silva |
| 10714 | 40335739334 | Joao Moreira da Silva Filho | 40335739334-Joao Moreira da Silva Filho |
| 11145 | 32757217801 | Dalid Roque | 32757217801-Dalid Roque |
| 11186 | 46440375830 | ANDERSON SAMUEL LIMA LOPES | 46440375830-ANDERSON SAMUEL LIMA LOPES |
| 11336 | 13555182617 | Marco Nilton Lopes Rodrigues Muniz | 13555182617-Marco Nilton Lopes Rodrigues Muniz |
| 11672 | 32762206871 | MISLENE DE SENA DOS SANTOS | 32762206871-MISLENE DE SENA DOS SANTOS |
| 11934 | 39321807802 | MARIANNA GRACIELLE SILVA SOARES | 39321807802-MARIANNA GRACIELLE SILVA SOARES |
| 12077 | 16122153869 | SIMONE APARECIDA DA SILVA | 16122153869-SIMONE APARECIDA DA SILVA |
| 13347 | 51788567838 | FABIANA CHAVES CAMPOS | 51788567838-FABIANA CHAVES CAMPOS |

After the customer runs the SQL, the next integrator sync will `PUT` to the app, fixing the name automatically.

---

## To deliver — Bucket B5 (2 pairs with shared CPF across different people)

### Situation

The same CPF appears in 2 rows of the normalized source with names of clearly different people. Probable typo in one of the rows. **4Shark cannot decide** which CPF is correct — risk of disabling the wrong person. Only Commcenter knows.

### The 2 cases

| CPF | Person 1 (with prefix, older) | Person 2 (without prefix, more recent) |
|---|---|---|
| `32294989848` | norm 10617 — **JULIANO MARTINS SOUSA** | norm 13388 — **Telma Benedita de Morais** |
| `01673768881` | norm 10692 — **PEDRO SERRANO MORENO** | norm 13424 — **Antonio Carlos Moreno** |

### Commcenter's action

For each CPF, confirm which is the real owner of the CPF:

- "For CPF `32294989848`, which person owns the correct CPF: **JULIANO MARTINS SOUSA** or **Telma Benedita de Morais**?"
- "For CPF `01673768881`, which person owns the correct CPF: **PEDRO SERRANO MORENO** or **Antonio Carlos Moreno**?"

After the answer, 4Shark disables the row of the person whose CPF was wrong, and the customer updates the correct CPF in the source.

CSV: `~/Downloads/commcenter_suspect_same_cpf_diff_person_20260526.csv`

---

## Done — Bucket C3 (3 duplicates where the bugged one never reached the app)

### Situation

Separate bucket from B1 because the duplicate **never reached the app** — the integrator's POST was rejected and the Resource stayed `pending` in mongo. The correct Client (with prefix) is already integrated in mongo and active in the app.

| norm.id (bugged, no prefix) | CPF | Name | Correct sibling (in app, integrated) |
|---|---|---|---|
| `13436` | 08610437400 | Marciano Santos da Silva | norm 13263 / app 244510 |
| `13444` | 08831495836 | Maria Aparecida Santaliestra | norm 11909 / app 243122 |
| `13445` | 07422281693 | Mara Rubia Gomes Silva | norm 13305 / app 244565 |

### Solution (different from B1 — note that the app is NOT touched)

1. **App:** do not touch — the correct Client is already there active, nothing to deconflict
2. **Mongo:** `resource.set(integration_status: 'disabled')` on the 3 pending Resources (via 3 scripts pre-flight + mutation + verification — pre-flight expects `pending`)
3. **Customer recommendation:** delete the 3 ids `13436, 13444, 13445` from the normalized base (added to the list together with the 33 from B1)

### Why it is a separate bucket from B1

The 4Shark action differs — B1 involves re-pointing Deals and disabling Clients in the app; C3 does not touch the app. Even though the final customer recommendation has the same shape (delete from source), the internal effort is distinct. Documenting separately avoids confusion in future audits.

---

## To deliver — Bucket B7 (Felipe Granuzzio Fascirolli)

### What happened (full timeline, evidence-backed)

1. Some time before 2026-05-04: Felipe is in the source with `id=9902`. Integrator extracts → Mongo Client `9902` → POST `/clients` returns **201** at 2026-05-04 14:44:43 UTC → Client created in app
2. 2026-05-04 13:18:49 UTC: customer creates a new row in source with `id=9999, name="FELIPE GRANUZZIO FASCIROLLI" (no prefix)` and 1 deal (`norm.id=14050, ext_id=65574, date=2026-03-21, sold_price=109.99`) with `client_id=9999`
3. 2026-05-04 14:44:47 UTC: integrator POSTs `/clients` for `9999` → **422 "name ja esta em uso"** (Client.name uniqueness in app — conflicted with the `9902` row created 4 seconds earlier). Mongo `9999` stays `pending`
4. 2026-05-04 14:47:01 UTC: integrator POSTs `/deals` for `14050` with `client_id: 9999` → app accepts with **201** but silently sets `client_id=nil` (resolver returned nil for unknown 9999 — bug logged in memory)
5. **2026-05-19 04:01:22 UTC: integrator POSTs `/deals` for `13969`** with `client_id: 9902` → **201**, app creates Deal app.id=19941012 linked to Felipe Client 9902. Details: vendor `user_id=735` (Bleica Ariadene Alves Possiano, `bpossiano@commcenter.com.br`), date=2026-03-30, sold_price=R$ 60,00, description="Numero para contato (whatsapp)", status="movel", type=Sale
6. 2026-05-22 20:47:22 UTC: last PUT 204 on `/deals/13969` — Deal still in app, Client 9902 still in app
7. **Between 2026-05-22 and 2026-05-26: Emerson hard-destroys Client 9902** in the app (via `Client.destroy`). The `dependent: :destroy` on `Client.has_many :deals` cascades → **Deal 13969 destroyed alongside**

### Current state (snapshot 2026-05-26)

- **Source normalized:** `id=9999` active (no prefix, B6-shape). The deal `13969` was already deleted from source by the customer earlier; only `14050` remains
- **Mongo:** Client `9902 integrated` (vestige — no longer in app), Client `9999 pending` (POST keeps failing on retries because the row that conflicted is gone from app but the `9999` POST still returns 422 — to be verified next sync after name fix), Deal `13969 integrated` (vestige — no longer in app), Deal `14050 integrated` (in app, `client_id=nil`)
- **App:** no Client with ext_id `9902` or `9999`; Deal `14050` exists with `client_id=nil`; Deal `13969` does not exist (cascaded)

### Confirmed impact of the cascade

| Cascade target | dependent | Impact |
|---|---|---|
| `commissionings` | destroy | **0 lost** — checked Bleica's UserCommissions (0 exist). 7 commissions in cpy 2077 cover only Jan-Mar 2025; Deal date is 2026-03-30 → no commission could ever have run for it |
| `deal_eligibilities` | restrict_with_exception | None (otherwise the destroy would have failed) |
| `enrollments` | restrict_with_exception | None |
| `fields` (DealField) | restrict_with_exception | None |
| `user_deal_histories` | restrict_with_exception | None |
| `kpi_enrollments` | nullify | Not verified globally — even if some were nullified, recoverable when deal is re-created |
| `delete_datasets` callback | after_destroy | Datasets are precomputed/recomputable — re-runs when deal exists again |

**Net data loss:** the Deal 13969 itself (R$ 60, Bleica/Felipe, 2026-03-30). No commission damage. No goal damage. The Deal is the only thing lost.

### Why we cannot recreate it ourselves

We have the full deal data from the mongo import, **but** the new Felipe Client (9999) is not in the app yet because the name conflict prevented the original POST and the subsequent retries also failed. The pre-flight script (`/tmp/integration_debug_phase2_scripts_v2_commcenter_*.html` style) confirms: `Client 9999` not present in app. So we cannot create the Deal pointing to it.

The customer needs to act so that (a) the Client 9999 enters the app correctly, and (b) the Deal 13969 is re-created in the source pointing to the right id.

### Customer-side actions required

1. **Update name on source for `id=9999`** to include the CPF prefix:
   - From: `FELIPE GRANUZZIO FASCIROLLI`
   - To: `40249179865-FELIPE GRANUZZIO FASCIROLLI`
   - This is the same shape as the 15 B6 updates (so B6 effectively becomes 16 ids). Bumping `updated_at` is mandatory — without it, the integrator will not pick up the change on the next sync
2. **Re-create the Deal 13969 in the source normalized base** with the same details (date=2026-03-30, sold_price=60.0, description, etc.) pointing now to `client_id=9999` (the new Felipe id). Force `updated_at = NOW()` so integrator picks it up
3. After the next sync runs: `POST /clients` for 9999 succeeds (name now unique, and the conflicting Client 9902 is gone from app), Client lands in app; subsequent `POST /deals` for the re-created Deal works (client_id resolves correctly)

### 4Shark-side actions (post customer fix)

- `resource.set(integration_status: 'disabled')` on mongo Client `9902` (vestige cleanup)
- `resource.set(integration_status: 'disabled')` on mongo Deal `13969` (vestige cleanup — the new re-created deal will have a different ext_id, so this stays as historical record)
- Optionally re-trigger sync to accelerate

---

## Proposed message for Commcenter (commcenter)

> Oi pessoal,
>
> Encontramos 58 Clients que entraram na nossa base sem o prefixo do CPF no nome (formato `<cpf>-<nome>`), causado por uma mudanca no script de cadastro de voces que comecou em maio/2026. Desses, **36 ja foram tratados** do nosso lado e **17 precisam de acao de voces**.
>
> **33 duplicatas resolvidas no app (4Shark fez):**
> Para cada CPF duplicado em que as duas versoes (correta com prefixo + bugada sem prefixo) chegaram ao app, identificamos qual e qual, movemos todas as Deals da versao bugada para a correta, desativamos a versao bugada no app, e atualizamos o status do integrador. Lista detalhada de IDs em anexo.
>
> **3 duplicatas resolvidas so no integrador (4Shark fez):**
> Sao casos onde o re-cadastro (bugado) tentou subir e foi rejeitado pelo app, ficando pendente no nosso integrador. O Client correto ja estava la funcionando. Marcamos esses 3 como desativados no integrador para nao tentar de novo. Esses 3 IDs entram na lista de recomendacao abaixo.
>
> **15 cadastros unicos com nome bugado (voces precisam atualizar):**
> Sao registros que nao tem versao correta na base normalizada. Para esses, voces precisam rodar o SQL anexo na base normalizada para prefixar o nome com o CPF. Apos rodar, o integrador propaga a correcao para o app automaticamente.
>
> **2 casos de CPF compartilhado por pessoas diferentes (precisamos da confirmacao de voces):**
> Encontramos dois CPFs onde a mesma CPF aparece em registros com nomes de pessoas claramente diferentes — provavelmente houve typo do CPF em uma das duas rows. Como nao podemos saber qual e' a pessoa real, precisamos que voces confirmem:
> - Para CPF `32294989848`, qual pessoa tem a CPF correta: **JULIANO MARTINS SOUSA** ou **Telma Benedita de Morais**?
> - Para CPF `01673768881`, qual pessoa tem a CPF correta: **PEDRO SERRANO MORENO** ou **Antonio Carlos Moreno**?
>
> **Recomendacao adicional (opcional, mas importante):**
> Para os **36 registros** que desativamos do nosso lado (33 do app + 3 que ficaram so no integrador), recomendamos que voces apaguem as linhas correspondentes da base normalizada (ids listados abaixo) para evitar que esses registros sejam reutilizados acidentalmente no futuro. Nao e obrigatorio para os 33 que ja sumiram do app, mas para os 3 do integrador e' particularmente recomendado — se voces atualizarem qualquer atributo dessas rows na fonte, nosso integrador vai tentar reativar e o ciclo de duplicacao volta.
>
> **1 caso especifico (Felipe Granuzzio Fascirolli) — voces precisam de duas correcoes:**
> Esse e' um caso especial. O cadastro novo do Felipe (id=9999 na base de voces) nao chegou ao app porque o nome esta sem o prefixo do CPF e bateu com uniqueness do nome do cadastro antigo (que foi removido depois). Alem disso, uma transacao desse cliente (id=13969 originalmente, descricao "Numero para contato (whatsapp)", data 2026-03-30, R$ 60, vendedor Bleica) foi removida do app quando o cadastro antigo foi apagado.
>
> Para resolver, precisamos que voces:
> 1. **Atualizem o nome do Felipe (id=9999) na base normalizada** para incluir o prefixo do CPF: `40249179865-FELIPE GRANUZZIO FASCIROLLI`. E garantam que o `updated_at` da linha mude (forca o integrador a pegar a mudanca na proxima sync).
> 2. **Re-criem a transacao 13969 na base normalizada** com os mesmos dados (data=2026-03-30, valor=R$ 60, vendedor `4sk_735` Bleica, descricao "Numero para contato (whatsapp)", status="movel") apontando agora para `client_id=9999` (o novo Felipe). Pode usar qualquer id novo da fonte para essa linha. Forcem `updated_at = NOW()`.
>
> Apos voces fazerem essas duas alteracoes, a proxima sincronizacao automatica cadastra o Felipe corretamente e re-insere a transacao no app, ja apontando para o cliente certo.
>
> Qualquer duvida, estamos disponiveis.

(Customer-facing message above is kept in pt-BR because that is the language the customer reads.)

---

## Next steps

1. **Handle C3** — 4Shark runs the 3 scripts (pre-flight + mutation + verification) in `bin/ecs run integrator-commcenter` to flip the 3 pending Resources to disabled
2. **Deliver to Commcenter** — single package containing:
   - B6 SQL (15 UPDATEs in the normalized source)
   - B5 questions (2 CPFs to confirm — Juliano/Telma and Pedro/Antonio)
   - B1 + C3 list (36 disabled ids — recommendation to delete from source; particularly important for the 3 from C3)
3. **Handle B7 (Felipe)** — internal 4Shark decision on whether to bring him back to the app
4. **After customer answers B5** — 4Shark disables the incorrect rows
5. **After customer runs B6** — verify via audit that the 15 turned OK
6. **Final verification** — re-run full audit (`integration_audit:client[2077]` + `mongo:client` + `normalized:client`) confirming the 58 left the "no prefix" bucket
7. **Final consolidated report** — `.xlsx` or `.pptx` in `~/Downloads/`
