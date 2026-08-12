# COMPLIANCE — Atento TPRM Questionnaire (Chile)

Planilla: `4Shark_Atento_TPRM_Questionnaire.xlsx` · Versión 001.2025 · Solicitante: Estefani M Pérez Gimenez (Global Systems | RRHH, Atento Chile)

Fuente de las respuestas: cuestionarios de seguridad ya respondidos por 4Shark — Grupo Barigui (`vendor-assessment-barigui/COMPLIANCE.md`) y Positivo (`vendor-assessment-positivo/COMPLIANCE.md`) — más el estado actual registrado en `legal-compliance-documents/ANALYSIS.md`.

**Leyenda de estado**

| Marca | Significado |
|---|---|
| ✅ | Respuesta lista — sustentada en un formulario ya respondido o en un control verificado |
| ⚠️ | Borrador listo — Paulo debe confirmar un dato antes de enviar |
| ❌ | Sin base — Paulo debe responder desde cero |

**Cómo se llena la planilla**: columna D = `SÍ` / `NO` / `N/A`; columna E = el texto de **Respuesta**; columna F = el nombre del documento adjunto (ver § Anexos al final).

---

## Pestaña `Instructions_ESP` — Información del proveedor

| Campo | Valor | Estado |
|---|---|---|
| Nombre de la compañía | 4SHARK TECNOLOGIA LTDA. (nombre comercial: 4Shark) — CNPJ 23.839.883/0001-23 | ✅ |
| Dirección registrada | São Paulo/SP, Brasil — `<dirección completa a completar>` | ⚠️ |
| Contacto del CISO | 4Shark no tiene un CISO formal. El punto de contacto de seguridad y privacidad es Paulo Ribeiro — Co-Founder & CTO / DPO — paulo@4shark.com.br. Canal de incidentes: security@4shark.com.br | ⚠️ |
| Datos personales tratados por cuenta de Atento | Datos de identificación y de contacto de los colaboradores de Atento usuarios de la plataforma: nombre, correo electrónico corporativo, documento de identificación nacional, cargo, posición jerárquica y gestor directo, además de los datos de desempeño y remuneración variable procesados por el servicio. No se tratan datos personales sensibles. | ⚠️ |
| Fecha de finalización | `<fecha de envío>` | — |
| Nombre de quien completa | Paulo Ribeiro | ✅ |
| Rol | Co-Founder & CTO / Encargado de Protección de Datos (DPO) | ✅ |
| Correo de contacto | paulo@4shark.com.br | ✅ |

> **Nota**: la respuesta a Barigui registró el DPO como `paulo@forcheck.com.br`. `ANALYSIS.md` ya marcó eso para normalizar al dominio 4Shark — aquí se usa `paulo@4shark.com.br`.

---

## Sección 1 — Inventario y control de activos corporativos

### 1.1 — Inventario preciso, detallado y actualizado de todos los activos (endpoints, red, IoT, servidores), revisado al menos semestralmente ❌

**Respuesta sugerida**: `NO`

**Texto**: 4Shark mantiene un inventario completo y versionado de la **infraestructura productiva**: la totalidad de los servidores, contenedores, redes y servicios en la nube está declarada como código en Terraform y Ansible, con historial auditable por commit — cada activo tiene propietario, propósito y configuración rastreables. No existe, en cambio, un inventario formal de **dispositivos de usuario final** (portátiles y móviles) con dirección de hardware, propietario y aprobación de conexión, ni herramienta MDM. 4Shark es una empresa de ingeniería de tamaño reducido con acceso a producción controlado por identidad y no por dispositivo (ver ítems 6.3 a 6.5).

> ❌ **Paulo decide**: mantener `NO` con la explicación compensatoria, o levantar un inventario de endpoints antes de responder. Ninguno de los formularios anteriores (Barigui/Positivo) preguntó esto.

### 1.2 — Proceso semanal de gestión de activos no autorizados ❌

**Respuesta sugerida**: `NO` — misma justificación que 1.1. En la red productiva no existe la figura del activo no autorizado: nada se conecta fuera de lo declarado en Terraform, y el acceso a la infraestructura interna exige VPN más credencial individual.

---

## Sección 2 — Inventario y control de software

### 2.1 — Inventario detallado de todo el software licenciado instalado en los activos ⚠️

**Respuesta sugerida**: `SÍ` (parcial — evaluar con Paulo si se responde `SÍ` o `NO`)

**Texto**: El inventario de software de la plataforma es completo y automático: todas las dependencias de aplicación (gems Ruby, paquetes npm, imágenes Docker, GitHub Actions) están declaradas en archivos de manifiesto versionados, con versión exacta fijada en archivos de bloqueo, y son inventariadas y monitoreadas de forma continua por GitHub Dependabot. Para el software de estación de trabajo no existe un inventario formal con proveedor, fecha de instalación y propósito de negocio.

### 2.2 — Solo software soportado designado como autorizado; revisión mensual ✅

**Respuesta**: `SÍ`

**Texto**: 4Shark mantiene toda la plataforma en versiones soportadas. Las dependencias se actualizan de forma continua vía Dependabot, con pull requests abiertos automáticamente tras cada publicación y fusionados diariamente por el equipo técnico. El sistema operativo y el motor de base de datos son gestionados por AWS (Amazon ECS y Amazon RDS Aurora) con parcheo automático conforme al AWS Shared Responsibility Model. La adopción de una nueva dependencia pasa por revisión de código obligatoria antes del merge.

### 2.3 — Software no autorizado retirado o con excepción documentada ⚠️

**Respuesta sugerida**: `SÍ` para la plataforma — ninguna dependencia entra en la aplicación fuera del proceso de pull request con revisión de código y verificación automatizada; no existe canal por el cual se instale software no revisado en el entorno productivo.

---

## Sección 3 — Protección de datos

### 3.1 — Inventario de datos, revisado al menos anualmente, priorizando datos confidenciales ✅

**Respuesta**: `SÍ`

**Texto**: 4Shark mantiene un Registro de Operaciones de Tratamiento (RoPA), que inventaria las actividades de tratamiento, las finalidades, las bases legales, las categorías de datos, los períodos de retención, los suboperadores y las transferencias internacionales. La clasificación de la información se realiza por tipo — datos personales, datos personales sensibles, credenciales de acceso, código fuente, documentos operativos internos y documentos públicos — con reglas específicas de tratamiento, control de acceso, almacenamiento, retención y descarte para cada tipo. Revisión anual.

**Evidencia (col. F)**: RoPA — Registro de Operaciones de Tratamiento.

### 3.2 — Listas de control de acceso basadas en necesidad de conocer ✅

**Respuesta**: `SÍ`

**Texto**: El acceso a los datos se controla en dos planos. En la **plataforma**, el modelo de permisos es de denegación por defecto y jerárquico: cada usuario ve exclusivamente los datos de su posición en la estructura organizativa y de las posiciones subordinadas, según el perfil de permisos atribuido. En la **infraestructura**, se aplica el principio de menor privilegio a todos los colaboradores: las cuentas personales de los ingenieros tienen permiso de solo lectura por defecto en recursos AWS, y toda la concesión de permisos y roles IAM se gestiona como código (Terraform) con revisión de código y trazabilidad por commit.

### 3.3 — Retención conforme al proceso de gestión de datos, con períodos mínimos y máximos ✅

**Respuesta**: `SÍ`

**Texto**: Los períodos de retención están definidos en la política interna de almacenamiento, anonimización y descarte, y registrados en el RoPA. Los datos personales de los usuarios se conservan hasta 5 años y 1 mes contados desde la desactivación del usuario en el cliente — plazo definido con base en el período de prescripción aplicable al vínculo entre el titular y el cliente — y son anonimizados de forma automática e irreversible al cumplirse ese plazo. Los archivos generados por funcionalidades de extracción se descartan automáticamente 48 horas después de su generación. Las copias de seguridad tienen retención de 7 días en la región primaria y 7 días en la región de recuperación ante desastres.

**Evidencia (col. F)**: Política de Almacenamiento, Anonimización y Descarte.

### 3.4 — Eliminación segura de datos, proporcional a la sensibilidad ✅

**Respuesta**: `SÍ`

**Texto**: La eliminación se ejecuta mediante anonimización irreversible de todos los identificadores del usuario (nombre, correo electrónico, documento de identificación y demás identificadores suministrados), sin posibilidad de reversión, con registro auditable en la base de datos. Los datos personales se almacenan exclusivamente en la base de datos relacional PostgreSQL; las demás capas (MongoDB, Elasticsearch, Redis) operan solo sobre identificadores internos y no persisten datos personales. Los documentos adjuntos se eliminan del almacenamiento de objetos. El proceso se ejecuta de forma sistemática y está documentado en un procedimiento operativo con lista de verificación de PII residual.

**Evidencia (col. F)**: Política de Almacenamiento, Anonimización y Descarte.

### 3.5 — Cifrado en reposo, en tránsito y en almacenamiento — con protocolos y algoritmos ✅

**Respuesta**: `SÍ`

**Texto**:
- **En tránsito**: TLS 1.2 o superior obligatorio en todas las comunicaciones externas, impuesto en la capa perimetral (CloudFlare). Las versiones inseguras (SSL 3.0, TLS 1.0, TLS 1.1) están deshabilitadas. Los certificados se gestionan con renovación automática y monitoreo continuo de validez.
- **En reposo**: AES-256 mediante AWS KMS en Amazon Aurora PostgreSQL (base de datos primaria) y Amazon S3 (objetos), con clave de cifrado dedicada por entorno.
- **Copias de seguridad**: AES-256 vía AWS KMS, tanto en la región primaria como en la copia interregional.
- **Credenciales**: almacenadas cifradas en AWS Systems Manager Parameter Store (SecureString, KMS) y en la bóveda corporativa 1Password; nunca en código fuente.
- **Contraseñas de usuario**: hash criptográfico con 16 niveles de salt más pepper, almacenamiento irreversible.

### 3.6 — [SaaS] ¿La solución procesa, almacena o transmite PII, PHI u otros datos confidenciales? ✅

**Respuesta**: `SÍ`

