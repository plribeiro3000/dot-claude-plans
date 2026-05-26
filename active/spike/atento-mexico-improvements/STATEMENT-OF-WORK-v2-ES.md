# Propuesta de Mejoras — Atento México

**Fecha:** 27 de febrero de 2026

---

## Resumen

Tras un análisis detallado de las 17 solicitudes de mejora y la reunión de alineación realizada el 26 de febrero de 2026, presentamos el plan de acción propuesto.

Las solicitudes se organizaron en cuatro frentes:

- **Ajustes y entregas sin costo** — correcciones inmediatas y funcionalidades disponibles mediante configuración
- **7 mejoras de la plataforma** — priorizadas en el roadmap a solicitud de Atento México
- **2 desarrollos personalizados** — exclusivos para Atento México
- **1 sesión de capacitación** — formación sobre funcionalidades existentes

Adicionalmente, 4 solicitudes fueron evaluadas y ya están cubiertas por funcionalidades existentes en la plataforma.

---

## 1. Ajustes y Entregas Sin Costo

### 1.1 — Correcciones Inmediatas

Ajustes puntuales ya incorporados al próximo sprint de desarrollo.

**Fecha de registro en Usos Mensuales** — La pantalla de detalle pasará a mostrar la fecha de registro de cada colaborador en la plataforma.

**Resumen del plan en el resultado Parcial** — La pantalla de resultado parcial pasará a mostrar los datos generales del plan asociado (nombre, tipo, calendario, grupo, estado).

**Permisos de reportes de compensaciones** — Los permisos para la generación automática de reportes serán habilitados para todos los administradores de Atento México.

**Corrección de la página de reportes en lote** — El problema de carga de la página de reportes en lote de compensaciones será corregido.

| Ítem | Horas |
|------|-------|
| Fecha de registro en Usos Mensuales | 3h |
| Resumen del plan en el resultado Parcial | 4h |
| Permisos de reportes de compensaciones | 1h |
| Corrección de la página de reportes en lote | 3h |
| **Total — Correcciones Inmediatas** | **10h** |

**Plazo:** Próximo sprint
**Costo adicional:** Ninguno

---

## 2. Mejoras de la Plataforma

Funcionalidades de la plataforma que serán desarrolladas a solicitud de Atento México.

El orden de entrega considera el valor entregado al cliente y las dependencias técnicas entre los ítems.

### 2.1 — Control de Accesos e Historial de Inicio de Sesión — 70h

**Problema:** Atento México necesita auditar los accesos de los colaboradores a la plataforma — quién accedió, cuándo, cuántas veces, y si hubo intentos de acceso sin éxito. Los colaboradores ocasionalmente alegan no haber visto una declaración; la empresa necesita evidencias para confrontar esas situaciones.

**Solución:** Registro automático de todos los accesos a la plataforma, independientemente del método de autenticación utilizado (inicio de sesión directo o single sign-on). Cada acceso registra: colaborador, fecha y hora, dirección IP, método de autenticación, proveedor de identidad (cuando aplique), y si el acceso fue exitoso o no.

Los datos quedan disponibles para consulta directamente en la plataforma por 90 días, con filtros por período, colaborador, método de autenticación y resultado. Después de 90 días, los registros son archivados automáticamente en almacenamiento de largo plazo, quedando disponibles bajo solicitud.

### 2.2 — Actualización de colaboradores vía carga masiva — 25h

**Problema:** La importación de colaboradores actualmente solo permite la creación de nuevos registros. Cuando un colaborador ya existe, la carga rechaza la fila. Para corregir datos de ~20 colaboradores por quincena (errores de captura, cambios de estado), es necesario editarlos uno por uno.

**Solución:** La carga de colaboradores pasará a identificar registros existentes y actualizará sus datos automáticamente, manteniendo el comportamiento de creación para colaboradores nuevos.

### 2.3 — Exportación del Historial del Colaborador — 35h

**Problema:** El Historial del Colaborador muestra datos paginados, haciendo impráctico consultar cientos de registros para auditorías, transferencias o promociones.

