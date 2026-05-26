# SPIKE — ShutDownWorker não desliga ECS após integração noturna

**Data:** 2026-04-10
**Contexto:** Clientes maqnelson e almaviva foram encontrados com web/worker ECS rodando contra Mongo parado. Integração havia rodado na noite anterior (relatórios chegaram), mas os serviços ECS ficaram de pé gerando logs de erro de conexão em loop.

## Pergunta

Por que o ECS continua rodando depois que o job de shutdown da integração termina, se o Mongo é corretamente desligado?

## Investigação

### 1. Estado observado no início da sessão

Executado `bash ~/.claude/scripts/integrator-instances.sh --state running` e `integrator-services.sh --client <name>`:

| Cliente | EC2 Mongo | ECS web | ECS worker | ECS runner |
|---|---|---|---|---|
| maqnelson | stopped | 1/1 | 2/2 | 0/0 |
| almaviva | stopped | 1/1 | 2/2 | 0/0 |
| redebrasil | stopped | 0/0 | 0/0 | 0/0 |

Rede Brasil estava consistente. Maqnelson e almaviva com inconsistência: Mongo off, ECS on.

### 2. Logs do ECS — sintoma

`/ecs/integrator-maqnelson-web` e `/ecs/integrator-maqnelson-worker` (últimas 24h) mostram loop contínuo:

```
MONGODB | Error checking 4client-maqnelson-mongo003:27017: SocketTimeoutError
MONGODB | Error checking 4client-maqnelson-mongo004:27017: EHOSTUNREACH (10.1.2.105:27017)
MONGODB | Error checking 4client-maqnelson-mongo005:27017: EHOSTUNREACH (10.1.2.88:27017)
```

Intercalado com `GET /health 200` (ALB health check mantendo a task viva). Sidekiq processando jobs sem conseguir ler Mongo.

### 3. Histórico do GitHub Actions

Consultado com `gh run list`:

- `shutdown.yaml` é `workflow_dispatch` (manual). Última execução pra maqnelson: **2026-04-09 23:32 UTC**, status success.
- Última execução pra almaviva: **2026-04-07 13:49 UTC** — ou seja, almaviva não era rodado manualmente há 3 dias.
- `startup.yaml` também manual. Última maqnelson: 2026-04-09 22:45 UTC.

Conclusão parcial: o fluxo noturno **não é** acionado via GitHub Actions. Tem que ser outra coisa.

### 4. EventBridge Scheduler

`aws scheduler list-schedules` mostra, pra cada cliente:

| Schedule | Cron (UTC) |
|---|---|
| `integrator-maqnelson-start-mongodb` | `cron(20 1 * * ? *)` — 01:20 |
| `integrator-maqnelson-scale-up-worker` | `cron(25 1 * * ? *)` — 01:25 |
| `integrator-maqnelson-scale-up-web` | `cron(25 1 * * ? *)` — 01:25 |
| `integrator-almaviva-start-mongodb` | `cron(50 0 * * ? *)` — 00:50 |
| `integrator-almaviva-scale-up-worker/web` | `cron(55 0 * * ? *)` — 00:55 |
| `integrator-redebrasil-start-mongodb` | `cron(50 1 * * ? *)` — 01:50 |
| `integrator-redebrasil-scale-up-worker/web` | `cron(55 1 * * ? *)` — 01:55 |

**Só existem schedules pra subir.** Nenhum pra descer. Descer é responsabilidade do `ShutDownWorker` que roda como último job do Sidekiq após os consumidores de relatório.

### 5. CloudTrail — quem chamou quem

`aws cloudtrail lookup-events` filtrado pelo `userAgent`:

Pro mongo005 da maqnelson (últimos 5 dias):

| Evento | userAgent | Origem |
|---|---|---|
| 2026-04-10 02:51:26 StopInstances | `fog-core/2.6.0` | **ShutDownWorker** (IAM user `integrator-maqnelson`) |
| 2026-04-10 01:20:11 StartInstances | `AmazonEventBridgeScheduler` | scheduler `start-mongodb` |
| 2026-04-09 23:33:30 StopInstances | `aws-cli os/linux#...azure` | shutdown.yaml workflow (GH Actions runner) |
| 2026-04-09 22:46:04 StartInstances | `aws-cli os/linux#...azure` | startup.yaml workflow |
| 2026-04-09 02:42:23 StopInstances | `fog-core/2.6.0` | **ShutDownWorker** (noite anterior) |

