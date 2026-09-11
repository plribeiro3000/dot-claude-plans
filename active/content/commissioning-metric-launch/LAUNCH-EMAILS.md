# Lançamento Métricas de Comissão — e-mails de comunicação

Documento de conteúdo (entregável client-facing). Classificação de idioma: enquadramento em pt-BR (coordenação do time); os e-mails são conteúdo embutido, preservados no idioma de cada destinatário (LANGUAGE-POLICY.md, categoria cliente + embedded).

## Contexto

Lançamento da funcionalidade Métricas de Comissão (backend `CommissioningMetric` + telas de autoria/declaração), disponível por padrão apenas para usuários de nível administrador — sem feature flag, então o deploy libera para todos.

- Deploy productivo: sexta-feira, 11/09 (final do dia). Começa sexta à noite.
- E-mail Atento Colômbia (cliente que pediu): enviar sexta, 11/09.
- E-mails de massa (Brasil + demais países Atento, clientes que não pediram): enviar segunda, 14/09, de manhã, pelo time de operações.

## Itens a preencher antes de enviar

- Confirmar/trocar o nome da funcionalidade: usado "Métricas de Comissão" / "Métricas de Comisión".
- Nome da reunião recorrente com a Atento Colômbia (placeholder no e-mail 1).
- Anexar os 3 prints (ver abaixo). Prints parciais, não a página inteira.

## Prints (máx. 3, parciais)

1. O novo tipo de métrica de comissão — tela de cadastro da métrica, mostrando a agregação (soma/média) e a variável de destino.
2. O cadastro do plano — uma regra/faixa associada a uma métrica de comissão.
3. A declaração de resultado — o valor calculado pela métrica aparecendo para o usuário.

Descartado: print do cadastro com erro de validação — num e-mail de lançamento um estado de erro passa insegurança.

---

## E-mail 1 — Atento Colômbia (ES) — enviar sexta, 11/09

```
Asunto: Entrega de la funcionalidad de Métricas de Comisión

Hola, equipo de Atento Colombia,

Tal como nos solicitaron y según lo acordado, 4Shark entrega hoy, 11 de septiembre, la funcionalidad de Métricas de Comisión, ya disponible para los usuarios de nivel administrador.

En resumen: ahora existen métricas de resultado de comisión que agregan los resultados de las reglas para utilizarlos en un paso posterior del plan.

[Imagen 1 — el nuevo tipo de métrica de comisión: la pantalla de registro de la métrica, con la agregación (suma/promedio) y la variable de destino]
[Imagen 2 — el registro del plan: una regla asociada a una métrica de comisión]
[Imagen 3 — la declaración de resultado: el valor calculado por la métrica]

Como creemos que se entiende mucho mejor en vivo que por capturas, nos gustaría presentársela y mostrarles cómo utilizarla en la próxima reunión de [nome da reunião recorrente] — o podemos adelantarla a otra fecha si lo prefieren.

Quedamos a disposición.

Saludos,
Equipo 4Shark
```

## E-mail 2 — Clientes do Brasil (PT) — enviar segunda, 14/09

```
Assunto: Nova funcionalidade: Métricas de Comissão

Olá, pessoal,

Acabamos de lançar a funcionalidade de Métricas de Comissão, disponível por padrão apenas para os usuários de nível administrador.

Com ela é possível criar métricas que agregam (somam) os resultados de comissão de uma ou mais regras em uma variável, para serem usados em um passo posterior do plano.

[Imagem 1 — o novo tipo de métrica de comissão: a tela de cadastro da métrica, com a agregação (soma/média) e a variável de destino]
[Imagem 2 — o cadastro do plano: uma regra associada a uma métrica de comissão]
[Imagem 3 — a declaração de resultado: o valor calculado pela métrica]

A funcionalidade já está acessível na plataforma. Se quiserem, podemos apresentar como utilizá-la em uma conversa rápida — é só nos avisar.

Abraço,
Equipe 4Shark
```

## E-mail 3 — Demais países da Atento (ES) — enviar segunda, 14/09

```
Asunto: Nueva funcionalidad: Métricas de Comisión

Hola a todos,

Acabamos de lanzar la funcionalidad de Métricas de Comisión, disponible por defecto solo para los usuarios de nivel administrador.

Con ella es posible crear métricas que agregan (suman) los resultados de comisión de una o más reglas en una variable, para utilizarlos en un paso posterior del plan.

[Imagen 1 — el nuevo tipo de métrica de comisión: la pantalla de registro de la métrica, con la agregación (suma/promedio) y la variable de destino]
[Imagen 2 — el registro del plan: una regla asociada a una métrica de comisión]
[Imagen 3 — la declaración de resultado: el valor calculado por la métrica]

La funcionalidad ya está accesible en la plataforma. Si lo desean, podemos presentarles cómo utilizarla en una breve reunión — solo avísennos.

Saludos,
Equipo 4Shark
```
