# Plan de Mejoras — Atento México (v2)

**Fecha:** 24 de marzo de 2026
**De:** 4Shark
**Para:** Atento México

**Cambios respecto a la v1 (11 de marzo de 2026):**
- El ítem "Control de Accesos" dejó de ser una configuración de infraestructura condicionada al SSO y pasó a ser un desarrollo de la plataforma, cubriendo todos los tipos de inicio de sesión (directo y SSO). Agregado como primer ítem de la Etapa 2.

---

Tras el análisis de las 17 solicitudes levantadas y la reunión de alineación realizada el 26 de febrero, presentamos el plan de acción acordado. Las mejoras fueron organizadas en tres etapas con modelos distintos de entrega e inversión.

---

**Nuestra recomendación de cómo avanzar:**

Iniciamos mediante aprobación con las correcciones de la Etapa 1, sin ningún costo. Luego, Atento México elige qué mejora de la Etapa 2 desea priorizar primero. Para cada ítem elegido, el pago de las horas correspondientes se realiza antes del inicio de la implementación. Tras la entrega, Atento México decide el siguiente ítem y el ciclo se repite.

De esta forma, no hay un compromiso financiero grande de una sola vez — cada aprobación es puntual, proporcional al ítem elegido, y la entrega ocurre antes de cualquier nueva inversión.

---

## Etapa 1 — Correcciones Inmediatas

Las siguientes correcciones serán entregadas en el próximo sprint de desarrollo, sin costo para Atento México.

- **Fecha de registro en Usos Mensuales** — La pantalla de detalle pasará a mostrar la fecha de registro de cada colaborador en la plataforma.
- **Resumen del plan en el resultado Parcial** — La pantalla de resultado parcial pasará a mostrar los datos generales del plan asociado (nombre, tipo, calendario, grupo, estado).
- **Permisos de reportes de compensaciones** — La generación automática de reportes será habilitada para todos los administradores de Atento México.
- **Corrección de la página de reportes en lote** — El problema de carga de la página de reportes en lote de compensaciones será corregido.

**Costo:** Ninguno
**Plazo:** Próximo sprint

---

## Etapa 2 — Mejoras de la Plataforma

Estas funcionalidades forman parte de la evolución planificada de la plataforma ForShark y beneficiarán a todos los clientes. Atento México solicita la anticipación de estos ítems en el roadmap — lo que requiere reorganización de la cola de desarrollo actual.

El modelo de entrega es secuencial y bajo demanda: Atento México prioriza el primer ítem, aprueba la inversión correspondiente, 4Shark entrega, y luego avanza al siguiente. No es necesario aprobar todo de una vez.

### 2.1 — Control de Accesos e Historial de Inicio de Sesión — 70h

**Problema:** Atento México necesita auditar los accesos de los colaboradores a la plataforma — quién accedió, cuándo, cuántas veces, y si hubo intentos de acceso sin éxito. Los colaboradores ocasionalmente alegan no haber visto una declaración; la empresa necesita evidencias para confrontar esas situaciones.

**Solución:** Registro automático de todos los accesos a la plataforma, independientemente del método de autenticación utilizado (inicio de sesión directo o single sign-on). Cada acceso registra: colaborador, fecha y hora, dirección IP, método de autenticación, proveedor de identidad (cuando aplique), y si el acceso fue exitoso o no.

Los datos quedan disponibles para consulta directamente en la plataforma por 90 días, con filtros por período, colaborador, método de autenticación y resultado. Después de 90 días, los registros son archivados automáticamente en almacenamiento de largo plazo, quedando disponibles bajo solicitud.

| Ítem | Horas |
|------|-------|
| Control de Accesos e Historial de Inicio de Sesión | 70h |
| Actualización de colaboradores vía carga masiva | 25h |
| Exportación del Historial del Colaborador | 35h |
| Información adicional en los listados de Parciales y Compensaciones | 50h |
| Importación masiva de Grupos | 40h |
| Importación masiva de Planes | 160h |
| Reglas de Validación para Indicadores | 120h |
| **Total** | **500h** |