Pro worker-service da maqnelson (UpdateService, 5 dias):

```
2026-04-10 01:25:11  AssumedRole  scheduler-role    desiredCount: 2  ← scale-up-worker schedule
2026-04-09 01:25:11  AssumedRole  scheduler-role    desiredCount: 2  ← noite anterior
2026-04-08 01:25:11  AssumedRole  scheduler-role    desiredCount: 2  ← 2 noites atrás
```

**Nenhum `UpdateService` via fog-core pra scale-down.** O `Ecs.scale_down` nunca chegou na AWS.

### 6. Código do integrator

Sequência `ShutDownWorker#perform` → `Ec2.stop_machine` → `Ecs.scale_down`:

**`app/workers/shut_down_worker.rb`:**
```ruby
class ShutDownWorker < ApplicationWorker
  def perform
    return unless Rails.env.production?

    Ec2.stop_machine
    Ecs.scale_down
  end
end
```

Chamado de 13 lugares (todos os `*/consumer.rb` dos relatórios e o `Resource::Producer`/`Resource::Consumer`) via `ShutDownWorker.perform_async if job.computation.done?`.

**`app/models/ec2.rb`:**
```ruby
def self.stop_machine
  return if ApplicationConfiguration.aws_instance_ids.blank?
  adapter.stop_instances(ApplicationConfiguration.aws_instance_ids)
end
```

**`app/models/ecs.rb`:**
```ruby
def self.scale_down
  adapter.update_service(
    'cluster' => ApplicationConfiguration.aws_ecs_cluster,
    'service' => ApplicationConfiguration.aws_ecs_worker_service,
    'desiredCount' => 0
  )
  adapter.update_service(
    'cluster' => ApplicationConfiguration.aws_ecs_cluster,
    'service' => ApplicationConfiguration.aws_ecs_web_service,
    'desiredCount' => 0
  )
rescue Fog::AWS::ECS::Error => e
  Rails.logger.warn("ECS scale down skipped: #{e.message}")
end
```

`Ecs.adapter` e `Ec2.adapter` são inicializados em `config/initializers/fog.rb:16-27` via `Fog::Compute.new` e `Fog::AWS::ECS.new`.

**`lib/application_configuration.rb:169-185`:**
```ruby
def aws_ecs_cluster
  return if aws_ecs_environment.blank?
  "integrator-#{aws_ecs_environment}-cluster"
end

def aws_ecs_web_service
  return if aws_ecs_environment.blank?
  "integrator-#{aws_ecs_environment}-web-service"
end

def aws_ecs_worker_service
  return if aws_ecs_environment.blank?
  "integrator-#{aws_ecs_environment}-worker-service"
end
```

Lê de `ENV['AWS_ECS_ENVIRONMENT']`. No task def atual (`integrator-maqnelson-worker` rev 8) está setado como `maqnelson` (minúsculo) — verificado via `aws ecs describe-task-definition`.

### 7. Smoking gun — logs do Sidekiq

Buscado com `aws logs tail /ecs/integrator-maqnelson-worker --filter-pattern "scale down skipped"`:

**4 dias seguidos, mesmo erro, mesma task, mesmo horário (~02:42–02:51 UTC):**

```
2026-04-07 01:49:01  ECS scale down skipped: AccessDeniedException => User: arn:aws:iam::405749097490:user/integrator-maqnelson
  is not authorized to perform: ecs:UpdateService on resource:
  arn:aws:ecs:sa-east-1:405749097490:service/integrator-Maqnelson-cluster/integrator-Maqnelson-worker-service
  because no identity-based policy allows the ecs:UpdateService action

2026-04-08 03:30:21  ECS scale down skipped: AccessDeniedException => ...integrator-Maqnelson-cluster...
2026-04-09 02:42:23  ECS scale down skipped: AccessDeniedException => ...integrator-Maqnelson-cluster...
2026-04-10 02:51:26  ECS scale down skipped: AccessDeniedException => ...integrator-Maqnelson-cluster...
```

E logo em seguida:
```
2026-04-10 02:51:25.969  class=ShutDownWorker: start
2026-04-10 02:51:26.756  class=ShutDownWorker elapsed=0.788: done
```

Sidekiq reporta o job como **concluído com sucesso** em 788ms.