**Solución:** Nueva exportación a Excel con toda la información consolidada: pagos, indicadores, transacciones, grupos, jerarquía, metas y estados de cuenta.

### 2.4 — Información adicional en los listados de Parciales y Compensaciones — 50h

**Problema:** Los listados de parciales y compensaciones muestran solo información básica (ID, Plan, Período, Estado). Para validar los valores de cada plan, es necesario abrir cada ítem individualmente — con 130 planes, esto consume tiempo significativo.

**Solución:** Adición de tres informaciones en ambos listados: nombre del grupo, cantidad de colaboradores y valor total generado. Los valores respetan la jerarquía de acceso (el administrador ve el total, el gestor ve solo su equipo).

### 2.5 — Importación masiva de Grupos — 40h

**Problema:** La creación de grupos se realiza uno a uno desde la interfaz. Con ~130 nuevos grupos por mes, el proceso manual es inviable.

**Solución:** Nueva importación de grupos mediante archivo, que permite la creación y actualización masiva. Los grupos existentes serán identificados y actualizados; los nuevos grupos serán creados automáticamente.

### 2.6 — Importación masiva de Planes — 160h

**Problema:** La creación de 130 planes por mes se realiza de forma manual, seleccionando calendario, grupo, incentivos y tipos de pago uno a uno para cada plan.

**Solución:** Nueva importación de planes mediante archivo. El archivo permite definir todos los parámetros del plan (calendario, grupo, incentivos, tipos de pago, aprobadores). Validación completa antes de la creación — si cualquier fila tiene error, el archivo completo es rechazado con un mensaje detallado indicando el error y la fila.

Esta funcionalidad requiere una etapa de preparación de la plataforma: los incentivos existentes deben recibir un identificador externo para ser referenciados en el archivo de importación. Esta preparación incluye migración de los registros existentes y pruebas extensivas para garantizar que ningún cálculo en curso sea afectado.

**Dependencia:** La importación de grupos (ítem 2.5) debe ser entregada primero, ya que los planes hacen referencia a grupos que deben existir en la plataforma.

### 2.7 — Reglas de Validación para Indicadores — 120h

**Problema:** Datos incorrectos en indicadores (ej: calidad superior al 100%, valores negativos) solo son detectados tardíamente — cuando la compensación ya fue calculada o, peor aún, cuando la carta de compensación ya fue enviada al colaborador. Corregir en ese punto es costoso y riesgoso.

**Solución:** Reglas de validación configurables por variable de incentivo. Los datos son validados en el momento de entrada al sistema, impidiendo que valores inválidos se propaguen hacia cálculos y pagos. La validación ocurre en la entrada, no en la salida — el sistema previene el problema en lugar de permitir que llegue hasta el pago.

Las reglas tienen su propio ciclo de vida (activación y desactivación) con historial completo para auditoría.

Incluye un período inicial de prueba de concepto para validar el enfoque técnico y definir el nivel de complejidad de las reglas que el sistema podrá soportar.

| Ítem | Horas |
|------|-------|
| Control de Accesos e Historial de Inicio de Sesión | 70h |
| Actualización de colaboradores vía carga masiva | 25h |
| Exportación del Historial del Colaborador | 35h |
| Información adicional en los listados | 50h |
| Importación masiva de Grupos | 40h |
| Importación masiva de Planes | 160h |
| Reglas de Validación para Indicadores | 120h |
| **Total — Mejoras de la Plataforma** | **500h** |

---

## 3. Personalización

### 3.1 — Cifrado de los campos adicionales del colaborador — 80h

Los campos adicionales del colaborador almacenan datos asociados a cada usuario (clave-valor), alimentados mediante carga masiva. Actualmente estos campos no cuentan con cifrado — lo que impide el almacenamiento de datos sensibles como el salario mensual (protegido por la LFPDPPP).