**Texto**: La solución procesa datos personales de identificación y contacto de los colaboradores del cliente (nombre, correo corporativo, documento de identificación nacional, cargo, posición jerárquica), además de datos de desempeño y remuneración variable. **No** se procesan datos de salud (PHI) ni ninguna otra categoría de datos personales sensibles conforme al art. 5.º II de la LGPD brasileña y equivalentes.

### 3.7 — Informe de auditoría SOC 2 Tipo II ✅

**Respuesta**: `NO`

**Texto**: 4Shark no cuenta con un informe SOC 2 Tipo II ni con certificaciones formales vigentes. La empresa adopta prácticas y controles alineados con los marcos ISO/IEC 27001 e ISO/IEC 27002, documentados en su conjunto de políticas internas de seguridad de la información, formalmente aprobadas por la dirección y con revisión anual prevista. Los proveedores de infraestructura crítica utilizados por 4Shark (AWS, CloudFlare, GitHub, Google Workspace, 1Password) sí cuentan con SOC 2 Tipo II, ISO 27001 e ISO 27018, con auditoría independiente continua.

### 3.8 — Restricción por IP pública autorizada y/o MFA para los usuarios ✅

**Respuesta**: `SÍ`

**Texto**: La plataforma utiliza Keycloak como proveedor de identidad y admite autenticación federada vía SSO con SAML 2.0, OAuth 2.0 y OpenID Connect. Cuando el cliente conecta su propio proveedor de identidad corporativo (Active Directory, Entra ID / Azure AD, Google Workspace, Okta), Keycloak delega la autenticación a ese IdP y **todas las políticas de MFA configuradas allí se respetan íntegramente**, sin solicitar un segundo factor redundante. Es el modelo recomendado para Atento.

En autenticación local (sin SSO), la plataforma no impone MFA como exigencia propia; la credencial es individual e intransferible, con reglas de complejidad (mínimo 8 caracteres, combinación de mayúsculas, minúsculas, números y caracteres especiales) y almacenamiento irreversible con hash salado. La restricción de acceso por lista de IPs públicas autorizadas puede evaluarse como configuración específica para Atento.

> ⚠️ **Paulo decide**: si conviene comprometer la restricción por IP, o presentar solo el camino SSO/MFA delegado.

### 3.9 — Informe de pentest realizado en los últimos 6 meses ⚠️

**Respuesta sugerida**: `SÍ` o `NO` **según la fecha del último pentest** — la pregunta acota explícitamente a 6 meses.

**Texto**: El pentest de la plataforma 4Shark fue realizado por una empresa independiente especializada en seguridad ofensiva. Todos los hallazgos fueron remediados y validados en retest. El resumen ejecutivo puede ponerse a disposición mediante NDA específico o cláusula en el acuerdo vigente.

> ⚠️ **Paulo confirma la fecha del ejercicio.** Si superó los 6 meses, la respuesta honesta es `NO` con el texto anterior en la columna E indicando la fecha real — Atento pregunta por la ventana, no por la existencia del pentest.

---

## Sección 4 — Configuración segura de activos y software

### 4.1 — Proceso de configuración segura para activos y software, revisado anualmente ⚠️

**Respuesta sugerida**: `SÍ` para la infraestructura productiva.

**Texto**: Toda la configuración de la infraestructura productiva está definida como código (Terraform para el aprovisionamiento AWS, Ansible para la configuración de servidores), lo que garantiza una línea base reproducible, versionada y auditable. Cualquier cambio de configuración pasa por pull request con revisión de código antes de aplicarse. Para los dispositivos de usuario final no existe una línea base de endurecimiento documentada.

### 4.2 — Proceso de configuración segura para dispositivos de red ✅

**Respuesta**: `SÍ`

**Texto**: La red es enteramente definida por software en AWS y declarada en Terraform: VPCs, subredes, tablas de rutas, Security Groups y reglas de acceso, todo con historial de cambios por commit. Los Security Groups aplican el principio de menor privilegio; no hay exposición directa de servicios internos a Internet — el único punto de entrada público es la capa perimetral CloudFlare sobre HTTPS.

### 4.3 — Bloqueo automático de sesión por inactividad (15 min escritorio / 2 min móvil) ❌

> ❌ **Paulo responde.** Ningún formulario anterior lo cubre. Depende de si el bloqueo de pantalla está configurado y verificado en las estaciones de trabajo del equipo.

### 4.4 — Firewall en los servidores ✅

**Respuesta**: `SÍ`

**Texto**: Todos los recursos productivos operan dentro de VPCs AWS protegidas por Security Groups con reglas de menor privilegio, funcionando como firewall a nivel de instancia y de servicio, con denegación por defecto para todo el tráfico no autorizado explícitamente. La configuración está declarada en Terraform y es auditable.

### 4.5 — Firewall basado en host o filtrado de puertos en dispositivos de usuario final, con denegación por defecto ❌

> ❌ **Paulo responde** — control de endpoint, no cubierto por los formularios anteriores.

### 4.6 — Gestión segura de activos y software (IaC, SSH/HTTPS, sin Telnet/HTTP) ✅

**Respuesta**: `SÍ`

**Texto**: La gestión de configuración se realiza mediante infraestructura como código bajo control de versiones (Terraform y Ansible). El acceso administrativo ocurre exclusivamente por protocolos seguros: HTTPS (TLS 1.2+) para interfaces de gestión y SSH con autenticación por clave para acceso a servidores. No se utilizan Telnet ni HTTP en la gestión. El acceso a la infraestructura interna y a las bases de datos productivas exige VPN — la base de datos no es accesible directamente desde el dispositivo del colaborador; el acceso pasa por un servidor dedicado dentro de la red privada del sistema correspondiente, y cada sistema opera en red aislada.

### 4.7 — Gestión de cuentas estándar (root, administrador, preconfiguradas por el proveedor) ✅

**Respuesta**: `SÍ`

**Texto**: Las operaciones administrativas amplias — alteración de permisos de identidad y cambios estructurales de infraestructura — requieren una cuenta administrativa dedicada operada exclusivamente mediante llave física YubiKey (MFA por hardware), bajo custodia de la dirección técnica. Esa cuenta opera en modelo break-glass: se usa solo para el acto de aplicar cambios, con traza completa en git y en los registros de ejecución. Ninguna cuenta personal, incluida la de la dirección técnica, tiene privilegio de administración en uso diario. En todos los sistemas SaaS integrados (AWS, GitHub, Google Workspace, 1Password), la cuenta propietaria es la cuenta break-glass.

---

## Sección 5 — Gestión de cuentas

### 5.1 — Eliminar/modificar configuraciones antes de producción; cambiar contraseñas por defecto; validar contra NIST 800-53 ⚠️

**Respuesta sugerida**: `SÍ` (parcial)

**Texto**: Ningún recurso entra en producción con configuración por defecto: todo el aprovisionamiento se realiza vía Terraform, con credenciales generadas específicamente por entorno y almacenadas cifradas en AWS Parameter Store — no existen contraseñas por defecto ni cuentas preconfiguradas activas. La configuración segura está documentada como código y revisada por pares. 4Shark **no** realiza validación formal contra NIST 800-53; el marco de referencia adoptado es ISO/IEC 27001 y 27002.

### 5.2 — Inventario de todas las cuentas gestionadas (nombre, usuario, fechas de alta/baja, departamento), validado trimestralmente ⚠️

**Respuesta sugerida**: `SÍ` (parcial) — Paulo decide entre `SÍ` y `NO`

**Texto**: El conjunto completo de accesos de cada colaborador está declarado en código (Terraform), con revisión por commit en cada cambio y auditoría vía git — es un inventario de cuentas y permisos íntegramente rastreable, y la identidad base es la cuenta de Google Workspace, desde la cual se propaga el acceso a los sistemas integrados. No existe, sin embargo, una **validación recurrente de cadencia fija** (trimestral) formalizada como proceso con registros; la revisión se realiza ante eventos organizativos (ingreso, salida, cambio de rol).

> ⚠️ Este es el ítem P5 del gap analysis interno (recertificación periódica de accesos), aún abierto.

### 5.3 — Contraseñas únicas para todos los activos ✅

**Respuesta**: `SÍ`

**Texto**: Todas las credenciales son únicas por sistema y por entorno. Las credenciales de aplicación se generan específicamente por entorno y se almacenan en AWS Systems Manager Parameter Store cifradas con KMS. Las credenciales compartidas por el equipo humano se gestionan en la bóveda corporativa 1Password, con MFA habilitado y contraseñas generadas por la propia herramienta. No hay reutilización de credenciales entre sistemas ni entre entornos.

### 5.4 — Eliminar o desactivar cuentas inactivas tras 90 días ❌

> ❌ **Paulo responde.** No hay una política de inactividad automática registrada; la revocación se ejecuta en la desvinculación (ver 6.2), lo cual es un control distinto.

### 5.5 — Privilegios de administrador restringidos a cuentas administrativas dedicadas ✅

**Respuesta**: `SÍ`

**Texto**: Sí — ver ítem 4.7. Las cuentas personales de los colaboradores operan con permiso de solo lectura por defecto en AWS; la elevación para acciones de mutación exige autenticación multifactor y está limitada a una sesión de una hora, cubriendo únicamente un subconjunto restringido de operaciones. Las operaciones administrativas amplias exigen la cuenta break-glass dedicada con llave física YubiKey. Las actividades de uso general (navegación, correo, suite de productividad) se realizan siempre desde la cuenta personal sin privilegio administrativo.

---

## Sección 6 — Gestión de control de acceso

### 6.1 — Proceso, preferentemente automatizado, para conceder acceso (recontratación, privilegios, cambio de rol) ✅

**Respuesta**: `SÍ`

**Texto**: Al incorporar un nuevo colaborador, los accesos necesarios (IAM AWS, GitHub, Google Workspace) se conceden mediante cambio en Terraform, con cada concesión registrada en un commit revisado. El colaborador recibe una cuenta en la bóveda corporativa 1Password con credenciales individuales. El mismo camino se aplica a un cambio de rol: la modificación del nivel de acceso pasa por el repositorio de infraestructura bajo revisión de código, con traza auditable. No hay concesión manual fuera de ese canal.

**Evidencia (col. F)**: Política de Identidad y Acceso · Procedimiento de Ciclo de Vida de Identidad.