El orden presentado refleja las dependencias técnicas entre los ítems (ej: la importación de planes requiere que los grupos ya existan en la plataforma). La secuencia puede ser ajustada en conjunto en caso de que Atento México desee priorizar ítems de mayor valor inmediato.

---

## Etapa 3 — Desarrollo Personalizado

Este ítem es un desarrollo exclusivo para Atento México — no será disponibilizado para otros clientes de la plataforma.

### Reporte Consolidado por Calendario (Sábana)

Nuevo reporte que sustituye la hoja de cálculo TBL General mantenida manualmente hoy. Consolida todos los planes en una única tabla: una fila por colaborador, con datos de registro, campos adicionales, indicadores operacionales y resultados de cálculo por tipo de pago. Disponible en cualquier momento del proceso, con indicación del estado de aprobación de cada pago.

Las ~120 columnas de la TBL General fueron mapeadas en la reunión de alineación:
- **Datos que ForShark entrega automáticamente:** jerarquía organizacional, indicadores operacionales, resultados de cálculo, estado de pago.
- **Datos que Atento México alimenta vía campos adicionales:** centro de costo, login/AC, fecha de ingreso, sueldo mensual.
- **Fuera del reporte:** campos de observaciones y aclaraciones (texto libre extenso). Recomendamos complementar mediante BUSCARV en Excel, usando el identificador único del colaborador como clave — el reporte incluirá todos los identificadores para facilitar ese cruzamiento.

En caso de que Atento México identifique columnas no contempladas en el mapeo actual, el alcance será revisado en conjunto antes de iniciar el desarrollo.

**Nota:** Recomendamos que las Reglas de Validación (último ítem de la Etapa 2) sean entregadas antes de este reporte, garantizando la calidad de los datos exportados. El orden puede ser ajustado conforme la prioridad de Atento México.

| | Horas |
|-|-------|
| Reporte Consolidado (Sábana) | 160h |

---

## Capacitación

Dos solicitudes de capacitación serán atendidas en una sesión única, sin costo adicional:

- **Sistema de identificadores** — múltiples identificadores por colaborador y su relevancia para la integración con nómina
- **Módulos de la plataforma** — cobertura de los módulos aún no utilizados por el equipo de Atento México

La sesión incluirá una demostración de restablecimiento masivo de contraseñas.

**Próximo paso:** Confirmar fecha y lista de participantes.

---

## Fuera del Alcance

Las solicitudes a continuación fueron analizadas y no serán implementadas:

| Solicitud | Situación |
|-----------|-----------|
| Creación de parciales en lote y eliminación del bloqueo de 24h | El sistema ya genera parciales automáticamente todas las noches. Para cierre y validación, el flujo de compensaciones en lote ya cubre esta necesidad. |
| Generación automática de reportes para parciales | Los parciales son instrumentos de monitoreo — los reportes completos son generados en el flujo de compensaciones. |
| Creación selectiva de compensaciones y eliminación del bloqueo de 24h | El procesamiento en lote ya opera de forma inteligente. El intervalo de 24h garantiza la estabilidad del procesamiento. |
| Ordenamiento de calendarios por ID | El ordenamiento alfabético es el estándar de la plataforma. Modificarlo para un cliente impactaría la experiencia de todos los demás. |

---

## Resumen de la Inversión

| Etapa | Horas | Costo |
|-------|-------|-------|
| Etapa 1 — Correcciones inmediatas | 10h | Sin costo |
| Etapa 2 — Mejoras de la plataforma | 500h | Por ítem, bajo aprobación |
| Etapa 3 — Reporte Consolidado (Sábana) | 160h | Bajo aprobación |
| Capacitación | — | Sin costo |
| **Total** | **670h** | |

---

## Próximos Pasos

1. **Etapa 1** — las correcciones inmediatas serán entregadas en el próximo sprint, independientemente de cualquier aprobación adicional.
2. **Etapa 2** — definir el primer ítem a ser priorizado. Recomendamos iniciar por el Control de Accesos (ítem 2.1). La entrega es incremental; no es necesario aprobar todo de una vez.
3. **Etapa 3** — validar el mapeo de columnas del reporte Sábana antes de iniciar el desarrollo.
4. **Capacitación** — confirmar fecha y lista de participantes.
