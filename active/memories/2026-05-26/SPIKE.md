# SPIKE — Memory Cleanup 2026-05-26

**Status:** Open — proposing destinations; engineer decisions pending.
**Run folder:** `~/.claude/plans/active/memories/2026-05-26/`
**Round:** 1

## Proposed destinations

| # | Source | Summary | Destination | Why | Origin |
|---|---|---|---|---|---|
| 1 | `~/.claude/memory/20260522-100010-pr-6273-html-lint-followup.md` | Follow-up para ativar HTML linting via `@angular-eslint/template` em `app-webclient` depois que PR #6273 (ESLint v9 + flat config) for mergeado. | active plan (`app-webclient-html-lint`) | Trabalho in-flight, depende de outro PR mergeado primeiro; não é uma regra, é um TODO contextual. | NEW |
| 2 | `~/.claude/projects/-Users-plribeiro3000-Projects-4Shark-app/memory/feedback_api_exposure_verification.md` | Ao classificar superfície de API em Rails, sempre começar por `config/routes.rb` + strong_params; nunca inferir de nomes de model. | Tier 2 doc: `~/.claude/docs/RAILS-CONVENTIONS-CONTEXT.md` | Convenção aplicável a qualquer projeto Rails (app, integrator, setup) — não cabe num `<repo>/CLAUDE.md` específico. Conteúdo não está coberto na doc atual. | NEW |
| 3 | `~/.claude/projects/-Users-plribeiro3000-Projects-4Shark-terraform/memory/feedback_temporary_resources_no_changelog.md` | Recursos temporários (VMs de exploração, tooling ad-hoc) não entram no `CHANGELOG.md` do terraform, apesar da regra global exigir changelog em toda feature branch. | `~/Projects/4Shark/terraform/CLAUDE.md` (CRIAR — arquivo ainda não existe) | Exceção específica ao repo terraform; não é regra cross-cutting. O CLAUDE.md do terraform ainda não existe — este memory cria. | NEW |
| 4 | `~/.claude/projects/-Users-plribeiro3000-Projects-4Shark-terraform/memory/feedback_terraform_use_worktree.md` | Mudanças no repo terraform devem rodar em worktree, nunca trocar branch no checkout principal (outras sessões podem estar trabalhando em paralelo). | `~/Projects/4Shark/terraform/CLAUDE.md` (APPEND) | Mesma justificativa do #3 — regra específica do repo terraform. Após merge do PR #3, este PR fará append no mesmo arquivo. | NEW |

## Manual handling

Nenhum. Todos os caminhos decodificados existem em disco.

## Summary

Total: 4 entradas — 0 drops · 0 CLAUDE.md global · 1 Tier 2 edit · 2 per-repo edits · 1 plan migration · 0 manual · 0 carry-overs.

PRs that will be opened: 3 (rows 2, 3, 4).
Plan migrations (local, no PR): 1 (row 1).

**Note on rows 3 and 4:** ambas as memórias destinam-se ao mesmo arquivo (`~/Projects/4Shark/terraform/CLAUDE.md`). Cada uma vira PR separado por design do skill. O PR da row 4 saí de `develop` antes do PR 3 ser mergeado — após o merge do PR 3, será necessário rebase no PR 4 para resolver o conflito de criação/append no mesmo arquivo. Alternativa: aceitar somente um por vez (ex.: aprovar 3, deixar 4 carry-over para o próximo run).