### 6.2 — Proceso para revocar acceso con desactivación inmediata tras desvinculación ✅

**Respuesta**: `SÍ`

**Texto**: La revocación ocurre en el momento de la desvinculación, con plazo efectivo dentro de 24 horas. Comprende la remoción de la cuenta de los proveedores integrados (Google Workspace, AWS, GitHub) vía Terraform, la revocación inmediata en la bóveda corporativa y la desactivación de la cuenta de correo. La propagación a los sistemas que dependen del SSO de Google Workspace (Slack y demás SaaS integrados) es inmediata tras la desactivación de la identidad base. Se opta por la desactivación en lugar de la eliminación cuando es necesario preservar los registros de auditoría.

**Evidencia (col. F)**: Procedimiento de Ciclo de Vida de Identidad.

### 6.3 — MFA obligatorio en todas las aplicaciones expuestas externamente ⚠️

**Respuesta sugerida**: `SÍ` para el entorno interno de 4Shark; para la plataforma entregada al cliente, MFA se aplica vía el IdP corporativo del cliente.

**Texto**: En el entorno 4Shark, el correo corporativo (Google Workspace) tiene MFA obligatorio y actúa como proveedor de SSO central — los sistemas integrados (Slack y demás SaaS) heredan esa autenticación y propagan el MFA del IdP. En la plataforma entregada al cliente, la autenticación federada vía Keycloak delega al IdP corporativo del cliente y respeta íntegramente sus políticas de MFA; para Atento, ese es el modelo recomendado. En autenticación local sin SSO, la plataforma no impone MFA propio (ver 3.8).

### 6.4 — MFA para acceso remoto a la red ✅

**Respuesta**: `SÍ`

**Texto**: El acceso remoto a la infraestructura interna y a las bases de datos productivas exige VPN, y la identidad que autoriza ese acceso está anclada en el proveedor de identidad corporativo con MFA obligatorio.

### 6.5 — MFA para todas las cuentas de acceso administrativo ✅

**Respuesta**: `SÍ`

**Texto**: Sí. La elevación de privilegio para acciones de mutación en AWS exige autenticación multifactor y está limitada a una sesión de una hora. Las operaciones administrativas amplias exigen la cuenta break-glass operada exclusivamente mediante llave física YubiKey (MFA por hardware) bajo custodia de la dirección técnica. Las credenciales sensibles se almacenan y comparten exclusivamente mediante la bóveda corporativa 1Password, con MFA habilitado. Este diseño garantiza que cualquier concesión o revocación de acceso a un sistema crítico pase por aprobación rastreable y llave física custodiada.

---

## Sección 7 — Gestión continua de vulnerabilidades

### 7.1 — Proceso documentado de gestión de vulnerabilidades, revisado anualmente ⚠️

**Respuesta sugerida**: `SÍ` (parcial) — Paulo decide

**Texto**: 4Shark mantiene un proceso continuo de gestión de vulnerabilidades en todo el stack, descrito en su política interna de desarrollo seguro. Las dependencias de aplicación se escanean de forma automática y continua vía GitHub Dependabot, con pull requests de corrección abiertos inmediatamente tras la divulgación de cada vulnerabilidad y fusionados diariamente. El sistema operativo, el runtime y el motor de base de datos son parcheados por AWS. La capa perimetral (CloudFlare WAF con reglas OWASP) actualiza continuamente las protecciones contra ataques conocidos. No existe un documento independiente de política de gestión de vulnerabilidades con SLA formal basado en CVSS.

> ⚠️ Ítem P12 del gap analysis interno.

### 7.2 — Estrategia de remediación documentada basada en riesgos, con revisión mensual ⚠️

**Respuesta sugerida**: `SÍ` (en la práctica) / `NO` (como documento formal) — Paulo decide.

**Texto**: La remediación es continua y prioritaria por criticidad: la ventana típica entre la publicación de una vulnerabilidad y su corrección en producción es de horas a pocos días, igualando o superando los SLA habituales del mercado (Crítico ≤72h, Alto ≤30 días). La revisión es diaria, no mensual, por la cadencia de merge de los pull requests de Dependabot.

### 7.3 — Actualizaciones del sistema operativo mediante parcheo automatizado, mensual o más frecuente ✅

**Respuesta**: `SÍ`

**Texto**: El sistema operativo y el motor de base de datos son gestionados por AWS (Amazon ECS y Amazon RDS Aurora) con parcheo automático conforme al AWS Shared Responsibility Model. Las imágenes base de los contenedores se actualizan con reconstrucción automatizada vía pipeline de CI/CD.

### 7.4 — Actualizaciones de aplicaciones mediante parcheo automatizado, mensual o más frecuente ✅

**Respuesta**: `SÍ`

**Texto**: Las bibliotecas, frameworks y middleware (gems Ruby, paquetes npm, dependencias de aplicación) se actualizan continuamente vía Dependabot, con pull requests automáticos abiertos inmediatamente tras cada publicación y fusionados diariamente. Las dependencias del pipeline (GitHub Actions) también son monitoreadas y actualizadas por la misma vía. La cadencia real es diaria, superior a la mensual solicitada.

---

## Sección 8 — Gestión de registros de auditoría

### 8.1 — Proceso de gestión de registros de auditoría con requisitos de conservación, revisado anualmente ⚠️

**Respuesta sugerida**: `SÍ` (parcial)

**Texto**: Los registros de auditoría de la infraestructura se recopilan y conservan de forma estructurada: AWS CloudTrail registra todas las acciones ejecutadas en la cuenta y se conserva indefinidamente en almacenamiento de objetos dedicado. Los cambios de permisos y de infraestructura quedan registrados en git, con autor, fecha y diff. Los registros de aplicación, infraestructura y seguridad se centralizan en AWS CloudWatch. La persistencia de los **eventos de autenticación de la plataforma** (fecha, hora e IP de cada inicio de sesión) con retención superior a 6 meses e interfaz administrativa de extracción está en fase final de desarrollo.

> ⚠️ Ítem T1 del gap analysis interno (`security-events-platform`). **Paulo confirma si ya está en producción** — si lo está, la respuesta se refuerza y también cierra el ítem 8.2.

### 8.2 — Recopilación de registros de auditoría habilitada en todos los activos ⚠️

**Respuesta sugerida**: `SÍ` — con la misma salvedad del ítem 8.1 respecto a los eventos de autenticación de la plataforma.

### 8.3 — Capacidad de almacenamiento adecuada en los destinos de registro ✅

**Respuesta**: `SÍ`

**Texto**: Los registros se almacenan en AWS CloudWatch Logs y en almacenamiento de objetos Amazon S3, ambos servicios gestionados con capacidad elástica — no existe límite fijo de almacenamiento que pueda agotarse e interrumpir la recopilación.

---

## Sección 9 — Protecciones de correo electrónico y navegador

### 9.1 — Solo navegadores y clientes de correo soportados, en la versión más reciente ❌

> ❌ **Paulo responde.** El correo corporativo es Google Workspace (cliente web, siempre actualizado por el proveedor), pero la exigencia de versión más reciente de navegador en las estaciones de trabajo no está formalizada.

### 9.2 — Servicios de filtrado DNS para bloquear dominios maliciosos ❌

> ❌ **Paulo responde.** No hay registro de filtrado DNS en las estaciones de trabajo en los formularios anteriores. Google Workspace aplica filtrado antiphishing y antimalware al correo, lo cual cubre parcialmente el vector — puede citarse como control compensatorio.

---

## Sección 10 — Defensas contra malware

### 10.1 — Software antimalware en todos los activos ❌

> ❌ **Paulo responde.** Los equipos son macOS con XProtect/Gatekeeper nativos; si no hay solución antimalware gestionada, la respuesta honesta es `NO` con la mención de los controles nativos del sistema operativo y del hecho de que la infraestructura productiva son contenedores efímeros reconstruidos desde imágenes versionadas, sin superficie de instalación persistente.

### 10.2 — Reproducción automática (autoplay) deshabilitada para medios extraíbles ❌

> ❌ **Paulo responde.**

---

## Sección 11 — Recuperación de datos

### 11.1 — Proceso de recuperación de datos documentado, revisado anualmente ✅

**Respuesta**: `SÍ`

**Texto**: 4Shark cuenta con un Plan de Continuidad del Negocio y Recuperación ante Desastres (BCP/DRP) documentado y formalmente aprobado, que define el alcance de las actividades de recuperación, la priorización, la seguridad de los datos de respaldo, los objetivos RPO y RTO y los dos escenarios de recuperación previstos (corrupción de datos con la región primaria sana, y pérdida total de región). El procedimiento operativo de restauración está documentado en un runbook interno.

**Evidencia (col. F)**: Política de Continuidad del Negocio y Recuperación ante Desastres (BCP/DRP) · Política de Copias de Seguridad.

### 11.2 — Copias de seguridad automatizadas, semanales o más frecuentes ✅

**Respuesta**: `SÍ`

**Texto**: Las copias de seguridad son **diarias y continuas**, muy por encima de la cadencia semanal solicitada. Las bases Amazon Aurora PostgreSQL cuentan con respaldo continuo vía Point-in-Time Recovery (PITR) más snapshots automáticos diarios. Retención: 7 días en la región primaria (us-east-1) y 7 días en la región de recuperación (us-west-2). Las copias se ejecutan de forma automatizada por AWS Backup, con alarmas configuradas tanto para el fallo de la copia como para el fallo de la réplica interregional.

**Evidencia (col. F)**: Política de Copias de Seguridad.

### 11.3 — Datos de recuperación protegidos con controles equivalentes a los originales ✅

**Respuesta**: `SÍ`

**Texto**: Las copias de seguridad se cifran con AES-256 vía AWS KMS, con el mismo estándar aplicado a los datos originales, y el acceso a las bóvedas de respaldo se controla por políticas IAM gestionadas como código. La copia de recuperación ante desastres reside en una región AWS distinta (us-west-2), con separación geográfica respecto de la región primaria.

### 11.4 — Infraestructura de red mantenida actualizada, revisión mensual de versiones ✅

**Respuesta**: `SÍ`

