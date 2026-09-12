# Lançamento Métricas de Comissão — e-mails de comunicação

Documento de conteúdo (entregável client-facing). Classificação de idioma: enquadramento em pt-BR (coordenação do time); os e-mails são conteúdo embutido, preservados no idioma de cada destinatário (LANGUAGE-POLICY.md, categoria cliente + embedded).

## Contexto

Lançamento da funcionalidade Métricas de Comissão (backend `CommissioningMetric` + telas de autoria/declaração), disponível por padrão apenas para usuários de nível administrador — sem feature flag, então o deploy libera para todos.

- Deploy productivo: feito — release 1.288.0 do `app-webclient` liberada em 11/09 (tag `v1.288.0`). Sem feature flag: já disponível por padrão para todos os usuários de nível administrador.
- E-mail Atento Colômbia (cliente que pediu): enviado 11/09.
- E-mails de massa (Brasil + demais países Atento, clientes que não pediram): enviar segunda, 14/09, de manhã, pelo time de operações.

## Itens a preencher antes de enviar

- Nome da funcionalidade: confirmado — "Métricas de Comissão" (PT) / "Métricas de Comisión" (ES).
- Prints 1 e 2 só existem em espanhol entre as imagens disponíveis. Para os e-mails ES (Atento CO e demais países) servem direto; para o e-mail 2 (Brasil, PT) faltam as versões PT das telas de cadastro — decidir entre gerar os prints PT ou enviar o e-mail do Brasil com os prints 1 e 2 em espanhol.

## Prints (máx. 3, parciais)

Arquivos em `~/Downloads/`. Prints parciais, não a página inteira.

1. O novo tipo de métrica de comissão — tela de cadastro da métrica, com a agregação (soma/média) e a variável de destino.
   - ES: `crear_metrica.png` (Tipo "Métrica de comisión", Cálculo "Suma", Variable "Pago Cuenta") — já é parcial, serve como está.
   - PT: pendente (só há versão ES).
2. O cadastro do plano — uma regra associada a uma métrica de comissão.
   - ES: `exemplo_incentivo_declaracao_regras.png` (a regra e a nota "calculados por la métrica Pago Cuenta y guardados en la variable Pago Cuenta").
   - PT: pendente (só há versão ES).
3. A declaração de resultado — o valor calculado pela métrica aparecendo para o usuário.
   - ES: `declaracion_resultado_metrica_ES.png` (recorte da tabela "Métrica" + "Compensaciones de indicadores", extraído da declaração ES `declaracao_resutlados2.png`).
   - PT: `declaracao_resultado_metrica_PT.png` (mesmo recorte, extraído da declaração PT `declaracao_resutlados.png`).

Descartado: print do cadastro com erro de validação — num e-mail de lançamento um estado de erro passa insegurança.

---

## E-mail 1 — Atento Colômbia (ES) — enviado 11/09

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
