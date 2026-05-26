# PLAN — Corrigir `ShutDownWorker` para desligar ECS ao fim da integração

**Projeto:** integrator
**Input:** `SPIKE.md` neste diretório
**Data:** 2026-04-10

## Problema

`ShutDownWorker` termina reportando sucesso, mas **nunca escala o ECS pra 0**. O erro de `AccessDeniedException` na chamada `ecs:UpdateService` é engolido por um `rescue Fog::AWS::ECS::Error` que só escreve um warning. Resultado: web + worker ECS rodam dia e noite contra um Mongo parado, gerando loop de erro de conexão invisível pra quem não olha os logs. Já dura pelo menos 4 dias pra maqnelson e 3 pra almaviva.

Detalhes completos em `SPIKE.md`.

## Escopo

**Dentro do escopo desta correção (esta PR no repo `integrator`):**

1. Remover o `rescue` silencioso em `Ecs.scale_down` — deixar o erro explodir.
2. Quebrar `scale_down` em duas etapas: **web primeiro, worker por último**.
3. Manter a ordem `Ec2.stop_machine` → `Ecs.scale_down` no `ShutDownWorker` (Mongo primeiro, ECS depois).

**Fora do escopo (separados como follow-ups):**

- **IAM `ecs:UpdateService` para `integrator-{client}`** — fix no Terraform. Tem outra sessão trabalhando no Terraform agora; o fix entra depois, como uma PR separada no repo `terraform`. Não dá pra abrir aqui porque o erro só desaparece com a policy atualizada.
- **`CLIENT_NAME` capitalizado vs slug de recurso AWS** — confirmar que todo task def tem `AWS_ECS_ENVIRONMENT` no formato slug correto. É Terraform também. Também vira PR separada.
- **Criar schedule de scale-down no EventBridge** — alternativa discutida, mas decidimos NÃO seguir esse caminho. Ver "Decisões tomadas".

## Decisões tomadas

### Decisão 1 — Manter a ordem `Mongo → ECS`, NÃO inverter

**Por quê:** O próprio `ShutDownWorker` está rodando dentro de uma task do `worker-service`. Se o ECS for escalado pra 0 primeiro, o container recebe SIGTERM e o Sidekiq começa shutdown graceful — o job atual (`ShutDownWorker`) pode ser interrompido antes de chamar `Ec2.stop_machine`. Então o Mongo nunca desliga.

A ordem correta **é**: parar o Mongo primeiro (via fog), e só depois pedir pro ECS se auto-desligar.

_(Correção de leitura que fiz errado no meio da sessão. O Paulo me corrigiu: "O sidekick tá rodando no ECS. Se você derrubou o ECS, você não consegue derrubar o Mongo. O primeiro a ser derrubado é o Mongo.")_

### Decisão 2 — Remover o `rescue Fog::AWS::ECS::Error` de `Ecs.scale_down`

**Por quê:** O rescue atual garante que qualquer erro vira warning silencioso e o job termina com sucesso. Isso é pior do que não ter rescue:
- Se o erro é temporário (rate limit, glitch), Sidekiq retry tentaria de novo automaticamente — com o rescue, não tenta.
- Se o erro é permanente (permissão, config), precisa ser visto — com o rescue, passa despercebido indefinidamente (4 dias nesse caso).

**Política desejada:** erro explode → Sidekiq retry → se recupera, ótimo; se não recupera, o engineer vê o job na retry queue pela manhã e corrige manualmente.

### Decisão 3 — Ordem dentro do scale_down: `web` primeiro, `worker` por último

**Por quê:** Escalar o `worker-service` pra 0 mata a própria task que está executando o `ShutDownWorker`. Tem que ser o último passo do job pra não cortar a própria execução no meio.

`web-service` pode ser escalado primeiro sem afetar o worker. Resolvido: web, depois worker.

_(Sem o rescue engolindo erro, essa ordem é segura: se o web falhar, worker nem é tocado, o erro explode, e ninguém fica num estado parcial silencioso.)_

### Decisão 4 — NÃO mover o shutdown pra EventBridge

**Alternativa considerada:** criar schedules `scale-down-web` e `scale-down-worker` no EventBridge, equivalentes aos `scale-up-*` que já existem. Assim a responsabilidade de desligar fica fora do worker.

**Por que não:** 
- Não dá pra saber de antemão _quando_ o processamento termina. Cliente pequeno termina em 20 min, cliente grande em 4h. Horário fixo no cron ou desliga antes de terminar, ou desperdiça muito tempo ligado.
- O Sidekiq sabe exatamente quando terminou (os `Consumer.computation.done?`). Essa sinalização já existe e funciona.
- Manter a lógica no `ShutDownWorker` é mais simples e não introduz novo ponto de falha.

## Mudanças previstas no código

### `app/models/ecs.rb`

Quebrar `scale_down` em `scale_down_web` e `scale_down_worker`, remover o rescue:

```ruby
class Ecs
  class << self
    attr_accessor :adapter
  end

  def self.scale_down_web
    adapter.update_service(
      'cluster' => ApplicationConfiguration.aws_ecs_cluster,
      'service' => ApplicationConfiguration.aws_ecs_web_service,
      'desiredCount' => 0
    )
  end

  def self.scale_down_worker
    adapter.update_service(
      'cluster' => ApplicationConfiguration.aws_ecs_cluster,
      'service' => ApplicationConfiguration.aws_ecs_worker_service,
      'desiredCount' => 0
    )
  end
end
```