**Texto**: La infraestructura de red es enteramente gestionada por AWS (VPC, Security Groups, balanceadores) y por CloudFlare en la capa perimetral — ambos servicios gestionados, mantenidos y actualizados de forma continua por los proveedores, sin versiones de software bajo responsabilidad de 4Shark. 4Shark no opera equipamiento de red propio.

### 11.5 — Instancia aislada de los datos de recuperación ✅

**Respuesta**: `SÍ`

**Texto**: Existe una copia de recuperación aislada en una segunda región AWS (us-west-2), replicada diariamente desde la región primaria mediante AWS Backup, con bóveda y clave de cifrado propias. La restauración a partir de esa copia interregional se prueba de forma **automatizada y mensual** mediante AWS Backup Restore Testing, con evidencia fechada, además de un ejercicio anual de recuperación completa (game-day) que mide el RTO extremo a extremo.

---

## Sección 12 — Concienciación y capacitación en seguridad

### 12.1 — Programa de concienciación en seguridad, formación en la contratación y al menos anual ⚠️

**Respuesta sugerida**: `SÍ` (parcial) — Paulo decide entre `SÍ` y `NO`

**Texto**: 4Shark imparte orientación de seguridad de la información en el onboarding de todos los nuevos colaboradores, dictada directamente por la dirección técnica, con reciclaje anual. Los temas incluyen los principios de seguridad de la plataforma, la normativa de protección de datos aplicable, la gestión de credenciales y el uso de la bóveda corporativa, las amenazas comunes (phishing, ingeniería social) y el proceso de respuesta a incidentes. El público objetivo es la totalidad de los colaboradores. Existe una política interna de programa de concienciación aprobada; el registro formal de finalización por participante es un control en implementación.

> ⚠️ Ítem P9 del gap analysis interno (programa documentado + registros de finalización).

### 12.2 — Capacitación para reconocer ingeniería social (phishing, spoofing, uso no autorizado) ✅

**Respuesta**: `SÍ` — cubierto por el programa descrito en 12.1; phishing e ingeniería social son temas explícitos del contenido.

### 12.3 — Capacitación en mejores prácticas de autenticación (MFA, composición de contraseñas, gestión de credenciales) ✅

**Respuesta**: `SÍ` — cubierto por el programa descrito en 12.1; la gestión de credenciales y el uso de la bóveda corporativa son temas explícitos.

### 12.4 — Capacitación en manejo de datos confidenciales (almacenamiento, transferencia, archivo, destrucción; escritorio y pantalla despejados) ⚠️

**Respuesta sugerida**: `SÍ` — el tratamiento de datos personales está cubierto por la formación y por las políticas internas (tratamiento de datos personales; almacenamiento, anonimización y descarte), firmadas por los colaboradores. Las prácticas de escritorio y pantalla despejados no están formalizadas como tema específico.

### 12.5 — Capacitación sobre las causas de exposición no intencionada de datos ⚠️

**Respuesta sugerida**: `SÍ` — cubierto de forma general por la formación en protección de datos.

### 12.6 — Capacitación para reconocer y reportar un posible incidente ✅

**Respuesta**: `SÍ`

**Texto**: El proceso de respuesta a incidentes es tema explícito de la formación de onboarding y del reciclaje anual, y está formalizado en la política interna de respuesta a incidentes, que define los roles, el flujo de escalamiento y los criterios de severidad. El canal de reporte es security@4shark.com.br.

### 12.7 — Capacitación para verificar y reportar parches desactualizados o fallos en procesos automatizados ⚠️

**Respuesta sugerida**: `SÍ`

**Texto**: El equipo técnico opera diariamente el flujo de actualización de dependencias (revisión y merge de los pull requests de Dependabot) y recibe alertas automatizadas de fallos de pipeline y de infraestructura en el canal corporativo de comunicación — la verificación y el reporte de fallos en procesos automatizados forman parte de la rutina operativa. Al ser 4Shark un equipo íntegramente técnico, no existe la separación entre "personal" y "equipo de TI" que la pregunta presupone.

### 12.8 — Capacitación sobre riesgos de redes no seguras y configuración segura de la red doméstica ⚠️

**Respuesta sugerida**: `SÍ` (parcial)

**Texto**: El acceso a la infraestructura y a las bases de datos productivas exige VPN desde cualquier red, lo que neutraliza el riesgo de la red de origen como control técnico. El tema se aborda en la orientación de seguridad, aunque no existe un módulo formal de configuración de red doméstica.

---

## Sección 13 — Gestión de proveedores de servicios

### 13.1 — Inventario de proveedores de servicios con clasificación y contacto corporativo, revisado anualmente ⚠️

**Respuesta sugerida**: `SÍ` (parcial) — Paulo decide

**Texto**: Los suboperadores y proveedores que participan en el tratamiento de datos están inventariados en el RoPA, con identificación, finalidad y ubicación. 4Shark mantiene la política de seleccionar exclusivamente proveedores de tecnología de gran porte y reconocimiento internacional para infraestructura crítica — AWS, CloudFlare, GitHub, Google Workspace y 1Password —, todos con certificaciones reconocidas (SOC 2 Tipo II, ISO 27001, ISO 27018), auditoría independiente continua y contratos con cláusulas formales de protección de datos. No existe un procedimiento independiente de calificación de proveedores con clasificación de criticidad y revisión anual formalizada.

> ⚠️ Ítem P10 del gap analysis interno. Ver también 20.1.

---

## Sección 14 — Gestión de respuesta a incidentes

### 14.1 — Persona clave y al menos un suplente designados para gestionar el proceso de incidentes ⚠️

**Respuesta sugerida**: `SÍ`

**Texto**: La política interna de respuesta a incidentes define los roles y las responsabilidades. La coordinación es responsabilidad de la dirección técnica (Paulo Ribeiro, Co-Founder & CTO / DPO), con suplencia asignada dentro del equipo técnico.

> ⚠️ **Paulo confirma el nombre del suplente** para completar la respuesta.

### 14.2 — Información de contacto de las partes a informar en un incidente, verificada anualmente ⚠️

**Respuesta sugerida**: `SÍ` — la política de respuesta a incidentes contempla la notificación al cliente, a la autoridad de protección de datos competente y a las partes interesadas afectadas. Los contactos por cliente se mantienen en el acuerdo vigente.

### 14.3 — Proceso corporativo de reporte de incidentes, disponible públicamente para todos los empleados ✅

**Respuesta**: `SÍ`

**Texto**: 4Shark mantiene un canal dedicado para el reporte de incidentes de seguridad: **security@4shark.com.br**, disponible 24 horas al día para la recepción de comunicaciones, con confirmación automática de entrega. El proceso de reporte — plazo de notificación, destinatarios, mecanismo e información mínima a informar — está formalizado en la política interna de respuesta a incidentes, que cubre las cinco etapas del proceso (planificación, identificación, contención, erradicación y recuperación), con flujo de escalamiento por severidad y criterios de clasificación. La política es conocida y firmada por todos los colaboradores.

**Evidencia (col. F)**: Política de Respuesta a Incidentes.

---

## Sección 15 — Continuidad del negocio y recuperación ante desastres

### 15.1 — BCP y DRP documentados, actualizados y formalmente aprobados ✅

**Respuesta**: `SÍ`

**Texto**: 4Shark cuenta con un Plan de Continuidad del Negocio y Recuperación ante Desastres documentado, formalmente aprobado por la dirección y con revisión periódica. El plan establece los objetivos de recuperación, los dos escenarios previstos (corrupción de datos con la región primaria operativa, y pérdida total de la región primaria), la separación geográfica interregional de las copias y la cadencia de pruebas de recuperación.

**Evidencia (col. F)**: Política de Continuidad del Negocio y Recuperación ante Desastres (BCP/DRP).

### 15.2 — Valores de RTO y RPO definidos para los servicios críticos ✅

**Respuesta**: `SÍ`

**Texto**:
- **RPO (Objetivo de Punto de Recuperación): ≤ 1 hora** — sustentado por Amazon Aurora PostgreSQL con Point-in-Time Recovery continuo y snapshots automáticos diarios.
- **RTO (Objetivo de Tiempo de Recuperación): 4 horas** — sustentado por Amazon Aurora Multi-AZ con failover automático y Amazon ECS con auto-recuperación de contenedores.

### 15.3 — Pruebas periódicas de BCP/DRP (al menos anuales) con evidencia de resultados y acciones correctivas ✅

**Respuesta**: `SÍ`

**Texto**: Las pruebas de restauración se ejecutan de forma **automatizada y mensual** mediante AWS Backup Restore Testing, restaurando la copia interregional en la región de recuperación y generando evidencia fechada de cada ejecución. Adicionalmente se realiza un ejercicio anual de recuperación completa (game-day) que ejecuta el cambio real de la aplicación hacia la base restaurada y mide el RTO extremo a extremo. El procedimiento y los resultados están documentados en el runbook interno de pruebas de restauración.

**Evidencia (col. F)**: Registro de pruebas de restauración (evidencia fechada AWS Backup) · runbook de pruebas de restauración.

### 15.4 — Mecanismos redundantes (infraestructura, comunicaciones y respaldos) ✅

**Respuesta**: `SÍ`

**Texto**:
- **Base de datos**: Amazon Aurora PostgreSQL Multi-AZ con failover automático entre zonas de disponibilidad.
- **Aplicación**: Amazon ECS con múltiples instancias por servicio y auto-recuperación de contenedores.
- **Capa perimetral**: CloudFlare (CDN, WAF y anti-DDoS) con redundancia global.
- **Respaldos**: retención local más copia en una segunda región AWS (us-west-2).
- **Disponibilidad medida**: superior al 99,9%.

---

## Sección 16 — Privacidad: tratamiento de datos y cumplimiento normativo

### 16.1 — Medidas técnicas y organizativas para datos personales, de contacto, de identificación, financieros o económicos ✅

**Respuesta**: `SÍ`

