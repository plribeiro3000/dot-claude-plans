# SPIKE — Dashboard zerado: "Remuneração variável total" R$ 0,00 (Grupo Luiz Hohl)

**Data:** 2026-06-12
**Tenant:** Grupo Luiz Hohl (`company_id` 2209), app shared-001
**Disparo:** ticket "DASHBOARD ZERADO" — colaboradora Flávia Costa Ferreira (matrícula 02126, `user_id` 1037901) vê R$ 0,00 no Dashboard do calendário (Maio/2026), mas a tela de Compensação mostra R$ 3.245,45. Mais 2 consultores do mesmo plano no mesmo cenário.
**Resultado:** causa-raiz selada + hotfix 3.36.1 deployado (`app/elastic_indexes`).

---

## 1. Pergunta

Por que o Dashboard mostra R$ 0,00 enquanto a Compensação mostra R$ 3.245,45 para o mesmo usuário/plano/período, de forma **intermitente** (alguns dias com valor, outros zerados)?

---

## 2. Hipóteses descartadas (com evidência)

| # | Hipótese | Por que caiu |
|---|---|---|
| 1 | Cache do navegador (orientação do suporte) | O R$ 0,00 vem do servidor; 3 consultores afetados; `Ctrl+Shift+R` não resolveu |
| 2 | Dashboard (Mongo `UserCommissionDataset`) vs SQL divergem por design | Verdade que leem stores diferentes (Mongo denormalizado × SQL vivo), mas o snapshot Mongo estava `money=0` **de verdade**, não stale por leitura |
| 3 | Denormalização (Producer/Consumer) com bug | O Consumer **inclui** as `IndicatorCommissioning`; o snapshot zerou porque a métrica de origem zerou |
| 4 | Comissão `locked`-não-`final` + parcial sobrescreve o dashboard | Real e contribui (a parcial denormaliza enquanto não há `final`), mas a parcial em si calculou 0 — o zero nasce **antes**, na métrica |
| 5 | Corrida de **refresh** do OpenSearch (deals indexados mas não refreshados na hora) | **Falsificada por dado persistido**: os `DealIndexationBatch` da Flávia ficaram `refreshed` às 00:27:16, e a métrica leu às 00:28:08 — **52s depois**. Não foi miss de refresh |
| 6 | **Expirator** removeu os deals do índice na janela | **Falsificada por log**: o expirator rodou às **04:01 UTC**, ~33min **depois** da métrica gravar 0 (03:28:08 UTC) |

---

## 3. Causa-raiz (selada)

**Colisão de `_id` no OpenSearch entre comissões que compartilham o mesmo deal.**

O documento de deal no índice é gravado com **`_id = deal.id`** (cru) e `commission_uuid` como **um único campo mutável** (`app/elastic_indexes/application_elastic_index.rb:48`, `app/elastic_indexes/deal_elastic_index.rb:6-7`).

Os deals da Flávia são reindexados **por mais de uma comissão na mesma madrugada**:
- Plano dela: **CONSULTORES DE PEÇAS** (`plan_id` 77864, parcial 1502003).
- Plano do gestor: **GERENTE DE PEÇAS** (`plan_id` 77865, override, parcial 1502016) — o caminho `override` do `UserProducer` (`app/workers/deal_elastic_index/user_producer.rb:20-43`) puxa os deals dos subordinados.

Como o `_id` é só `deal.id`, **a última comissão a indexar "ganha" o `commission_uuid` do doc**. A métrica (`Metric::Consumer` → `Metric::TotalAdapter` → `DealElasticIndex.fetch_ids_by(commission_uuid:)`) filtra por `commission_uuid`. Então **o plano que perde a corrida lê 0 deals** → métrica 0 → `Indicator` (compartilhado, por user/variable/dia) gravado 0 → `AggregatedIndicator` 0 → `modifier_options` 0 → `UserCommission.billable_money` 0 na parcial → como a comissão está `locked`-não-`final`, a parcial denormaliza → `UserCommissionDataset` (dashboard) zerado → **Dashboard R$ 0,00**. A Compensação lê o SQL congelado da commission cheia (computada 05/06, antes do dado expirar) → **R$ 3.245,45**.

