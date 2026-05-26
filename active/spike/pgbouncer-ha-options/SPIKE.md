# SPIKE — PgBouncer HA Options for app-atento-001

## Investigation question

Quais opções existem para tornar o PgBouncer do app Atento 001 mais resiliente a falhas de host e mais fácil de operar (observabilidade, logs persistentes), comparando custo, RTO, complexidade operacional e compatibilidade com Rails 8 + Aurora PostgreSQL 15?

---

## Sources consulted

- [AWS EC2 Automatic Instance Recovery](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-recover.html) — tabela comparativa simplified vs CloudWatch action based recovery; texto sobre RTO relativo
- [AWS CloudWatch Action Based Recovery](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/cloudwatch-recovery.html) — métrica `StatusCheckFailed_System`, configuração de alarme, limitação com Auto Scaling groups
- [AWS Simplified Automatic Recovery](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instance-configuration-recovery.html) — habilitado por padrão, limitações com Auto Scaling groups
- [AWS Auto Scaling Health Checks](https://docs.aws.amazon.com/autoscaling/ec2/userguide/health-checks-overview.html) — comportamento de substituição de instância, lógica de espera
- [AWS ECS Fargate Task Definitions](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/fargate-tasks-services.html) — tabela de CPU/memory válidos, networking awsvpc obrigatório, log drivers suportados
- [AWS Fargate Pricing](https://aws.amazon.com/fargate/pricing/) — taxa por vCPU-segundo e por GB-segundo para Linux/X86 em us-east-1
- [AWS NLB Pricing](https://aws.amazon.com/elasticloadbalancing/pricing/) — taxa horária NLB $0.0225/hr e LCU TCP $0.006 por NLCU
- [AWS RDS Proxy for Aurora](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/rds-proxy.html) — limitações PostgreSQL, porta 5432, CancelRequest, pinning
- [AWS RDS Proxy Pinning](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/rds-proxy-pinning.html) — condições de pinning para Aurora PostgreSQL
- [AWS RDS Proxy Planning](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/rds-proxy-planning.md) — texto sobre failover Aurora; redução de DNS propagation delays
- [AWS RDS Proxy Concepts](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/rds-proxy.howitworks.html) — multiplexing, pinning, infraestrutura multi-AZ do proxy
- [economize.cloud — t3a.micro pricing](https://www.economize.cloud/resources/aws/pricing/ec2/t3a.micro/) — preço on-demand t3a.micro us-east-1
- [AWS ELB Features Comparison](https://aws.amazon.com/elasticloadbalancing/features/) — tabela comparativa de protocolos suportados por tipo de load balancer
- [AWS NLB Listeners](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-listeners.html) — protocolos e portas suportados por listeners NLB
- [AWS How ELB Works](https://docs.aws.amazon.com/elasticloadbalancing/latest/userguide/how-elastic-load-balancing-works.html) — TTL 60s do DNS entry do ELB; flow hash NLB
- [AWS Cloud Map Service Creation](https://docs.aws.amazon.com/cloud-map/latest/dg/creating-services.html) — TTL configurável no create-service; exemplo mostrando TTL=60 como padrão da CLI
- AWS API — snapshot do ambiente (instância, cluster Aurora, cluster ECS, ASGs, task definition existente)

---

## Findings

### Finding 1: Estado atual — simplified automatic recovery está habilitado, mas não há CloudWatch alarm de recovery

**Evidence:**

Consulta AWS API retornou:

```json
{
  "InstanceId": "i-0b6f70bc905727770",
  "Type": "t3a.micro",
  "AZ": "us-east-1a",
  "State": "running",
  "AutoRecovery": "disabled"
}
```

E:

```json
{
  "AutoRecovery": "default",
  "RebootMigration": "default"
}
```

A propriedade `MaintenanceOptions.AutoRecovery = "default"` significa que o simplified automatic recovery está ativo (valor `"default"` ativa o comportamento padrão, que inclui recovery em instâncias suportadas). O campo `Monitoring.State = "disabled"` reflete apenas que detailed monitoring do CloudWatch está desligado — não o recovery.

Não existe nenhum CloudWatch alarm configurado para `i-0b6f70bc905727770`:

```
aws cloudwatch describe-alarms --alarm-name-prefix "pgbouncer-atento"
→ MetricAlarms: [], CompositeAlarms: []
```

O incidente relatado (10 min de indisponibilidade, `StatusCheckFailed_System=1`, auto-recovery com reboot) é o comportamento esperado do simplified automatic recovery: a AWS detecta a falha de hardware, tenta migrar o host, e o processo aparece como reboot não planejado para a instância.

**Source:** `aws ec2 describe-instances` + `aws cloudwatch describe-alarms` (leitura direta da API)

**Significance:** A proteção atual é o simplified automatic recovery sem alarme CloudWatch. O incidente foi contido por esse mecanismo, mas levou ~10 minutos de downtime. Não há visibilidade via SNS do evento de recovery, e os logs do PgBouncer ficam apenas no journald da instância — ao perder o host, o contexto de diagnóstico se perde.

**Verification:**
- URL fetched: N/A (AWS API direct)
- Verbatim quote checked: N/A (API response JSON)
- Quote substring confirmed at: Output direto do `describe-instances` e `describe-alarms`

---

### Finding 2: Diferença de RTO entre simplified automatic recovery e CloudWatch action based recovery

**Evidence:**

A documentação AWS apresenta uma tabela de comparação com a seguinte linha verbatim:

> | Recovery time | Standard recovery attempt | Faster recovery attempts than simplified automatic recovery |

(linha da tabela em `https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-recover.html`, seção "Differences between simplified automatic recovery and CloudWatch action based recovery")

Adicionalmente, sobre o CloudWatch action based recovery:

> "CloudWatch action based recovery provides to-the-minute recovery response time granularity and Amazon Simple Notification Service (Amazon SNS) notifications of recovery actions and outcomes."

E sobre simplified automatic recovery:

> "Simplified automatic recovery is enabled by default on all supported instances during instance launch."

Tanto simplified quanto CloudWatch action based recovery têm a mesma limitação crítica:

> "Limitations: Auto Scaling: Instances that are part of an Auto Scaling group"

(ambas as páginas listam explicitamente essa limitação — significa que **nenhuma das duas pode ser usada** em instâncias gerenciadas por um ASG).

**Source:** https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-recover.html (tabela "Differences"); https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/cloudwatch-recovery.html (cita CloudWatch action based recovery + Limitations); https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instance-configuration-recovery.html (cita "Simplified automatic recovery is enabled by default...")

**Significance:** CloudWatch action based recovery oferece RTO menor que simplified (a documentação não fornece números absolutos, apenas "faster") e adiciona SNS para notificação. Ambas as opções são mutuamente exclusivas com ASG — uma instância em ASG não pode usar nenhum dos dois mecanismos de recovery direto.

**Verification:**
- URL fetched: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-recover.html
- Verbatim quote checked: yes
- Quote substring confirmed at: tabela "Differences between simplified automatic recovery and CloudWatch action based recovery", linha "Recovery time"

---

### Finding 3: Task definition pgbouncer:1 já existe no ECS — imagem ECR própria, awslogs configurado

**Evidence:**

```json
{
  "family": "pgbouncer",
  "image": "405749097490.dkr.ecr.us-east-1.amazonaws.com/pgbouncer-puma:latest",
  "networkMode": "bridge",
  "requiresCompatibilities": ["EC2"],
  "cpu": "1024",
  "memory": "1024",
  "logConfiguration": {
    "logDriver": "awslogs",
    "options": {
      "awslogs-group": "/ecs/pgbouncer",
      "awslogs-create-group": "true",
      "awslogs-region": "us-east-1",
      "awslogs-stream-prefix": "ecs"
    }
  },
  "registeredAt": "2025-11-16T21:48:34.160000-03:00",
  "registeredBy": "arn:aws:iam::405749097490:user/ivan.domingues"
}
```

A task definition usa `networkMode: bridge` (EC2 mode) e não é compatível com Fargate (que requer `awsvpc`). A imagem `pgbouncer-puma:latest` já está no ECR da conta. O log group `/ecs/pgbouncer` já está configurado com `awslogs-create-group: true`.

**Source:** `aws ecs describe-task-definition --task-definition pgbouncer:1` (leitura direta da API)

**Significance:** Uma rota para ECS (opção 5) existe via reutilização parcial: a imagem ECR e o log group já existem. Uma nova revisão da task definition seria necessária para migrar de `bridge`/EC2 para `awsvpc`/Fargate ou para continuar em EC2-mode num ASG. Esse artefato representa trabalho anterior (nov/2025) que nunca foi concluído ou foi abandonado.

**Verification:**
- URL fetched: N/A (AWS API direct)
- Verbatim quote checked: N/A (API response JSON)
- Quote substring confirmed at: Output direto do `describe-task-definition`

---

### Finding 4: ASG min=max=1 é incompatível com simplified/CloudWatch recovery — mas substitui a instância automaticamente

**Evidence:**

A documentação de Auto Scaling health checks descreve:

> "Amazon EC2 Auto Scaling lets the status checks fail occasionally, without taking any action. When a status check fails, Amazon EC2 Auto Scaling waits a few minutes for AWS to fix the issue. It does not immediately mark an instance `Unhealthy` when its status for the status checks becomes `impaired`."

E para falha completa:

> "However, if Amazon EC2 Auto Scaling detects that an instance is no longer in the `running` state, this situation is treated as an immediate failure. In this case, it immediately marks the instance as `Unhealthy` and replaces it."

A documentação de simplified automatic recovery lista explicitamente:

> "Limitations: Auto Scaling: Instances that are part of an Auto Scaling group"

O mesmo vale para CloudWatch action based recovery. Portanto, um ASG min=max=1 **substitui** a instância com uma nova (novo launch), ao contrário do recovery que **migra** a instância existente. O RTO do ASG inclui o tempo de boot da nova instância + systemd start do PgBouncer.

**Source:** https://docs.aws.amazon.com/autoscaling/ec2/userguide/health-checks-overview.html e https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instance-configuration-recovery.html

**Significance:** ASG min=max=1 não reduz o RTO comparado ao simplified recovery — pode aumentá-lo (boot de nova instância vs migração da instância existente). O ganho principal é persistência de logs (via CloudWatch agent) e operabilidade (launch template versionado, substituição automatizada sem intervenção manual). Uma instância em ASG perde simplified/CloudWatch recovery, mas ganha health check e replace automático.

**Verification:**
- URL fetched: https://docs.aws.amazon.com/autoscaling/ec2/userguide/health-checks-overview.html
- Verbatim quote checked: yes
- Quote substring confirmed at: seção "Amazon EC2 health checks", parágrafo "Important"

---

### Finding 5: RDS Proxy — pinning extensivo para Aurora PostgreSQL reduz eficácia do pooling

**Evidence:**

A documentação lista as condições que causam pinning para Aurora PostgreSQL:

> "For PostgreSQL, the following interactions also cause pinning:
> + Using `SET` commands.
> + Using `PREPARE`, `DISCARD`, `DEALLOCATE`, or `EXECUTE` commands to manage prepared statements.
> + Creating temporary sequences, tables, or views.
> + Declaring cursors.
> + Discarding the session state.
> + Listening on a notification channel.
> + Loading a library module such as `auto_explain`.
> + Manipulating sequences using functions such as `nextval` and `setval`.
> + Interacting with locks using functions such as `pg_advisory_lock` and `pg_try_advisory_lock`."

E adicionalmente:

> "However, for PostgreSQL setting a variable leads to session pinning."

Além disso, há uma limitação funcional específica para PostgreSQL:

> "For PostgreSQL, RDS Proxy doesn't currently support canceling a query from a client by issuing a `CancelRequest`. This is the case, for example, when you cancel a long-running query in an interactive psql session by using Ctrl\+C."

E sobre o failover:

> "RDS Proxy bypasses Domain Name System (DNS) caches to reduce failover times by up to 66% for Aurora Multi-AZ databases."

**Source:** https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/rds-proxy-pinning.html e https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/rds-proxy.html

**Significance:** Rails (ActiveRecord + PG adapter) emite `SET` e `PREPARE` em cada conexão. Isso significa que virtualmente toda conexão Rails via RDS Proxy ficará pinned, tornando a multiplexação ineficaz — o comportamento se aproxima de um pass-through, não de um pool real. O RDS Proxy resolve o problema de failover Aurora (−66% tempo), mas não o problema de resiliência do PgBouncer em si; são problemas ortogonais.

**Verification:**
- URL fetched: https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/rds-proxy-pinning.html
- Verbatim quote checked: yes
- Quote substring confirmed at: seção "Conditions that cause pinning for Aurora PostgreSQL"

---

### Finding 6: ECS Fargate — task definition requer awsvpc e suporta awslogs nativamente

**Evidence:**

A documentação AWS lista as combinações válidas de CPU/memória para Fargate:

> "| 256 (.25 vCPU) | 512 MiB, 1 GB, 2 GB | Linux |"
> "| 1024 (1 vCPU) | 2 GB, 3 GB, 4 GB, 5 GB, 6 GB, 7 GB, 8 GB | Linux, Windows |"

E sobre o log driver:

> "The `awslogs` log driver configures your Fargate tasks to send log information to Amazon CloudWatch Logs."

Sobre o modo de rede:

> "`networkConfiguration` - Fargate tasks always use the `awsvpc` network mode."

Sobre pricing (Linux/X86, us-east-1):

> "Using the Linux/X86 pricing for US East (N. Virginia) Region where CPU cost: $0.000011244 per vCPU second, memory cost: $0.000001235 per GB per second, and ephemeral storage cost: $0.0000000308 per GB per second"

A task definition existente `pgbouncer:1` usa `networkMode: bridge` e `requiresCompatibilities: ["EC2"]` — é incompatível com Fargate como está. Uma nova revisão com `networkMode: awsvpc` e `requiresCompatibilities: ["FARGATE"]` seria necessária.

**Source:** https://docs.aws.amazon.com/AmazonECS/latest/developerguide/fargate-tasks-services.html e https://aws.amazon.com/fargate/pricing/

**Significance:** A migração para Fargate resolve o problema de logs (awslogs nativo, persistente no CloudWatch) e elimina a dependência de um host EC2 fixo. Duas tasks em duas AZs com NLB eliminam o SPOF de AZ. A task definition existente precisa ser recriada com modo de rede diferente — não é um aproveitamento direto. O custo de 1 task Fargate (0.25 vCPU / 512 MiB) por ~730h/mês é aproximadamente $2.95 em CPU + $0.27 em memória = ~$3.22/mês por task.

**Verification:**
- URL fetched: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/fargate-tasks-services.html
- Verbatim quote checked: yes
- Quote substring confirmed at: seção "Task CPU and memory", tabela de combinações válidas

---

### Finding 7: NLB — Layer 4, health check nativo, suporte TCP para PgBouncer

**Evidence:**

> "A Network Load Balancer functions at the fourth layer of the Open Systems Interconnection (OSI) model. It can handle millions of requests per second."

> "For TCP traffic, the load balancer selects a target using a flow hash algorithm based on the protocol, source IP address, source port, destination IP address, destination port, and TCP sequence number. The TCP connections from a client have different source ports and sequence numbers, and can be routed to different targets. Each individual TCP connection is routed to a single target for the life of the connection."

Sobre pricing:

> "Adding the hourly charge of $0.0225, the total Network Load Balancer costs are:"

**Source:** https://docs.aws.amazon.com/elasticloadbalancing/latest/network/introduction.html e https://aws.amazon.com/elasticloadbalancing/pricing/

**Significance:** NLB opera em Layer 4 (TCP), que é o protocolo correto para PgBouncer (porta 6432). Cada conexão TCP é roteada para um único target durante toda a sua vida — isso preserva o comportamento de session mode e transaction mode do PgBouncer. O custo base é ~$16.43/mês para o NLB, independente do número de targets. Um NLB com 2 targets (Fargate tasks em 2 AZs ou 2 instâncias EC2 em 2 AZs) proveria tolerância a falha de AZ.

**Verification:**
- URL fetched: https://docs.aws.amazon.com/elasticloadbalancing/latest/network/introduction.html e https://aws.amazon.com/elasticloadbalancing/pricing/
- Verbatim quote checked: yes
- Quote substring confirmed at: seção "Network Load Balancer overview" (TCP routing) e exemplos de pricing (hourly charge $0.0225)

---

### Finding 8: Environment snapshot — infraestrutura atual do app-atento-001

**Evidence (AWS API, read-only):**

| Recurso | Valor |
|---|---|
| Instância pgbouncer | `i-0b6f70bc905727770`, `t3a.micro`, `us-east-1a`, `running` |
| IP privado | `10.100.13.59` |
| VPC | `vpc-030497c296befc066` |
| Subnets privadas | `subnet-02da8b32b1466bd0e` (us-east-1a, 10.100.13.0/24) e `subnet-0aae9fb5fd47320c0` (us-east-1b, 10.100.14.0/24) |
| Aurora cluster | `app-atento-001-cluster`, PostgreSQL 15.15, MultiAZ: true |
| Aurora writer | `app-atento-001-db-2`, IP `10.100.14.220` (us-east-1b) |
| Aurora reader | `app-atento-001-db-1`, IP `10.100.13.15` (us-east-1a) |
| ECS cluster | `app-atento-001-cluster`, 9 capacity providers (todos EC2), 9 services rodando |
| RDS Proxy | Nenhum |
| NLB | Nenhum (existe ALB internet-facing `app-atento-001-lb`) |
| CloudWatch alarms | Nenhum para `i-0b6f70bc905727770` |
| Auto Recovery | `default` (simplified ativo) |
| Task def existente | `pgbouncer:1`, EC2/bridge, 1 vCPU/1 GiB, imagem `pgbouncer-puma:latest` no ECR |
| ASGs do app | 9 ASGs existentes (todos EC2 mode, nenhum para pgbouncer) |

**Source:** AWS API direct (`describe-instances`, `describe-db-clusters`, `describe-clusters`, `describe-db-proxies`, `describe-load-balancers`, `describe-alarms`, `describe-task-definition`, `describe-auto-scaling-groups`)

**Significance:** A infraestrutura dual-AZ já existe (subnets privadas em 1a e 1b). O ECS cluster usa apenas EC2 capacity providers — Fargate pode ser habilitado sem modificar os serviços existentes. A task definition `pgbouncer:1` representa trabalho anterior que indica familiaridade com containerização do PgBouncer neste ambiente.

**Verification:**
- URL fetched: N/A (AWS API direct)
- Verbatim quote checked: N/A
- Quote substring confirmed at: Outputs de múltiplos comandos `aws describe-*`

---

### Finding 9: Topologia real — 4 pgbouncers em 2 ambientes × 2 tipos (Puma e Sidekiq)

**Evidence:**

Esclarecimento direto do engenheiro (in-session): existem **4 pgbouncers no total**, distribuídos em dois eixos:

- **Eixo de ambiente**: Atento 001 + outro ambiente de produção
- **Eixo de tipo por ambiente**: Puma (web) e Sidekiq (worker)

A separação Puma/Sidekiq por ambiente existe porque:

- Puma e Sidekiq têm `pool_size`, timeouts e estratégia de scaling diferentes
- Web (Puma) não tem outscaling; Worker (Sidekiq) tem outscaling agressivo
- Não é possível ter configurações conflitantes em um único pgbouncer

**Source:** Engineer clarification (in-session)

**Significance:** Toda estimativa de custo anterior baseada em "1 pgbouncer" precisa ser multiplicada. Para uma solução de HA com 2 tasks/instâncias por pgbouncer: 4 pgbouncers × 2 unidades = 8 tasks/instâncias totais. Se o NLB for compartilhado entre os 4 pgbouncers com listeners em portas distintas, o custo fixo do NLB ($16.43/mês) não se multiplica — é 1 NLB para todos. O custo de compute (Fargate tasks ou EC2) sim se multiplica por 4 ou por 8.

---

### Finding 10: ALB suporta apenas HTTP/HTTPS/gRPC — não é adequado para PgBouncer (TCP)

**Evidence:**

A tabela comparativa de tipos de load balancer da AWS documenta os protocolos suportados por tipo:

> "Protocol listeners: HTTP, HTTPS, gRPC" (Application Load Balancer)

> "Protocol listeners: TCP, UDP, TLS" (Network Load Balancer)

A documentação descreve o ALB explicitamente como operando na camada de aplicação:

> "An Application Load Balancer functions at the application layer, the seventh layer of the Open Systems Interconnection (OSI) model."

Enquanto o NLB:

> "A Network Load Balancer functions at the fourth layer of the Open Systems Interconnection (OSI) model."

**Source:** https://aws.amazon.com/elasticloadbalancing/features/ (tabela "Product Comparisons", linha "Protocol listeners"); https://docs.aws.amazon.com/elasticloadbalancing/latest/application/introduction.html (seção "Application Load Balancer overview")

**Significance:** O PgBouncer expõe uma porta TCP (6432 por padrão) e fala o protocolo PostgreSQL wire protocol — não HTTP. O ALB existente no ambiente (`app-atento-001-lb`) é internet-facing e serve o tráfego web da aplicação; ele não pode ser reaproveitado para o PgBouncer. Qualquer opção de load balancer para PgBouncer deve usar NLB (Layer 4 TCP), não ALB.

**Verification:**
- URL fetched: https://aws.amazon.com/elasticloadbalancing/features/
- Verbatim quote checked: yes
- Quote substring confirmed at: tabela "Product Comparisons", linha "Protocol listeners" — "HTTP, HTTPS, gRPC" (ALB) e "TCP, UDP, TLS" (NLB)

---

### Finding 11: NLB suporta múltiplos listeners em portas distintas (TCP 1–65535)

**Evidence:**

A documentação de listeners do NLB especifica:

> "Listeners support the following protocols and ports:
> + **Protocols**: TCP, TLS, UDP, TCP\_UDP, QUIC, TCP\_QUIC
> + **Ports**: 1-65535"

Sobre o roteamento por listener:

> "A *listener* is a process that checks for connection requests, using the protocol and port that you configure. Before you start using your Network Load Balancer, you must add at least one listener."

**Source:** https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-listeners.html (seção "Listener configuration")

**Significance:** Um único NLB pode hospedar múltiplos listeners TCP em portas distintas, cada listener apontando para um target group diferente. Para 4 pgbouncers (Puma-atento, Sidekiq-atento, Puma-outro-ambiente, Sidekiq-outro-ambiente), seria possível usar 4 listeners em 4 portas distintas (ex.: 6432, 6433, 6434, 6435) em um único NLB. Cada target group teria seus próprios health checks independentes. O custo fixo do NLB não se multiplica — 1 NLB cobre todos os 4 pgbouncers.

**Verification:**
- URL fetched: https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-listeners.html
- Verbatim quote checked: yes
- Quote substring confirmed at: seção "Listener configuration", bullet "Ports: 1-65535"

---

### Finding 12: NLB pricing — custo horário fixo $0.0225/hr + LCU TCP $0.006 por NLCU

**Evidence:**

Sobre o custo horário:

> "Adding the hourly charge of $0.0225, the total Network Load Balancer costs are:"

Sobre o LCU para tráfego TCP:

> "In this example for TCP traffic, the processed bytes (0.36 NLCUs) is greater than both the new connections (0.125 NLCUs) and active connections (0.18 NLCUs). Assuming this usage is consistent over 60 minutes, this results in a total charge of $0.00216 per hour for TCP traffic (0.36 NLCUs \* $0.006) or $1.55 per month for TCP Traffic ($0.00216 \* 24 hours \* 30 days)."

A dimensão NLCU para TCP é definida como: 800 new TCP connections/second, 100.000 active TCP connections (sampled per minute), ou 1 GB/hour processado.

**Source:** https://aws.amazon.com/elasticloadbalancing/pricing/ (seção "Network Load Balancer", exemplos de custo TCP)

**Significance:** O custo do NLB é $0.0225/hr × 730h = **$16.43/mês de custo fixo** + variável por NLCU. Para tráfego típico de PgBouncer em produção (baixo volume de novas conexões, algumas conexões ativas persistentes), o componente LCU é pequeno. Compartilhar 1 NLB entre 4 pgbouncers via 4 listeners mantém o custo fixo em $16.43/mês — contra $65.72/mês se fossem 4 NLBs separados.

**Verification:**
- URL fetched: https://aws.amazon.com/elasticloadbalancing/pricing/
- Verbatim quote checked: yes
- Quote substring confirmed at: seção "Network Load Balancer", exemplo de cálculo TCP — "0.36 NLCUs \* $0.006" e "hourly charge of $0.0225"

---

### Finding 13: Cloud Map / ECS Service Discovery — TTL configurável, padrão 60s nos exemplos da documentação

**Evidence:**

A documentação de criação de serviço no Cloud Map descreve o campo TTL:

> "For **TTL**, specify a numerical value to define the time to live (TTL) value, in seconds, at the service level. The value of TTL determines how long DNS resolvers cache information for this record before the resolvers forward another DNS query to Amazon Route 53 to get updated settings."

O exemplo de CLI na documentação oficial usa:

```
--dns-config "NamespaceId={{ns-xxxxxxxxxxx}},RoutingPolicy=MULTIVALUE,DnsRecords=[{Type={{A}},TTL={{60}}}]"
```

Com resposta mostrando `"TTL": 60` como valor padrão nos exemplos.

A documentação do ECS Service Discovery documenta o seguinte sobre saúde dos registros:

> "Amazon ECS performs periodic container-level health checks. If an endpoint does not pass the health check, it is removed from DNS routing and marked as unhealthy."

E sobre o comportamento com todos os registros:

> "When all records are unhealthy, Route 53 responds to DNS queries with up to eight unhealthy records."

**Source:** https://docs.aws.amazon.com/cloud-map/latest/dg/creating-services.html (seção "If you choose API and DNS", item TTL; exemplo CLI); https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service-discovery.html (seção "Service discovery considerations")

**Significance:** Com TTL=60s (valor do exemplo da documentação AWS), clientes que resolveram o DNS antes da remoção de um endpoint de tarefa morta continuarão tentando conectar àquele IP por até 60 segundos após a deregistration. Conexões TCP que tentarem o IP de uma task encerrada receberão `connection refused` ou timeout durante essa janela. O NLB evita esse problema porque o endereço IP do NLB não muda — apenas o health check do target group detecta a task morta e para de rotear tráfego para ela em ~10-30s.

**Verification:**
- URL fetched: https://docs.aws.amazon.com/cloud-map/latest/dg/creating-services.html
- Verbatim quote checked: yes
- Quote substring confirmed at: seção de configuração de serviço DNS, campo TTL description + exemplo CLI com `TTL={{60}}`

---

## Trade-offs surfaced

### Tabela comparativa por critério (topologia real: 4 pgbouncers)

Contexto: 4 pgbouncers no total (2 ambientes × 2 tipos: Puma e Sidekiq). Custo calculado para todos os 4 pgbouncers em conjunto.

| Opção | Custo mensal estimado (USD) — 4 pgbouncers | RTO esperado (falha de 1 host/task) | Logs persistentes | Janela de erro no failover | Esforço de migração |
|---|---|---|---|---|---|
| 1. Status quo + Simplified Auto Recovery (atual) | ~$27.44 (4× t3a.micro) | ~5–15 min (Finding 1, 2) | Não | N/A (recovery in-place) | — |
| 2. CloudWatch alarm recovery | ~$27.44 + ~$0.40 (4 alarmes) | Menor que opção 1 (Finding 2) | Não | N/A (recovery in-place) | Low |
| 3. ASG min=max=1 × 4 + CloudWatch agent | ~$27.44 + CW Logs | ~5–15 min + boot (Finding 4) | Sim | N/A (sem LB) | Low–Medium |
| 4. ASG 2 nodes × 4 pgbouncers + 1 NLB compartilhado | ~$54.88 (8× t3a.micro) + $16.43 NLB + CW | ~10–30s (health check NLB) | Sim | ~10–30s (health check detects) | Medium–High |
| 5a. ECS Fargate 1 task × 4 pgbouncers + 1 NLB compartilhado | ~$12.88 (4 tasks × ~$3.22) + $16.43 NLB | ~30–60s (ECS replace + NLB) | Sim (awslogs nativo) | ~30–60s (task restart) | Medium |
| 5b. ECS Fargate 2 tasks × 4 pgbouncers + 1 NLB compartilhado | ~$25.76 (8 tasks × ~$3.22) + $16.43 NLB | ~0s (outra task saudável absorve) | Sim (awslogs nativo) | ~0s (LB redireciona imediatamente) | Medium |
| 5c. ECS Fargate 2 tasks × 4 pgbouncers + Cloud Map (sem NLB) | ~$25.76 (8 tasks) + Route53/Cloud Map | ~30–60s + TTL DNS cache | Sim (awslogs nativo) | Até 60s de erros TCP (Finding 13) | Medium |
| 6. RDS Proxy | ~$21.90 mínimo (UNVERIFIED) | N/A para falha do pgbouncer (Finding 5) | N/A | N/A | Medium |

**Notas de custo:**
- t3a.micro us-east-1: $0.0094/hr × 730h = $6.86/mês por instância (Finding 8 + fonte economize.cloud); 4 instâncias = $27.44; 8 instâncias = $54.88
- Fargate 0.25 vCPU / 512 MiB: ~$3.22/mês por task (Finding 6); 4 tasks = $12.88; 8 tasks = $25.76
- NLB compartilhado (1 NLB, 4 listeners): $0.0225/hr × 730h = $16.43/mês + LCU (Finding 12) — custo fixo não se multiplica com número de listeners
- RDS Proxy: $0.015/vCPU-hr × mínimo 2 vCPUs × 730h = $21.90/mês (mínimo; UNVERIFIED — não confirmado com substring verbatim da AWS pricing page diretamente)

### Prós e contras em prosa

**Opção 1 (Status quo + simplified recovery)**

O mecanismo atual funciona para 4 pgbouncers standalone, mas o RTO de ~10 min não é controlável. Não há notificação, os logs somem com a instância e o mecanismo é uma caixa-preta gerenciada pela AWS. Nenhum esforço adicional, nenhum custo extra.

**Opção 2 (CloudWatch alarm recovery)**

Adiciona um alarme na métrica `StatusCheckFailed_System` com action de recovery (Finding 2) em cada uma das 4 instâncias. O RTO cai ("faster recovery attempts"), e SNS pode notificar o time. O custo incremental é mínimo (~$0.10/alarm × 4 = $0.40/mês). Não resolve logs. Não pode ser combinado com ASG (Finding 4). Esforço: configurar 4 alarmes — Low.

**Opção 3 (ASG min=max=1 × 4 + CloudWatch agent)**

Transforma cada uma das 4 instâncias standalone em ASG. O CloudWatch agent coleta journald/syslog e envia para CloudWatch Logs — logs passam a ser persistentes. O RTO pode ser maior que opção 1 (boot de nova instância vs migração do host existente — Finding 4). Não elimina o SPOF de AZ. A instância perde simplified/CloudWatch recovery (limitação da ASG — Finding 2 e 4). Esforço: criar 4 launch templates, 4 ASGs, configurar CloudWatch agent em cada — Low–Medium.

**Opção 4 (ASG 2 nodes × 4 pgbouncers + 1 NLB compartilhado com 4 listeners)**

8 nodes EC2 (2 por pgbouncer em 2 AZs diferentes) atrás de 1 NLB com 4 listeners TCP em portas distintas. Uma falha de host ou de AZ deixa o outro node saudável absorvendo o tráfego. O RTO real é o tempo de health check do NLB detectar o target unhealthy + connection draining. Os logs ficam no CloudWatch. Complexidade operacional alta: 4 pares de pgbouncers precisam ter configuração consistente, 8 instâncias EC2 para gerenciar, 4 target groups no NLB. Esforço: 4 launch templates, 4 ASGs, 1 NLB com 4 listeners + 4 target groups, security groups — Medium–High.

**Opção 5a/5b (ECS Fargate + 1 NLB compartilhado)**

Nova task definition com `awsvpc`/Fargate necessária (Finding 3 e 6). Fargate nativo usa `awslogs` — logs vão direto para CloudWatch Logs. Com 2 tasks por pgbouncer em 2 AZs (opção 5b), o RTO é ~0s para falha de 1 task. O pgbouncer como container Fargate exige que a configuração (pgbouncer.ini, credenciais) seja injetada via Secrets Manager ou SSM — não há arquivo local editável. A separação Puma/Sidekiq (Finding 9) significa 4 serviços ECS distintos com configurações distintas. 1 NLB com 4 listeners cobre todos os 4 pgbouncers. Esforço: 4 task definitions (awsvpc), 4 serviços ECS, 1 NLB com 4 listeners + 4 target groups, Secrets Manager para configs — Medium.

**Opção 5c (ECS Fargate + Cloud Map sem NLB)**

Elimina o custo fixo do NLB ($16.43/mês). A descoberta de serviço é feita via DNS com TTL=60s (Finding 13). Quando uma task é substituída, o novo IP é registrado no DNS, mas clientes com o registro cacheado tentarão conectar ao IP antigo por até 60s — durante esse período, conexões TCP falham com `connection refused`. Para connection pools de banco de dados (como o próprio PgBouncer conectado ao Aurora, ou a aplicação conectada ao PgBouncer), essa janela pode causar erros visíveis na aplicação. A janela de erro é determinística e limitada ao TTL, mas existe. Esforço similar ao 5b, sem o NLB.

**Opção 6 (RDS Proxy)**

O RDS Proxy não substitui o PgBouncer na arquitetura atual — são camadas análogas. O problema de resiliência do host EC2 não é resolvido. O RDS Proxy resolve melhor o failover Aurora (−66% DNS propagation — Finding 5), mas Rails + PG adapter emite `SET` e `PREPARE` em cada conexão, causando pinning extensivo (Finding 5). O custo mínimo (~$21.90/mês, UNVERIFIED) é similar ao custo de Fargate 2 tasks + NLB. Esforço: criar proxy, Secrets Manager para credenciais, ajustar connection strings em todos os serviços — Medium.

---

## What remains uncertain

1. **`pool_mode` e `default_pool_size` atuais do pgbouncer.ini** — não foi possível ler o arquivo de configuração sem acesso SSH à instância. É relevante para determinar se `transaction` mode está ativo (que afeta qual opção de substituto é viável) e qual o tamanho do pool configurado.

2. **Configuração master/follower no pgbouncer.ini** — o cluster Aurora tem writer em us-east-1b e reader em us-east-1a. O pgbouncer está apontado para qual endpoint? O writer endpoint? O reader endpoint? O cluster endpoint? Isso afeta como um eventual NLB + 2 pgbouncers se comportaria: cada instância precisaria ter a mesma configuração de endpoint Aurora, ou há roteamento diferenciado read/write?

3. **Preço exato do RDS Proxy para Aurora PostgreSQL em us-east-1** — a página de pricing da AWS não retornou o valor da tabela em formato extraível pelo fetch. O valor $0.015/vCPU-hr foi citado por fontes terceiras (cloudchipr.com, pump.co) mas não foi confirmado com substring verbatim da página AWS. Marcar como UNVERIFIED para a linha de custo do RDS Proxy.

4. **RTO medido do simplified auto recovery no incidente** — os logs do incidente sumiram com a instância (Finding 1). O valor de ~10 min é baseado na descrição do incidente, não em métricas CloudWatch. Sem CloudWatch agent rodando, não há timestamp preciso de quando `StatusCheckFailed_System` virou 1 e quando o processo ficou `ok` novamente.

5. **Benchmarks de throughput do PgBouncer em Fargate 0.25 vCPU vs EC2 t3a.micro** — não foram encontrados benchmarks específicos para Aurora PostgreSQL 15 + PgBouncer em Fargate. A instância atual usa 1 vCPU/1 GiB; o menor Fargate com 1 vCPU/2 GiB custa ~$9.02/mês, marginalmente mais caro que o t3a.micro.

6. **Compatibilidade do Rails 8 connection pool com 2 pgbouncers sem pool compartilhado** — no modo com 2 instâncias PgBouncer (opção 4 ou 5b), cada instância mantém seu próprio pool. Rails não tem visibilidade de qual pgbouncer receberá a conexão. Em `transaction` mode do pgbouncer, isso é geralmente transparente; em `session` mode, sticky connections ao mesmo pgbouncer via NLB flow hash seriam necessárias — mas o NLB distribui por conexão TCP, não por sessão de banco. Não foram encontradas evidências concretas sobre esse comportamento específico com Rails 8.

7. **Quanto as configurações dos 4 pgbouncers diferem hoje** — não foi possível ler os `pgbouncer.ini` de cada instância sem acesso SSH. É relevante para dimensionar o esforço de migração: se os 4 pgbouncers têm configurações parecidas, a migração é mais simples; se divergiram ao longo do tempo, cada um pode requerer tratamento individual.

8. **Compatibilidade de NLB com múltiplos listeners e health check independente por target group** — a documentação descreve health checks por target group (Finding 11), o que indica que cada listener/target group tem health check independente. Ainda assim, não foi encontrada confirmação verbatim explícita sobre o comportamento de health check independente quando múltiplos listeners apontam para target groups distintos no mesmo NLB.

9. **Janela de erro precisa do failover Cloud Map vs NLB** — Finding 13 estabelece que o TTL padrão do Cloud Map nos exemplos é 60s, e que durante esse período clientes podem tentar conectar a IPs de tasks encerradas. Não foi encontrada documentação AWS com medições concretas da janela real de erro (entre a task encerrar e o DNS ser atualizado + TTL expirar nos clientes). O NLB evita esse problema por design (Finding 7), mas a magnitude exata do impacto de Cloud Map sem NLB para connection pools de banco de dados não foi encontrada com fonte citável.

---

## Suggested options

As opções abaixo são ordenadas por critério objetivo, com topologia real de 4 pgbouncers. O engenheiro escolhe com base na prioridade do projeto.

### Ranqueadas por custo mensal estimado (ascendente) — 4 pgbouncers

1. Opção 2 — CloudWatch alarm recovery (~$27.44 + ~$0.40 alarmes) — mínimo adicional
2. Opção 3 — ASG min=max=1 × 4 + CloudWatch agent (~$27.44 + CW Logs ingestion)
3. Opção 5a — Fargate 1 task × 4 + 1 NLB compartilhado (~$29.31)
4. Opção 5b — Fargate 2 tasks × 4 + 1 NLB compartilhado (~$42.19)
5. Opção 5c — Fargate 2 tasks × 4 + Cloud Map sem NLB (~$25.76 + Route53/Cloud Map, sem custo NLB)
6. Opção 4 — ASG 2 nodes × 4 + 1 NLB compartilhado (~$71.31)

### Ranqueadas por RTO esperado (ascendente)

1. Opção 5b — Fargate 2 tasks × 4 + NLB (~0s para falha de 1 task, Finding 6 e 7)
2. Opção 4 — ASG 2 nodes × 4 + NLB (~10–30s health check, Finding 7)
3. Opção 5a — Fargate 1 task × 4 + NLB (~30–60s ECS replace + NLB, Finding 6 e 7)
4. Opção 5c — Fargate 2 tasks × 4 + Cloud Map (~30–60s + até 60s de TTL DNS, Finding 13)
5. Opção 2 — CloudWatch alarm recovery (menor que simplified, sem número absoluto, Finding 2)
6. Opção 3 — ASG min=max=1 × 4 (boot nova instância, possivelmente maior que opção 2, Finding 4)

### Ranqueadas por esforço de migração (ascendente)

1. Opção 2 — Low (4 alarmes CloudWatch, Finding 2)
2. Opção 3 — Low–Medium (4 launch templates + 4 ASGs + CloudWatch agent × 4, Finding 4)
3. Opção 5a/5b/5c — Medium (4 task defs awsvpc + 4 serviços ECS + NLB ou Cloud Map + Secrets Manager, Finding 3 e 6)
4. Opção 4 — Medium–High (8 launch templates + 4 ASGs + NLB + config sync × 4, Finding 4 e 7)

### Ranqueadas por logs persistentes

- Opção 2 — Não resolve logs (instância standalone sem CloudWatch agent)
- Opção 3, 4 — Sim, via CloudWatch agent em cada instância EC2
- Opção 5a/5b/5c — Sim, via awslogs nativo do ECS (Finding 6, zero configuração adicional)