**Texto**: Las medidas técnicas incluyen: cifrado en tránsito (TLS 1.2+) y en reposo (AES-256 / AWS KMS); control de acceso jerárquico de denegación por defecto en la plataforma; menor privilegio con elevación temporal vía MFA en la infraestructura; segregación total de entornos (desarrollo, homologación y producción operan con credenciales, VPCs e infraestructura independientes, y los entornos inferiores usan exclusivamente datos sintéticos); WAF con reglas OWASP; limitación de tasa en dos capas; hash irreversible de contraseñas; anonimización irreversible al final del período de retención; y registro auditable de acceso. Las medidas organizativas incluyen el conjunto de 15 políticas internas de seguridad y privacidad formalmente aprobadas, acuerdos de confidencialidad firmados por todos los colaboradores, formación en el onboarding con reciclaje anual, y desarrollo seguro con revisión de código y revisión de seguridad obligatorias antes del merge.

**Evidencia (col. F)**: Política de Seguridad de la Información (paraguas) · Política de Tratamiento de Datos Personales.

### 16.2 — Medidas para datos personales SENSIBLES ✅

**Respuesta**: `N/A`

**Texto**: 4Shark **no trata datos personales sensibles** por cuenta de sus clientes — no se procesan datos de salud, genéticos, biométricos, de origen racial o étnico, de convicción filosófica o política, ni relativos a la orientación sexual. Existe una declaración interna formal en ese sentido. Las medidas descritas en el ítem 16.1 se aplican igualmente a la totalidad de los datos tratados.

**Evidencia (col. F)**: Declaración de No Tratamiento de Datos Sensibles.

### 16.3 — ¿Organización establecida en el país donde se prestarán los servicios? ✅

**Respuesta**: `NO`

**Texto**: 4Shark está constituida en Brasil (4SHARK TECNOLOGIA LTDA., São Paulo/SP). Los servicios se prestan en modalidad SaaS desde infraestructura alojada en Amazon Web Services, región us-east-1 (Norte de Virginia, Estados Unidos). Las salvaguardas aplicables a la transferencia internacional se detallan en el ítem 16.4.

### 16.4 — Cumplimiento de los requisitos legales de transferencia internacional ✅

**Respuesta**: `SÍ`

**Texto**: La transferencia internacional se ampara en **cláusulas contractuales específicas** celebradas con el proveedor de infraestructura (AWS Data Processing Addendum, que incorpora las Cláusulas Contractuales Tipo), conforme al art. 33, inciso II de la LGPD brasileña y a los mecanismos equivalentes de la Ley 19.628 y su reforma (Ley 21.719) en Chile. Adicionalmente, 4Shark celebra un Acuerdo de Tratamiento de Datos (DPA) con cada cliente, que incorpora las obligaciones sobre suboperadores, notificación de incidentes y derechos de auditoría. AWS cuenta con certificaciones SOC 2 Tipo II, ISO 27001 e ISO 27018.

**Evidencia (col. F)**: DPA — Acuerdo de Tratamiento de Datos · RoPA (sección de transferencias internacionales).

> ⚠️ **Paulo confirma** el estado de la aceptación formal del AWS DPA — ítem L1 del gap analysis interno.

### 16.5 — Garantía de tratamiento exclusivo para las finalidades acordadas ✅

**Respuesta**: `SÍ`

**Texto**: Sí. Los datos personales compartidos por Atento se tratan exclusivamente para las finalidades acordadas dentro del alcance de los servicios contratados. El compromiso está formalizado en el Acuerdo de Tratamiento de Datos (DPA) y registrado en el RoPA, que documenta la finalidad de cada actividad de tratamiento. 4Shark no vende, comparte ni divulga datos personales de clientes a terceros para ninguna otra finalidad.

**Evidencia (col. F)**: DPA — Acuerdo de Tratamiento de Datos.

---

## Sección 17 — Gobernanza de protección de datos

### 17.1 — Sistema de Gestión de Privacidad implementado (indicar componentes) ✅

**Respuesta**: `SÍ`

**Texto**: 4Shark mantiene un sistema de gestión de privacidad compuesto por:
- **Política de Privacidad pública**, publicada en www.4shark.com.br, con divulgación de analítica y cookies.
- **Términos de Uso**.
- **RoPA** — Registro de Operaciones de Tratamiento, con finalidades, bases legales, categorías de datos, períodos de retención, suboperadores y transferencias internacionales.
- **DPA** — Acuerdo de Tratamiento de Datos, celebrado por cliente.
- **Matriz de Aplicabilidad**, que define qué documento aplica y quién lo suscribe.
- **15 políticas internas** que cubren: seguridad de la información (paraguas), identidad y acceso, contraseñas, correo electrónico, activos y red de TI, desarrollo seguro, copias de seguridad, almacenamiento/anonimización/descarte, programa de concienciación, respuesta a incidentes, privacidad desde el diseño, tratamiento de datos personales, declaración de no tratamiento de datos sensibles, acuerdo de confidencialidad y continuidad del negocio.
- **Roles definidos**: DPO designado; responsabilidades de seguridad y privacidad atribuidas a la dirección técnica.
- **Controles técnicos**: descritos en el ítem 16.1.
- **Procedimientos operativos**: atención de solicitudes de titulares y ejecución técnica de eliminación de datos.

**Evidencia (col. F)**: Matriz de Aplicabilidad (lista completa de documentos) · Política de Seguridad de la Información.

### 17.2 — Estructura de gobernanza designada para Privacidad ⚠️

**Respuesta sugerida**: `SÍ`

**Texto**: 4Shark es una empresa de ingeniería de tamaño reducido, y la gobernanza de privacidad es ejercida directamente por la dirección ejecutiva: el Encargado de Protección de Datos (DPO) es Paulo Ribeiro, Co-Founder & CTO, lo que coloca la responsabilidad de privacidad en el mismo nivel que la decisión técnica y de producto — la aprobación de las políticas y la decisión sobre el tratamiento de datos no atraviesan una capa intermedia. No existe un comité de privacidad ni un área formal independiente, con estructura y presupuesto propios, en los moldes de una organización de gran porte.

### 17.3 — Campeones de Privacidad designados ✅

**Respuesta**: `NO`

**Texto**: 4Shark no cuenta con la figura de Campeones de Privacidad. Con un equipo del tamaño actual, la totalidad de los colaboradores recibe formación en protección de datos en el onboarding y en el reciclaje anual, y firma las políticas de privacidad aplicables — el rol de multiplicador que la figura busca cubrir no encuentra aquí una capa organizativa que atravesar.

### 17.4 — Responsable de Protección de Datos (DPO) designado ✅

**Respuesta**: `SÍ`

**Texto**: 4Shark cuenta con un Encargado de Protección de Datos (DPO) formalmente designado, identificado en la Política de Privacidad publicada en www.4shark.com.br:
- **Nombre**: Paulo Ribeiro
- **Cargo**: Co-Founder & CTO / DPO
- **Correo electrónico**: paulo@4shark.com.br
- **Canal de privacidad**: privacidade-dados@4shark.com.br

**Evidencia (col. F)**: Política de Privacidad (sección de contacto del DPO).

### 17.5 — Identificación de las leyes y normativas de privacidad aplicables ✅

**Respuesta**: `SÍ`

**Texto**: 4Shark identifica como aplicables: la Ley General de Protección de Datos brasileña (Ley 13.709/2018 — LGPD) como normativa principal, por ser la sede de la compañía y el lugar de tratamiento; y las normativas locales de los países donde residen los titulares atendidos por la plataforma — en el caso de Chile, la Ley 19.628 sobre Protección de la Vida Privada y su reforma por la Ley 21.719. El análisis de aplicabilidad está registrado en la Matriz de Aplicabilidad y en el RoPA.

### 17.6 — Cumplimiento de las leyes y normativas de privacidad aplicables ✅

**Respuesta**: `SÍ`

**Texto**: Sí. El cumplimiento se sustenta en: Política de Privacidad pública con bases legales y derechos de los titulares; RoPA; DPA por cliente; DPO designado; canal público para el ejercicio de derechos; períodos de retención definidos con anonimización automática al vencimiento; salvaguarda contractual para la transferencia internacional; y el conjunto de políticas internas de seguridad y privacidad. En 10 años de operación 4Shark no registró ningún incidente de fuga de datos ni sanción por parte de una autoridad de protección de datos.

### 17.7 — Marco de gobernanza de privacidad y/o seguridad adoptado ✅

**Respuesta**: `SÍ`

**Texto**: 4Shark adopta prácticas y controles alineados con **ISO/IEC 27001 e ISO/IEC 27002** para la gestión de seguridad de la información, y con los principios de la **LGPD** (arts. 6.º, 46 a 49) para privacidad, incluyendo Privacidad desde el Diseño y por Defecto. La infraestructura sigue el **AWS Well-Architected Framework**, en particular su pilar de Seguridad. No se cuenta con certificación formal en ninguno de estos marcos.

### 17.8 — [Solo EE. UU.] Venta, compartición o divulgación de datos personales a terceros ✅

**Respuesta**: `N/A` — 4Shark está establecida en Brasil, no en los Estados Unidos.

---

## Sección 18 — Responsabilidad proactiva

### 18.1 — Registro de actividades de tratamiento como Encargado del Tratamiento ✅

**Respuesta**: `SÍ`

**Texto**: 4Shark mantiene un RoPA que registra las actividades de tratamiento realizadas por cuenta de sus clientes en calidad de operador, con finalidad, categorías de datos y de titulares, base legal, período de retención, suboperadores involucrados y transferencias internacionales.

**Evidencia (col. F)**: RoPA — Registro de Operaciones de Tratamiento.

### 18.2 — Registro de actividades de tratamiento como Responsable del Tratamiento ✅

**Respuesta**: `SÍ`

**Texto**: El mismo RoPA cubre las actividades en las que 4Shark actúa como controlador — datos de sus propios colaboradores, contactos comerciales, proveedores y visitantes del sitio web (incluida la actividad de analítica).

**Evidencia (col. F)**: RoPA — Registro de Operaciones de Tratamiento.

### 18.3 — Evaluaciones de riesgo de privacidad sobre las actividades de tratamiento ⚠️

**Respuesta sugerida**: `NO` — Paulo decide

**Texto**: 4Shark no ejecuta un programa formal de evaluación periódica de riesgos de privacidad con metodología estructurada, registro de riesgos y ciclo de reevaluación en los moldes de ISO 31000. La evaluación de riesgos se ejerce de forma continua por la dirección técnica, integrada a las decisiones de arquitectura, desarrollo y operación: cada funcionalidad pasa por una evaluación de impactos de seguridad y privacidad durante la planificación, y por una revisión de seguridad dedicada antes del merge.

