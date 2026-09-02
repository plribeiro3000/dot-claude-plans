# Preparativo — Resposta aos documentos da Atento México

**Data:** 2026-09-01 · **Responsável:** Paulo · **Prazo de visibilidade Atento:** quinta 03/09
**Status:** ✅ Entregue ao Santiago (01/09 13:45) para validação final — aguardando o retorno dele.

Consolida o que a Atento México pediu (3 reuniões de 31/08), a arquitetura da integração e o conteúdo dos três documentos entregues. Partes em espanhol = texto que foi para os `.docx`/PDF; o resto é nota interna.

---

## 0. Princípio de divulgação (teto de segurança)

A 4Shark **não divulga infra interna** — nada de servidores, serviços, hostnames, IPs, ou se roda em ECS/Kubernetes/etc. A ficha entregue foi **um passo além do teto**: em vez de responder no nível de providers (AWS/Cloudflare), ela **omite a infra da 4Shark por completo** e documenta apenas os componentes e acessos **do lado da Atento** (as 3 bases + as VPNs). Foi a leitura correta do pedido — a Atento pediu o que ELA precisa manter, não a arquitetura da 4Shark.

---

## 1. De onde vieram os documentos

Os dois arquivos-modelo chegaram pelo **Slack**, do Santiago, na DM (31/08 17:40): *"estos son los dos documentos de mexico, creo que son simples"*, com **Ficha Técnica.docx** e **Ejemplo de_Riesgos - Impactos de Proyecto.docx**. Não são os questionários de segurança (TPRM/LGPD) — a reunião do México foi explícita: riscos/dependências do projeto **não** são os cuestionarios de seguridad.

---

## 2. Arquitetura da integração (México / Simplex)

Fluxo real, na ordem:

1. **App .NET (roda do lado da 4Shark).** Lê a base de produção do **Simplex** (RH deles) e **escreve na base normalizada**. Só isso.
2. **Integrador (app original da 4Shark, roda ~1h depois).** **Lê** da base normalizada (sem permissão de escrita), manda para a **API**, grava a resposta no seu **Mongo local**, gera **relatório** e envia por **email**.

**Base normalizada:** estrutura 100% controlada e documentada pela 4Shark — uma tabela por API, procedures, índice único, colunas de criação/última atualização, ID auto-incremental. A 4Shark entrega a estrutura e os scripts; a Atento executa.

**Do lado da Atento (o que vai na ficha):**
- VPN para a base normalizada + VPN para o servidor do Simplex (duas VPNs no México)
- A base normalizada
- A base de **Simplex** (fonte)
- A base de **VKPIs** (criada no servidor do Simplex, populada pela Atento a partir do Data Lake)

**Status:** Simplex já funciona. **VKPIs é o gargalo** (ver R03/R04 e as pendências da tabela abaixo).

---

## 3. Os três entregáveis (estado final)

| # | Documento | Arquivo (`~/Downloads/`) | Dono |
|---|-----------|--------------------------|------|
| 1 | Ficha Técnica (Memoria Técnica) | `Ficha Técnica - 4Shark Atento México.docx` | Claudio |
| 2 | Riesgos / Impactos de Proyecto | `Riesgos - Impactos de Proyecto - 4Shark Atento México.docx` | Paulo |
| 3 | Roadmap de funcionalidades | `roadmap_atento_mexico_20260901.pdf` | Paulo |

Todos entregues ao Santiago em 01/09 (§7). Fonte do roadmap em HTML/gerador nesta mesma pasta.

---

## 4. DOCUMENTO 1 — Ficha Técnica / Memoria Técnica

**Escopo entregue:** só os componentes e acessos que a **Atento** deve manter — sem infra interna da 4Shark (nem "no aplica"; simplesmente omitido). Seções: 1. Control de Versiones · 2. Objetivo · 3. Descripción de la Solución · 4. Terminología · 5. Infraestructura. As seções 6/7 (servidores) do template foram removidas.

**Conteúdo-chave:**
- **Objetivo:** documentar os componentes e acessos que a Atento México deve manter e garantir para o funcionamento da integração.
- **Descripción:** três bases do lado da Atento, em dois ambientes (produção + homologação), com os acessos VPN.
- **Terminología:** Base normalizada · Base de Simplex · Base VKPIs · VPN (acesso interno; os bancos só aceitam acesso interno, não público).
- **Infraestructura (tabela `Componente | Producción | Homologación`):** Base normalizada (escrita+leitura via VPN) · Base de Simplex (só leitura via VPN) · Base VKPIs (no servidor do Simplex, mesmo usuário e VPN, populada pela Atento desde o Data Lake). A homologação é justificada como o ambiente onde a Atento desenvolve/valida mudanças sem afetar produção.

**Pendências:**
- **"Elaborado por" está como Paulo Ribeiro** — o dono do documento é o **Claudio**; ajustar antes da versão final se for ele quem assina.
- Aguardar a **lista de campos que a Aryadna vai mandar** (via Claudio): confirmar se cabe nesse teto de componente/acesso; se pedirem servidor/serviço, não descer abaixo do nível de componente.