Para almaviva, mesmo padrão, 3 dias:
```
2026-04-08 01:02:52  ...integrator-Almaviva-cluster/integrator-Almaviva-worker-service...
2026-04-09 01:02:24  ...integrator-Almaviva-cluster...
2026-04-10 01:07:48  ...integrator-Almaviva-cluster...
```

## Causa raiz

Três bugs empilhados no fluxo de shutdown:

### Bug 1 — `Ecs.scale_down` engole o erro silenciosamente

```ruby
rescue Fog::AWS::ECS::Error => e
  Rails.logger.warn("ECS scale down skipped: #{e.message}")
end
```

`AccessDeniedException` do fog-aws é descendente de `Fog::AWS::ECS::Error`. O rescue captura, grava warning, e o método retorna normalmente. Sidekiq marca o job como `done`. **Nenhum sinal de alarme chega em ninguém.**

### Bug 2 — IAM user `integrator-{client}` sem `ecs:UpdateService`

O user usado pelo fog (credenciais que vão via env var pro container) tem permissão de `ec2:StopInstances`/`StartInstances` mas **não tem** `ecs:UpdateService`. Por isso a chamada AWS retorna 403.

### Bug 3 — Nome de cluster capitalizado: `integrator-Maqnelson-cluster`

Mesmo se o IAM tivesse a permissão, o recurso estaria errado. O erro mostra `integrator-Maqnelson-cluster` (M maiúsculo) e `integrator-Almaviva-cluster` (A maiúsculo). Recurso real: `integrator-maqnelson-cluster` (minúsculo).

Origem provável: `config/deploy/maqnelson.rb:3 → set :environment_name, 'Maqnelson'` (Capistrano legado). Ou uma revision antiga da task definition que tinha `AWS_ECS_ENVIRONMENT=Maqnelson`. A revision atual (8) está correta com `maqnelson`, mas os erros mostram que em algum momento foi capitalizado — pode ser drift ou herança de outra var.

**Importante:** derivar a forma correta a partir de `CLIENT_NAME` (usado pra título de relatórios) **não funciona**, porque nomes comerciais divergem dos slugs de recurso:
- `CLIENT_NAME=Atento México` → slug de recurso `atento-mx`, não `atento-mexico`.
- A derivação precisaria de uma tabela de mapeamento manual, o que é frágil e desnecessário.

A variável pra nomes de recurso (`AWS_ECS_ENVIRONMENT`) **já existe** e é separada de `CLIENT_NAME`. O que falta é garantir consistência em todo cliente no Terraform.

### Por que o ciclo estava se perpetuando

1. Noite 1 — Scheduler 00:55/01:25 UTC sobe Mongo e ECS
2. Integração roda, relatórios terminam, cada consumer chama `ShutDownWorker.perform_async`
3. ShutDownWorker: `Ec2.stop_machine` → Mongo para ✓
4. ShutDownWorker: `Ecs.scale_down` → AccessDenied → rescue → warn → done
5. ECS fica de pé até o engenheiro notar (nesse caso, eu/Paulo no dia seguinte)
6. Scheduler noite seguinte encontra ECS já em 2/1, `update-service desired-count=2` é no-op
7. Mongo sobe, integração roda em cima de ECS que **nunca desceu** — relatórios chegam, ninguém percebe
8. Ciclo se repete

Confirmado: 4 dias consecutivos pra maqnelson, 3 pra almaviva.

## Ações executadas durante a sessão

Apenas ações corretivas de estado (sem mudança de código):

- Scale down manual de `integrator-maqnelson-web-service` e `worker-service` pra 0
- Scale down manual de `integrator-almaviva-web-service` e `worker-service` pra 0
- Redebrasil já estava 0/0 — sem ação

Estado final de todos os três: Mongo stopped + ECS 0/0.

## Artefatos gerados

- `/tmp/cloudtrail_maqnelson_20260410_153452.json` — CloudTrail UpdateService maqnelson-worker-service
- `/tmp/cloudtrail_mongo_stops_20260410_*.json` — CloudTrail StartInstances/StopInstances mongo003 maqnelson
- `/tmp/logs_ecs_maqnelson_web_20260410_150234.log` — logs web maqnelson
- `/tmp/logs_ecs_maqnelson_worker_20260410_150438.log` — logs worker maqnelson
- `/tmp/logs_shutdownworker_maqnelson_*.log` — filtro ShutDownWorker