Esta entrega implementa cifrado en reposo en los campos adicionales, permitiendo que Atento México envíe datos sensibles con seguridad. El trabajo incluye: cifrado de las columnas de valor en 2 tablas, migración de todos los datos existentes en todos los entornos de la plataforma, y ajustes en los procesos internos que manipulan estos datos.

### 3.2 — Reporte consolidado por calendario (Sábana) — 160h

**Problema:** Atento México mantiene manualmente una hoja de cálculo Excel ("TBL General") que consolida todos los indicadores operacionales y resultados de cálculo de bonos de los 130 planes (~120 columnas). Esta hoja se utiliza para control financiero y auditoría ante el Banco de México.

**Solución:** Dos entregas:

Nuevo reporte que consolida todos los planes en una única tabla — una fila por colaborador, con columnas para datos del colaborador, campos adicionales (incluido el salario), indicadores y resultados de cálculo por tipo de pago. Disponible en cualquier momento del proceso (no solo tras el pago final), con indicación del estado de aprobación del pago.

**Condiciones:**

- Recomendamos que las Reglas de Validación (ítem 2.7) sean entregadas antes de este reporte, garantizando la calidad de los datos exportados

#### Mapeo de columnas — qué contendrá el reporte

Tras el análisis de la hoja de cálculo actual de Atento México y la reunión de alineación del 26 de febrero, realizamos el mapeo preliminar de las columnas. Las ~120 columnas de la TBL General se dividen en tres categorías:

**Categoría A — Datos que 4Shark ya tiene y el reporte entregará automáticamente:**

| Columna | Origen en 4Shark |
|---------|------------------|
| Mes | Calendario / Período |
| Id Coordinador | Jerarquía organizacional |
| Nombre Coordinador | Jerarquía organizacional |
| Id Supervisor | Jerarquía organizacional |
| Nombre Supervisor | Jerarquía organizacional |
| Id Agente | Identificador único del colaborador |
| Nombre Agente | Registro del colaborador |
| Servicio Específico | Nombre del grupo |
| Puntos Bono | Resultado del cálculo (puntos) |
| Porcentaje Bono | Resultado del cálculo (indicador agregado) |
| Bono Política (tope) | Resultado del limitador |
| Monto Final | Valor monetario final de la compensación |
| Comisión | Valores monetarios por tipo de pago |
| Indicadores operacionales (Calidad, Adherencia, Hold, Casos, Resolución, Captura, Cumplimiento, etc.) | Indicadores agregados — siempre que sean alimentados como variables en la plataforma |
| Estado de pago | "Pago aprobado" / "No pago aprobado" |

El reporte incluirá los identificadores únicos de cada colaborador (ID, external_id, documento único), permitiendo cruzamiento con datos de otros sistemas mediante BUSCARV.

**Categoría B — Datos que Atento México puede incluir mediante campos adicionales del colaborador:**

La plataforma permite asociar campos adicionales (clave-valor) a cada colaborador. Estos campos pueden ser alimentados mediante carga masiva y serán incluidos en el reporte.

| Columna | Cómo alimentar |
|---------|----------------|
| Centro | Campo adicional del colaborador — alimentar mediante carga masiva con el código del centro de costo |
| Login/AC | Campo adicional del colaborador — alimentar mediante carga masiva con el ID del sistema telefónico |
| Fecha de Ingreso | Campo adicional del colaborador — alimentar mediante carga masiva con la fecha de ingreso a la empresa |
| Sueldo Mensual | Campo adicional del colaborador (cifrado) — alimentar mediante carga masiva con el salario mensual |

Estas columnas dependen de que Atento México mantenga los datos actualizados en la plataforma. La funcionalidad de campos adicionales ya existe — no hay desarrollo adicional para Centro, Login/AC y Fecha de Ingreso. El almacenamiento seguro del salario mensual es habilitado por la entrega 3.1 (cifrado de los campos adicionales).

**Categoría C — Datos que quedan fuera del reporte:**