Sem `rescue`. Sem método `scale_down` unificado (a lógica de ordenação vai pro worker).

### `app/workers/shut_down_worker.rb`

```ruby
class ShutDownWorker < ApplicationWorker
  def perform
    return unless Rails.env.production?

    Ec2.stop_machine        # 1. para Mongo
    Ecs.scale_down_web      # 2. escala web pra 0
    Ecs.scale_down_worker   # 3. escala worker pra 0 — mata o próprio container por último
  end
end
```

Ordem fixa, sem rescue, sem abstração intermediária.

## Fases de execução

### Fase 1 — Correção do código (esta PR)

1. Criar branch `fix/shutdown-worker-scale-down` a partir de `develop`
2. Aplicar mudanças em `app/models/ecs.rb` e `app/workers/shut_down_worker.rb`
3. Atualizar `CHANGELOG.md` (entry `### Fixed` — "Integration shutdown")
4. Abrir PR contra `develop`

**Importante:** Outra sessão está ativa no integrator agora. Essa fase só começa depois que ela terminar — **verificar antes** se há mudanças conflitantes em `app/models/ecs.rb`, `app/workers/shut_down_worker.rb` ou `lib/application_configuration.rb`.

### Fase 2 — IAM fix (PR separada, outro repo)

Depois que essa PR subir pra develop, a correção ainda **não funciona em produção** porque o user IAM não tem `ecs:UpdateService`. Abrir PR no repo `terraform` adicionando a permissão. Coordenar merge ordem: **primeiro terraform, depois deploy do integrator** — se for ao contrário, o `ShutDownWorker` vai explodir em produção na noite seguinte e deixar o Mongo de pé.

Ou: merger o fix do integrator mas **não fazer deploy** até o Terraform estar aplicado. O que for mais limpo de coordenar na hora.

### Fase 3 — Auditoria do `AWS_ECS_ENVIRONMENT` (Terraform)

Separadamente: confirmar que todo cliente tem `AWS_ECS_ENVIRONMENT` setado com o slug minúsculo correto em todas as task definitions. Olhar onde o `Maqnelson`/`Almaviva` capitalizados podem estar vindo:

- `config/deploy/maqnelson.rb:3` (Capistrano legado — pode ser fonte esquecida)
- Task definitions antigas ainda ativas
- Variáveis herdadas do `CLIENT_NAME` por engano em algum módulo Terraform

Essa é uma PR/investigação separada no repo `terraform`.

## Riscos

- **Risco 1 — Fase 1 sem Fase 2:** Se essa PR for pra produção antes do IAM estar corrigido, a primeira execução do `ShutDownWorker` vai explodir com `AccessDeniedException`, Sidekiq vai entrar em retry loop, e o Mongo fica de pé (porque `Ec2.stop_machine` já rodou antes). Estado é o **oposto** do bug atual — vai ser visível, mas é um falso problema. Mitigação: coordenar deploy com Fase 2, ou ignorar (o alerta vai chamar a atenção, que é o objetivo).
- **Risco 2 — Drift de `AWS_ECS_ENVIRONMENT`:** mesmo com IAM correto, se algum cliente ainda tem a var capitalizada, `UpdateService` vai falhar pro cluster errado. Fase 3 deveria limpar isso antes de confiar 100% na Fase 1. Mitigação: depois do deploy, monitorar por 2-3 noites os logs de `ShutDownWorker` dos clientes ativos.
- **Risco 3 — Outra sessão mexendo nos mesmos arquivos:** se a sessão ativa no integrator editar `ecs.rb` ou `shut_down_worker.rb` agora, vai dar conflito. Mitigação: conferir `git status`/`git log` do integrator antes de começar.

## Validação

Como saber que o fix funcionou (depois de Fase 1 + Fase 2 em produção):

1. Logs de `/ecs/integrator-maqnelson-worker` na noite seguinte ao deploy não devem ter `scale down skipped`
2. CloudTrail deve mostrar 2 eventos `UpdateService` via `fog-core` pra cada cliente por noite: um no `web-service`, outro no `worker-service`, ambos com `desiredCount: 0`
3. `aws ecs describe-services` logo após o horário esperado de término da integração deve mostrar `runningCount: 0` e `desiredCount: 0`
4. No dia seguinte, antes do schedule `scale-up-*` rodar, todos os serviços devem estar em 0/0 e os Mongos em `stopped`

## Notas operacionais

- Estado atual (fim desta sessão): maqnelson, almaviva, redebrasil — todos ECS 0/0 + Mongo stopped. Manualmente corrigido durante a investigação.
- Próxima noite sem o fix: scheduler vai subir ECS de novo às 00:55/01:25/01:55 UTC. Se nada for feito até lá, maqnelson e almaviva voltam pro estado de bug (sidekick rodando contra Mongo parado). Redebrasil também entra no mesmo estado porque o bug é o mesmo.
- Se não der pra abrir PR hoje, vale pelo menos desabilitar os schedules `scale-up-*` dos 3 clientes até o fix estar em produção, pra não acumular mais um dia de erro.