> ⚠️ Ítem P4 del gap analysis interno (programa formal de gestión de riesgos).

### 18.4 — Evaluaciones de Impacto en la Protección de Datos (DPIA) sobre tratamientos de alto riesgo ⚠️

**Respuesta sugerida**: `NO`

**Texto**: 4Shark no ha realizado una DPIA formal con el contenido estructural descrito. El tratamiento realizado por la plataforma no involucra datos personales sensibles, decisiones automatizadas con efectos jurídicos sobre los titulares, ni monitoreo sistemático a gran escala — los criterios que habitualmente disparan la obligatoriedad de una DPIA. La evaluación de impacto se realiza de forma integrada al proceso de desarrollo, conforme al ítem 18.3.

### 18.5 — Metodología para determinar si un tratamiento implica RIESGO ALTO ⚠️

**Respuesta sugerida**: `NO` — no existe una metodología formalizada. Ver 18.3.

### 18.6 — Privacidad desde el Diseño y por Defecto ✅

**Respuesta**: `SÍ`

**Texto**: Sí, formalizado en la política interna de Privacidad desde el Diseño. En la práctica se aplica mediante:
- **Anonimización irreversible** de todos los identificadores del titular al término del período de retención, sin posibilidad de reversión.
- **Minimización**: los datos personales se almacenan exclusivamente en la base de datos relacional; las demás capas de la arquitectura (MongoDB, Elasticsearch, Redis) operan solo sobre identificadores internos y no persisten datos personales.
- **Descarte automático** de los archivos generados por funcionalidades de extracción a las 48 horas.
- **Denegación por defecto** en el modelo de permisos: el usuario solo ve lo que su posición jerárquica autoriza.
- **Datos sintéticos** en los entornos de desarrollo y homologación — nunca copia de datos productivos.
- **Evaluación de impactos de privacidad** durante la planificación de cada funcionalidad, con revisión de seguridad dedicada antes del merge.

**Evidencia (col. F)**: Política de Privacidad desde el Diseño.

---

## Sección 19 — Ciclo de vida de los datos

### 19.1 — Marco de gestión del ciclo de vida de los datos (mapeo, clasificación, diagramas de flujo) ✅

**Respuesta**: `SÍ`

**Texto**: El ciclo de vida está cubierto por: el **RoPA** (mapeo de las actividades de tratamiento, del origen al descarte); la **clasificación por tipo de información** (datos personales, datos personales sensibles, credenciales de acceso, código fuente, documentos operativos internos, documentos públicos), con reglas específicas de tratamiento, acceso, almacenamiento, retención y descarte para cada tipo; la **política de almacenamiento, anonimización y descarte** (períodos y método de eliminación); y el **diagrama de arquitectura** de la plataforma, que representa los componentes, el flujo de datos, las integraciones y las capas de seguridad.

**Evidencia (col. F)**: RoPA · Política de Almacenamiento, Anonimización y Descarte · Diagrama de arquitectura.

### 19.2 — Medidas técnicas y organizativas de seguridad, confidencialidad e integridad ✅

**Respuesta**: `SÍ` — ver el detalle en el ítem 16.1.

### 19.3 — Medidas para mantener los datos debidamente actualizados ✅

**Respuesta**: `SÍ`

**Texto**: La base de usuarios y su estructura organizativa se mantienen actualizadas mediante una integración dedicada con los sistemas de origen del cliente: las altas, cambios de cargo, cambios de gestor y desvinculaciones se propagan desde el sistema fuente hacia la plataforma, lo que mantiene el dato sincronizado con la fuente autoritativa y evita registros creados ad hoc sin trazabilidad. Adicionalmente, los usuarios pueden corregir sus propios datos de perfil, y los titulares pueden solicitar la rectificación mediante el canal de derechos.

### 19.4 — Políticas que limiten el período de conservación de los datos personales ✅

**Respuesta**: `SÍ`

**Texto**: La política interna de almacenamiento, anonimización y descarte define los períodos de retención. En calidad de operador por cuenta del cliente, el período es de **5 años y 1 mes** contados desde la desactivación del usuario en el cliente, tras lo cual los datos son anonimizados de forma automática e irreversible. Ese plazo se definió con base en el período de prescripción aplicable al vínculo entre el titular y el cliente, y representa el máximo que se conservan los datos. Los archivos de extracción se descartan a las 48 horas. Las copias de seguridad tienen retención de 7 días por región.

**Evidencia (col. F)**: Política de Almacenamiento, Anonimización y Descarte.

> ⚠️ **Paulo confirma** la fecha de aprobación de la política para completar la respuesta con el dato que la pregunta solicita.

### 19.5 — Obtención del consentimiento cuando la ley lo exige ✅

**Respuesta**: `SÍ`

**Texto**: En el tratamiento realizado por cuenta del cliente, 4Shark actúa como operador y la base legal la determina el controlador (el cliente) — típicamente la ejecución del contrato de trabajo y el legítimo interés, no el consentimiento. En el tratamiento en el que 4Shark actúa como controlador, se recoge consentimiento donde la ley lo exige, en particular para cookies y analítica en el sitio web, mediante un mecanismo de consentimiento previo con registro.

### 19.6 — Marco de gestión del consentimiento (cuándo, de quién, contenido) ✅

**Respuesta**: `SÍ`

**Texto**: Para el consentimiento de cookies y analítica en el sitio web, el mecanismo registra el momento de la obtención, el ámbito de las categorías aceptadas y la posibilidad de revocación por el titular, con registro correspondiente. La actividad y su registro de consentimiento están documentados en el RoPA.

---

## Sección 20 — Terceros y proveedores

### 20.1 — Procedimiento de calificación de proveedores que evalúe requisitos de privacidad ⚠️

**Respuesta sugerida**: `NO` (procedimiento formal) — con la práctica descrita en la columna E. Paulo decide.

**Texto**: 4Shark no cuenta con un procedimiento independiente y formalizado de calificación de proveedores. En la práctica, la selección de proveedores para infraestructura crítica sigue el criterio de contratar exclusivamente proveedores de gran porte y reconocimiento internacional con certificaciones independientes vigentes — AWS, CloudFlare, GitHub, Google Workspace y 1Password, todos con SOC 2 Tipo II, ISO 27001 e ISO 27018, auditoría independiente continua y contratos con cláusulas formales de protección de datos. Los suboperadores están registrados en el RoPA y declarados en el DPA celebrado con cada cliente.

> ⚠️ Ítem P10 del gap analysis interno.

### 20.2 — DPA con el subencargado imponiendo las mismas obligaciones ✅

**Respuesta**: `SÍ`

**Texto**: 4Shark no subcontrata la prestación del servicio a terceros — el desarrollo, la operación y el soporte son íntegramente internos y nacionales. Los suboperadores existentes son exclusivamente los proveedores de infraestructura en la nube, con los cuales existen acuerdos de tratamiento de datos vigentes:
- **Amazon Web Services** (infraestructura, EE. UU.) — AWS Data Processing Addendum, con Cláusulas Contractuales Tipo.
- **CloudFlare** (capa perimetral) — Data Processing Addendum.
Todos están declarados en el RoPA y en el DPA celebrado con el cliente.

**Evidencia (col. F)**: RoPA (sección de suboperadores) · DPA.

> ⚠️ **Paulo confirma** las fechas de suscripción de cada acuerdo, si Atento las exige.

### 20.3 — Cumplimiento legal cuando el subencargado está fuera del territorio ✅

**Respuesta**: `SÍ` — ver ítem 16.4. La salvaguarda aplicada son las cláusulas contractuales específicas del AWS Data Processing Addendum, que incorpora las Cláusulas Contractuales Tipo, conforme al art. 33, II de la LGPD y a los mecanismos equivalentes de la normativa chilena.

### 20.4 — [Solo EE. UU.] Cláusulas CCPA/CPRA en los contratos con subcontratistas ✅

**Respuesta**: `N/A` — 4Shark está establecida en Brasil, no en los Estados Unidos.

---

## Sección 21 — Plan de respuesta a incidentes

### 21.1 — Plan de Respuesta a Incidentes que cubra identificación, evaluación de riesgo, plan de acción y notificación a la autoridad ✅

**Respuesta**: `SÍ`

**Texto**: La política interna de respuesta a incidentes de seguridad de la información cubre las cinco etapas del proceso — planificación, identificación, contención, erradicación y recuperación — con roles y responsabilidades definidos, flujo de escalamiento por severidad y criterios de clasificación. Incluye la identificación de incidentes que afecten datos personales, la evaluación del riesgo y del impacto sobre la privacidad, el establecimiento de un plan de acción mitigador, y la evaluación de la necesidad de notificación a la autoridad nacional de protección de datos y a los titulares afectados dentro de los plazos legales aplicables, además de la notificación al cliente. El proceso contempla registro, investigación con análisis de causa raíz, documentación e identificación de lecciones aprendidas.

**Evidencia (col. F)**: Política de Respuesta a Incidentes.

### 21.2 — Notificación a Atento en un plazo de 24 horas desde el conocimiento del impacto ⚠️

**Respuesta sugerida**: `SÍ` — **pero es una decisión contractual de Paulo, no un dato existente.**

**Texto**: El compromiso vigente de 4Shark, formalizado en el DPA y ofrecido a sus clientes, es de notificación **en hasta 72 horas** desde el conocimiento del incidente, alineado con el art. 48 de la LGPD y el art. 33 del RGPD. 4Shark puede asumir el plazo de **24 horas** para Atento mediante formalización en el acuerdo de tratamiento de datos.

> ⚠️ **Paulo decide**: comprometer las 24 horas (y actualizar el DPA para Atento) o responder `NO` manteniendo el compromiso vigente de 72 horas. Atento pregunta explícitamente por 24 horas; responder `SÍ` sin ajustar el DPA crearía una discrepancia entre lo declarado y lo contratado.

### 21.3 — Medidas para restablecer oportunamente la disponibilidad y el acceso tras un incidente ✅

**Respuesta**: `SÍ`