### Intermitência = ordem da corrida no burst noturno

O cron das 00:28 dispara ~386 comissões indexando ao mesmo tempo. Vence quem ler a métrica antes do outro plano reindexar. Confirmado por CloudWatch + batches persistidos:

| dia | CONSULTORES indexa | GERENTE sobrescreve | gap | métrica CONSULTORES lê | resultado |
|---|---|---|---|---|---|
| 11/06 (valor) | 03:26:41 | 03:27:59 | +78s | burst 03:27:31–52 (antes) | **3245** |
| 12/06 (zero) | 03:27:16 | 03:27:25 | +9s | 03:28:08 (depois) | **0** |

Discriminador quantitativo: a métrica roda ~50s após o refresh da própria parcial. Gap do outro plano > 50s → lê antes → valor; gap < 50s → sobrescrita antes → zero.

### Evidência-chave (teste de mesa, dado real)

Deal `19969365` (compartilhado pelas 2 parciais):
- `_id` antigo (ambas) = `19969365` → colidem.
- `_id` novo CONSULTORES = `p_1502003_1037901_19969365`; GERENTE = `p_1502016_1037901_19969365` → distintos, sem colisão.

---

## 4. Correção (hotfix 3.36.1)

DSL declarativo `document_id` na base + uso só no caminho **bulk** (`save_documents!`, o único ativo no cálculo — `deal_elastic_index/consumer.rb:26`):

```ruby
# application_elastic_index.rb (base) — DSL no estilo de document_attributes/extra_attributes
def document_id(*document_id)
  return @document_id || [:id] if document_id.blank?
  @document_id = Array(document_id)
end
# save_documents!: _id passa a ser document.slice(*document_id).values.join('_')

# deal_elastic_index.rb
document_id :commission_uuid, :user_id, :id
```

- `_id` composto `commission_uuid_user_id_dealid` → cada comissão mantém o próprio doc → sem overwrite.
- **Leitura intacta:** `fetch_ids_by` retorna o campo `id` (= `deal.id`), não o `_id`; `Deal.where(id:)` segue funcionando.
- **Delete intacto:** Expirator faz round-trip do `_id` (`destroyer.rb:8`).
- **Singular/Sower-Grower** (inativo) não coberto — `_id = deal.id` ainda; follow-up.
- **`_id` validado contra ES:** aceita string + underscore; limite 512 bytes; composto ~26–36 bytes (folga ~14×).

PR #5132 → master+develop via `git hf hotfix finish`. Deploy concluído em todos os ambientes (imagem `latest` = sha `f586565` = merge do hotfix).

---

## 5. Remediação dos dados

Sem fix manual: o dashboard **se auto-cura na próxima indexação por comissão** pós-deploy (parcial noturna ~00:28). Os docs antigos (`_id` cru) coexistem sem causar erro (duplicatas dedupadas por `Deal.where(id:)`) e o Expirator os remove em ≤ 2 dias (campo `updated_at` = `deal.updated_at`, já antigo). Não apagar o índice (criaria buraco de busca/métrica).

---

## 6. Itens em aberto

- **Version bump pulado:** `config/version.rb` ficou `3.36.0`; a imagem saiu `3.36.0-<sha>` apesar da tag git `3.36.1`. Mismatch a corrigir (3.36.2 ou próximo release).
- **Sower/Grower (singular `save_document!`):** quando ativar, precisa do mesmo `_id` composto.
- **Validação amanhã pós-parcial:** confirmar `fetch_ids_by(commission_uuid: <nova parcial>, user 1037901)` > 0 e `metric.calculate(...)` ≈ 519955 para a Flávia.
- **Auditoria de escala:** o `_id` composto multiplica o doc por comissão que toca o deal (override multinível) — dimensionar vs a saturação do OpenSearch (ADR-0001).

---

## 7. Artefatos

- Logs CloudWatch: `/tmp/cw_dealidx_zeronight_*.txt`, `/tmp/cw_metric_*.txt`, `/tmp/cw_expirator_0612.txt`
- Relatórios HTML de diagnóstico: `/tmp/diagnostic_dashboard_zerado_flavia*.html`
- PR: https://github.com/4shark/app/pull/5132
