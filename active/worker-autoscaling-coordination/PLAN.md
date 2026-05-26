# Worker Autoscaling — Coordenação ASG ↔ ECS

## Status

**Aberto** — diagnóstico concluído em 2026-05-08, decisão de implementação pendente. Retomar quando houver janela.

## Problema

Quando a Lambda de autoscaling do worker reduz o desired do ASG (scale-in), o ASG escolhe quais instâncias terminar usando sua própria policy, sem consultar o ECS sobre placement de tasks. Resultado: instâncias com tasks ativas podem ser terminadas, derrubando workers no meio do processamento.

A Lambda manda dois comandos independentes:
1. `set ECS service desired = N` (app-level, baseado em queue depth do Hirefire)
2. `set ASG desired = N` (infra-level, lockstep com o de cima)

ASG e ECS não se conversam: o ASG escolhe sozinho quais instâncias matar, e ECS placa tasks sozinho. Em scale-in, é loteria — pode coincidir de o ASG matar exatamente o host onde está a task ativa.

## Evidência

Incidente em 2026-05-08 às 18:51 UTC, em `shared-001-worker-commission-service`:

```
18:46:21 UTC — Lambda scale UP 1→3, Jobs: 1081
18:51:22 UTC — Lambda scale DOWN 3→1
18:51:28 UTC — ASG (shared-001-worker-commission-asg) terminou:
                 - i-0da6526579af3bd1b  (rodava a task 294971a48b2941bcbe46f9416e0e4dc4)
                 - i-0071a4e70e95cdbb7
              Sobreviveu: i-0b5778babe5d8e088
19:02:01 UTC — Alarme `shared-001-ecs-service-down-shared-001-worker-commission-service` disparou
19:16:19 UTC — ECS marcou task 294971 como STOPPED
              StoppedReason: "Host EC2 (instance i-0da6526579af3bd1b) terminated."
              StopCode:      TerminationNotice
```

Verificação cruzada: a task replacement `5894af20d95144fba5fee10b87ba6729` foi placada na instância sobrevivente e o Sidekiq registrou normal no dashboard. Ou seja, **não é Sidekiq travado** — é a coordenação ASG/ECS que faltou.

Mesmo padrão observado mais cedo no `shared-001-worker-system-service` às 18:13 UTC: scale 8→1, 3 tasks com `ExitCode=null` (force-kill quando o host foi terminado debaixo delas).

## Impacto

- Tasks ativas morrem ungraceful → jobs em processamento podem ser perdidos silenciosamente (Sidekiq OSS sem `reliable_fetch` não recoloca jobs do processing set após SIGKILL)
- Janela de `RunningTaskCount=0` durante substituição da task → alarmes disparam
- Recorrência: acontece em toda rajada que termina em scale-in (ou seja, todo dia)

## Opções consideradas

### 1. ECS ASG Capacity Provider com Managed Scaling — VIÁVEL

ECS assume o controle do `desired` do ASG via métrica `CapacityProviderReservation`. Habilitando `managedTerminationProtection: ENABLED`, o ECS marca `protectFromScaleIn=true` nas instâncias **que têm tasks ativas**, forçando o ASG a só matar instâncias vazias.

**Não exige migração para Fargate** — continua usando as mesmas EC2 atuais.

Mudanças necessárias:
- Wrappar o ASG (`shared-001-worker-*-asg`) em um capacity provider
- Habilitar `NewInstancesProtectedFromScaleIn` no ASG
- Associar capacity provider ao ECS service (em `defaultCapacityProviderStrategy`)
- **Remover da Lambda a parte que seta `ASG desired_capacity`** — ECS passa a fazer isso
- Lambda mantém só `ECS service desiredCount` (decisão app-level via Hirefire)

Doc canônica: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/asg-capacity-providers.html (seções "Auto Scaling group capacity providers" + "Managed termination protection").

Trade-offs:
- ✅ Resolve a coordenação na origem
- ✅ Padrão recomendado pela AWS
- ✅ Sem custo adicional
- ⚠️ Mexe em ASG, capacity provider, service e Lambda — não é trivial
- ⚠️ Proteção só vale para scale-in via ASG. Termination manual ou spot interruption ainda matam (não usa spot hoje, OK)

### 2. Lambda escolher qual instância terminar — DESCARTADA

Lambda usaria `terminate-instance-in-auto-scaling-group --should-decrement-desired-capacity` numa instância específica.

**Por que descartada**: a Lambda não tem como saber em runtime qual instância está drenada (sem task ativa).

### 3. Marcar `protectFromScaleIn=true` em instâncias drenadas — DESCARTADA

Mesma razão da #2: sem mecanismo para detectar drain de Sidekiq em runtime.

## Pendente para retomar

- [ ] Mapear estado atual dos 3 ASGs do `shared-001` (`worker-system-asg`, `worker-user-asg`, `worker-commission-asg`) — termination policy ativa, configuração de health check, lifecycle hooks
- [ ] Ler código da Lambda de autoscaling — identificar onde mexe no ASG, e por que a Lambda de `commission` tem uma camada `Aggregated capacity desired | Threshold for balancing lambda: 10.0` que não aparece na Lambda de `system`. Pode ser uma diferença de versão / lógica que precisa de tratamento separado
- [ ] Decidir rollout: os 3 workers do `shared-001` ao mesmo tempo, ou um a um (commission primeiro, dado que foi onde o incidente original aconteceu)
- [ ] Decidir efeito sobre os outros ambientes (`beta-001`, `demo-001`, `app-atento-001`) — todos têm o mesmo padrão de Lambda autoscaling, então a mudança propaga

## Fora do escopo deste plano

A pressão JVM no OpenSearch `app-shared-001` durante rajada (504s → retries Sidekiq) é um problema **separado**. Mitigações já discutidas (throttle da queue `deal_indexation`, ajustar `refresh_interval` do índice `deals`) não dependem desta decisão. Se quiser endereçar, planejar em arquivo próprio.