**Texto**: Sí — sustentado por la arquitectura de alta disponibilidad y por el plan de recuperación descrito en la sección 15: Aurora Multi-AZ con failover automático, ECS con auto-recuperación de contenedores, respaldo continuo con PITR más snapshots diarios, copia interregional, y objetivos declarados de RPO ≤ 1 hora y RTO de 4 horas, con pruebas de restauración automatizadas mensuales y un ejercicio anual completo.

### 21.4 — Procedimiento para prevenir y mitigar incidentes causados por error humano ✅

**Respuesta**: `SÍ`

**Texto**: La prevención del error humano está incorporada al diseño operativo:
- **Ningún cambio llega a producción sin revisión por pares** — revisión de código obligatoria más revisión de seguridad dedicada antes del merge, con ramas protegidas y reglas de aprobación obligatoria.
- **Toda la infraestructura y la concesión de permisos son código** — un cambio de permiso exige modificación en el repositorio bajo revisión, con traza auditable; no existe la concesión manual susceptible de error no revisado.
- **Menor privilegio por defecto** — las cuentas personales tienen solo lectura; el error de un colaborador no alcanza recursos que su cuenta no puede modificar.
- **Elevación temporal limitada a una hora** con MFA, y operaciones administrativas amplias restringidas a la cuenta break-glass con llave física.
- **Pruebas automatizadas** (unitarias y de integración) ejecutadas en cada pull request; el merge solo se aprueba con todas las pruebas en verde.
- **Segregación total de entornos** — la manipulación en desarrollo u homologación no alcanza datos productivos, que además nunca se copian a entornos inferiores.
- **Formación** de onboarding y reciclaje anual, con foco en gestión de credenciales, phishing e ingeniería social.

### 21.5 — Registro de los incidentes de seguridad que afectan datos personales ✅

**Respuesta**: `SÍ`

**Texto**: El registro de incidentes está previsto en la política de respuesta a incidentes, que exige el registro, la investigación con análisis de causa raíz y la documentación de lecciones aprendidas. **En 10 años de operación, 4Shark no ha registrado ningún incidente de seguridad con afectación de datos personales.** Los incidentes operativos (disponibilidad o rendimiento) se tratan mediante post-mortem con identificación de causa raíz y acciones correctivas documentadas.

### 21.6 — Plan de Continuidad del Negocio ✅

**Respuesta**: `SÍ` — ver ítem 15.1.

> ⚠️ **Paulo confirma** la fecha de aprobación del BCP para completar el dato que la pregunta solicita.

---

## Sección 22 — Gestión de los derechos de los titulares

### 22.1 — Procedimiento para gestionar solicitudes de ejercicio de derechos ✅

**Respuesta**: `SÍ`

**Texto**: 4Shark cuenta con un procedimiento operativo de atención de solicitudes de titulares, que cubre la recepción, la identificación del solicitante, el enrutamiento según el tipo de derecho ejercido (confirmación de tratamiento, acceso, corrección, anonimización, portabilidad, eliminación, información sobre compartición), la ejecución técnica y la respuesta al titular dentro del plazo legal aplicable. Cuando la solicitud alcanza datos tratados por cuenta de un cliente, 4Shark actúa como operador y encamina la solicitud al controlador, prestándole el apoyo técnico necesario. El procedimiento técnico de eliminación está documentado en un runbook con lista de verificación de PII residual, de modo que la eliminación se confirma antes de comunicarse al titular.

**Evidencia (col. F)**: Política de Privacidad (sección de derechos de los titulares) · procedimiento de atención de solicitudes de titulares.

> ⚠️ **Paulo confirma** el nombre y la fecha de publicación del procedimiento.

### 22.2 — Canal público para que los titulares ejerzan sus derechos ✅

**Respuesta**: `SÍ`

**Texto**: El canal está publicado en la Política de Privacidad, disponible públicamente en www.4shark.com.br: **privacidade-dados@4shark.com.br**, con identificación del Encargado de Protección de Datos (Paulo Ribeiro).

**Evidencia (col. F)**: Enlace a la Política de Privacidad · captura de pantalla de la sección de contacto.

---

## Sección 23 — Empleados

### 23.1 — Acuerdo de confidencialidad firmado, con obligación indefinida incluso tras la terminación ✅

**Respuesta**: `SÍ`

**Texto**: Todos los colaboradores de 4Shark firman un acuerdo de confidencialidad que los obliga a no divulgar información a la que tengan acceso durante la prestación de sus servicios, con vigencia indefinida y subsistencia tras la terminación de la relación laboral. El acuerdo forma parte del conjunto de políticas internas formalmente aprobadas y suscritas.

**Evidencia (col. F)**: Acuerdo de Confidencialidad (NDA) — modelo.

### 23.2 — Capacitación sobre obligaciones normativas de protección de datos ✅

**Respuesta**: `SÍ` — ver ítem 12.1. La formación de onboarding y el reciclaje anual cubren la normativa de protección de datos aplicable y las obligaciones de los colaboradores.

> ⚠️ **Paulo confirma** la fecha de la última sesión de formación, dato que la pregunta solicita en la columna E.

### 23.3 — Capacitación sobre medidas técnicas y organizativas de seguridad específicas ✅

**Respuesta**: `SÍ` — ver ítem 12.1. Los temas incluyen los principios de seguridad de la plataforma, la gestión de credenciales y el uso de la bóveda corporativa, las amenazas comunes y el proceso de respuesta a incidentes.

> ⚠️ **Paulo confirma** la fecha, igual que en 23.2.

### 23.4 — Campañas periódicas de concienciación sobre protección de datos ⚠️

**Respuesta sugerida**: `NO` (como campañas formales) — Paulo decide

**Texto**: 4Shark no ejecuta campañas de concienciación en el formato de una organización de gran porte. La concienciación se realiza mediante la formación de onboarding y el reciclaje anual, más la discusión de escenarios de seguridad e impacto operativo integrada al proceso de revisión de seguridad de cada nueva funcionalidad — lo que sitúa el tema en la rutina técnica en lugar de en un evento periódico separado.

### 23.5 — Comunicación efectiva de la Política de Privacidad y controles de verificación ✅

**Respuesta**: `SÍ`

**Texto**: Las políticas internas de privacidad y seguridad se comunican a todos los colaboradores y se suscriben formalmente en el momento de la incorporación, mediante un instrumento de acuse de conocimiento por documento (formato *Termo de Ciência*). La Matriz de Aplicabilidad define qué documento aplica a quién, lo que constituye el control de verificación de la cobertura. La Política de Privacidad externa está publicada en www.4shark.com.br.

**Evidencia (col. F)**: Matriz de Aplicabilidad.

---

## Sección 24 — Auditorías

### 24.1 — Auditorías de cumplimiento en protección de datos en los últimos 2 años ⚠️

**Respuesta sugerida**: `NO` (auditoría formal de privacidad) — Paulo decide

**Texto**: 4Shark no ha realizado una auditoría formal de cumplimiento en protección de datos por parte de un tercero independiente. Sí se han realizado, en el período: un **pentest** ejecutado por una empresa independiente especializada en seguridad ofensiva, con todos los hallazgos remediados y validados en retest; y evaluaciones de seguridad y privacidad conducidas por clientes corporativos (procesos de due diligence de proveedores) cuyos planes de mitigación fueron acordados y están en ejecución.

> ⚠️ Ítem P3 del gap analysis interno (procedimiento de auditoría interna + primer informe). **Paulo confirma** si el primer ciclo de auditoría interna ya se ejecutó — si es así, la respuesta cambia a `SÍ`.

### 24.2 — Implementación de las medidas correctivas identificadas por las auditorías, con revisión de eficacia ✅

**Respuesta**: `SÍ`

**Texto**: Todos los hallazgos del pentest fueron remediados y validados en un retest por la misma empresa independiente. Los planes de mitigación acordados con clientes en procesos de due diligence se ejecutan con seguimiento de plazos y se verifican al cierre de cada ítem.

---

## Sección 25 — Sanciones y penalidades

### 25.1 — ¿Sancionada por incumplimiento de normativa de protección de datos en los últimos 5 años? ✅

**Respuesta**: `NO`

**Texto**: 4Shark nunca ha sido sancionada por incumplimiento de normativa de protección de datos. En 10 años de operación no se ha registrado ningún incidente de fuga de datos ni comprometimiento de seguridad.

### 25.2 — ¿Involucrada actualmente en algún procedimiento sancionador ante una Autoridad de Control? ✅

**Respuesta**: `NO`

**Texto**: 4Shark no está involucrada en ningún procedimiento sancionador ante una autoridad de control o cualquier organismo competente. 4Shark no integra un grupo empresarial.

> ⚠️ **Paulo confirma** la afirmación sobre grupo empresarial antes del envío.

---

## Sección 26 — Certificaciones

### 26.1 — Certificación ISO 27001 ✅

**Respuesta**: `NO`

**Texto**: 4Shark no cuenta con certificación ISO 27001. La empresa adopta prácticas y controles alineados con ISO/IEC 27001 e ISO/IEC 27002, documentados en su conjunto de políticas internas de seguridad de la información, formalmente aprobadas por la dirección y con revisión anual prevista.

### 26.2 — Otra certificación relevante para el cumplimiento normativo ✅

**Respuesta**: `NO`

**Texto**: 4Shark no cuenta con certificaciones formales propias. Todos los proveedores de infraestructura crítica utilizados sí las poseen y son auditados de forma independiente y continua: **AWS** (SOC 1/2/3 Tipo II, ISO 27001, ISO 27017, ISO 27018), **CloudFlare** (SOC 2 Tipo II, ISO 27001), **GitHub** (SOC 2 Tipo II, ISO 27001), **Google Workspace** (SOC 2/3, ISO 27001, ISO 27017, ISO 27018) y **1Password** (SOC 2 Tipo II).

---

## Sección 27 — Inteligencia Artificial

> **Aplicabilidad**: la sección indica "Responder únicamente si se utiliza IA en los servicios prestados".

### 27.1 a 27.8 ⚠️

**Respuesta sugerida**: `N/A` para toda la sección.

**Texto**: La plataforma 4Shark entregada a Atento **no utiliza Inteligencia Artificial** en la prestación del servicio. El procesamiento realizado es determinístico — cálculo de resultados según reglas de negocio configuradas por el cliente — sin modelos de aprendizaje automático, inferencia estadística ni decisiones automatizadas basadas en IA. No existen decisiones automatizadas con efectos sobre los titulares derivadas de IA. Por lo tanto, la sección no resulta aplicable.