---

## 5. DOCUMENTO 2 — Riesgos / Impactos

Registro real do projeto, **espelhando os componentes da ficha** (as dependências do lado da Atento) + um risco baixo do lado da 4Shark. Formato `ID | Fase | Riesgo | Dependencia | Impacto Potencial | Probabilidad | Impacto | Mitigación`.

| ID | Componente / Fase | Prob. | Imp. | Núcleo |
|----|-------------------|-------|------|--------|
| R01 | Base normalizada (manter base + VPN, prod+homolog) | Media | Alto | Sem ela a integração não lê nem escreve |
| R02 | Base de Simplex (usuário leitura + VPN, prod+homolog) | Media | Alto | Sem captura da fonte, a integração não se alimenta |
| R03 | Base VKPIs — **estrutura** (índice único, coluna ID, sem duplicados) | Alta | Alto | Duplicados não-determinísticos: o resultado varia entre corridas e **aparenta bug de integração quando é de dados** |
| R04 | Base VKPIs — **população** (fluxo Data Lake → VKPIs) | Alta | Alto | Decisão da própria Atento não dar acesso ao Data Lake; sem dados populados, a integração VKPI não inicia |
| R05 | Base VKPIs — **homologação** (cópia de homolog) | Media | Medio | Sem ela, testes rodam sobre produção |
| R06 | Desenvolvimento (4Shark) | Baja | Medio | 4Shark inicia o desenvolvimento assim que a estrutura final do banco for entregue |

**R03 + R04 são o coração** — os bloqueios que dependem 100% da Atento. R04 deixa claro que **foi decisão deles** não dar acesso ao Data Lake e fazer o espelhamento por conta; não é pedir acesso de volta, é registrar que o risco é a Atento não cumprir a decisão que ela mesma tomou.

**Deliberadamente fora:** os questionários de segurança (TPRM/LGPD) e a adoção no go-live — a reunião do México separou riscos de projeto dos cuestionarios de seguridad.

---

## 6. DOCUMENTO 3 — Roadmap de funcionalidades

**Formato:** o mesmo design da Colômbia (`roadmap_atento_colombia_20260820.pdf`) — cards de contagem, "Cómo leer", timeline vertical por mês, card "Próxima integración", tabela "Temas en seguimiento". Nome de arquivo na convenção da Colômbia: `roadmap_atento_mexico_<YYYYMMDD>.pdf`.

**Conteúdo:** **14 itens** (12 funcionalidades novas + 2 melhorias de fluxo), maio→agosto 2026, todos já em produção e disponíveis para a operação do México. Seção 3 (Próxima integración / Temas en seguimiento): **VKPI** + integração de metas.

**Critério de curadoria (o que É e o que NÃO é roadmap):**
- **É:** funcionalidade completa nova, ou melhoria que altera o **fluxo** de uma funcionalidade existente. Quando a Atento começou a usar, a plataforma já estava pronta — o roadmap mostra o que a 4Shark **desenvolveu de novo** desde então.
- **NÃO é:** correção de tela / detalhe / adaptação pontual; nada de incentive, pay/nómina, ventas, transacciones, SSO/login (só implementado no Brasil, aguardando o time interno deles); funcionalidade que não muda nada para o México (ex.: retenção por país, cujo período não foi confirmado do lado deles).

---

## 7. Fecho — entrega ao Santiago (01/09 13:45, `#atento-mx`)

> **Paulo → @Santiago Velasquez:** "seguem los documentos de atento mexico preenchidos. Peço que haga una validación para garantizar que não deixei nada de fora."

Os três arquivos foram entregues ao Santiago (nativo) para a validação final antes de irem à Atento, conforme a norma do time. Prazo de visibilidade da Atento: **quinta 03/09**.

---

## 8. Pendências abertas (não bloqueiam a entrega)

- **Retorno do Santiago** sobre os três documentos.
- **Ficha:** trocar "Elaborado por" para o Claudio se for ele quem assina; encaixar a lista de campos da Aryadna quando chegar (via Claudio), sem descer abaixo do nível de componente.
- **Do lado da Atento (destrava o início da integração VKPI):** entregar a tabela VKPI corrigida — coluna-chave com a chave 4Shark, valor único consolidado por pessoa/indicador/período (hoje há duplicados com resultados distintos), índice único (fecha+pessoa+chave), fecha como `date` real, e garantia de `DT__INSERT`/`DT_MODIFIED` (só-criação / sempre-que-muda) para a carga incremental funcionar. Confirmar que `NR_RE` é o carnet do empregado (chave de cruzamento no México).

---

## Changelog
- **2026-09-01** — Documentos finalizados e entregues ao Santiago para validação. Ficha reduzida ao nível de componente/acesso da Atento (sem infra 4Shark). Riesgos consolidado em R01–R06, espelhando os componentes da ficha + risco 4Shark. Roadmap reconstruído no formato Colômbia com 14 funcionalidades de núcleo (mai–ago), curado para conter só funcionalidade completa nova ou melhoria de fluxo.