| Columna | Motivo |
|---------|--------|
| Observaciones | Campo de texto libre de gran extensión, incompatible con los campos adicionales del colaborador (limitados a valores cortos). **Recomendación:** complementar mediante BUSCARV en Excel tras la exportación, utilizando el identificador único del colaborador como clave de cruzamiento. |
| Aclaraciones | Ídem Observaciones. |

#### Resumen

La gran mayoría de las ~120 columnas de la TBL General corresponde a indicadores operacionales que ya son alimentados en la plataforma. El reporte consolidará automáticamente todos estos datos — incluido el salario mensual, que podrá ser almacenado de forma segura como campo adicional cifrado. Las dos columnas que quedan fuera (observaciones y aclaraciones) pueden ser complementadas mediante BUSCARV en Excel — el reporte incluirá todos los identificadores únicos del colaborador para facilitar ese cruzamiento.

En caso de que Atento México identifique columnas adicionales que no encajen en las categorías anteriores, el alcance y la estimación serán revisados en conjunto.

| Ítem | Horas |
|------|-------|
| 3.1 — Cifrado de los campos adicionales del colaborador | 80h |
| 3.2 — Reporte Consolidado (Sábana) | 160h |
| **Total — Personalización** | **240h** |

---

## 4. Funcionalidades Existentes

Las solicitudes a continuación fueron evaluadas y ya están cubiertas por funcionalidades existentes en la plataforma:

| Solicitud | Situación |
|-----------|-----------|
| Creación de parciales en lote y eliminación del bloqueo de 24h | El sistema genera parciales automáticamente todas las noches con datos actualizados. Para cierre y validación final, el flujo de compensaciones en lote ya cubre esta necesidad. |
| Generación automática de reportes para parciales | Los parciales son instrumentos de monitoreo vía dashboard. Los reportes completos están disponibles en el flujo de compensaciones. |
| Creación selectiva de compensaciones y eliminación del bloqueo de 24h | El procesamiento en lote ya opera de forma inteligente: crea nuevas compensaciones, reprocesa pendientes y preserva las aprobadas. El intervalo de 24h existe para garantizar la estabilidad del procesamiento. |
| Ordenamiento de calendarios por ID | El ordenamiento alfabético es el estándar de la plataforma para todos los clientes. Modificarlo impactaría la experiencia de uso de los demás clientes. |

---

## 5. Capacitación

Dos solicitudes de capacitación serán atendidas en una sesión única:

- **Identificaciones** — Sistema de múltiples identificadores por colaborador y su relevancia para la integración con nómina
- **Módulos de la plataforma** — Reportes de rendimiento, Productos, Clientes, Incentivos transaccionales, Clasificaciones, Campañas, Transacciones, Transacciones colaborativas, Métricas, Configuraciones de clasificaciones, Estados y Razones de reconocimiento

La sesión incluirá una demostración de la funcionalidad de restablecimiento masivo de contraseñas.

**Costo adicional:** Ninguno
**Próximo paso:** Confirmar fecha y participantes

---

## Cronograma

| Fase | Alcance | Inicio |
|------|---------|--------|
| **Fase 1** | Correcciones inmediatas (sección 1.1) | Próximo sprint |
| **Fase 2** | 7 mejoras de la plataforma (500h) | Tras aprobación |
| **Fase 3** | Reporte consolidado + cifrado (240h) | Tras aprobación |
| **Capacitación** | 1 sesión | Agendar de forma independiente |

La Fase 2 será entregada en el orden presentado en la sección 2, respetando las dependencias técnicas entre los ítems.

---

## Próximos Pasos

1. **Aprobar el alcance de las mejoras de la plataforma** (Fase 2) para iniciar la reorganización del roadmap
2. **Validar el mapeo de columnas del reporte consolidado** (Fase 3) — el mapeo preliminar está descrito en la sección 3 de este documento. En caso de que Atento México identifique columnas adicionales no contempladas, el alcance será revisado en conjunto
3. **Confirmar fecha y participantes** para la sesión de capacitación
4. Las correcciones inmediatas (Fase 1) serán entregadas de forma independiente en el próximo sprint