> ⚠️ **Paulo confirma** que ninguna funcionalidad entregada al cliente incorpora IA. Nota: el uso de herramientas de IA en el proceso interno de desarrollo (asistentes de codificación) **no** es "IA en los servicios prestados" y no cambia la respuesta — pero conviene tenerlo claro por si Atento repregunta.

---

## Bloque de controles de dispositivo de usuario final — postura y texto de respuesta

Nueve ítems del cuestionario (1.1, 1.2, 4.3, 4.5, 5.4, 9.1, 9.2, 10.1, 10.2) evalúan la gestión del parque de estaciones de trabajo. Comparten una misma justificación, y por eso se tratan aquí en conjunto.

**El argumento del tamaño de la compañía NO sirve como justificación, y no debe usarse.** Las salvaguardas que estos ítems reproducen — inventario de activos (1.1), firewall en dispositivo de usuario final (4.5), filtrado DNS (9.2), antimalware (10.1) — pertenecen todas al **Implementation Group 1** de los CIS Controls v8.1, el nivel que el propio CIS define como *"essential cyber hygiene"* y describe como dirigido a una empresa *"typically small to medium-sized with limited IT and cybersecurity expertise"*. Un revisor de seguridad que conozca el marco responderá exactamente eso a un argumento de tamaño: IG1 existe para una empresa de este porte. La justificación tiene que apoyarse en el **riesgo mitigado**, no en el número de empleados.

**El argumento que sí se sostiene: el dispositivo no es la frontera de confianza en 4Shark, y la población con acceso privilegiado es nominada y acotada.** Cada una de estas salvaguardas mitiga el mismo riesgo — que una estación de trabajo comprometida o no gestionada se convierta en una vía de acceso a los datos corporativos o del cliente. En 4Shark esa vía está cerrada por controles de identidad y de red, no por controles de dispositivo, y el conjunto de personas que puede recorrerla está identificado individualmente.

El acceso se organiza en dos planos, y la respuesta debe declarar los dos:

- **Infraestructura y bases de datos productivas — dos personas nominadas** de la Dirección Técnica, que constituyen la totalidad de la población con esa capacidad. Ese acceso exige, de forma acumulativa: identidad en el proveedor corporativo con MFA obligatorio, conexión VPN, permiso de solo lectura por defecto en la nube, elevación temporal vía MFA limitada a una sesión de una hora para cualquier acción de mutación, y llave física (YubiKey) para operaciones administrativas amplias. Cada permiso concedido está declarado como código en Terraform, con trazabilidad por commit.
- **Aplicación — la totalidad del equipo**, con credencial individual e intransferible, en modo de solo lectura para las funciones de soporte y con la visibilidad acotada por el modelo jerárquico de permisos de la plataforma. Sin acceso a infraestructura, a la base de datos ni a credenciales productivas.

Los controles que sustentan ambos planos:

- El acceso a cualquier sistema corporativo exige identidad en Google Workspace con **MFA obligatorio**, que actúa como proveedor de SSO central.
- El acceso a la infraestructura interna y a las bases de datos productivas exige **VPN**; la base de datos no es accesible directamente desde el dispositivo del colaborador — el acceso pasa por un servidor dedicado dentro de la red privada del sistema correspondiente.
- Las cuentas personales operan con **permiso de solo lectura por defecto** en AWS; cualquier acción de mutación exige elevación temporal vía MFA limitada a una sesión de una hora.
- Las operaciones administrativas amplias exigen una **cuenta break-glass operada exclusivamente mediante llave física YubiKey**, bajo custodia de la dirección técnica.
- Los **datos del cliente residen en Amazon Aurora dentro de la VPC**, y se acceden a través de la aplicación. La estación de trabajo no es un repositorio autorizado de datos de cliente; los archivos generados por funcionalidades de extracción se descartan automáticamente a las 48 horas.
- No existe una **red corporativa** a la que un dispositivo no autorizado pueda conectarse y desde ahí alcanzar datos: 4Shark no opera oficina con red propia ni infraestructura on-premises — todo es SaaS y AWS detrás de identidad.

La consecuencia práctica: la pérdida o el compromiso de una estación de trabajo de 4Shark no produce por sí sola acceso a datos productivos ni a datos de cliente. Ese es el hecho que la respuesta debe transmitir.

**Texto de respuesta para la columna E (aplicable a los ítems que se respondan `NO`)**:

> 4Shark no opera una plataforma de gestión centralizada de dispositivos de usuario final (MDM) ni un inventario formal de estaciones de trabajo. El riesgo que este control mitiga se aborda mediante controles de identidad y de red: el acceso a cualquier sistema corporativo exige autenticación en el proveedor de identidad corporativo con MFA obligatorio; el acceso a la infraestructura interna y a las bases de datos productivas exige adicionalmente VPN y no es posible directamente desde el dispositivo del colaborador; las cuentas personales operan con permiso de solo lectura por defecto, con elevación temporal vía MFA limitada a una sesión de una hora; y las operaciones administrativas amplias exigen una cuenta dedicada operada mediante llave física (MFA por hardware). Los datos de cliente residen exclusivamente en la base de datos gestionada dentro de la nube privada virtual y se acceden a través de la aplicación — la estación de trabajo no es un repositorio autorizado de datos de cliente. 4Shark no opera red corporativa ni infraestructura on-premises. En consecuencia, el compromiso de una estación de trabajo no produce por sí solo acceso a datos productivos o de cliente. Todos los colaboradores suscriben un acuerdo de confidencialidad de vigencia indefinida y reciben formación en seguridad de la información en la incorporación, con reciclaje anual.

**Los ítems que este texto NO debe cubrir.** Cuatro de los nueve corresponden a controles nativos del sistema operativo que pueden activarse y verificarse de inmediato, y responderlos `SÍ` con veracidad es preferible a justificar un `NO`: bloqueo automático de sesión (4.3), firewall del sistema operativo en la estación de trabajo (4.5), protección antimalware nativa (10.1) y actualización automática del navegador (9.1). El ítem 10.2 (autoplay de medios extraíbles) describe una función del sistema operativo Windows; en macOS corresponde `N/A`. Verificar y, en su caso, activar esos controles en cuatro máquinas es una tarea acotada — sustancialmente menor que el costo de sostener la justificación de un `NO` frente a un revisor.

## Resumen del estado

| Estado | Cantidad | Significado |
|---|---|---|
| ✅ Listo | ~62 | Respuesta sustentada; solo revisar y pegar |
| ⚠️ Confirmar | ~26 | Borrador listo; Paulo confirma un dato o toma una decisión |
| ❌ Sin base | ~9 | Paulo responde desde cero (controles de endpoint, principalmente) |

**Los ❌ se concentran en un solo tema**: controles de dispositivo de usuario final — inventario de activos y MDM (1.1, 1.2), bloqueo de pantalla (4.3), firewall de host (4.5), cuentas inactivas (5.4), versión de navegador (9.1), filtrado DNS (9.2), antimalware (10.1), autoplay (10.2). Ninguno de los formularios anteriores lo cubrió, porque ni Barigui ni Positivo preguntaron por la capa de endpoint. Este cuestionario está construido sobre CIS Controls v8, que sí la cubre exhaustivamente. La postura y el texto de respuesta para todo el bloque están en la sección anterior.

**Las decisiones que solo Paulo puede tomar**, en orden de peso:

1. **21.2 — notificación en 24 horas.** El compromiso vigente en el DPA es de 72 horas. Responder `SÍ` obliga a ajustar el DPA para Atento.
2. **3.9 — pentest en los últimos 6 meses.** La respuesta depende de la fecha real del ejercicio, no de su existencia.
3. **8.1 / 8.2 — eventos de autenticación persistidos.** Si la `security-events-platform` ya está en producción, dos respuestas se refuerzan y se cierra un compromiso pendiente con tres clientes.
4. **La capa de endpoint completa** — decidir entre responder `NO` con la justificación compensatoria (postura honesta, coherente con el tamaño y el modelo de acceso de 4Shark) o levantar los controles antes de responder.

---

## Anexos (columna F)

Documentos que pueden adjuntarse como evidencia, según lo que Paulo autorice compartir:

| # | Documento | Sustenta los ítems |
|---|---|---|
| 1 | Política de Seguridad de la Información (paraguas) | 16.1, 17.1 |
| 2 | Política de Identidad y Acceso | 6.1, 6.2 |
| 3 | Procedimiento de Ciclo de Vida de Identidad | 6.1, 6.2 |
| 4 | Política de Contraseñas | 5.3 |
| 5 | Política de Desarrollo Seguro | 7.1, 21.4 |
| 6 | Política de Copias de Seguridad | 11.1, 11.2 |
| 7 | Política de Almacenamiento, Anonimización y Descarte | 3.3, 3.4, 19.1, 19.4 |
| 8 | Política de Respuesta a Incidentes | 14.3, 21.1 |
| 9 | Política de Continuidad del Negocio y Recuperación ante Desastres | 11.1, 15.1, 21.6 |
| 10 | Política de Privacidad desde el Diseño | 18.6 |
| 11 | Política de Tratamiento de Datos Personales | 16.1 |
| 12 | Declaración de No Tratamiento de Datos Sensibles | 16.2 |
| 13 | Acuerdo de Confidencialidad (NDA) — modelo | 23.1 |
| 14 | Política de Programa de Concienciación | 12.1 |
| 15 | RoPA — Registro de Operaciones de Tratamiento | 3.1, 16.4, 18.1, 18.2, 19.1, 20.2 |
| 16 | DPA — Acuerdo de Tratamiento de Datos | 16.4, 16.5, 20.2 |
| 17 | Matriz de Aplicabilidad | 17.1, 23.5 |
| 18 | Política de Privacidad (pública) | 17.4, 22.1, 22.2 |
| 19 | Diagrama de arquitectura | 19.1 |
| 20 | Registro de pruebas de restauración (evidencia AWS Backup) | 15.3 |
| 21 | Resumen ejecutivo del pentest (bajo NDA) | 3.9, 24.1 |
