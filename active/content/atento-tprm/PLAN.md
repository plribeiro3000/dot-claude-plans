# Atento TPRM Questionnaire — Approved Answers

Record of the item-by-item review. Each answer was approved by the engineer in conversation and is
recorded here with the question, the verdict, the justification as it goes into the cell, and the
reasoning behind the corrections made to the vendor-template text.

All 119 items are reviewed — 90 `SÍ`, 18 `NO`, 11 `N/A`. The workbook
`~/Downloads/4Shark_Atento_TPRM_Questionnaire_respondido_20260818.xlsx` is written once, from this
file, with the yellow working highlight dropped. `TASKS.md` § "The gate before the workbook is
written" names the four things that must be settled before that write.

Source of the questions: sheet `Information Security & Privacy`, 119 items.

Answer values must be exactly `SÍ`, `NO` or `N/A` — column D carries a validation list and the
accent on `SÍ` is required.

## Sequence

The answers describe the target state. The engineer reviews them with the partners, the controls
they describe get applied, and the questionnaire is sent after that — not before. The section
"Controls to apply before sending" below is the list that follows from the answers written here.

## Review principle

The control is often not met in the terms the question describes, and saying so plainly is the
answer. What follows the negative is the set of controls 4Shark operates, stated as facts and kept
short: a long justification reads as evasion to the assessor, which is the opposite of the intent.

Four constraints the engineer set, each from a correction made during the review:

- **Never assert a control that does not exist.** Session renewal was described as absent; the
  platform has a session-extension feature. State only what was asked.
- **State the general case first.** Most of the team reaches only the application. Infrastructure
  access belongs to engineering and reads as the exception, never as how the company works.
- **Never disclose headcount or how many people hold an access.** The key custody is stated as one
  person because that is a fact about the key, not a count of the team.
- **Length is a signal.** The strongest argument is the encryption key: the data is unreadable
  without it regardless of device, permission or credential. That fits in one line and belongs at
  the end, not buried.
- **Each answer earns its own sentences.** The assessor reads the items in sequence, so a paragraph
  reused from an earlier answer reads as padding twice over — and the opening formula repeated item
  after item reads as a template. Answer what *this* question asks and let the neighbouring items
  carry what they already said.
- **The justification never restates the verdict.** Column D already carries `SÍ` or `NO`, so a
  sentence in column E announcing that the answer is negative spends a line saying what the reader
  just read. State the fact — what does not exist — and move on to what does.

## Controls to apply before sending

`TASKS.md` carries them, grouped by who has to be involved — the partner conversation, the
engineering work, and the facts still to confirm. Each entry there names the questionnaire items it
blocks, so an answer written here can be traced to the action that makes it true, and its last
section separates what gates the workbook WRITE from what gates the SENDING.

## Status

| Item | Answer | State |
|---|---|---|
| 1.1 | NO | approved |
| 1.2 | N/A | approved |
| 2.1 | NO | approved |
| 2.2 | NO | approved |
| 2.3 | SÍ | approved — target state |
| 3.1 | SÍ | approved — classification paragraph conflicts with 19.1, engineer to decide |
| 3.2 | SÍ | approved — homologação synthetic-data confirmation open |
| 3.3 | SÍ | approved — Mexico/Colombia 3680-day legal check open |
| 3.4 | SÍ | approved |
| 3.5 | SÍ | approved |
| 3.6 | SÍ | approved |
| 3.7 | NO | approved |
| 3.8 | SÍ | approved |
| 3.9 | SÍ | approved — figures to verify against the report |
| 4.1 | SÍ | approved — target state |
| 4.2 | SÍ | approved |
| 4.3 | SÍ | approved — target state |
| 4.4 | SÍ | approved |
| 4.5 | SÍ | approved — target state |
| 4.6 | SÍ | approved |
| 4.7 | SÍ | approved |
| 5.1 | NO | approved — flipped from the workbook's SÍ |
| 5.2 | NO | approved |
| 5.3 | SÍ | approved |
| 5.4 | NO | approved |
| 5.5 | SÍ | approved — target state |
| 6.1 | SÍ | approved |
| 6.2 | SÍ | approved |
| 6.3 | SÍ | approved |
| 6.4 | SÍ | approved |
| 6.5 | SÍ | approved — target state |
| 7.1 | SÍ | approved |
| 7.2 | SÍ | approved |
| 7.3 | SÍ | approved |
| 7.4 | SÍ | approved |
| 8.1 | SÍ | approved — target state |
| 8.2 | SÍ | approved |
| 8.3 | SÍ | approved |
| 9.1 | SÍ | approved |
| 9.2 | NO | approved |
| 10.1 | SÍ | approved |
| 10.2 | SÍ | approved |
| 11.1 | SÍ | approved — target state |
| 11.2 | SÍ | approved |
| 11.3 | SÍ | approved |
| 11.4 | SÍ | approved |
| 11.5 | SÍ | approved |
| 12.1 | SÍ | approved |
| 12.2 | SÍ | approved |
| 12.3 | SÍ | approved |
| 12.4 | SÍ | approved |
| 12.5 | SÍ | approved |
| 12.6 | SÍ | approved |
| 12.7 | SÍ | approved |
| 12.8 | SÍ | approved |
| 13.1 | SÍ | approved — verdict changed from NO once compliance PR #13 merged |
| 14.1 | SÍ | approved |
| 14.2 | SÍ | approved |
| 14.3 | SÍ | approved |
| 15.1 | SÍ | approved |
| 15.2 | SÍ | approved |
| 15.3 | SÍ | approved |
| 15.4 | SÍ | approved |
| 16.1 | SÍ | approved |
| 16.2 | N/A | approved |
| 16.3 | NO | approved |
| 16.4 | SÍ | approved |
| 16.5 | SÍ | approved |
| 17.1 | SÍ | approved |
| 17.2 | SÍ | approved |
| 17.3 | NO | approved |
| 17.4 | SÍ | approved |
| 17.5 | SÍ | approved |
| 17.6 | SÍ | approved |
| 17.7 | SÍ | approved |
| 17.8 | NO | approved — verdict changed from N/A |
| 18.1 | SÍ | approved |
| 18.2 | SÍ | approved |
| 18.3 | NO | approved |
| 18.4 | NO | approved — rewritten after the methodology landed |
| 18.5 | SÍ | approved — verdict changed from NO |
| 18.6 | SÍ | approved |
| 19.1 | SÍ | approved |
| 19.2 | SÍ | approved |
| 19.3 | SÍ | approved |
| 19.4 | SÍ | approved — `[FECHA]` marker survives to the final write |
| 19.5 | SÍ | approved |
| 19.6 | SÍ | approved |
| 20.1 | SÍ | approved — verdict changed from NO once compliance PR #13 merged |
| 20.2 | SÍ | approved |
| 20.3 | SÍ | approved |
| 20.4 | N/A | approved |
| 21.1 | SÍ | approved |
| 21.2 | SÍ | approved — 24h commitment, no mention of the 72h standard |
| 21.3 | SÍ | approved |
| 21.4 | SÍ | approved |
| 21.5 | SÍ | approved |
| 21.6 | SÍ | approved — `[FECHA]` marker |
| 22.1 | SÍ | approved — `[FECHA]` marker; enabled by compliance PR #14 |
| 22.2 | SÍ | approved |
| 23.1 | SÍ | approved |
| 23.2 | SÍ | approved — `[FECHA]` from the training register |
| 23.3 | SÍ | approved — same training date |
| 23.4 | SÍ | approved — verdict changed from NO |
| 23.5 | SÍ | approved |
| 24.1 | NO | approved — dates optional, engineer's call |
| 24.2 | SÍ | approved |
| 25.1 | NO | approved |
| 25.2 | NO | approved — group-structure claim removed as false |
| 26.1 | NO | approved |
| 26.2 | NO | approved |
| 27.1 | N/A | approved |
| 27.2 | N/A | approved |
| 27.3 | N/A | approved |
| 27.4 | N/A | approved |
| 27.5 | N/A | approved |
| 27.6 | N/A | approved — organisation-scoped, engineer chose the platform-scoped answer |
| 27.7 | N/A | approved — same decision as 27.6 |
| 27.8 | N/A | approved — same decision as 27.6 |

All 119 items reviewed.

### Vendor-template claims that must not reach the workbook

Three claims sit in the workbook's own cells for items 3.2 and 3.3 and must be overwritten by the
approved text, because each was examined and found false:

- **`sin mecanismo de renovación`** (3.2) — the platform has a session-extension feature. The
  session's one-hour absolute expiry is the fact; the absence of renewal is not, and nothing
  replaces it.
- **`registrados en el RoPA`** (3.3) — the claim was written when no RoPA was reachable. One exists
  now in `compliance/records/`, so the mention may return, but the approved text does not carry it.
- **`hasta 5 años y 1 mes`** as a single global figure (3.3) — retention is per country.

## 1.1

**Question** — ¿Su organización establece y mantiene un inventario preciso, detallado y actualizado
de todos los activos de la compañía con capacidad para almacenar o procesar datos? El inventario
debe registrar dirección de red, dirección de hardware, nombre del equipo, propietario,
departamento y aprobación para conectarse a la red corporativa, y revisarse cada seis meses.

**Answer** — NO

**Justification**

4Shark no mantiene un inventario de dispositivos con dirección de hardware, nombre de equipo y aprobación de conexión. El control se ejerce sobre el acceso y sobre el dato, no sobre el dispositivo.

El equipo accede a los datos únicamente a través de la aplicación, con credencial individual, permisos de denegación por defecto y jerárquicos, sesión con expiración de una hora y sin exportación masiva. El acceso a la infraestructura está reservado a ingeniería, exige VPN y alcanza sólo el entorno de homologación, que opera con datos de prueba; los entornos productivos están restringidos a la Dirección Técnica. Ninguna estación de trabajo es repositorio autorizado de datos de cliente.

Los datos residen exclusivamente en la base gestionada dentro de la nube privada virtual, cifrados, con la clave del entorno productivo bajo custodia de una única persona: sin esa clave el dato es ilegible, con independencia del dispositivo, del permiso o de la credencial que se obtenga. La separación entre entornos es criptográfica, no una configuración de permisos.

Todo acceso depende de la cuenta del proveedor de identidad con MFA obligatorio; su revocación retira el acceso a todos los recursos desde cualquier equipo, sin depender de recuperar el dispositivo físico. 4Shark no opera red corporativa ni infraestructura on-premises: no hay red a la que un dispositivo pueda conectarse para alcanzar datos.

## 1.2

**Question** — ¿Su organización garantiza que exista un proceso establecido para gestionar los
activos no autorizados de forma periódica (al menos semanalmente)?

**Answer** — N/A

**Justification**

El control presupone una red corporativa de la que un activo no autorizado pueda ser retirado o aislado. 4Shark no opera red corporativa ni infraestructura on-premises: no existe red de la que retirar un dispositivo, ni acceso que se obtenga por estar conectado a ella.

El acceso depende siempre de una identidad autenticada en el proveedor corporativo con MFA obligatorio, y la infraestructura exige además VPN. Un dispositivo no autorizado no alcanza ningún recurso, con independencia de la red desde la que se conecte. El equivalente que 4Shark sí ejerce es la revocación de la identidad, que retira el acceso desde cualquier dispositivo en el momento de la desvinculación.

## 2.1

**Question** — ¿Su organización establece y mantiene un inventario detallado de todo el software con
licencia instalado en los activos corporativos, con proveedor, fecha de instalación y propósito de
negocio, revisado semestralmente?

**Answer** — NO

**Justification**

No existe un inventario de software instalado con proveedor, fecha de instalación y propósito de negocio.

El alcance que el control describe es reducido en 4Shark porque el trabajo no depende de software instalado. El equipo opera sobre la aplicación web y sobre las herramientas en la nube, accesibles por navegador; no hay software de negocio que instalar en la estación de trabajo. Las licencias que sí existen — el sistema operativo, adquirido con el equipo, y la suite ofimática, contratada y asignada por 4Shark — están controladas por la compañía.

En las estaciones de trabajo los usuarios operan sin privilegio administrativo y no pueden instalar software. La instalación se realiza únicamente mediante la cuenta administrativa, bajo custodia exclusiva de la Dirección Técnica: no es posible instalar software que exija elevación, modificar el sistema operativo, instalar controladores ni cargar código en el núcleo del sistema.

## 2.2

**Question** — ¿Su organización garantiza que únicamente el software actualmente soportado sea
designado como autorizado, con excepciones documentadas y revisión mensual?

**Answer** — NO

**Justification**

No existe una lista de software autorizado con revisión mensual de estado de soporte.

La plataforma de 4Shark es una aplicación web alojada en la nube. El usuario final no instala ni actualiza nada: accede por navegador y siempre a la versión vigente, de modo que en las estaciones de trabajo no hay software de negocio cuyo estado de soporte controlar. El sistema operativo y la suite ofimática son versiones soportadas por sus fabricantes, con actualización automática activa.

El mantenimiento de versiones es responsabilidad del equipo de ingeniería y se ejerce sobre la plataforma, no sobre el equipo del usuario. Las dependencias de la aplicación se actualizan de forma continua mediante propuestas de cambio abiertas automáticamente tras cada publicación, sujetas a un período mínimo de maduración antes de poder incorporarse y a revisión de código obligatoria. El sistema operativo de los servidores y el motor de base de datos son servicios gestionados por el proveedor de nube, con parcheo bajo su responsabilidad. No hay software fuera de soporte en producción.

## 2.3

**Question** — ¿Su organización garantiza que el software no autorizado sea retirado del uso en los
activos corporativos o que cuente con una excepción documentada, con revisión mensual?

**Answer** — SÍ

**Justification**

En las estaciones de trabajo los usuarios operan sin privilegio administrativo y no pueden instalar software. La instalación se realiza únicamente mediante la cuenta administrativa, bajo custodia exclusiva de la Dirección Técnica, de modo que ningún componente entra en un equipo corporativo fuera de esa vía: el software no autorizado no llega a instalarse. La verificación mensual confirma que lo instalado sigue correspondiendo a lo autorizado.

En el entorno productivo las cargas de trabajo son contenedores efímeros, reconstruidos en cada despliegue a partir de imágenes versionadas y sin acceso interactivo. Ningún componente entra en la aplicación fuera del proceso de revisión de código, y cualquier alteración del sistema de archivos se descarta en el ciclo siguiente.

**Notes** — the verdict rests on the install-privilege removal recorded in `TASKS.md`: once the
standard account cannot install anything, unauthorized software cannot appear, so the control holds
itself rather than depending on someone remembering to look. The monthly verification the question
asks for becomes a confirmation rather than a hunt, which is what makes this one of the two items
worth flipping.

## 3.1

**Question** — ¿Su organización establece y mantiene un inventario de datos basado en el proceso de
gestión de datos de la compañía, incluyendo como mínimo los datos confidenciales? Revise y
actualice el inventario al menos de forma anual, dando prioridad a los datos confidenciales.

**Answer** — SÍ

**Justification**

El inventario de los datos que 4Shark trata es el esquema de la base de datos, declarado como código y versionado: cada campo que existe en producción está allí, con su tipo y su tabla, y ninguno puede crearse sin pasar por una migración revisada y registrada. El inventario coincide con el estado real por construcción, sin depender de una revisión periódica para estar al día.

La clasificación de la información es un dominio gobernado por la Política de Seguridad de la Información, que la delega en políticas específicas: el almacenamiento, la retención, la anonimización y el descarte constan en la Política de Almacenamiento, Anonimización y Descarte de Datos; el dato personal y el dato personal sensible tienen cada uno su política propia; y las credenciales de acceso se rigen por la Política de Contraseñas y la Política de Desarrollo Seguro.

Los datos confidenciales de cliente residen exclusivamente en la base gestionada dentro de la nube privada virtual, cifrados; las demás capas del sistema operan sobre identificadores internos y no persisten datos personales.

**Notes** — schema-as-code is literally a data inventory: always current, with history, and no field
reaches production without a reviewed migration. That is the argument, and it is what carries the
`SÍ`. The RoPA mention from the vendor template was cut at the time because no RoPA was reachable;
one exists now in `compliance/records/`, so the mention can return if it strengthens the cell.

**The classification paragraph states the governance, not a type taxonomy, and the distinction is
verified rather than assumed.** `compliance/internal/politica-de-seguranca-da-informacao-e-cibernetica.md:18`
lists *"Classificação, retenção, anonimização e descarte da informação"* as a governed domain and
delegates it to the Política de Armazenamento, Anonimização e Descarte; the two lines below it
delegate personal data and sensitive personal data to their own policies. So classification IS
governed and the answer says where each rule lives.

What the document set does **not** carry is a six-type taxonomy with per-type handling, access,
storage, retention and disposal rules — the shape the vendor-template text asserted. The storage
policy has three sections (armazenamento, retenção, anonimização) and no type list, and a repository
search finds `código-fonte` only as the subject of a rule ("do not store secrets in it"), never as a
classified type. Naming where each rule lives answers the question better than a list would, and it
holds against a document request.

## 3.2

**Question** — ¿Su organización configura listas de control de acceso a los datos en función del
principio de necesidad de conocer de cada usuario? Aplique listas de control de acceso a los datos,
también conocidas como permisos de acceso, a sistemas de archivos locales y remotos, bases de datos
y aplicaciones.

**Answer** — SÍ

**Justification**

El acceso a los datos se controla en tres planos.

En la aplicación, el modelo de permisos es de denegación por defecto y jerárquico: cada usuario ve exclusivamente los datos de su posición en la estructura organizativa y de las posiciones subordinadas, según el perfil atribuido. El equipo accede a los datos únicamente por esta vía, en modo de consulta.

En la infraestructura, las cuentas personales tienen permiso de solo lectura por defecto, y toda la concesión de permisos y roles se gestiona como código, con revisión obligatoria y trazabilidad por commit. El acceso exige VPN y alcanza sólo el entorno de homologación; los entornos productivos están restringidos a la Dirección Técnica.

En el dato productivo el control no es una política de permisos sino la custodia de la clave de cifrado, bajo responsabilidad de una única persona. La separación entre entornos es criptográfica, no declarativa: sin la clave productiva el dato es ilegible con independencia de cualquier permiso concedido.

**Notes** — this is the answer carrying the questionnaire's central argument, stated in three layers:
hierarchical permission in the application, least privilege as code in the infrastructure, and the
encryption key on production data. Same thesis as 1.1 and 1.2 seen from the affirmative side. Three
corrections against the vendor template: `sin mecanismo de renovación` went (the platform has session
extension — the 1.1 correction), the product names went, and `datos sintéticos` went because it could
not be confirmed. **Open for the engineer**: whether homologation ever receives a copy of production
data. If it never does, the synthetic-data claim returns — it is a strong statement and worth making
if true.

## 3.3

**Question** — ¿Su organización conserva los datos de conformidad con el proceso de gestión de datos
de la compañía? La retención de datos debe incluir períodos mínimos y máximos de conservación.

**Answer** — SÍ

**Justification**

Los períodos de retención están definidos en la Política de Almacenamiento, Anonimización y Descarte de Datos y parametrizados por jurisdicción en la propia plataforma: cada país tiene su ventana de conservación, derivada de la legislación de protección de datos y del período de prescripción aplicables en él, y el sistema aplica a cada titular la ventana del país cuya legislación rige su relación.

Cumplido ese plazo desde la desactivación del titular, sus datos personales son anonimizados de forma automática e irreversible, sin depender de una ejecución manual. A modo de referencia, la ventana aplicable en Brasil es de 5 años y 1 mes.

Los archivos generados por funcionalidades de extracción se descartan automáticamente 48 horas después de su generación. Las copias de seguridad tienen retención de 7 días en la región primaria y 7 días en la región de recuperación ante desastres.

**Notes** — retention is **per jurisdiction**, and that is what the answer had to say. The window is
an `anonymizing_window_days` column on the countries table, and the anonymisation workers filter by
`retention_jurisdiction_country_id` — so the period is an attribute of the jurisdiction, not a global
constant. Brazil is 1855 days (5 years and 1 month), Mexico and Colombia 3680 days, each set by its
own migration. A single figure would have been a visible error for a client operating in Brazil,
Chile, Mexico and Colombia — it would announce that retention ignores jurisdiction. **Only Brazil is
cited as a reference**: 3680 days is what the code holds, but whether it is the legally correct period
for Mexico and Colombia is unconfirmed, and asserting a wrong statutory period in a compliance
questionnaire is worse than not citing one. `sin depender de una ejecución manual` was added because
it is true (`Company::Anonymizer` runs on cron) and is what separates a written policy from a working
control. The backup figures were verified rather than carried over:
`modules/app/rds.tf:78,112` (`backup_retention_period = 7`) and
`modules/cross_region_backup/variables.tf:25,31` (`local_retention_days` and
`destination_retention_days`, both default 7), with the DR vault and the daily cross-region copy plan
existing in that module. **Caveat**: those are module defaults; a stack passing a different value
changes its own environment's number, and the calls were not checked one by one.

**Open for the engineer**: whether 3680 days is legally correct for Mexico and Colombia. If it is, all
three countries get cited instead of Brazil alone.

## 3.4

**Question** — ¿Su organización elimina los datos de forma segura, según lo descrito en el proceso
de gestión de datos de la compañía? Asegúrese de que el proceso y el método de eliminación sean
proporcionales a la sensibilidad de los datos.

**Answer** — SÍ

**Justification**

La eliminación se ejecuta mediante anonimización irreversible de todos los identificadores del titular — nombre, correo electrónico, documento de identificación y demás identificadores suministrados — sin posibilidad de reversión y con registro auditable.

Los datos personales se almacenan exclusivamente en la base de datos relacional; las demás capas del sistema operan sobre identificadores internos y no persisten datos personales, de modo que la eliminación alcanza un único repositorio conocido. Los documentos adjuntos se eliminan del almacenamiento de objetos.

El proceso está documentado en un procedimiento operativo con lista de verificación de datos personales residuales, que se ejecuta antes de declarar concluida cualquier eliminación solicitada.

## 3.5

**Question** — ¿Su organización implementa medidas de cifrado para proteger los datos en reposo, en
tránsito y durante el almacenamiento? En caso afirmativo, proporcione comentarios adicionales sobre
cómo se implementan dichas medidas, incluidos los protocolos y algoritmos utilizados.

**Answer** — SÍ

**Justification**

**En tránsito:** TLS 1.2 o superior obligatorio en todas las comunicaciones externas, impuesto en la capa perimetral; las versiones inseguras (SSL 3.0, TLS 1.0, TLS 1.1) están deshabilitadas. Los certificados se gestionan con renovación automática y monitoreo continuo de validez.

**En reposo:** AES-256 en la base de datos relacional, en el almacenamiento de objetos y en el gestor de parámetros. La clave es propia de 4Shark y dedicada por entorno — no una clave compartida del proveedor de nube: la política de acceso a la clave la define 4Shark, su uso queda registrado en el rastro de auditoría, y la separación entre entornos es criptográfica, no una configuración de permisos. La rotación de la clave está habilitada de forma automática.

**Copias de seguridad:** AES-256 bajo la misma clave dedicada, tanto en la región primaria como en la copia interregional.

**Credenciales:** almacenadas cifradas en el gestor de parámetros del proveedor de nube y en la bóveda corporativa, nunca en código fuente.

**Contraseñas de usuario:** hash criptográfico bcrypt con factor de coste 11 más pepper, almacenamiento irreversible y no reversible por diseño.

**Notes** — the algorithm and the key custody are separate axes, and the answer carries both because
the question asks for the algorithm by name. A dedicated key does not replace AES-256; the data stays
AES-256 either way and what the dedicated key changes is who controls decryption, who can revoke it,
and whether key use appears in the audit trail. Verified: `min_tls_version = "1.2"`
(`dns/security_4sharkpay_com.tf:8`); `storage_encrypted = true` with a per-stack key
(`modules/app/rds.tf:83-84`, key minted at `modules/app/kms.tf:302`); no
`customer_master_key_spec` is set, so the key is `SYMMETRIC_DEFAULT` — AES-256-GCM;
`enable_key_rotation = true`; bcrypt cost 11 (`app/config/initializers/devise.rb:112-117`).

The credentials line describes the target state: the Devise pepper is committed in plaintext at
`app/config/initializers/devise.rb:120`, so "nunca en código fuente" becomes true only after the
action recorded in `TASKS.md`.

## 3.6

**Question** — ¿La solución SaaS procesará, almacenará o transmitirá datos sensibles como
Información de Identificación Personal (PII), Información de Salud Protegida (PHI) u otros datos
confidenciales?

**Answer** — SÍ

**Justification**

La solución procesa datos personales de identificación y contacto de los colaboradores del cliente: nombre, correo corporativo, documento de identificación nacional, identificador interno de registro del cliente, cargo y posición jerárquica, además de área, unidad y localidad de actuación. Procesa asimismo datos de desempeño y de remuneración variable, y metadatos de conexión generados por el propio acceso — fecha, hora y dirección IP de inicio de sesión.

No se procesa ninguna categoría de dato personal sensible: ni datos de salud, ni datos genéticos o biométricos, ni origen racial o étnico, convicciones religiosas o filosóficas, opiniones políticas, afiliación sindical o datos sobre la vida sexual. Tampoco se procesan datos de cuentas bancarias ni de medios de pago: los importes de remuneración variable se calculan y se transmiten al sistema del propio cliente, que es quien ejecuta el pago.

**Notes** — the enumeration is drawn from the schema rather than from the vendor template, because
an incomplete list is worse than a general one: an assessor who finds an undeclared field treats
every other answer as possibly incomplete. Location (`users.city`, `users.state_id`), the client's
internal register identifier (`users.unique_register_id` with `register_type`) and sign-in IP
(`users.current_sign_in_ip`, `users.last_sign_in_ip`) are declared for that reason.

No bank or payment-instrument data exists in the platform: `user_payments` carries amounts and
points only (`db/schema.rb:2408-2422`). Saying so is worth a clause — an assessor assumes the
opposite of a variable-remuneration system, so the absence removes a risk they had already
imagined.

The sensitive categories are named rather than cited to a statute. The questionnaire is answered in
Spanish for a group operating across Latin America, so anchoring to one country's law reads as an
answer written for one country; the category list holds in every jurisdiction and spares the
assessor a translation step.

## 3.7

**Question** — ¿Su organización cuenta actualmente con un informe de auditoría SOC 2 Tipo II? En caso
afirmativo, adjunte el informe más reciente o proporcione detalles sobre su alcance y el período de
cobertura.

**Answer** — NO

**Justification**

4Shark no cuenta con un informe SOC 2 Tipo II ni con certificaciones formales de seguridad vigentes.

Los controles que la compañía opera están documentados en su conjunto de políticas internas de seguridad de la información, aprobadas por la dirección y con revisión anual. Los principales: control de acceso de denegación por defecto y jerárquico, con sesión que expira tras una hora de inactividad y privilegio mínimo en la infraestructura; separación criptográfica entre entornos mediante clave de cifrado dedicada, además de cifrado en tránsito y en reposo; e infraestructura declarada como código, con revisión de código obligatoria y trazabilidad por commit de todo cambio.

La infraestructura sobre la que opera la plataforma está provista por proveedores que cuentan con SOC 2 Tipo II e ISO/IEC 27001, con auditoría independiente periódica.

**Notes** — a claim of alignment with ISO/IEC 27001 and 27002 has no gap analysis behind it and is
the easiest assertion in the questionnaire to knock down, so the answer names the controls 4Shark
operates instead. Naming the infrastructure suppliers belongs to a sub-processor question, not to a
question about 4Shark's own audit report.

The line stating the policies are approved by management describes the target state: the policy set
carries unfilled `[DD/MM/AAAA]` and `[Nome do Responsável Técnico]` placeholders. This is the most
exposed of the target-state claims, because an assessor who requests a policy sees the blank
approval field in the attachment 4Shark itself sent. It is the same action that unblocks 19.4.

## 3.8

**Question** — ¿La solución permite restringir el acceso mediante direcciones IP públicas
autorizadas y/o incluye autenticación multifactor (MFA) para los usuarios? Por favor, detalle cómo
se configuran y aplican estos controles.

**Answer** — SÍ

**Justification**

La plataforma admite autenticación federada mediante SSO con SAML 2.0, OAuth 2.0 y OpenID Connect. Cuando el cliente conecta su propio proveedor de identidad corporativo, la autenticación se delega íntegramente a ese proveedor y las políticas de MFA definidas allí se aplican sin solicitar un segundo factor redundante: el control de MFA permanece bajo la administración del propio cliente, con sus reglas de exigencia, excepción y revocación.

En autenticación local, sin SSO, la plataforma no impone MFA como exigencia propia. La credencial es individual e intransferible; la contraseña definida por el usuario exige longitud mínima de 8 caracteres y combinación de mayúsculas, minúsculas, números y caracteres especiales, con almacenamiento irreversible mediante hash bcrypt. La cuenta se bloquea automáticamente tras intentos fallidos sucesivos y la sesión expira tras una hora de inactividad.

La plataforma no dispone de restricción de acceso por lista de direcciones IP públicas autorizadas.

**Notes** — the `SÍ` rests on the MFA half; the question joins the two controls with "y/o". The IP
restriction does not exist and the answer says so, in place of offering to evaluate it — an offer
recorded in a supplier questionnaire becomes a commitment nobody decided to make.

Verified: minimum length 8 (`config/initializers/devise.rb:169`); the uppercase, lowercase, number
and special-character requirement (`app/models/user.rb:301-311`); `:lockable` and `:timeoutable`
enabled (`app/models/user.rb:12`).

The wording is `la contraseña definida por el usuario` because `password_requirements` returns early
on `registration_password?` (`app/models/user.rb:304`), and both password-recovery paths set that
flag when they write the new password. Complexity is therefore enforced on the logged-in change and
not on recovery; the flag reaches the frontend through the session payload and the GraphQL type, so
the frontend is what prompts for a definitive password. The frontend was not read, so what is
established is only that the backend does not force it.

## 3.9

**Question** — ¿La solución cuenta con un informe de prueba de penetración (pentest) realizado en
los últimos 6 meses? En caso afirmativo, adjunte el resumen ejecutivo del informe, incluyendo los
principales hallazgos y el estado de remediación.

**Answer** — SÍ

**Justification**

La plataforma fue sometida a una prueba de intrusión en modalidad black box, ejecutada por Avant Services, empresa independiente especializada en seguridad ofensiva. El ejercicio se realizó en marzo de 2026, el informe técnico se entregó el 7 de abril de 2026 y el retest de verificación se ejecutó el 11 de mayo de 2026.

Se identificaron 11 hallazgos: 1 de severidad alta, 7 de severidad media y 3 de severidad baja. El retest validó la remediación de todos los hallazgos con impacto de seguridad, incluido el de severidad alta. Permanece abierta una recomendación de endurecimiento sobre la política de Content Security Policy, sin impacto explotable identificado en el retest.

El resumen ejecutivo del informe se pone a disposición de Atento bajo acuerdo de confidencialidad.

**Notes** — the figures and the three dates come from the pre-review text and the report itself was
not available to check them against. Verify all of them against the Avant report before the
workbook is written.

This item expires. On a strict reading of "in the last 6 months" the date that counts is the
execution date in March 2026, which leaves the window around mid-September 2026; read against the
report delivery of 7 April, the window closes 7 October. Either way the answer has weeks of shelf
life rather than months, and a slipped send turns it into a decision about re-running the test.

The answer states the dates rather than asserting they fall inside the window — an answer that
argues it is within the deadline draws attention to the deadline. The open CSP item is named
because the question asks for remediation status, but the reason it stays open is not: explaining
why a finding will not be fixed invites the assessor to press on a point the retest already
classified as carrying no exploitable impact.

## 4.1

**Question** — ¿Su organización establece y mantiene un proceso de configuración segura para los
activos de la compañía (dispositivos de usuario final, incluidos dispositivos portátiles y móviles,
dispositivos no informáticos/IoT y servidores) y para el software (sistemas operativos y
aplicaciones)? Revise y actualice la documentación de forma anual o cuando se produzcan cambios
significativos.

**Answer** — SÍ

**Justification**

4Shark mantiene una línea base de configuración segura para las estaciones de trabajo, aplicada mediante la cuenta administrativa y documentada: cuenta de usuario sin privilegio administrativo, bloqueo automático de sesión tras 15 minutos de inactividad y firewall de host con denegación por defecto para el tráfico entrante. El usuario no puede alterar ninguno de esos ajustes, y la documentación de la línea base se actualiza con cada cambio de configuración.

Para los servidores y el software de la plataforma, la configuración está declarada como código, versionada y auditable por commit; cada cambio pasa por revisión antes de aplicarse, de modo que el estado documentado y el estado real no divergen.

**Notes** — the workstation visit produces the baseline as a by-product: the three settings it
applies *are* the baseline, so the only gap between this and a `SÍ` was writing them on one page.
That page is the `TASKS.md` entry.

The documentation cadence carries no recurring commitment. The question offers "annually **or** on
significant change", and the baseline page is updated when the configuration changes — the same
reading applied at 4.2, and the reason this item is cheap where 2.1 and 2.2 are not.

The IoT and network-device scope elements are covered by 1.1 and 4.2 and are not restated here.

## 4.2

**Question** — ¿Su organización establece y mantiene un proceso de configuración segura para los
dispositivos de red? Revise y actualice la documentación de forma anual o cuando se produzcan
cambios significativos.

**Answer** — SÍ

**Justification**

La red de la plataforma es definida por software: no hay dispositivos físicos de red bajo gestión de 4Shark. Su topología completa — redes virtuales, subredes, tablas de rutas y reglas de acceso entre componentes — está declarada como configuración versionada, con historial de cambios por autor y fecha.

Las reglas de acceso siguen el principio de menor privilegio: cada componente alcanza únicamente los destinos que su función exige, y ningún servicio interno está expuesto directamente a Internet. El único punto de entrada público es la capa perimetral, sobre HTTPS.

Ninguna modificación de la topología o de las reglas de acceso se aplica sin revisión previa, de modo que la revisión acompaña cada cambio significativo.

**Notes** — the verdict differs from 4.1 on scope coverage, not on rigour. In 4.1 an entire asset
class inside the question's scope has no process at all; here every network element that exists is
declared, versioned and reviewed before application. What is absent is the annual documentary
ritual, and the question itself offers "annually **or** on significant change" — the second branch
is met literally.

This is the test to carry through the rest of block 4: missing scope coverage decides `NO`; a
cadence the question's own alternative already satisfies does not.

## 4.3

**Question** — ¿Su organización configura el bloqueo automático de sesión en los activos
corporativos tras un período definido de inactividad? Para los sistemas operativos de uso general,
el período no debe exceder los 15 minutos. Para los dispositivos móviles de usuario final, el
período no debe exceder los 2 minutos.

**Answer** — SÍ

**Justification**

Las estaciones de trabajo corporativas aplican bloqueo automático de sesión tras 15 minutos de inactividad, configurado mediante directiva de máquina bajo la cuenta administrativa. El usuario no dispone de privilegio administrativo y no puede modificar ni desactivar ese plazo.

En la capa de la aplicación, donde reside el acceso a los datos, la sesión expira tras una hora de inactividad y exige nueva autenticación. El acceso a la infraestructura exige una elevación de privilegio que también caduca en una hora.

4Shark no entrega dispositivos móviles corporativos, por lo que el umbral de 2 minutos no tiene activo aplicable.

**Notes** — the workstation paragraph describes the target state; the enforcement is the `TASKS.md`
entry that pairs with the install-privilege change, since both are applied on the same visit to the
same machines. 15 minutes is taken from the question's own threshold: promising less buys nothing
and promising more fails the requirement.

The mobile threshold has no applicable asset — employees receive a computer and no corporate phone.

Session expiry is stated as inactivity-based throughout, matching `config.timeout_in = 1.hour` with
Devise `:timeoutable` (`config/initializers/devise.rb:179`, `app/models/user.rb:12`). Describing it
as an absolute expiry would claim a stronger control than the one configured: a session held by an
active user does not end at the hour. The module's semantics were read from configuration rather
than traced through the request hook, and the users table carries no `last_request_at` column, so a
live check before sending is worth the two minutes it costs.

## 4.4

**Question** — ¿Su organización implementa y gestiona un firewall en los servidores donde sea
compatible? Algunos ejemplos de implementación incluyen un firewall virtual, un firewall del
sistema operativo o un agente de firewall de terceros.

**Answer** — SÍ

**Justification**

Cada carga de trabajo productiva está protegida por un firewall virtual propio, con denegación por defecto: sólo alcanza el servicio el tráfico explícitamente autorizado, definido por origen, puerto y protocolo para cada componente por separado y no como una regla común del entorno.

Las reglas se gestionan como parte de la configuración declarada de la infraestructura, con historial de cambios y revisión previa a cada modificación.

**Notes** — the question names a virtual firewall as a valid implementation, which is what runs
here, so the `SÍ` needs no stretching.

The distinct content against 4.2 is granularity: each component carries its own rule set rather
than one environment-wide rule. That answers "implementa"; the second sentence answers "gestiona".
4.2 already carries the topology and the least-privilege framing and is not repeated.

## 4.5

**Question** — ¿Su organización implementa y gestiona un firewall basado en el host o una
herramienta de filtrado de puertos en los dispositivos de usuario final, con una regla de denegación
por defecto que bloquee todo el tráfico, excepto los servicios y puertos explícitamente permitidos?

**Answer** — SÍ

**Justification**

Las estaciones de trabajo aplican un firewall basado en el host con regla de denegación por defecto para todo el tráfico entrante: sólo se permiten las conexiones explícitamente autorizadas. La configuración se impone mediante directiva de máquina bajo la cuenta administrativa, de modo que el usuario, que no dispone de privilegio administrativo, no puede desactivarla ni alterar sus reglas.

Ninguna estación expone servicios a sistemas de 4Shark: el acceso a la infraestructura sale del equipo hacia la VPN y nunca en sentido contrario.

**Notes** — target state, enforced by the `TASKS.md` entry that rides along with the other two
workstation settings. Windows already blocks inbound connections by default; what the answer adds
is 4Shark imposing it rather than relying on the default staying untouched, which is also what the
`SÍ` commits to going forward — a new machine, a reinstall or a new hire arriving with the firewall
enforced.

## 4.6

**Question** — ¿Su organización gestiona de forma segura los activos corporativos y el software?
Algunos ejemplos de implementación incluyen la gestión de configuraciones mediante infraestructuras
controladas por versiones, como infraestructura como código, y el acceso a interfaces
administrativas a través de protocolos de red seguros, como SSH y HTTPS. No utilice protocolos de
gestión inseguros, como Telnet y HTTP, a menos que sean operativamente críticos.

**Answer** — SÍ

**Justification**

La gestión de la configuración de los activos y del software se realiza mediante infraestructura como código bajo control de versiones.

El acceso administrativo se realiza exclusivamente por protocolos cifrados: SSH con autenticación por clave para los servidores y HTTPS con TLS 1.2 o superior para las interfaces de gestión. No se emplean Telnet ni HTTP en ninguna tarea de gestión.

El acceso a la infraestructura interna y a las bases de datos productivas exige además conexión VPN. La base de datos no es alcanzable desde el equipo del colaborador: el acceso pasa por un servidor dedicado dentro de la red privada del sistema correspondiente, y cada sistema opera en una red aislada.

**Notes** — infrastructure as code appears in one line rather than a paragraph. It is the fourth
consecutive item in block 4 whose natural opening is that phrase, and 4.2 and 4.4 already carry the
topology and the rule granularity; the question names it as an example, so it belongs, but only
once.

The space goes to the protocols, which no earlier item covers, including the explicit negative on
Telnet and HTTP that the question names. TLS 1.2 is the same figure verified at 3.5
(`dns/security_4sharkpay_com.tf:8`).

## 4.7

**Question** — ¿Su organización gestiona las cuentas estándar en los activos y el software de la
compañía, tales como cuentas root, cuentas de administrador y otras cuentas preconfiguradas por el
proveedor? Algunos ejemplos de implementación incluyen deshabilitar las cuentas predeterminadas o
imposibilitar su uso.

**Answer** — SÍ

**Justification**

Las cuentas propietarias de cada servicio corresponden a una cuenta administrativa dedicada, operada exclusivamente mediante llave física de seguridad y bajo custodia de la Dirección Técnica. Funciona en modelo break-glass: se emplea únicamente para el acto de aplicar un cambio, con traza en el control de versiones y en los registros de ejecución. Ninguna cuenta personal, incluida la de la Dirección Técnica, dispone de privilegio administrativo en uso diario.

La credencial maestra de las bases de datos no es establecida ni conocida por ninguna persona: se genera de forma automática y se custodia cifrada en el gestor de secretos del proveedor de nube. La aplicación opera con credenciales distintas, de menor privilegio.

En las estaciones de trabajo la administración se realiza mediante una cuenta creada por 4Shark para ese fin, no mediante una cuenta predeterminada del sistema operativo.

**Notes** — the pre-review text described the break-glass model, which answers a neighbouring
question about privilege management rather than this one about vendor-preconfigured accounts. The
database master credential is the missing piece and the strongest one:
`manage_master_user_password = true` (`modules/app/rds.tf:71`, `:105`) means the provider generates
and holds it, so no person types it or knows it — which is the "make its use impossible" the
question offers as an example.

The clause stating the application runs on lower-privilege credentials rests on 4Shark's own
`/create-app` documentation, which describes the migration role as distinct from the master, rather
than on a connection-configuration read. Confirm before sending if full rigour is wanted.

## 5.1

**Question** — ¿Su organización elimina o modifica las configuraciones antes de que nuevos sistemas
o dispositivos se pongan en producción? ¿Se cambian todas las contraseñas predeterminadas y se
deshabilitan las cuentas innecesarias? ¿La aplicación de configuraciones seguras está documentada y
validada de conformidad con estándares internacionales de seguridad, como NIST 800-53?

**Answer** — NO

**Justification**

4Shark no valida formalmente la aplicación de configuraciones seguras contra un estándar internacional como NIST 800-53, ni mantiene una certificación equivalente.

Sobre las dos primeras cuestiones, el control sí existe y opera en el momento del aprovisionamiento: un recurso nace con su configuración definida como código y con credenciales generadas para ese entorno, de modo que no llega a existir una ventana en la que opere con valores por defecto. No hay contraseñas predeterminadas en uso ni cuentas preconfiguradas activas, y la configuración aplicada queda registrada en el propio código, revisada antes de aplicarse.

**Notes** — the question bundles three. The first two are met and verified; the third is not, and it
is explicit, so the verdict follows it. Answering `SÍ` and conceding the missing validation in the
closing sentence is the shape corrected at 4.1 — the assessor resolves the contradiction himself
and starts doubting the neighbouring answers.

The claim of alignment with ISO/IEC 27001 and 27002 is removed here for the same reason it was
removed at 3.7. It reappears because the pre-review text uses it across several items, so each one
has to be cleaned separately — the sweep recorded in `TASKS.md`.

What this item carries that 4.7 does not is the timing: a resource is born configured, so no
interval exists in which it runs on factory values. 4.7 covers managing the vendor account itself.

## 5.2

**Question** — ¿Su organización establece y mantiene un inventario de todas las cuentas gestionadas
dentro de la compañía? El inventario debe incluir cuentas de usuario y cuentas administrativas. Como
mínimo, el inventario debe contener el nombre de la persona, nombre de usuario, fechas de inicio y
fin, y el departamento. Valide que todas las cuentas activas estén autorizadas de forma recurrente,
al menos trimestralmente.

**Answer** — NO

**Justification**

No existe un inventario de cuentas con nombre de la persona, nombre de usuario, fechas de alta y baja y departamento, ni una validación recurrente de cadencia trimestral formalizada con registros.

La concesión de accesos está declarada como código y es rastreable por commit, de modo que en cualquier momento puede establecerse qué cuenta tiene qué permiso y desde cuándo. La revisión se produce ante eventos organizativos — ingreso, salida y cambio de función — y no en una cadencia fija.

**Notes** — commit traceability partially answers the "start dates" the question asks for: when a
permission was granted is recoverable, which a hand-kept inventory usually cannot guarantee. It is
stated as a fact rather than as a substitute for the inventory.

A `NO` answer stays short. Expanding on what 4Shark does have reads as compensation, and the
declared-as-code framing is already carried by four items in block 4.

This is the sibling of 2.1 and 2.2 in the pending-cadence group, and the cheapest of the three: the
accesses are already declared, so a quarterly review would be reading what is written rather than
gathering new information.

## 5.3

**Question** — ¿Su organización utiliza contraseñas únicas para todos los activos de la compañía? La
implementación de buenas prácticas incluye el uso de contraseñas de al menos 12 caracteres para las
cuentas que utilizan autenticación multifactor (MFA).

**Answer** — SÍ

**Justification**

Todas las credenciales son únicas por sistema y por entorno; no hay reutilización entre sistemas ni entre entornos.

Las credenciales de máquina se generan automáticamente, con longitud muy superior a los 12 caracteres que la pregunta cita, y se custodian cifradas en el gestor de parámetros del proveedor de nube. Ninguna persona las elige ni las conoce.

Las credenciales del equipo humano se gestionan en la bóveda corporativa, con MFA habilitado y contraseñas generadas por la propia herramienta, de modo que tampoco son elegidas por la persona que las usa.

**Notes** — uniqueness on its own is an assertion the assessor cannot check. Saying no person
chooses the credentials explains why they are unique and strong, which is the part that is hard to
doubt.

The length claim stays general because one generated credential was verified at 32 characters
(`modules/app/mongodb.tf:145`), not the whole set. Naming 32 in the answer would need that check
widened.

## 5.4

**Question** — ¿Su organización elimina o desactiva cualquier cuenta inactiva después de un período
de 90 días de inactividad, cuando sea compatible?

**Answer** — NO

**Justification**

No existe una política de desactivación automática de cuentas por inactividad de 90 días.

El control sobre el ciclo de vida de las cuentas se ejerce en el evento y no en el plazo: la cuenta se revoca en el momento de la desvinculación.

**Notes** — three things were removed from the pre-review text. `La población de cuentas es
reducida` discloses headcount by implication and answers nothing the question asks. The 24-hour
offboarding figure is unverified and reads as an SLA commitment in a supplier questionnaire — the
same number was already dropped from 1.1 and survived here. And the cross-reference to item 6.2
creates a dependency on an answer not yet rewritten.

## 5.5

**Question** — ¿Su organización restringe los privilegios de administrador a cuentas administrativas
dedicadas en los activos corporativos? Las actividades de uso general, como la navegación en
Internet, el correo electrónico y el uso de la suite de productividad, deben realizarse desde la
cuenta principal del usuario sin privilegios administrativos.

**Answer** — SÍ

**Justification**

En las estaciones de trabajo, la cuenta con la que el colaborador realiza su actividad diaria — navegación, correo y suite de productividad — no dispone de privilegio administrativo. La administración se realiza mediante una cuenta dedicada, distinta y bajo custodia de la Dirección Técnica.

En la infraestructura, las cuentas personales operan con permiso de solo lectura por defecto; la elevación para acciones de mutación exige autenticación multifactor y caduca en una hora. Las operaciones administrativas amplias exigen una cuenta dedicada operada mediante llave física de seguridad.

El privilegio administrativo no está asociado a ninguna persona: reside en cuentas dedicadas cuyo uso es puntual y trazable, incluso para la Dirección Técnica.

**Notes** — the question's own examples — browsing, email, office suite — happen on the workstation,
so the answer leads there rather than with the cloud infrastructure the pre-review text described.
The workstation paragraph is target state, resting on the same `TASKS.md` visit.

The encryption-key custody paragraph was cut: it concerns reading data, not administrative
privilege, and 1.1 and 3.2 already carry it.

The closing sentence is rephrased rather than repeated from 4.7 — privilege belongs to accounts
rather than to people, which is sharper here and avoids the verbatim reuse.

## 6.1

**Question** — ¿Su organización establece y sigue un proceso, preferentemente automatizado, para
otorgar acceso a los activos de la compañía en casos de recontratación, asignación de privilegios o
cambios en el rol de un usuario?

**Answer** — SÍ

**Justification**

La concesión de accesos sigue siempre el mismo camino, con independencia de si se trata de una incorporación, una recontratación, una asignación de privilegios o un cambio de función: el acceso se declara como código y el cambio pasa por revisión antes de aplicarse.

La concesión queda así registrada con autor y fecha en el propio historial, y no existe vía manual paralela: un permiso que no esté declarado no llega a existir.

Las credenciales individuales se entregan a través de la bóveda corporativa.

**Notes** — the question names three triggers and the pre-review text covered two, leaving rehire
out. Stating that the path does not depend on the trigger is both true and shorter than enumerating
them.

`Un permiso que no esté declarado no llega a existir` answers "preferably automated" better than
claiming automation does: the strength is not that granting is automatic but that no other route to
grant exists.

This is the positive counterpart of 5.2, which is `NO`: no account inventory is kept, but the record
of how each access was granted is. Read together the two answers are coherent rather than
contradictory.

## 6.2

**Question** — ¿Su organización establece y sigue un proceso, preferentemente automatizado, para
revocar el acceso a los activos de la compañía mediante la desactivación inmediata de las cuentas
tras la terminación de la relación laboral, la revocación de derechos o el cambio de rol de un
usuario? La desactivación de cuentas, en lugar de su eliminación, puede ser necesaria para preservar
los registros de auditoría.

**Answer** — SÍ

**Justification**

La revocación se produce en el momento de la desvinculación y actúa sobre la identidad corporativa, que es la puerta de entrada a todos los sistemas: al desactivarla, el acceso a cuanto depende de ella cesa de inmediato, sin necesidad de intervenir sistema por sistema.

Las concesiones declaradas como código se retiran a continuación por el mismo canal que las otorgó, con la misma traza. Las credenciales compartidas se revocan en la bóveda corporativa.

Se opta por la desactivación en lugar de la eliminación cuando es necesario preservar los registros de auditoría.

**Notes** — this is where the 24-hour figure originates, and here it works against the answer: the
question asks for *immediate* deactivation and the pre-review text offered 24 hours, handing the
assessor the reason to mark the item unmet. The mechanism is in fact immediate — disabling the
corporate identity cuts everything that authenticates through it — and the 24 hours described the
cleanup that follows, not access still standing.

So the answer separates the two: identity revocation is immediate and is what removes access;
withdrawing the declared grants follows through the same channel. No figure is stated, because the
figure weakened it.

Declaring an SLA remains possible and some assessors prefer to see one, but it would belong to the
cleanup step and the number has to be one the engineer confirms.

## 6.3

**Question** — ¿Su organización exige que todas las aplicaciones expuestas externamente, ya sean
corporativas o de terceros, apliquen autenticación multifactor (MFA)? La aplicación de MFA a través
de un servicio de directorio o un proveedor de inicio de sesión único (SSO) se considera una
implementación adecuada de esta protección.

**Answer** — SÍ

**Justification**

Todas las aplicaciones corporativas expuestas externamente que 4Shark utiliza — correo, repositorios de código, consola de infraestructura y bóveda de credenciales — se autentican a través del proveedor de identidad corporativo, con MFA obligatorio. La autenticación no se configura aplicación por aplicación: el proveedor de identidad es la puerta única, de modo que el MFA se aplica una vez y alcanza a todas.

En la plataforma entregada al cliente, la autenticación federada delega en el proveedor de identidad del propio cliente, de modo que las políticas de MFA definidas allí se aplican íntegramente.

**Notes** — the scope reading decides the verdict. "Aplicaciones expuestas externamente, ya sean
corporativas o de terceros" describes the applications the organization uses, not the product it
sells; the product's MFA posture is item 3.8, which states plainly that local authentication carries
no 4Shark-imposed MFA. Under that reading the `SÍ` holds whole and the two answers do not collide.

The pre-review text tried to answer both at once and produced the `SÍ`-then-concede shape corrected
at 4.1, 5.1 and 6.3's own closing sentence, plus a cross-reference to 3.8 — the same fragile
dependency removed at 5.4 — and the "recommended model for Atento" sales phrasing already dropped
from 3.8.

## 6.4

**Question** — ¿Su organización exige el uso de autenticación multifactor (MFA) para el acceso
remoto a la red?

**Answer** — SÍ

**Justification**

El acceso remoto a la infraestructura exige conexión VPN, y la autenticación de esa conexión se realiza contra el proveedor de identidad corporativo, cuyo MFA es obligatorio. No existe una vía de acceso remoto alternativa que evite ese paso.

**Notes** — the whole answer rests on the VPN delegating authentication to the identity provider. The
VPN module declares no authentication settings, and that decides nothing either way because the
configuration lives in the VPN product's own admin interface. The `TASKS.md` entry is therefore
written as confirm-or-configure: correct whether the integration already exists or has to be made,
and it closes in minutes in the first case.

## 6.5

**Question** — ¿Su organización exige autenticación multifactor (MFA) para todas las cuentas de
acceso administrativo compatibles en todos los activos de la compañía, ya sea que se gestionen
localmente o a través de un proveedor externo?

**Answer** — SÍ

**Justification**

El acceso administrativo a la infraestructura exige autenticación multifactor en todos sus niveles: la elevación de privilegio para acciones de mutación la requiere y caduca en una hora, y las operaciones administrativas amplias exigen una cuenta dedicada operada mediante llave física de seguridad.

El perfil de soporte de la aplicación exige igualmente un segundo factor en la autenticación, con credencial individual e intransferible por persona.

**Notes** — target state: the support profile's second factor is an open pull request that ships
alongside the workstation changes, recorded in `TASKS.md`. Both have to land before the questionnaire
is sent.

Six things were removed from the pre-review text, and they concentrate here because it was one of
the longest answers — length was being used to compensate for a `NO`. Headcount ("una única
persona"), the absolute-expiry and no-renewal claims, the verdict restated in prose, and the
roadmap promise are all shapes corrected elsewhere.

The sixth has no precedent in the other items: the pre-review text described what the unprotected
support profile could write — tenant and identity administration. In an answer conceding missing
MFA, naming the reach of that access hands the reader a target. The verdict was already given; the
detail only added the map.

## 7.1

**Question** — ¿Su organización establece y mantiene un proceso documentado de gestión de
vulnerabilidades para los activos corporativos? Revise y actualice la documentación de forma anual o
cuando se produzcan cambios significativos.

**Answer** — SÍ

**Justification**

La gestión de vulnerabilidades es continua y automatizada. Las dependencias de la aplicación se analizan de forma permanente y cada vulnerabilidad divulgada genera de inmediato una propuesta de corrección.

Las actualizaciones ordinarias de dependencias quedan sujetas a un período mínimo de maduración antes de poder incorporarse, de modo que una versión comprometida recién publicada no llega a integrarse; las correcciones de seguridad no esperan ese plazo, porque una vulnerabilidad ya divulgada es pública y esperar sólo beneficia a quien la explota.

El sistema operativo, el entorno de ejecución y el motor de base de datos son servicios gestionados por el proveedor de nube, con parcheo bajo su responsabilidad. La capa perimetral aplica reglas de protección frente a ataques conocidos.

El proceso está descrito en la política interna de desarrollo seguro, que se actualiza cuando el proceso cambia.

**Notes** — the pre-review text closed by volunteering that no independent vulnerability-management
policy with a CVSS-based SLA exists. The question asks for neither. Conceding a gap nobody asked
about is the inverse of over-claiming and costs more, because the assessor would not have raised it.

`Con revisión anual` is replaced by updating when the process changes — the alternative the question
itself offers, and one that does not depend on the policy-dating task.

The minimum release age is the distinctive control and earns its space; the security exemption is
stated alongside it because without that the sentence would be false, and the reason for the
exemption is worth reading on its own.

## 7.2

**Question** — ¿Su organización establece y mantiene una estrategia de remediación documentada,
basada en riesgos, dentro de un proceso de remediación, con revisiones mensuales o con mayor
frecuencia?

**Answer** — SÍ

**Justification**

La estrategia de remediación distingue por riesgo de forma mecánica, no por evaluación caso a caso: una vulnerabilidad divulgada se trata como urgente y genera de inmediato una propuesta de corrección, mientras que una actualización ordinaria queda sujeta al período mínimo de maduración antes de poder incorporarse. La distinción está impuesta por las herramientas que abren y bloquean cada cambio, de modo que no depende de que alguien la recuerde.

Cada propuesta de corrección se evalúa cuando se abre, sin esperar a un ciclo de revisión.

La estrategia está descrita en la política interna de desarrollo seguro.

**Notes** — the question asks for a risk basis and the pre-review text answered with deadlines. The
risk basis does exist and is binary rather than a CVSS matrix: a disclosed vulnerability and a
routine update take different paths, and the separation is enforced by tooling rather than by
judgement.

Three claims were removed, and all three invite verification. The comparison to market SLAs is the
superiority framing rejected at 1.1 and it dares the assessor to check whether the figures are met.
The "hours to a few days" window is a performance figure nobody has measured. And the confession
about lacking a formal risk matrix repeats 7.1's pattern of conceding what was not asked.

`La revisión es diaria, no mensual` argues with the question; evaluating each proposal as it opens is
more frequent than monthly by construction and claims no cadence that was not verified.

## 7.3

**Question** — ¿Su organización realiza actualizaciones del sistema operativo en los activos
corporativos mediante la gestión automatizada de parches de forma mensual o con mayor frecuencia?

**Answer** — SÍ

**Justification**

El sistema operativo y el motor de base de datos de la infraestructura son servicios gestionados por el proveedor de nube, que aplica el parcheo bajo su responsabilidad.

Las imágenes base de los contenedores se reconstruyen de forma automatizada cuando la imagen base recibe una actualización, de modo que las cargas de trabajo productivas no acumulan versiones antiguas del sistema operativo.

En las estaciones de trabajo, la actualización automática del sistema operativo está activa.

**Notes** — "activos corporativos" covers the workstations, which the pre-review text omitted. The
same scope jump appeared at 4.1 and 5.5; here it does not force a `NO`, because automatic updates
are already active on the machines — a fact the approved 2.2 answer records.

`La cadencia real es superior a la mensual solicitada` is the same arguing-with-the-question shape
removed from 7.2 one item earlier.

Available and not taken: enforcing by policy that automatic updates stay on, in the same visit as
the other three settings. That would replace "inherited from the system default" with "guaranteed by
4Shark", at the cost of one more standing commitment. The answer holds without it.

## 7.4

**Question** — ¿Su organización realiza actualizaciones de aplicaciones en los activos corporativos
mediante la gestión automatizada de parches de forma mensual o con mayor frecuencia?

**Answer** — SÍ

**Justification**

Las bibliotecas y dependencias de la aplicación se actualizan de forma continua: cada publicación de una versión nueva genera automáticamente una propuesta de actualización, sin que nadie tenga que buscarla. Lo mismo se aplica a las dependencias del propio proceso de construcción y despliegue.

En las estaciones de trabajo, la suite ofimática se actualiza automáticamente por su fabricante.

**Notes** — block 7 splits one subject across three items and none of them retells the others: 7.1
owns the documented process and the minimum release age, 7.2 owns the risk basis, and this one owns
reach and the fact that proposals arrive rather than being sought.

`La cadencia real es diaria, superior a la mensual solicitada` closes 7.2, 7.3 and 7.4 in the
pre-review text — a tic of that text rather than an argument, removed in all three. The daily merge
cadence went with it as an unverified figure.

## 8.1

**Question** — ¿Su organización establece y mantiene un proceso de gestión de registros de auditoría
que defina los requisitos de conservación de registros de la compañía? Como mínimo, debe abordar la
recopilación, revisión y retención de los registros de auditoría de los activos corporativos.

**Answer** — SÍ

**Justification**

Los registros de auditoría se recopilan, se conservan y se analizan.

Las acciones ejecutadas sobre la infraestructura se registran de forma íntegra y se conservan indefinidamente en un almacenamiento dedicado con bloqueo de objetos: los registros no pueden ser alterados ni eliminados, tampoco por quien dispone de acceso administrativo. Los registros de aplicación e infraestructura se conservan 180 días. Los cambios de permisos y de configuración quedan en el control de versiones con autor, fecha y diferencia, y los eventos de autenticación de la plataforma — fecha, hora, dirección IP, resultado y motivo de fallo — se persisten en la base de datos.

El análisis de esos registros es continuo y automatizado: un servicio de detección procesa las trazas de auditoría, el tráfico de red y las resoluciones de nombres, y genera hallazgos sin depender de que alguien los busque. Los requisitos de conservación están definidos en la propia declaración de la infraestructura.

**Notes** — the question names three minimums and the review is the one that decides it. Collection
and retention are strong and verified: `object_lock_enabled = true` with `prevent_destroy` on the
audit bucket (`terraform/audit/cloudtrail.tf:7-14`), the 1095-day expiration deliberately dropped
with the reason written in the file header, and 180 days for the execution logs
(`modules/app/services.tf:142`). Object lock is the strongest fact here and the pre-review text
omitted it — it answers the question an auditor actually has, which is whether whoever acted can
erase the trace.

The review comes from the `TASKS.md` activation, and its `SÍ` is target state. The Positivo vendor
assessment raised the same gap and its reviewer rejected wording that SIEM adoption was "under
evaluation", demanding fact and forcing a downgrade — so this answer requires the activation to have
happened.

The pre-review text carried a literal `[PENDIENTE:]` marker asking whether the authentication-event
store was in production. It is: `security_events` sits in `db/schema.rb:2057` with `occurred_at`,
`ip_address`, `outcome` and `failure_reason`, so the migration has run.

## 8.2

**Question** — ¿Su organización recopila registros de auditoría? Asegúrese de que el registro de
eventos, de conformidad con el proceso de gestión de registros de auditoría de la compañía, esté
habilitado en todos los activos de la organización.

**Answer** — SÍ

**Justification**

La recopilación de registros está habilitada en todos los activos productivos: las acciones sobre la cuenta de infraestructura, los registros de aplicación y de ejecución, y todo cambio de configuración y de permisos en el control de versiones.

En las estaciones de trabajo, el registro de eventos del sistema operativo está activo de forma predeterminada.

**Notes** — the workstation line claims that event logging is enabled, which is what the question
asks, and not that it is centralized, which it is not and which the question does not ask. An
incident on a workstation therefore leaves a local trace only. Stating the narrower true thing keeps
a later item in block 8 from forcing a contradiction.

The cross-reference to 8.1's caveat was removed on both counts: pointers age badly while every
answer is being rewritten, and the caveat itself no longer holds now that the authentication-event
store is confirmed in production.

## 8.3

**Question** — ¿Su organización garantiza que los destinos de los registros mantengan una capacidad
de almacenamiento adecuada para cumplir con el proceso de gestión de registros de auditoría de la
compañía?

**Answer** — SÍ

**Justification**

Los registros se almacenan en servicios gestionados de capacidad elástica. No existe un límite fijo de almacenamiento que pueda agotarse e interrumpir la recopilación: la capacidad crece con el volumen registrado.

**Notes** — the answer addresses what the control fears rather than its wording: logging stopping
because the disk filled. Elastic capacity removes the failure mode instead of leaving headroom
against it, so one paragraph is the whole answer.

The only change from the pre-review text is genericizing the service names — the first item whose
content arrived correct.

## 9.1

**Question** — ¿Su organización garantiza que únicamente puedan ejecutarse en la compañía navegadores
y clientes de correo electrónico totalmente compatibles, utilizando exclusivamente la versión más
reciente proporcionada por el proveedor?

**Answer** — SÍ

**Justification**

No hay clientes de correo instalados en las estaciones de trabajo: el correo corporativo se utiliza exclusivamente a través de su cliente web, cuya versión mantiene el proveedor de forma continua y sin intervención del usuario. No existe, por tanto, un cliente de correo que pudiera quedar en una versión sin soporte.

Los navegadores en uso son productos soportados por sus fabricantes, con actualización automática habilitada, que aplican cada versión publicada sin acción del usuario.

**Notes** — the absence of an installed mail client leads, because it removes half the question's
risk rather than mitigating it, and the pre-review text buried it mid-paragraph.

Naming a single browser is an assertion about every machine that breaks the moment someone installs
another. Every mainstream browser self-updates, so the general statement is true under any
configuration and answers the same thing.

## 9.2

**Question** — ¿Su organización utiliza servicios de filtrado DNS en todos los activos de la
compañía para bloquear el acceso a dominios maliciosos conocidos?

**Answer** — NO

**Justification**

4Shark no opera un servicio de filtrado DNS en las estaciones de trabajo.

El correo corporativo aplica filtrado antiphishing y antimalware, que cubre el principal vector por el que un dominio malicioso alcanza a una persona.

**Notes** — the pre-review text ran to roughly 340 words recycling 1.1, 3.2 and 4.5 whole, plus the
two retracted session claims and a paragraph on confidentiality agreements and training that belongs
to another item.

Buried in it was the fleet composition — macOS, Windows and Linux by individual preference. The
operations team, which is the part that reaches real client data, works on Windows; engineering and
the partners run macOS and Ubuntu. `TASKS.md` carries the per-system equivalents, because the five
workstation answers say "the workstations" without qualifying.

## 10.1

**Question** — ¿Su organización implementa y mantiene software antimalware en todos los activos de
la compañía?

**Answer** — SÍ

**Justification**

Las estaciones de trabajo cuentan con la protección antimalware integrada en su sistema operativo, activa por defecto y mantenida de forma continua por el fabricante.

El correo corporativo aplica filtrado antimalware y antiphishing del lado del servidor, antes de la entrega a cualquier dispositivo, de modo que la protección no depende de que un agente esté instalado y actualizado en el equipo del destinatario.

En la infraestructura productiva las cargas de trabajo son contenedores efímeros, reconstruidos a partir de imágenes versionadas y sin acceso interactivo: no existe una superficie de instalación persistente donde un código malicioso pueda alojarse.

**Notes** — one layer per paragraph, replacing roughly 400 words that carried the recycled block for
the fourth time.

The sharpest removal is `Es una propiedad de la arquitectura, más fuerte que la detección por firmas
que el control presupone` — telling the assessor his control rests on an inferior premise invites
him to disagree. The ephemeral-container fact stands on its own; the judgement about it does not
belong in the answer.

## 10.2

**Question** — ¿Su organización deshabilita la función de reproducción automática (autoplay) para
los medios extraíbles?

**Answer** — SÍ

**Justification**

La ejecución automática de código desde medios extraíbles no ocurre en los equipos utilizados: los sistemas operativos actuales no ejecutan código de un medio conectado sin acción explícita del usuario.

**Notes** — a one-line question gets a one-line answer. The pre-review text ran to roughly 400 words,
of which 380 were the recycled block appearing for the fifth time across 4.3, 4.5, 9.2, 10.1 and
here.

The answer states the state rather than claiming an action: nobody disabled autoplay, it ships
disabled. The Windows `Turn off AutoPlay` policy would turn "inherited" into "enforced" in the same
configuration session, and is deliberately not in `TASKS.md` — unlike the firewall, the default here
is already safe and the gain is formal.

## 11.1

**Question** — ¿Su organización establece y mantiene un proceso de recuperación de datos? En dicho
proceso, se debe abordar el alcance de las actividades de recuperación de datos, la priorización de
la recuperación y la seguridad de los datos de respaldo.

**Answer** — SÍ

**Justification**

El proceso de recuperación está documentado y define dos escenarios distintos, con objetivos de tiempo propios para cada uno: corrupción de datos con la región primaria sana, que se resuelve desde la copia local, y pérdida de la región, que se resuelve desde la copia mantenida en una región secundaria.

El proceso no se limita a estar escrito. Una prueba de restauración automatizada se ejecuta mensualmente sobre todas las bases de datos: restaura el punto de recuperación en una base desechable, valida la integridad de los datos, mide el tiempo y la elimina, sin intervención humana; un fallo genera alerta. Una vez al año la prueba se ejecuta de forma manual y completa, incluyendo la conmutación de la aplicación hacia la base restaurada.

Las copias de seguridad están cifradas con la clave dedicada del entorno y se conservan en dos regiones.

**Notes** — the recurring proof of restore is the strongest fact in the questionnaire so far and the
pre-review text omitted it entirely, claiming instead that a BCP/DRP exists and is reviewed
annually. Every vendor claims a documented plan; few can show it exercised monthly with integrity
validation and an alarm on failure.

Coverage across all databases is target state — `TASKS.md` carries the extension, which the restore
plan's list-shaped input makes cheap.

`Formalmente aprobado` was dropped for the reason it was dropped at 3.7: it collides with the
undated, unsigned policy set. The answer rests on the runbook and the tested mechanism, which exist
whether or not the policy document carries a signature.

The measured restore times per scenario are documented but not published here. They were measured on
one database and scale with size, so quoting them as company-wide figures would be a false precision
an assessor can test. They exist if he asks.

## 11.2

**Question** — ¿Su organización realiza copias de seguridad automatizadas de los activos corporativos
dentro del alcance? Las copias de seguridad deben ejecutarse de forma semanal o con mayor
frecuencia, dependiendo de la sensibilidad de los datos.

**Answer** — SÍ

**Justification**

Las copias de seguridad son automatizadas y continuas: además de las instantáneas diarias, la base de datos mantiene un respaldo permanente que permite restaurar a cualquier punto en el tiempo dentro de la ventana de retención.

Tanto el fallo de una copia como el fallo de su réplica en la región secundaria generan alarma.

**Notes** — the failure alarm was buried at the end of the pre-review text and is promoted here: the
question asks for backups to be *automated*, and an automated backup that fails silently is the
appearance of one. Alarming on both the copy and the cross-region replica is what makes "automated"
mean something.

Retention is deliberately absent. The question asks about frequency, and volunteering a figure an
assessor may read as short repeats the 7.1 and 7.2 pattern of conceding what was not asked. A later
item asking about retention gets the number.

Region names were removed: naming them in a document that leaves the company says where things live
and answers nothing.

## 11.3

**Question** — ¿Su organización protege los datos de recuperación con controles equivalentes a los
aplicados a los datos originales? Haga referencia al cifrado o a la separación de datos, según los
requisitos.

**Answer** — SÍ

**Justification**

Las copias de seguridad se cifran con el mismo estándar aplicado a los datos originales — AES-256 — bajo claves dedicadas a las bóvedas de respaldo, distintas por entorno y por región. El acceso a esas bóvedas está gobernado por políticas declaradas como código.

La copia destinada a recuperación ante desastres reside en una región distinta de la primaria y bajo su propia clave, de modo que la pérdida o el compromiso de una región no alcanza la copia mantenida en la otra.

**Notes** — the backup vaults carry their own keys, `aws_kms_key.local` and `aws_kms_key.dr`
(`modules/cross_region_backup/main.tf:29,42`), rather than the application's key. Assuming otherwise
from the application module's multi-Region key would have inverted the argument: it is not "same key,
same protection" but "separate keys, so compromising one region does not reach the other region's
copy" — which answers the question's separation half better than sameness would.

## 11.4

**Question** — ¿Su organización asegura que la infraestructura de red se mantenga actualizada?

**Answer** — SÍ

**Justification**

La infraestructura de red se declara como código y se aplica mediante revisión por pares, de modo que ningún cambio llega al entorno sin quedar registrado en el control de versiones. Los componentes gestionados por el proveedor de nube reciben las actualizaciones dentro de las ventanas de mantenimiento configuradas.

Las versiones de los proveedores y módulos de infraestructura se revisan de forma automatizada, con propuestas de actualización abiertas periódicamente y sujetas a un período mínimo de cuarentena antes de poder incorporarse.

**Notes** — product names genericized. The quarantine claim is the `minimumReleaseAge` practice, which
does cover the Terraform providers.

## 11.5

**Question** — ¿Su organización establece y mantiene una instancia aislada de los datos de
recuperación? Algunos ejemplos incluyen el control de versiones de los destinos de respaldo mediante
sistemas o servicios fuera de línea, en la nube o fuera de las instalaciones.

**Answer** — SÍ

**Justification**

La copia destinada a recuperación reside en una región distinta de la que aloja el entorno productivo, en una bóveda propia y bajo su propia clave. La escribe el servicio de respaldo, no la aplicación.

De ese modo, ni un fallo de la región primaria ni un compromiso del entorno de aplicación alcanzan la copia de recuperación.

**Notes** — isolation is this item's own content; 11.1 owns the monthly restore test and 11.3 owns the
protection equivalence, so neither is repeated here. **No `vault_lock` configuration exists** in
`modules/cross_region_backup/` — immutability is deliberately not claimed, unlike the CloudTrail
bucket, which does carry `object_lock_enabled = true`. The isolation covers regional failure and an
application-side compromise; it does not cover account-level compromise, and nothing in the text
suggests it does.

## 12.1

**Question** — ¿Su organización establece y mantiene un programa de concienciación en seguridad? […]
La formación debe impartirse en el momento de la contratación y, como mínimo, de forma anual. Revise
y actualice el contenido de manera anual o cuando se produzcan cambios significativos […]

**Answer** — SÍ

**Justification**

La formación en seguridad de la información se imparte a todos los colaboradores en el momento de la incorporación y se repite con periodicidad anual, conducida por la Dirección Técnica.

El contenido abarca los principios de seguridad de la plataforma, la normativa de protección de datos aplicable, la gestión de credenciales y el uso de la bóveda corporativa, las amenazas de phishing e ingeniería social, y el procedimiento de respuesta a incidentes.

Cada sesión queda registrada con fecha, tema, participantes, responsable de la sesión y material utilizado.

**Notes** — three removals. The headcount ("en una compañía de siete personas") is the engineer's
standing constraint, and here it carried the whole final paragraph. That paragraph argued a company
that size needs no attendance list — a defence of an objection nobody raised, which concedes
informality while handing over the team size. The training log was named in Portuguese inside a
Spanish document; its CONTENTS are what prove the control, so they are described and the filename is
not. The record with date, topic, participants, facilitator and material is the strong part and an
assessor can ask for it.

## 12.2

**Question** — ¿Su organización capacita a los miembros del personal para reconocer ataques de
ingeniería social, tales como phishing, suplantación (spoofing) y uso no autorizado?

**Answer** — SÍ

**Justification**

El reconocimiento de ataques de ingeniería social forma parte del contenido obligatorio: phishing, suplantación de identidad y solicitudes de acceso o de información que llegan por fuera del canal establecido.

La orientación es operativa antes que conceptual: ante una solicitud de credenciales, de datos o de un cambio que llegue por correo o mensaje, la instrucción es verificar por el canal habitual con la persona o el cliente antes de actuar, y escalar a la Dirección Técnica cuando la verificación no sea posible.

**Notes** — the pre-review text was a bare cross-reference to 12.1, which is the extreme case of an
answer with no sentence of its own and costs most here, since an assessor reading row by row is sent
backwards. The way out is not repeating 12.1: 12.1 asks whether the programme exists and is annual,
this one asks whether people can RECOGNIZE an attack — curriculum versus effect on the person. The
second paragraph is that effect, confirmed by the engineer as what is actually taught. `suplantación
de identidad` matches the vocabulary of the question itself. No phishing simulation is claimed —
4Shark runs no simulated campaign, and an assessor would ask for the evidence.

## 12.3

**Question** — ¿Su organización capacita a los miembros del personal en las mejores prácticas de
autenticación? Algunos temas de ejemplo incluyen autenticación multifactor (MFA), composición de
contraseñas y gestión de credenciales.

**Answer** — SÍ

**Justification**

La formación cubre las prácticas de autenticación que la organización exige: credenciales únicas por servicio, nunca reutilizadas ni compartidas; almacenamiento exclusivo en la bóveda corporativa, de modo que el colaborador no necesita memorizar ni anotar ninguna; y activación del segundo factor en todo servicio que lo ofrezca.

El énfasis está en que la práctica sea sostenible: la bóveda genera y guarda las contraseñas, de modo que la composición fuerte y la ausencia de reutilización dejan de depender de la disciplina individual.

**Notes** — the pre-review text was another bare cross-reference to 12.1. The second paragraph is what
earns the item: the vault removes the dependency on individual discipline, which is the honest reason
a small company can claim this control without a security team. **The application's password
complexity rule (`app/app/models/user.rb:301`) is deliberately NOT used** — it governs the PRODUCT's
users, while this question is about training the personnel; pulling it in would answer the
neighbouring question. `activación del segundo factor en todo servicio que lo ofrezca` sits inside
"the practices the organization requires", so it states what is taught and demanded rather than an
audit result — which keeps it true while 6.5 (the support profile's second factor) is still target
state.

## 12.4

**Question** — ¿Su organización capacita a los miembros del personal sobre cómo identificar y
gestionar adecuadamente los datos confidenciales, incluyendo su almacenamiento, transferencia,
archivo y destrucción? Esto también incluye […] despeje de escritorio y pantalla […]

**Answer** — SÍ

**Justification**

La formación cubre el ciclo completo del dato confidencial: los datos de cliente residen exclusivamente en la base gestionada dentro de la red privada y nunca en el equipo de la persona; la transferencia ocurre por canales cifrados; los archivos generados por las funcionalidades de extracción se descartan automáticamente a las 48 horas; y la destrucción se ejecuta por anonimización irreversible al término del período de retención.

Sobre las prácticas de escritorio y pantalla despejados, la orientación al equipo cubre el bloqueo de la pantalla al ausentarse del puesto y el borrado de las superficies compartidas al cerrar una reunión. El bloqueo no queda librado a la memoria del colaborador: la estación bloquea de forma automática tras quince minutos de inactividad, por política que su cuenta no puede alterar, y la sesión de la aplicación caduca tras una hora sin actividad.

**Notes** — three removals, two of them factual errors. The pre-review text said the session expires
`de forma absoluta en una hora`; `:timeoutable` with `config.timeout_in = 1.hour`
(`app/config/initializers/devise.rb:179`) is INACTIVITY, the same correction already applied at 3.7
and 3.8. It also claimed mass export is impossible from that screen, three lines after naming the
extraction features — a self-contradiction an assessor catches on the first pass. The third removal
was strategic rather than factual: a paragraph arguing 4Shark has no office, so the clean-desk
scenario does not materialize. That argues with the question, concedes nothing useful and describes
how the company operates. The second paragraph now matches 4.3's fifteen-minute policy lock, so both
answers say the same thing. **The 48-hour figure is verified** — `ttl 2.days` on seven attachment
models, among them `app/app/models/payment_exportation_attachment.rb:5` and
`app/app/models/user_history_attachment.rb:5`.

## 12.5

**Question** — ¿Su organización capacita a los miembros del personal para que conozcan las causas de
la exposición no intencionada de datos? […] la entrega incorrecta de datos confidenciales, la pérdida
de un dispositivo portátil […] o la publicación de datos a audiencias no deseadas.

**Answer** — SÍ

**Justification**

La entrega incorrecta de información es el escenario más probable en la operación diaria — una planilla enviada al destinatario equivocado, o un dato de cliente remitido por un canal que no corresponde — y es el caso trabajado con más detalle. Incluye la conducta esperada cuando es el propio cliente quien remite información que no debía salir de su entorno: no reenviarla, no incorporarla a ningún registro y avisar.

La pérdida de un dispositivo se aborda junto con su consecuencia real en esta arquitectura: el equipo no almacena datos de cliente, y la revocación de la identidad corporativa retira el acceso a los servicios en el acto. Por eso la respuesta correcta ante una pérdida es avisar de inmediato, y no intentar recuperar el equipo por cuenta propia.

La publicación a audiencias no previstas se trata en el contexto de los entornos de desarrollo y homologación, que operan con datos sintéticos y nunca con copia de datos productivos.

**Notes** — the strongest pre-review answer in block 12; all three causes already carried 4Shark-specific
content. Split into one paragraph per cause, since a ten-line block makes the assessor hunt for where
each of the three was answered. `retira todo acceso` narrowed to `retira el acceso a los servicios`:
revoking the corporate identity drops what sits behind the identity provider, not the machine's local
account nor the vault installed on it, and a universal like that is what a technical assessor picks
for the follow-up question. The explicit conduct for the client-sends-what-they-should-not case was
ADDED — in a questionnaire Atento reads, it turns a scenario that could read as a jab into a
statement that 4Shark protects the client's data even when the client errs.

## 12.6

**Question** — ¿Su organización capacita a los miembros del personal para reconocer un posible
incidente y reportarlo?

**Answer** — SÍ

**Justification**

La orientación define qué cuenta como incidente a efectos de reporte, y el criterio es deliberadamente amplio: cualquier acceso, mensaje o comportamiento del sistema que la persona no sepa explicar. No se le pide al colaborador que califique la severidad ni que confirme que hubo un incidente antes de avisar — esa evaluación corresponde a quien recibe el reporte.

El canal es security@4shark.com.br, un buzón compartido por los responsables de seguridad. A partir de allí se aplica la política interna de respuesta a incidentes, que define los roles, el flujo de escalamiento y los criterios de severidad.

**Notes** — the pre-review text answered `reportarlo` well and `reconocer` barely; those are two
questions, the same pair 12.2 carries. The first paragraph is the recognition half, and the control it
describes is a real one: the reporting threshold is deliberately low, because requiring someone to
judge severity before speaking is what makes them rationalize instead of report. **The address is
verified** — `dot-claude-plans/active/content/vendor-assessment-barigui/PLAN.md:253` records
`security@4shark.com.br` as an existing group with Paulo and Émerson, configured to accept external
posts, checked off. It stays in the answer because it is the easiest claim in the questionnaire for
an assessor to test, and it holds.

## 12.7

**Question** (asked in English in the workbook) — Train your workforce to understand how to check for
and report outdated software patches or any failures in automated processes and tools. Part of this
training should include notifying IT staff of any failures in automated processes and tools.

**Answer** — SÍ

**Justification**

Las actualizaciones de dependencias no dependen de que alguien las busque: un servicio automatizado abre propuestas de actualización de forma continua, y la verificación en integración continua impide incorporar una versión que no haya cumplido el período mínimo de cuarentena. La revisión y la incorporación de esas propuestas forman parte de la rutina del equipo de desarrollo.

Los fallos de los procesos automatizados — tanto de las canalizaciones de construcción y despliegue como de la infraestructura — se notifican por sí mismos en el canal corporativo que el equipo técnico monitorea. La orientación al resto del equipo es avisar por el mismo canal de incidentes cuando una herramienta se comporta de forma anómala.

**Notes** — the removed closing sentence claimed 4Shark is an entirely technical team, so the
question's premise of separate general staff and IT does not hold. It argues with the question (the
12.4 clean-desk defect) and it is FALSE: the operations team is not technical in that sense, and the
workstation answers describe exactly that separation — an assessor reading the whole document finds
both statements and one destroys the other. The dependency-update product name was dropped for the
same reason as 11.4 and because naming one tool describes a three-layer arrangement badly (instant
security PRs, regular updates, the CI minimum-age check). The second paragraph closes the real gap:
the question is about the WORKFORCE reporting failures, and the pre-review text covered only the
technical team.

## 12.8

**Question** — ¿Su organización capacita a los miembros del personal sobre los riesgos de conectar y
transmitir datos a través de redes no seguras […]? Si la compañía cuenta con empleados remotos, la
capacitación debe incluir directrices […] para configurar de forma segura la infraestructura de red de
sus hogares.

**Answer** — SÍ

**Justification**

El riesgo de la red insegura está resuelto por diseño, antes de depender de la conducta del usuario: todo el tráfico corporativo viaja cifrado con TLS 1.2 o superior, y el acceso a la infraestructura interna y a las bases de datos productivas exige VPN desde cualquier red, sin excepción para la red doméstica. Una red comprometida no expone el contenido de la sesión ni concede acceso a recurso alguno.

La formación cubre ese principio y las medidas que sí dependen de la persona en el entorno doméstico: mantener el enrutador con credencial propia y no la de fábrica, su firmware actualizado, y la red inalámbrica con cifrado vigente.

**Notes** — the central argument was kept whole: the control does not rest on the network, so a bad
network is not a variable, which is stronger than any training. TLS 1.2 is verified at
`terraform/dns/security_4sharkpay_com.tf:8`. One sentence removed — that connecting from a public or
third-party network is neither forbidden nor requires special configuration. Nobody asked what the
policy on public networks IS; "not forbidden" is what a checklist assessor marks and returns as a
follow-up. `la totalidad del equipo` also went: the question already assumes remote workers, so
answering about the home environment needs no statement of company composition. Wi-Fi encryption was
ADDED to the home-network list (the engineer confirmed) — the question asks about configuring the home
network securely and router password plus firmware alone is thin; no protocol version is named.

## 13.1

**Question** — ¿Su organización establece y mantiene un inventario de proveedores de servicios? El
inventario debe enumerar a todos los proveedores de servicios conocidos, incluir sus clasificaciones
y designar un contacto corporativo para cada proveedor de servicios. Revise y actualice el inventario
de forma anual o cuando se produzcan cambios significativos […]

**Answer** — SÍ

**Justification**

4Shark mantiene un inventario de sus proveedores de servicios con la función que cada uno desempeña, si trata datos personales por cuenta de 4Shark, su clasificación de criticidad y el contacto corporativo designado. El inventario se revisa anualmente y ante cualquier contratación, sustitución o cese de proveedor.

La selección está además restringida por política a proveedores de tecnología de gran porte y reconocimiento internacional que mantengan certificaciones independientes vigentes, auditoría externa continua y cláusulas contractuales de protección de datos.

**Notes** — the `SÍ` rests on `compliance/records/inventario-de-fornecedores.md` and
`compliance/internal/politica-de-gestao-de-fornecedores-e-suboperadores.md` (PR #13), which carry the
two fields the question names — criticality classification and a designated corporate contact per
provider — plus the annual review. Before those documents existed the answer was `NO`: the RoPA is a
record of PROCESSING ACTIVITIES and carries neither field.

**The answer does not enumerate providers, and that is the load-bearing decision.** The authoritative
list lives in the inventory; a list typed into a spreadsheet cell is what drifts from it. The
questionnaire's own draft demonstrated the failure — it named five providers while the RoPA carries
ten, included Zendesk and the observability providers and omitted GitHub, so an assessor holding both
documents would have seen two different inventories of one company. The per-provider certification
claim goes with the list for the same reason: SOC 2 and ISO 27001 were never verified across a set
that includes Redis Cloud and New Relic. An assessor wanting certifications per provider gets the
inventory.

Also removed: the verdict-restating sentence, and the undated roadmap promise (`prevista para
implantación`) — the future-tense shape the Positivo reviewer rejected when demanding fact over
intent.

## 14.1

**Question** — ¿Su organización designa a una persona clave y al menos un suplente que gestionen el
proceso de gestión de incidentes de la compañía? […] Si se utiliza un proveedor externo, se debe
designar al menos a una persona dentro de la compañía para supervisar el trabajo de terceros. Revise
este esquema de forma anual […]

**Answer** — SÍ

**Justification**

La política interna de respuesta a incidentes define los roles y las responsabilidades del proceso. La coordinación corresponde a la Dirección Técnica — Paulo Ribeiro, Co-Founder & CTO y Encargado de Protección de Datos — con suplencia designada en la persona de Émerson Oliveira, que comparte el buzón de reporte de incidentes.

La gestión de incidentes es interna y no está delegada a un proveedor externo. El esquema se revisa de forma anual.

**Notes** — the pre-review text carried a literal `[PENDIENTE: indicar el nombre de la persona
suplente.]`, which is worse in a sent workbook than the gap it records: it shows the assessor the
document was answered halfway. The deputy is not an arbitrary pick — Émerson Oliveira already receives
`security@4shark.com.br` alongside Paulo, so the designation matches who can actually act when the
primary is away, which is the continuity the question is asking about. The sentence stating the
process is internal was ADDED: the question spends two lines on the outsourced case and its required
internal supervisor, so saying it does not apply closes that half instead of leaving the assessor to
infer.

## 14.2

**Question** — ¿Su organización establece y mantiene información de contacto para las partes que deben
ser informadas sobre incidentes de seguridad? Los contactos pueden incluir empleados internos,
proveedores externos, autoridades policiales, proveedores de seguros cibernéticos, agencias
gubernamentales relevantes, socios ISAC u otras partes interesadas. Verifique los contactos de forma
anual […]

**Answer** — SÍ

**Justification**

La política interna de respuesta a incidentes define a quién se notifica y en qué orden: el cliente afectado, la autoridad de protección de datos competente en la jurisdicción correspondiente, y los titulares cuando el incidente lo exija.

El contacto de cada cliente proviene del acuerdo vigente, que es la fuente que se mantiene actualizada por la propia relación contractual. La verificación de los contactos se realiza de forma anual.

**Notes** — the pre-review content was correct but compressed into one sentence and left the more
interesting half unanswered: WHERE each contact comes from and why it is current. The question asks
that the information be kept up to date, and what answers that is the source being the contract, which
stays alive through the commercial relationship — a contact drawn from a contract does not go stale the
way a contact spreadsheet does. Two deliberate omissions: the cyber-insurance / law-enforcement / ISAC
examples the question offers are not enumerated, because none exists at 4Shark and listing
inapplicable examples to look complete invites questions the wording (`pueden incluir`) does not
require; and the authority is named generically rather than as the ANPD, because the document serves
Brazil, Mexico, Chile and Colombia and a single-country anchor is the error already corrected earlier
in this questionnaire.

## 14.3

**Question** — ¿Su organización establece y mantiene un proceso corporativo para que el personal
reporte incidentes de seguridad? El proceso incluye el plazo de notificación, el personal al que deben
dirigirse los reportes, el mecanismo de reporte y la información mínima que debe informarse.
**Asegúrese de que el proceso esté disponible públicamente para todos los empleados.** Revise el
proceso de forma anual […]

**Answer** — SÍ

**Justification**

El reporte se dirige a un canal dedicado, security@4shark.com.br, que llega a los responsables de seguridad.

El proceso está formalizado en la política interna de respuesta a incidentes: plazo de notificación, destinatarios, mecanismo e información mínima a informar, con flujo de escalamiento por severidad y criterios de clasificación, sobre las cinco etapas de planificación, identificación, contención, erradicación y recuperación.

La política forma parte del conjunto documental que se entrega a todos los colaboradores en la incorporación y permanece accesible. Se revisa de forma anual.

**Notes** — two claims removed that an assessor tests in thirty seconds: `disponible 24 horas al día`
is empty (every mailbox always receives) while reading as a round-the-clock service commitment 4Shark
does not offer, and `confirmación automática de entrega` is a specific feature testable by sending one
email. The question's bolded requirement — that the process be AVAILABLE to every employee — went
unanswered by the pre-review text, which offered signing instead; signing proves awareness at a
moment, availability is what lets someone consult it during an incident. **`se firma` was dropped
rather than asserted**: the signature round on record covers the superseded hand-made set, not the
text in the `compliance` repository, and 14.3 never asks about signature — it asks that the process be
documented and available — so the claim costs nothing to omit. The repository keeps placeholders BY
DESIGN (`GENERATE-COMPLIANCE-DOCUMENTS.md`: copy → fill → render → DocuSign, never commit the filled
version), so unfilled placeholders are not evidence the documents are drafts.

## 15.1

**Question** — ¿Su organización cuenta con un Plan de Continuidad del Negocio (BCP) y un Plan de
Recuperación ante Desastres (DRP) documentados, actualizados y formalmente aprobados?

**Answer** — SÍ

**Justification**

4Shark cuenta con un Plan de Continuidad del Negocio y Recuperación ante Desastres documentado, con revisión periódica. El plan establece los objetivos de recuperación comprometidos, los dos escenarios previstos — corrupción de datos con la región primaria operativa, y pérdida total de la región primaria —, la separación geográfica interregional de las copias y la cadencia de pruebas de recuperación.

Las pruebas no son declarativas: la restauración se valida de forma automatizada y periódica, con registro fechado de cada ejecución, además de un ejercicio anual de recuperación completa.

**Notes** — the plan genuinely exists —
`compliance/internal/plano-de-continuidade-de-negocios-e-recuperacao-de-desastres.md`, created by PR #9
— and the two scenarios named here are the same two the restore runbook describes, so this is a
description of what is in place rather than vendor prose. `formalmente aprobado por la dirección` was
dropped: it is the same signature claim as 14.3, and the signature round on record covers the
superseded set rather than this text.
**Here the omission COSTS something**, unlike at 14.3 — the question asks for three properties and
approval is one of them — but it is also the one an assessor asks to see signed, so asserting it
unverified is the worse trade. The second paragraph is what separates this answer from the many
vendors who answer `SÍ` with a plan nobody ever exercised: automated restore validation with dated
evidence (`BACKUP-RESTORE-TESTING.md`, logged in the Drive sheet `Registro de Testes de Restauração de
Backup`) plus the annual full-recovery drill. RTO figures and measured times are deliberately absent —
the internal plan states the committed parameters and the measured margins stay in the internal
runbook, because publishing a measured margin turns it into an SLA.

## 15.2

**Question** — ¿Su organización ha definido los valores de RTO y RPO para los servicios críticos que
proporciona, y son compatibles con los requisitos de la organización?

**Answer** — SÍ

**Justification**

RPO igual o inferior a 1 hora y RTO de 4 horas, declarados en el Plan de Continuidad del Negocio y Recuperación ante Desastres.

Los valores se sustentan en la arquitectura de la plataforma: la base de datos gestionada mantiene recuperación a un punto en el tiempo de forma continua y copias automáticas diarias, opera en múltiples zonas de disponibilidad con conmutación automática, y la capa de aplicación se autorrecupera sin intervención. La restauración a partir de esas copias se prueba de forma periódica, de modo que los valores comprometidos están verificados y no solo estimados.

**Notes** — the question asks for numbers and the numbers exist (RPO ≤ 1h, RTO 4h — the same
committed to Barigui and stated in the internal plan), so they stay. Product names genericized as
since 11.4; what sustains the RPO is continuous point-in-time recovery existing, not the database's
commercial name. The closing sentence answers the question's SECOND half, `¿son compatibles con los
requisitos?` — the pre-review text asserted compatibility and stopped, and asserting is not
sustaining. What sustains it is the periodic restore test, which turns the RTO from a declared target
into a verified number. Same evidence as 15.1 but answering a different question: there it shows the
plan is exercised, here it shows the values are real. Measured times still withheld — stating
"verified" is the strong claim; stating a measured duration converts the margin into a contractual
expectation.

## 15.3

**Question** — ¿Su organización realiza pruebas periódicas de los planes de Continuidad del Negocio y
Recuperación ante Desastres (al menos de forma anual), y **puede proporcionar evidencia de los
resultados y de las acciones correctivas adoptadas**?

**Answer** — SÍ

**Justification**

Las pruebas de restauración se ejecutan de forma automatizada y mensual: la copia interregional se restaura en la región de recuperación y cada ejecución genera evidencia fechada, con alerta al equipo técnico si la validación falla.

Adicionalmente se realiza un ejercicio anual de recuperación completa, que ejecuta el cambio real de la aplicación hacia la base restaurada y mide el tiempo de recuperación extremo a extremo. El procedimiento y los resultados quedan registrados, y las correcciones derivadas de cada ejercicio se incorporan al plan.

**Notes** — the strongest item in block 15; the pre-review text was nearly right. The failure alert was
ADDED because without it "generates dated evidence" describes a test that runs and files a result
nobody reads, and the question is precisely about trusting the plan — the alarm is what turns a failure
into action rather than a log line. The closing clause answers the half the pre-review text skipped:
they ask for evidence of results AND of corrective actions taken, and saying corrections feed back into
the plan closes the loop that separates a test from a ritual. The explicit reference to the internal
runbook was REMOVED — naming an internal document in an external questionnaire invites a request for
it, and it holds the measured times and the operational procedure deliberately kept out. That results
are recorded is enough; where they are recorded is internal.

## 15.4

**Question** — ¿Su organización cuenta con mecanismos redundantes (infraestructura, comunicaciones y
respaldos) para garantizar la continuidad operativa y el cumplimiento de los objetivos RTO y RPO en
caso de interrupciones?

**Answer** — SÍ

**Justification**

La redundancia está presente en cada capa. La base de datos opera en múltiples zonas de disponibilidad con conmutación automática entre ellas. La aplicación corre con varias instancias por servicio y se autorrecupera ante la pérdida de cualquiera de ellas. La capa perimetral, que resuelve nombres y filtra el tráfico entrante, opera sobre una red distribuida globalmente.

Las copias de seguridad se retienen en la región primaria y se replican a una segunda región, de modo que la pérdida completa de una región no compromete la recuperación.

**Notes** — two removals. The region name `us-west-2` went, as at 11.2: that a second-region copy
exists is what answers the question, and which region it is adds nothing for the assessor while telling
an attacker where to look. **The availability figure `superior al 99,9%` is the removal that matters**
— a number in an assessment questionnaire is read as a commitment, not a statistic. It was not asked
(the question is whether redundant mechanisms exist, not what they yield), and nobody verified how it
was computed or over what window, so publishing it creates an expectation with nothing behind it. The
shape also changed: the pre-review text was a label-and-product list (`Base de datos:`, `Aplicación:`)
that describes an inventory, and prose lets each layer state WHAT HAPPENS WHEN SOMETHING FAILS, which
is what the question asks — "operates across availability zones" versus "switches over automatically
between them" is the difference between listing a feature and describing redundancy.

## 16.1

**Question** — ¿Su organización, en caso de procesar datos personales, de contacto, de identificación,
financieros o económicos **en nombre de Atento**, cuenta con las medidas técnicas y organizativas
necesarias para prevenir accesos no autorizados y garantizar la integridad de los datos?

**Answer** — SÍ

**Justification**

Las medidas técnicas cubren el dato en cada estado. En tránsito viaja cifrado con TLS 1.2 o superior; en reposo, bajo claves dedicadas por entorno. El acceso a la plataforma se rige por un control jerárquico de denegación por defecto, y el acceso a la infraestructura por menor privilegio con elevación temporal sujeta a segundo factor. Las contraseñas se almacenan con hash irreversible, y al término del período de retención los datos se anonimizan de forma irreversible.

Los entornos están segregados de extremo a extremo: desarrollo, homologación y producción operan con credenciales, redes e infraestructura independientes, y los entornos inferiores utilizan exclusivamente datos sintéticos. El tráfico entrante pasa por filtrado perimetral con reglas del estándar OWASP y limitación de tasa, y los accesos quedan registrados de forma auditable.

En el plano organizativo, el conjunto de políticas internas de seguridad y privacidad se complementa con acuerdos de confidencialidad suscritos por los colaboradores, formación en la incorporación con reciclaje anual, y desarrollo seguro con revisión de código y revisión de seguridad obligatorias antes de incorporar cualquier cambio.

**Notes** — the umbrella question of the block, so length is justified here in a way it was not where
length was padding; the pre-review text was reorganized from a semicolon-separated label list into
prose grouped by STATE OF THE DATA and by plane. Three factual edits: `AES-256 / AWS KMS` became
dedicated per-environment keys (the engineer's correction at 3.6 — the migration is complete and that
is the stronger claim); the count `15 políticas` went, because counting documents invites a request
for all fifteen and cardinality sustains nothing; `formalmente aprobadas` went for the same reason as
14.3 and 15.1, and `firmados por todos los colaboradores` was narrowed to `suscritos por los
colaboradores` since the universal is unconfirmed. On the wording `en nombre de Atento`: 4Shark
operates as processor for several clients on shared infrastructure, so the answer describes the
platform's measures without implying controls singular to one client — which is what tenant
segregation actually sustains.

## 16.2

**Question** — ¿Su organización, en caso de procesar datos personales SENSIBLES —salud, genéticos,
biométricos, origen racial o étnico, opiniones filosóficas o políticas, orientación sexual— en nombre
de Atento, cuenta con las medidas técnicas y organizativas necesarias […]?

**Answer** — N/A

**Justification**

4Shark no trata datos personales sensibles por cuenta de sus clientes: no se procesan datos de salud, genéticos, biométricos, de origen racial o étnico, de convicción filosófica o política, ni relativos a la orientación sexual.

Las medidas descritas en el ítem anterior se aplican por igual a la totalidad de los datos tratados, sin distinción de categoría.

**Notes** — `N/A` is the right verdict: the question is conditional (`en caso de procesar`) and the
condition does not hold. `Existe una declaración interna formal en ese sentido` was removed for two
reasons, the second specific to this item: it carries the same unconfirmed signature dependency as
elsewhere, AND it strengthens nothing — what answers the question is that no sensitive data is
processed, which is verifiable from what the platform collects, so pointing at an internal document
adds a layer of indirection and invites a request for it. The declaration is real
(`legal-compliance-documents/PLAN.md:126` — a Termo de Ciência defining the closed art. 5º II list and
declaring 4Shark does not treat those categories); the claim is not false, it is unnecessary and
priced. The closing clause became `sin distinción de categoría`, which closes better: the measures do
not depend on classification to apply. **A pre-session correction is what makes this `N/A` safe** —
`POLÍTICA DE TRATAMENTO DE DADOS PESSOAIS SENSÍVEIS` had held copied content describing biometric and
health processing, fiction that would have contradicted this answer directly if an assessor requested
it; it was rewritten as a truthful declaration.

## 16.3

**Question** — ¿Su organización está establecida en el país donde se prestarán los servicios?

**Answer** — NO

**Justification**

4SHARK TECNOLOGIA LTDA. está constituida en Brasil, con sede en São Paulo. La prestación es en modalidad SaaS, de alcance regional, por lo que la organización no cuenta con establecimiento societario en cada uno de los países donde el servicio es utilizado.

El tratamiento de datos y sus salvaguardas de transferencia internacional se detallan en el ítem siguiente.

**Notes** — the question is ambiguous and the verdict turns on which reading applies. Read as "the
client's country", Atento operates across several Latin American countries and 4Shark is incorporated
only in Brazil; read as "where the infrastructure runs", it is the United States. `NO` is kept because
the likely intent in a multinational vendor assessment is whether a local entity exists in each
jurisdiction served, and none does — answering `SÍ` because both companies exist in Brazil would be
picking the convenient reading. The pre-review text answered the infrastructure reading, which turns a
question about CORPORATE ESTABLISHMENT into a statement about infrastructure location — 16.4's
subject — and handed over the exact region, the class of detail trimmed since 11.2. Legal name and
seat stay: a third-party questionnaire has to identify the contracting entity, and both already appear
in the form's own header and in the public policies. **Open, and the engineer holds it**: if Atento
contracts through a Brazilian entity with the service rendered in Brazil, the reading changes and `SÍ`
becomes defensible.

## 16.4

**Question** — ¿Su organización […] cumple con los requisitos legales […] en materia de protección de
datos? Si la respuesta es afirmativa, indique en la columna E el tipo de salvaguarda aplicada para la
transferencia internacional de datos.

**Answer** — SÍ

**Justification**

El tratamiento ocurre en regiones de nube situadas fuera del territorio de constitución. La salvaguarda aplicada es la de cláusulas contractuales tipo suscritas con el proveedor de infraestructura, complementadas por las obligaciones de protección de datos previstas en el acuerdo de procesamiento con el cliente, que rige también la actuación de suboperadores.

El acceso a los datos se restringe al personal de 4Shark; no existen otras empresas del Grupo con acceso a los datos tratados por cuenta del cliente.

**Notes** — the question asks the safeguard to be NAMED in column E, so `cláusulas contractuales tipo`
appears in those words: that is the vocabulary the assessor scans for. The second paragraph answers
the half nobody had read closely — the question is literally about access `por otras empresas del
Grupo`, written for vendors that are multinationals moving data between affiliates, and saying that
does not exist at 4Shark eliminates a whole risk category rather than merely describing safeguards.
Statute citations (LGPD art. 33 II, the Chilean laws) were dropped: single-jurisdiction anchoring, made
worse by being PARTIAL — Brazil and Chile named, Mexico and Colombia omitted. Provider name and region
also dropped, per 16.3 and 11.2. **Two open dependencies, both the engineer's.** The pre-review text
carried `[PENDIENTE: confirmar el estado de la aceptación formal del AWS Data Processing Addendum.]`,
and that is material rather than cosmetic: the standard contractual clauses this `SÍ` names reach
4Shark THROUGH that addendum, so if it was never formally accepted, the safeguard declared in column E
does not exist. Separately, `legal-compliance-documents/PLAN.md:173` records four group CNPJs with the
operation fragmented across them — if any of those entities has access to client data, the second
paragraph is false. The document describes the fragmentation as fiscal and contractual rather than
data-access, but that is a reading of the page, not a confirmation.

## 16.5

**Question** — ¿Puede su organización garantizar que los datos personales compartidos por Atento serán
tratados exclusivamente para los fines acordados dentro del alcance de los servicios contratados y no
para ningún otro propósito?

**Answer** — SÍ

**Justification**

Los datos personales compartidos por el cliente se tratan exclusivamente para las finalidades acordadas dentro del alcance de los servicios contratados. El compromiso está formalizado en el acuerdo de tratamiento de datos y registrado en el Registro de Operaciones de Tratamiento, que documenta la finalidad y la base legal de cada actividad.

4Shark no vende, comparte ni divulga datos personales a terceros para ninguna otra finalidad. Como operadora, actúa únicamente conforme a las instrucciones del controlador.

**Notes** — `compartidos por Atento` became `compartidos por el cliente`: the answer describes a
platform practice, not an arrangement built for one company, and keeping the name would imply a
singular commitment that is not how the control works. `y la base legal` was added to what the RoPA
documents — true, and it strengthens the answer, since purpose limitation is stronger when the purpose
is bound to a declared legal basis. The closing sentence is what gives the rest its legal footing:
"we do not use it for anything else" is a promise, while acting as PROCESSOR under the controller's
instructions is the legal position that makes any other use a contractual and statutory violation
rather than a broken word — the argument a legal assessor looks for.

## 17.1

**Question** — ¿Su organización cuenta con un Sistema de Gestión de Privacidad implementado? En caso
afirmativo, **especifique qué componentes están incluidos** […] auditorías periódicas de privacidad,
etc.

**Answer** — SÍ

**Justification**

El sistema de gestión de privacidad se organiza en cuatro capas.

Documentos públicos: la Política de Privacidad, que incluye la divulgación de cookies y analítica, y los Términos de Uso, ambos publicados en el sitio corporativo.

Registros: el Registro de Operaciones de Tratamiento, que documenta por actividad la finalidad, la base legal, las categorías de datos, los plazos de retención, los suboperadores y las transferencias internacionales; y la Matriz de Aplicabilidad, que define qué documento aplica a cada área y quién lo suscribe. Con cada cliente se celebra además un acuerdo de tratamiento de datos.

Políticas internas: seguridad de la información, gestión de identidad y acceso, contraseñas, correo corporativo, activos y red, desarrollo seguro, copias de seguridad, almacenamiento y descarte, concienciación, respuesta a incidentes, privacidad desde el diseño, tratamiento de datos personales, declaración sobre datos sensibles, confidencialidad y continuidad del negocio.

Roles y controles: un Encargado de Protección de Datos designado, con las responsabilidades de seguridad y privacidad atribuidas a la Dirección Técnica; los controles técnicos descritos en el ítem 16.1; y los procedimientos operativos de atención a solicitudes de titulares y de eliminación técnica de datos.

**Notes** — enumeration is REQUESTED here (`especifique qué componentes están incluidos` with an
example list), so listing is the right answer, unlike 13.1 where listing created a contradiction. The
defect was form only: a fifteen-line run-on separated by semicolons, which forces the assessor to
disassemble the sentence to check each example off. Grouped into four layers it checks in one pass.
The count `15 políticas` was dropped — the list follows immediately, so the number informs nothing and
invites counting, and a count that comes out at fourteen gives the answer a defect it did not need.
**`auditorías periódicas de privacidad` is deliberately absent**: it does not exist (the RoPA is
reviewed on relevant change, an event trigger rather than a periodic audit), and since the question
offers examples rather than requirements, omitting is legitimate and needs no explanation. Claiming it
would be the easiest assertion in the questionnaire to disprove.

## 17.2

**Question** — ¿Su organización cuenta con una estructura de gobernanza designada para el área de
Privacidad? En caso afirmativo, identifique y explique brevemente su estructura de gobernanza […]

**Answer** — SÍ

**Justification**

La gobernanza de privacidad se ejerce directamente desde la dirección ejecutiva: el Encargado de Protección de Datos es Paulo Ribeiro, Co-Founder & CTO, de modo que la responsabilidad de privacidad reside en el mismo nivel que la decisión técnica y de producto.

La consecuencia operativa es que la aprobación de las políticas y las decisiones sobre tratamiento de datos no atraviesan una capa intermedia, y que el responsable de privacidad tiene autoridad directa sobre la arquitectura que trata los datos.

**Notes** — `4Shark es una empresa de ingeniería de tamaño reducido` was removed: it is the company-size
disclosure the engineer forbade, in a subtler form than a headcount but serving the same function —
asking for a discount up front. The structure stands on its own merits. `No existe un comité de
privacidad ni un área formal independiente` also went: conceding a gap nobody asked about, the 7.1 and
12.4 defect, and it turns a `SÍ` into an apology. The added clause — `autoridad directa sobre la
arquitectura que trata los datos` — is the real argument, and it is strong exactly where a large
company is weak: in committee structures the DPO often recommends rather than decides and must
negotiate with engineering, while here one person approves the policy and answers for the
architecture, which removes the gap between written policy and built system. 17.2 and 17.3 form a pair
— 17.3 answers `NO`, so any absence is declared there without 17.2 pre-empting it.

## 17.3

**Question** — ¿Su organización cuenta con Campeones de Privacidad designados?

**Answer** — NO

**Justification**

4Shark no cuenta con la figura de Campeones de Privacidad. La formación en protección de datos alcanza a la totalidad de los colaboradores, tanto en la incorporación como en el reciclaje anual, sin intermediarios.

**Notes** — the pre-review justification (`Con un equipo del tamaño actual […] el rol de multiplicador
que la figura busca cubrir no encuentra aquí una capa organizativa que atravesar`) was cut for two
reasons: it discloses company size again, in the `del tamaño actual` form 17.2 just lost, and it argues
against the question by explaining why the control would not make sense — the 12.4 and 12.7 defect.
What remains is stronger. A Privacy Champion is a MULTIPLIER role: someone per area carrying privacy to
the team because the DPO cannot reach everyone directly. Stating that training reaches every
collaborator directly answers what the role exists to solve without arguing it is unnecessary — the
assessor draws that conclusion themselves, and a conclusion they draw is worth more than one pushed at
them. The `NO` is correct and stays: the role does not exist, and inventing it would hand an assessor
who asks for the designated champions' names an empty list.

## 17.4

**Question** — ¿Su organización cuenta con un Responsable de Protección de Datos (DPO) designado o con
una persona responsable/oficial de protección de datos?

**Answer** — SÍ

**Justification**

4Shark cuenta con un Encargado de Protección de Datos formalmente designado e identificado en la Política de Privacidad publicada.

Nombre: Paulo Ribeiro. Cargo: Co-Founder & CTO / Encargado de Protección de Datos. Canal de contacto para asuntos de privacidad: privacidade-dados@4shark.com.br.

**Notes** — the personal address `paulo@4shark.com.br` was removed. The privacy channel already answers
both halves of the question — who the responsible person is and how to reach them — and it is the
address the public Privacy Policy itself publishes, so it is what Atento would find unaided. The
personal address adds no access and enters a distribution chain 4Shark does not control: this answer is
filed as a vendor contact record and circulates through the client's assessment chain. An institutional
channel also survives a change of person, while a personal address turns an HR event into stale
information sitting in the client's file. Name and title stay — nominal designation is literally what
the question asks and both already appear in the public policy. The site URL went too: stating it is in
the published Privacy Policy is enough, and the address is already in the form's own header.

## 17.5

**Question** — ¿Su organización identifica qué leyes y normativas de privacidad son aplicables a sus
actividades? En caso afirmativo, proporcione en la columna E su análisis de aplicabilidad o adjunte una
matriz de aplicabilidad en la columna F.

**Answer** — SÍ

**Justification**

4Shark identifica como normativa principal la Ley General de Protección de Datos brasileña (Ley 13.709/2018), por ser la jurisdicción de constitución de la compañía y la que rige su condición de operadora.

A ello se suman las normativas locales de protección de datos de cada país donde residen los titulares atendidos por la plataforma, cuya identificación se actualiza cuando la operación alcanza una nueva jurisdicción. El análisis está registrado en la Matriz de Aplicabilidad y en el Registro de Operaciones de Tratamiento.

**Notes** — **the ONE item where citing a statute is the correct answer**: the question literally asks
for the applicability analysis. The engineer's rule forbids anchoring a GENERIC answer in one country's
law; it does not forbid answering a question about which laws apply. The pre-review text broke
symmetry instead — it named the LGPD and then named ONLY Chile (Ley 19.628 and its reform by 21.719),
leaving out Mexico and Colombia, which Atento also operates and which already appeared in 3.3's
retention. An assessor serving four countries reads that list and concludes the analysis covered two.
Adding the missing statutes unaided is the wrong fix: the Mexican regime changed in 2025 with INAI
dissolved, and the Chilean law takes effect near the end of 2026, so naming specific laws with moving
dates and no legal confirmation creates a claim that ages by itself inside the client's file —
`legal-compliance-documents/PLAN.md:138` records exactly that recommendation, to confirm law and
authority per country with local counsel, Mexico and Chile especially. Describing the CRITERION instead
is true, complete for all four countries without naming any, and does not age. A nominal list is legal
counsel's work, and column F accepts the Applicability Matrix as an attachment, which is where such a
list would have proper backing.

## 17.6

**Question** — ¿Su organización cumple con las leyes y normativas de privacidad aplicables a sus
actividades? En caso afirmativo, proporcione en la columna E su análisis de cumplimiento […]

**Answer** — SÍ

**Justification**

El cumplimiento se sustenta en instrumentos verificables: la Política de Privacidad pública, que declara las bases legales de cada tratamiento y los derechos de los titulares; el Registro de Operaciones de Tratamiento; el acuerdo de tratamiento de datos celebrado con cada cliente; el Encargado de Protección de Datos designado; y el canal público para el ejercicio de derechos.

En el plano operativo, los plazos de retención están definidos por jurisdicción y la anonimización se ejecuta de forma automática al vencimiento, la transferencia internacional cuenta con salvaguarda contractual, y el conjunto de políticas internas de seguridad y privacidad rige la conducta del equipo.

**Notes** — the closing sentence (`En 10 años de operación 4Shark no registró ningún incidente de fuga
de datos ni sanción por parte de una autoridad de protección de datos`) was cut for three reasons, and
it is attractive enough to be worth stating them. It was NOT asked — the question wants the compliance
analysis, and incident history is another subject with its own items in block 14. **Absence of
sanction is not evidence of compliance**, and a risk assessor knows it, so the sentence signals that
the respondent conflates the two and weakens the perception of everything around it. And it creates a
permanent obligation: once 4Shark states in writing, in a filed document, that it never had a breach,
any future incident is read against that declaration — over a ten-year span nobody can verify today
with the rigour applied to every other claim in this review. What remains is stronger because each
item is a document or mechanism the assessor can request and check. Reorganized into two planes
(formal instruments, operational execution) for the 17.1 reason. `períodos de retención definidos`
became `definidos por jurisdicción`, the engineer's correction at 3.3, which has to read consistently
here.

## 17.7

**Question** — ¿Su organización sigue algún marco de gobernanza de privacidad y/o seguridad? En caso
afirmativo, identifíquelo(s) en la columna E.

**Answer** — SÍ

**Justification**

Para seguridad de la información, las prácticas y controles siguen ISO/IEC 27001 e ISO/IEC 27002 como marco de referencia. Para privacidad, los principios de la normativa aplicable, incluidas la privacidad desde el diseño y por defecto.

La arquitectura de infraestructura sigue el marco de buenas prácticas del proveedor de nube, en particular su pilar de seguridad.

**Notes** — the `LGPD (arts. 6.º, 46 a 49)` citation went: single-jurisdiction anchoring again, and
worse here than elsewhere because the question is about a GOVERNANCE FRAMEWORK rather than applicable
law — 17.5 is the item where statutes get named, so "the principles of the applicable regulation"
covers four countries without binding the framework to one. Cloud provider name genericized.
**The no-certification disclaimer was handled differently from the other concession cuts and the
distinction matters**: at 7.1, 12.4 and 17.2 the concession answered something nobody asked, but here
"we follow ISO 27001" is the claim most easily read AS certification, and an assessor who requests the
certificate and finds none doubts the whole questionnaire — so omitting it would carry real cost. The
resolution is in the VERB rather than a caveat: `como marco de referencia` states adopted reference
rather than certified conformance, affirmatively, and is the standard formulation for adopting without
certifying, which a TPRM assessor reads without needing the disclaimer. The explicit alternative
(`Ninguno de estos marcos cuenta con certificación formal`) remains available if the engineer prefers
leaving no margin.

## 17.8

**Question** — ¿Su organización vende, comparte o divulga datos personales a terceros? En caso
afirmativo, indique en la columna E cómo se ofrece la opción de exclusión (opt-out) […]

**Answer** — NO

**Justification**

4Shark no vende, comparte ni divulga datos personales a terceros bajo ninguna modalidad. Los datos tratados por cuenta del cliente se utilizan exclusivamente para la prestación del servicio contratado.

La única transmisión a terceros que ocurre es hacia los suboperadores necesarios para operar la plataforma, registrados en el Registro de Operaciones de Tratamiento y sujetos a obligaciones contractuales de protección de datos.

**Notes** — the verdict moved from `N/A` to `NO`. The pre-review reasoning was that the question
imports United States legislation (CCPA-style opt-out for sale and sharing) and therefore does not
apply to a Brazilian company — but the question asks a FACT, not a jurisdiction, and that fact has an
answer: 4Shark does not sell, share or disclose. The opt-out mechanism is requested only `en caso
afirmativo`. Answering `N/A` cost twice over: it discarded a clean negative, which is among the
strongest statements a data processor can make, and it reads as evasive precisely where an assessor is
most suspicious. It also contradicted 16.5, already approved, which states 4Shark does not sell or
share — two different answers to the same fact in one document. The second paragraph forecloses a
follow-up: `compartir` reads broadly in a privacy questionnaire, and an assessor may count transmission
to a subprocessor as sharing, so the answer names the only transmission that exists and shows it
registered and contractually bound — the same move made at 16.4 for group companies.

## 18.1

**Question** — ¿Su organización mantiene un inventario o registro de las actividades de tratamiento
realizadas en nombre de sus Clientes en calidad de Encargado del Tratamiento de Datos?

**Answer** — SÍ

**Justification**

4Shark mantiene un Registro de Operaciones de Tratamiento que documenta las actividades realizadas por cuenta de sus clientes en calidad de operadora, con la finalidad, las categorías de datos y de titulares, la base legal, el período de retención, los suboperadores involucrados y las transferencias internacionales de cada actividad.

El Registro se mantiene actualizado ante cualquier cambio relevante en las actividades de tratamiento.

**Notes** — the record's name is spelled out rather than abbreviated to `RoPA`: the acronym is known
inside privacy work, but the form is answered in Spanish for an assessment chain that includes
procurement and risk people, and the full term costs nothing. The maintenance sentence was added
because the question asks whether the register is MAINTAINED, not whether it exists, and a register
that exists but is frozen is not maintained — the vigencia-y-revisión clause is in the document
itself, so the claim is verifiable. **This is the item today's work most directly strengthened**: the
register the answer describes was updated by compliance PR #11, so the suboperator list it cites now
matches what the infrastructure provisions, and the document holds up if Atento requests it.

## 18.2

**Question** — ¿Su organización mantiene un inventario o registro de las actividades de tratamiento
realizadas en calidad de Responsable del Tratamiento de Datos? Por ejemplo, en relación con el uso de
datos de sus empleados, clientes, proveedores, etc.

**Answer** — SÍ

**Justification**

El mismo Registro cubre las actividades en las que 4Shark actúa como controladora, con la misma estructura de campos: datos de sus propios colaboradores, contactos comerciales, proveedores, y visitantes del sitio web en la actividad de analítica de uso, cuya base legal es el consentimiento captado por el banner de cookies.

**Notes** — `con la misma estructura de campos` answers a doubt the question creates on its own: having
just read 18.1's rich register (purpose, categories, legal basis, retention, subprocessors,
transfers), an assessor can read 18.2 as "a controller register also exists, perhaps thinner". Naming
the analytics legal basis matters because it is 4Shark's ONLY activity running on consent, and the
capture mechanism genuinely exists — the opt-in, default-denied cookie banner shipped with GA4 in
app-webclient 1.273.0. A privacy assessor looks precisely for consent-based activities whose capture
mechanism is weak or absent, so naming the banner answers before they ask. The pair 18.1/18.2 is where
the two roles become explicit in the document, which is favourable: separating what is processed for
the client from what is processed for itself shows the company understood the law's structure rather
than merely filling a form.

## 18.3

**Question** — ¿Su organización realiza evaluaciones de riesgos de privacidad […] tanto en calidad de
Responsable como de Encargado del Tratamiento? En caso afirmativo, indique en la columna E la fecha de
la evaluación más reciente y su alcance.

**Answer** — NO

**Justification**

La evaluación de riesgos de privacidad se ejerce de forma continua, integrada a las decisiones de arquitectura, desarrollo y operación: cada funcionalidad pasa por una evaluación de impactos de seguridad y privacidad durante la planificación, y por una revisión de seguridad dedicada antes de incorporar el cambio.

Esa evaluación no se ejecuta como programa periódico con metodología estructurada, registro de riesgos y ciclo de reevaluación documentado.

**Notes** — the change is ORDER. The pre-review text opened with the absence and then presented what
exists, so the assessor reads the negative first and the compensation second, which sounds like an
excuse. Inverted, they read the real control first and only then its boundary. **The boundary stays,
deliberately, unlike the concession cuts elsewhere**: this question asks for the DATE of the most
recent assessment and its scope, so it expects a dated event — leaving only the continuous process
would send the assessor hunting for a date, failing to find one, and concluding the answer is evasive.
Stating the limit is what prevents that reading. Worth carrying to the partner conversation: what is
missing here is the RECORD, not the assessment — 4Shark assesses privacy risk per feature; what does
not exist is a dated document proving it to a third party. Same shape as 13.1, and it makes this a
candidate to become `SÍ` cheaply: one documented risk assessment over the activities already in the
RoPA, with date and scope, plus a declared reassessment cycle.

## 18.4

**Question** — ¿Su organización realiza Evaluaciones de Impacto en la Protección de Datos (DPIA) sobre
actividades de tratamiento de alto riesgo […]? En caso afirmativo, indique […] la fecha […] su alcance
y su contenido estructural.

**Answer** — NO

**Justification**

4Shark no ha realizado una Evaluación de Impacto en la Protección de Datos con el contenido estructural descrito.

El tratamiento realizado por la plataforma no involucra datos personales sensibles, decisiones automatizadas con efectos jurídicos sobre los titulares, ni monitoreo sistemático a gran escala. La evaluación de impacto se realiza de forma integrada al proceso de desarrollo, según se describe en el ítem anterior.

**Notes** — the second sentence STAYS, and the distinction from the concessions cut elsewhere is that
it does not argue the control is unnecessary — it states VERIFIABLE FACTS about the processing: no
sensitive data, no automated decisions with legal effect, no large-scale systematic monitoring. Those
three are exactly the criteria that trigger a DPIA obligation, and each is checkable against other
answers in this questionnaire (16.2 already declares the absence of sensitive data; the platform
computes commission, it does not decide credit or employment). Dropped the explanation that these are
`los criterios que habitualmente disparan la obligatoriedad` — a privacy assessor knows that, it is
their repertoire, and explaining the criterion to whoever wrote the question reads as condescending.
Acronym spelled out on first mention, as at 18.1. **Deliberately NOT used**: `legal-compliance-documents/PLAN.md:163`
records that the DPIA obligation is not triggered partly because 4Shark is PROCESSOR and the
obligation belongs to the controller — true, but pushing responsibility onto Atento inside a
questionnaire Atento is administering is politically bad, and the answer stands on the three factual
criteria without it.

**Rewritten once the methodology landed (compliance PR #12).** The answer now cites the RESULT of a
named method rather than asserting the criteria are absent:

4Shark no ha realizado una Evaluación de Impacto en la Protección de Datos, porque ninguna de sus actividades de tratamiento se clasifica como de alto riesgo.

Esa clasificación no es una apreciación: resulta de aplicar el criterio de la autoridad nacional de protección de datos de la jurisdicción de constitución, que exige la presencia simultánea de un criterio general y uno específico. Ninguno de los criterios específicos se verifica — no hay datos sensibles ni de menores, no hay vigilancia de zonas públicas, y no hay decisiones tomadas unicamente con base en tratamiento automatizado. La metodología y el resultado por actividad están documentados.

## 18.5

**Question** — ¿Su organización cuenta con una metodología para determinar si una actividad de
tratamiento implica un RIESGO ALTO? En caso afirmativo, proporcione una breve explicación de la
metodología en la columna E.

**Answer** — SÍ

**Justification**

La metodología adoptada es la de la autoridad nacional de protección de datos de la jurisdicción en que 4Shark está constituida. La clasificación exige la presencia simultánea de al menos un criterio general — tratamiento en larga escala, o que afecte significativamente intereses y derechos fundamentales — y al menos un criterio específico — tecnologías emergentes, vigilancia de zonas accesibles al público, decisiones unicamente automatizadas, o datos sensibles y de menores o personas mayores.

La unidad de análisis es la actividad de tratamiento registrada, no la funcionalidad. Se aplica cuando se registra una actividad nueva, cuando una actividad registrada cambia materialmente, y en la revisión del propio Registro. El resultado de la aplicación está documentado por actividad.

**Notes** — verdict moved from `NO` to `SÍ`, enabled by
`compliance/internal/metodologia-de-classificacao-de-risco-de-tratamento.md` (PR #12). The engineer
asked whether a methodology could simply be chosen; the answer is that the ANPD criteria are not a
discretionary framework pick but the norm of the jurisdiction 4Shark is incorporated in, which removes
the need to defend the choice. **Two corrections were needed on the way**: the "nine criteria" are the
EDPB's, while ANPD uses two general plus four specific with a cumulative rule; and the document is
required, since 18.5 asks for a FORMALIZED methodology and without a written one the answer stays
`NO`. Neither the resolution nor the authority is named in the answer text, per the 17.5 discipline —
the document serves four countries and the exact reference lives in the internal document. The
criteria are described rather than pointed at, because column E asks for a brief explanation and a
cross-reference would be the 12.2 defect.

## 18.6

**Question** — ¿Su organización aplica el principio de Privacidad desde el Diseño y por Defecto […]?
En caso afirmativo, proporcione una breve explicación […] seudonimización, anonimización, limitación
de la recopilación […]

**Answer** — SÍ

**Justification**

El principio está formalizado en la política interna de Privacidad desde el Diseño y se aplica en dos planos.

En la arquitectura: los datos personales residen exclusivamente en la base de datos relacional, mientras las demás capas operan solo sobre identificadores internos; el modelo de permisos deniega por defecto; los archivos generados por las funcionalidades de extracción se descartan automáticamente a las 48 horas; los entornos de desarrollo y homologación utilizan exclusivamente datos sintéticos; y al término del período de retención los identificadores del titular se anonimizan de forma irreversible.

En el proceso: cada demanda pasa por un pre-planeamiento en el que se consideran la seguridad, la protección de datos y la minimización antes de definir la solución, y toda alteración pasa por una revisión dedicada de seguridad y protección de datos antes de ser incorporada. Son dos personas distintas en momentos distintos, de modo que la evaluación no depende de una sola.

**Notes** — the change is structure and EMPHASIS, and emphasis matters more here than elsewhere. Split
into architecture and process: the pre-review text ran everything as one list, so the planning
assessment and the pre-merge review arrived last, as one more enumerated item. They are not — privacy
by design is about WHEN privacy enters the decision, and what answers that is the process; the
architecture controls are the RESULT of applying the principle. The closing sentence (two different
people at two different moments) is what stops the principle depending on someone remembering; without
it an assessor reads "we consider privacy in planning" as intent rather than as a control with
redundancy. **Not written**: that the code is AI-generated — the two-review control is described
without opening a subject nobody asked about.

## 19.1

**Question** — ¿Su organización cuenta con un marco para la gestión adecuada de los datos personales
que abarque todo el ciclo de vida de los datos (por ejemplo, mapeo de datos, clasificación de la
información y diagramas de flujo)? En caso afirmativo, especifique qué marco(s) se aplican […]

**Answer** — SÍ

**Justification**

El ciclo de vida del dato personal está cubierto por tres instrumentos.

El Registro de Operaciones de Tratamiento mapea cada actividad desde el origen hasta el descarte, con finalidad, categorías de datos y de titulares, base legal, plazo de retención, suboperadores y transferencias internacionales.

La política de almacenamiento, anonimización y descarte define los plazos por jurisdicción y el método de eliminación al término de cada uno. Y el diagrama de arquitectura de la plataforma representa los componentes, el flujo de datos entre ellos, las integraciones y las capas de seguridad.

**Notes** — the answer names three instruments and the question offers mapping, classification and
diagrams as examples (`por ejemplo`), so covering the LIFECYCLE end to end is what carries the `SÍ`:
the RoPA maps, the disposal policy closes, the diagram shows the flow.

**The six-type taxonomy the vendor template asserted here was dropped, and item 3.1 carries the
accurate version of the same subject.** No document defines six information types with per-type
handling, access, storage, retention and disposal rules — the storage policy has three sections and no
type list. What DOES exist is the governance: `politica-de-seguranca-da-informacao-e-cibernetica.md:18`
names *"Classificação, retenção, anonimização e descarte da informação"* as a governed domain and
delegates it to a named policy. 3.1 states that; this answer omits it rather than contradicting it, so
the two cells agree. Adding the governance sentence here would strengthen the answer, since the prompt
names classification as one of its three examples.

**Open for the engineer**: whether a presentable architecture data-flow diagram exists —
`app/docs/architecture/` holds technical markdown, which is not necessarily something to show an
assessor. If none exists the mention is dropped and two instruments still sustain the `SÍ`.

## 19.2

**Question** — ¿Su organización cuenta con medidas técnicas y organizativas implementadas para
garantizar la seguridad, confidencialidad e integridad de los datos? En caso afirmativo, especifique
cuáles son dichas medidas en la columna E.

**Answer** — SÍ

**Justification**

Las medidas técnicas cubren el dato en cada estado: cifrado en tránsito con TLS 1.2 o superior y en reposo bajo claves dedicadas por entorno; control de acceso de denegación por defecto en la plataforma y menor privilegio con elevación temporal sujeta a segundo factor en la infraestructura; segregación de entornos con datos sintéticos en los inferiores; filtrado perimetral con reglas del estándar OWASP; hash irreversible de contraseñas; y registro auditable de los accesos.

Las medidas organizativas son el conjunto de políticas internas de seguridad y privacidad, los acuerdos de confidencialidad, la formación obligatoria en la incorporación con reciclaje anual, y la revisión de seguridad exigida antes de incorporar cualquier alteración.

**Notes** — the cross-reference to item 16.1 was replaced by the measures spelled out in full. The
prompt says `especifique cuáles son dichas medidas`, and pointing at another cell says the answer
lives elsewhere; a compliance matrix is read and scored row by row, sometimes by different people.
**Repeating here is correct** — the standing rule that each answer earns its own sentences exists to
stop a paragraph being recycled without thought, not to stop two items that genuinely ask the same
thing receiving the same information. The two prompts were checked and do coincide. Two deltas
against 16.1: end-of-retention anonymisation was cut (a lifecycle measure, not a security,
confidentiality or integrity one, and already carried by 19.1 and 16.1), and the mandatory security
review before any change ships was added to the organisational half — in 16.1 it sits inside secure
development; here it is the organisational measure that stops a change breaking the technical ones.

## 19.3

**Question** — ¿Su organización cuenta con medidas técnicas y organizativas implementadas para
garantizar que los datos se mantengan debidamente actualizados? En caso afirmativo, especifique
cuáles son dichas medidas […]

**Answer** — SÍ

**Justification**

La base de usuarios y su estructura organizativa se mantienen sincronizadas con los sistemas de origen del cliente mediante una integración dedicada: altas, cambios de cargo, cambios de gestor y desvinculaciones se propagan desde el sistema fuente hacia la plataforma. El dato permanece alineado con la fuente autoritativa, y no se crean registros sin trazabilidad hasta ella.

Como el cliente es el controlador, la exactitud del dato en origen es responsabilidad suya, y la integración es lo que garantiza que la plataforma refleje esa fuente. Adicionalmente, cada usuario puede corregir sus propios datos de perfil, y los titulares pueden solicitar la rectificación por el canal de ejercicio de derechos.

**Notes** — the substantive addition is the sentence placing responsibility for accuracy. It is
legally exact: the data-quality principle binds the controller, and 4Shark is the processor. The
previous text described the mechanism without positioning responsibility, which left implicit a
guarantee 4Shark cannot make — if the client never records a promotion in its own system, the
platform has no way to know. The sentence **protects 4Shark without pushing blame**: it states what
4Shark does guarantee (the platform mirrors the source) and where that stops. Distinct from what was
avoided at 18.4, where naming the controller's DPIA obligation would have handed a problem back to
Atento inside Atento's own questionnaire; here there is no problem to hand back. The opening sentence
was also reordered to lead with the outcome rather than the mechanism, since the question is about
the guarantee.

## 19.4

**Question** — ¿Su organización cuenta con políticas que limiten el período de conservación de los
datos personales? En caso afirmativo, especifique en la columna E el nombre de la Política o
Procedimiento, la fecha de aprobación, el alcance y la descripción del período de retención […]

**Answer** — SÍ

**Justification**

Política interna de almacenamiento, anonimización y descarte, aprobada en `[FECHA]`. Alcance: todos los datos personales tratados por 4Shark, en calidad de operadora y de controladora.

En el tratamiento por cuenta del cliente, el período se cuenta desde la desactivación del usuario y está definido por jurisdicción, conforme al plazo de prescripción aplicable al vínculo entre el titular y el cliente en cada país. Al vencimiento, los identificadores del titular se anonimizan de forma automática e irreversible. Los archivos generados por las funcionalidades de extracción se descartan a las 48 horas, y las copias de seguridad se retienen por 7 días en cada región.

**Notes** — carries the `[FECHA]` marker, deliberately distinct from the `[PENDIENTE]` markers cut
elsewhere: those recorded a content gap, this is a field the engineer fills with a datum that will
exist. **An internal contradiction was fixed that had nothing to do with the date**: the text
declared `el período es de 5 años y 1 mes` as a single figure, while item 3.3 — already approved —
establishes retention **by jurisdiction** with different numbers per country. Five years and one
month is the Brazilian figure; declaring it as *the* period would make two cells disagree about the
same rule, in the exact item where an assessor checks retention against what was said earlier. The
rewrite states the criterion instead, true for all four countries. The 7-day backup retention was
verified rather than assumed: `local_retention_days` and `destination_retention_days` are both `7` by
default in `terraform/modules/cross_region_backup/variables.tf:25,31`. **The DocuSign round exists but
covers the superseded hand-made version** — so the old date would attach the current text to an
approval of different content, which is what an assessor finds if they request the policy and compare.
The date to use is the one the publication of the updated set generates.

## 19.5

**Question** — ¿Su organización obtiene el consentimiento de los titulares de los datos antes de
tratar información personal, cuando así lo exige la ley?

**Answer** — SÍ

**Justification**

En el tratamiento realizado por cuenta del cliente, 4Shark actúa como operadora y la base legal la determina el controlador — típicamente la ejecución del contrato de trabajo y el legítimo interés, no el consentimiento.

En el tratamiento en que 4Shark actúa como controladora, se recoge consentimiento donde la ley lo exige. El caso es la analítica de uso del sitio, mediante un banner de consentimiento previo con opción negada por defecto y registro de la elección del titular.

**Notes** — `un mecanismo de consentimiento previo con registro` was replaced by the mechanism itself
(banner, default-denied option, choice recorded). The question is about **obtaining** consent, and
what separates valid consent from apparent consent is precisely the default-denied opt-in: describing
the mechanism proves validity, naming it generically does not. `el caso es` rather than `en
particular` closes the question — no residual doubt about unmentioned cases. The first half is the
strong part and is the same legal position that sustained 16.5: as processor, 4Shark does not choose
the legal basis. Not evasion but the structure of the law — "when the law requires it" is an
assessment belonging to the controller for the controller's activities.

## 19.6

**Question** — En los casos en que se requiera el consentimiento […] ¿su organización cuenta con un
marco de gestión del consentimiento que le permita demostrar cuándo se obtuvo el consentimiento, de
quién se obtuvo y el contenido del consentimiento?

**Answer** — SÍ

**Justification**

El mecanismo de consentimiento de cookies y analítica registra los tres elementos: el momento de la obtención, el identificador seudónimo del navegador al que corresponde, y el ámbito de las categorías aceptadas — que es el contenido de lo consentido.

La elección es revocable por el titular en cualquier momento, y la actividad y su base legal constan en el Registro de Operaciones de Tratamiento.

**Notes** — the prompt is an explicit triad (when, from whom, what) and the previous text answered
two, missing **from whom** — the hardest of the three in cookie consent, because no authenticated
user exists when the banner appears. The honest answer is the pseudonymous browser identifier, and
naming it beats omitting it twice over: a privacy assessor knows cookie consent anchors on a browser
identifier, so omission reads as evasion, and the pseudonym is the **correct** answer under
minimisation — binding cookie consent to a real identity would be worse. `con registro
correspondiente` was cut as vague. **Open for the engineer**: the three-element record was described
from how a default-denied consent mechanism works. If the banner only persists the preference in the
user's own browser with nothing queryable on the 4Shark side, "demonstrate" is weak because the proof
sits on the data subject's device — the `SÍ` still holds but the final clause about the record comes
out.

## 20.1

**Question** — ¿Su organización cuenta con un Procedimiento de Calificación de Proveedores que
evalúe el cumplimiento de los requisitos de privacidad y protección de datos? […] En caso contrario,
explique el procedimiento aplicado.

**Answer** — SÍ (changed from `NO` after compliance#13 merged)

**Justification**

El procedimiento consta en la política interna de gestión de proveedores y suboperadores, aprobada en `[FECHA]`. Alcance: todo proveedor que sustente la operación de la plataforma o que reciba datos personales en razón de ella.

El criterio de contratación restringe la selección a proveedores con certificaciones independientes vigentes, auditoría externa continua y cláusulas contractuales de protección de datos. Cada proveedor recibe clasificación de criticidad y contacto designado, y la relación se revisa anualmente verificando la vigencia de las certificaciones que fundamentaron la contratación.

**Notes** — the verdict moved because **the artifact came into existence**, not because the text
improved: `compliance/internal/politica-de-gestao-de-fornecedores-e-suboperadores.md` plus
`compliance/records/inventario-de-fornecedores.md` (PR #13). The pre-merge answer was `NO` with the
criterion described and the absence delimited. Modelled on ISO/IEC 27001:2022 Annex A 5.19–5.23 —
supplier relationships, contractual clauses, ICT supply chain, ongoing monitoring, cloud services —
chosen over ISO/IEC 27036 (four parts, built for large supplier ecosystems; would have been the
ISO 29134 trap of 18.5) and consistent with item 17.7, which already declares 27001/27002 as the
reference framework. **The provider list stays out of the cell**: the authoritative list lives in the
inventory, and a list typed into a cell is what can diverge from it — same decision as 13.1. Carries
the shared `[FECHA]`.

## 20.2

**Question** — ¿En caso de que su organización haya subcontratado la totalidad o parte de los
servicios, ha suscrito un Acuerdo de Tratamiento de Datos con el subencargado que imponga las mismas
obligaciones que las establecidas por Atento? En caso afirmativo, identifique en la columna E el
nombre del subencargado, su ubicación y la fecha de firma del acuerdo.

**Answer** — SÍ

**Justification**

4Shark no subcontrata la prestación del servicio: el desarrollo, la operación y el soporte son íntegramente internos.

Los suboperadores existentes son proveedores de infraestructura y de servicios de plataforma, todos registrados en el inventario de proveedores y en el Registro de Operaciones de Tratamiento, y declarados en el acuerdo de tratamiento de datos celebrado con cada cliente. Con cada uno de ellos rige un acuerdo de tratamiento de datos que incorpora las cláusulas contractuales tipo para la transferencia internacional cuando aplica.

**Notes** — the answer cannot deliver everything the prompt asks, and that is stated plainly rather
than papered over. Name and location live in the inventory; the **signature date does not exist in
queryable form** — cloud provider agreements are accepted by adhesion inside each console and produce
no dated signed document to attach to a spreadsheet. The prior text carried the fourth `[PENDIENTE]`
marker with a `si Atento la exige` hedge; the rewrite asserts only what is true and verifiable. If
Atento presses on the column, the honest answer is that acceptance is recorded in each provider
account and can be evidenced from there, which is different from having a signature date. Provider
names were removed for the inventory-divergence reason established at 13.1 and 20.1. **Dependency**:
this answer falls together with 16.4 and 20.3 if the infrastructure provider's DPA was never formally
accepted — the single most consequential open confirmation.

## 20.3

**Question** — ¿En caso de que su organización haya subcontratado […] a un subencargado ubicado
fuera de su territorio, cumple con los requisitos legales […]? En caso afirmativo, especifique en la
columna E qué salvaguardas se aplican para la transferencia internacional […]

**Answer** — SÍ

**Justification**

La salvaguarda aplicada son las cláusulas contractuales tipo, incorporadas al acuerdo de tratamiento de datos suscrito con cada proveedor de infraestructura ubicado fuera del territorio de constitución.

Esas cláusulas se complementan con las obligaciones de protección de datos previstas en el acuerdo celebrado con el cliente, que rige también la actuación de los suboperadores.

**Notes** — three cuts on a short text. The `Detalle completo en el ítem 16.4` cross-reference went
for the 19.2 reason: the prompt says `especifique en la columna E`. The legal citations
(`Art. 33, inciso II de la LGPD` plus `la normativa chilena`) went as the partial-jurisdiction anchor
already corrected at 16.4 and 17.5 — they name two of four countries and leave Mexico and Colombia
out; the safeguard is what the question asks for, and the enabling statute varies by country. The
provider name went for inventory consistency. What remains uses `cláusulas contractuales tipo`, the
prompt's own example wording. **Same dependency as 16.4 and 20.2.**

## 20.4

**Question** — ¿Los contratos de su organización con subcontratistas, proveedores de servicios o
contratistas incluyen cláusulas específicamente requeridas por la CCPA/CPRA y otras leyes federales o
estatales de los Estados Unidos […]?

**Answer** — N/A

**Justification**

Este ítem se refiere a cláusulas exigidas por la normativa de los Estados Unidos. 4Shark no está establecida en ese territorio ni presta servicios a titulares residentes en él, por lo que esas exigencias no alcanzan sus contratos.

Las obligaciones de uso limitado, confidencialidad y prohibición de uso secundario constan de todos modos en el acuerdo de tratamiento de datos celebrado con cada proveedor.

**Notes** — here `N/A` **is** correct, and the distinction against 17.8 (where it was not) is the
same test applied the other way. 17.8 asked whether 4Shark **sells or shares data** — a fact about
the operation, answerable regardless of which law motivated the question. This asks whether contracts
carry **clauses required by a specific named statute** — not a fact about the operation but
conformance with a regime that does not reach the company, so `N/A` is the literal and correct
answer. The second sentence is what stops the `N/A` reading as a dodge: the material obligations CCPA
imposes exist in 4Shark's contracts by another route. The inapplicability justification was also
widened — not being established in the US is only half, since CCPA reaches foreign companies
processing California residents' data; stating no residents there closes the other half.

## 21.1

**Question** — enumerates five aspects the incident response plan must cover: identification, risk
and impact assessment, mitigating action plan, assessment of the need to notify authority and data
subjects within deadlines, and other applicable requirements.

**Answer** — SÍ

**Justification**

La política interna de respuesta a incidentes de seguridad de la información cubre las cinco etapas del proceso — planificación, identificación, contención, erradicación y recuperación — con roles y responsabilidades definidos, flujo de escalamiento por severidad y criterios de clasificación.

Sobre los aspectos que el ítem enumera: la política contempla la identificación de incidentes que afecten datos personales, la evaluación del riesgo y del impacto sobre la privacidad, el establecimiento de un plan de acción mitigador, y la evaluación de la necesidad de notificar a la autoridad de protección de datos competente y a los titulares afectados dentro de los plazos legales aplicables, además de la notificación al cliente.

El proceso contempla además registro, investigación con análisis de causa raíz, documentación e identificación de lecciones aprendidas.

**Notes** — content was already right; the work was structural. Ten running lines forced the assessor
to hunt each of five requirements, so the second paragraph now answers the list **in the order it was
asked**. `la autoridad nacional de protección de datos` became `la autoridad de protección de datos
competente` — the prompt uses the singular from one vantage point, but the document serves four
countries with four authorities, same discipline as 14.2.

## 21.2

**Question** — ¿Su organización […] podría notificar a Atento dentro de un plazo de 24 horas desde el
momento en que tenga conocimiento del impacto […]?

**Answer** — SÍ

**Justification**

4Shark notifica al cliente dentro de las 24 horas siguientes al momento en que tenga conocimiento de un incidente de seguridad que afecte a datos personales tratados por su cuenta.

La notificación se emite por el canal definido en el acuerdo vigente y comprende, con la información disponible en ese momento, la naturaleza del incidente, las categorías y el volumen aproximado de datos y de titulares afectados, las medidas de contención ya adoptadas y el punto de contacto para el seguimiento. La información aún en determinación se remite de forma progresiva, sin retener la notificación inicial a la espera del análisis completo.

**Notes** — two defects removed from the prior text. `Será formalizado` was a future-tense promise,
the form the Positivo assessor rejected. And the sentence **disclosed the 72-hour deadline offered to
other clients** — commercial information about other contracts, not asked for, telling Atento in an
archived document that differentiated treatment exists between clients. **The engineer decided to
state only the commitment, with no comparison**: citing the general standard frames 24 hours as a
commercial exception, and an exception invites the follow-up question of how it is guaranteed if it
is not the normal process. The second paragraph is what makes this worth more than a "yes" — it says
**what arrives inside the 24 hours**, and the final clause about not holding the initial notification
answers the real objection: the fear is not the deadline on paper, it is a vague alert in 24 hours
with the useful content two weeks later. **`TASKS.md` records that the 24 hours must enter the DPA
with Atento** — until they do, the answer describes a practice; with the clause it describes an
obligation, and only the second sustains a `SÍ` in an archived questionnaire.

## 21.3

**Question** — ¿Su organización, en caso de producirse un incidente físico o técnico, adopta medidas
para restablecer de manera oportuna la disponibilidad y el acceso a los datos personales?

**Answer** — SÍ

**Justification**

La disponibilidad se restablece por la arquitectura antes de depender de intervención: la base de datos opera en múltiples zonas con conmutación automática, y la capa de aplicación se autorrecupera ante la pérdida de cualquiera de sus instancias.

Para la pérdida de datos, la recuperación se apoya en recuperación continua a un punto en el tiempo, copias automáticas diarias y una copia en segunda región, con objetivos declarados de RPO igual o inferior a 1 hora y RTO de 4 horas. La restauración a partir de esas copias se prueba de forma automatizada y periódica, además de un ejercicio anual de recuperación completa.

**Notes** — the `descrito en la sección 15` cross-reference and the product names were removed,
consistent with the rest. Split into two cases because the question covers two scenarios resolved
differently: **unavailability**, which the architecture resolves with nobody acting, and **data
loss**, which requires restoration. The previous text mixed them into one list, and it is exactly
that distinction which answers `de manera oportuna` — the first is immediate, the second has a
declared RTO.

## 21.4

**Question** — ¿Su organización, en caso de incidentes causados por error humano, cuenta con un
procedimiento para prevenir y mitigar dichos incidentes?

**Answer** — SÍ

**Justification**

La prevención del error humano está incorporada al diseño operativo, no delegada a la atención individual.

Ningún cambio llega a producción sin revisión por pares: revisión de código y revisión de seguridad obligatorias, sobre ramas protegidas con aprobación exigida y pruebas automatizadas en verde. La infraestructura y la concesión de permisos son código, de modo que un cambio de permiso exige modificación revisada en el repositorio y no existe concesión manual sin traza.

El alcance del error también está acotado: las cuentas personales operan con menor privilegio y de solo lectura, con elevación temporal sujeta a segundo factor; las operaciones administrativas amplias quedan restringidas a una cuenta de emergencia con llave física; y los entornos están segregados, de modo que la manipulación en desarrollo u homologación no alcanza datos productivos.

**Notes** — content was right, shape was a fifteen-line semicolon paragraph. Reorganised into two
principles, and the division is not cosmetic: **preventing the error** and **bounding its reach**.
Those are different strategies and a security assessor reads the second as a maturity signal, because
prevention alone assumes nobody errs; in a running list that distinction disappears. Training was cut
from the end — it answers 12.1 and 12.2, and closing a human-error item with "and we train people"
weakens the opening claim that the control does not depend on individual attention. `una hora` was
removed from temporary elevation: configuration detail that does not change the answer and is exactly
the kind of number an assessor tests.

## 21.5

**Question** — ¿Su organización mantiene un registro de los incidentes de seguridad que afectan a los
datos personales?

**Answer** — SÍ

**Justification**

La política de respuesta a incidentes exige el registro de cada incidente, su investigación con análisis de causa raíz y la documentación de las lecciones aprendidas.

Los incidentes operativos de disponibilidad o rendimiento siguen el mismo tratamiento, con post-mortem, identificación de causa raíz y acciones correctivas documentadas.

**Notes** — the "ten years without incident" sentence was cut, as at 17.6, and **here it is worse
than irrelevant**. There it merely proved nothing (absence of sanction is not conformance). Here it
can **turn a `SÍ` into a `NO` in the assessor's head**: the question is whether an incident register
exists, and saying no incident ever occurred answers something else while suggesting the register is
empty — and an empty register is indistinguishable from one that does not exist. What sustains the
`SÍ` is the process, and the second paragraph shows the process **actually runs**, because
operational incidents do happen and go through post-mortem. Evidence a mechanism is alive is far
stronger than asserting it never had to be used.

## 21.6

**Question** — ¿Su organización cuenta con un Plan de Continuidad del Negocio? En caso afirmativo,
especifique en la columna E la fecha de aprobación y el alcance […]

**Answer** — SÍ

**Justification**

Plan de Continuidad del Negocio y Recuperación ante Desastres, aprobado en `[FECHA]`. Alcance: la continuidad de la prestación del servicio y la recuperación ante desastres.

El plan establece los dos escenarios previstos — corrupción de datos con la región primaria operativa, y pérdida total de la región primaria —, los objetivos de recuperación comprometidos y la cadencia de pruebas, cuya ejecución se describe en el ítem anterior sobre pruebas de recuperación.

**Notes** — shares the `[FECHA]` marker with 19.4 and 20.1. `formalmente aprobado por la dirección`
was removed for the third time in the questionnaire: until the signature round runs over the current
set, the claim does not hold. When it runs, it returns in three answers — 14.3, 15.1 and this one —
together with the date. The `descrita en el ítem 15.3` cross-reference became a descriptive reference:
pointing at item numbers in a spreadsheet is fragile, since reordering rows breaks it.

## 22.1

**Question** — ¿Su organización cuenta con un procedimiento establecido para gestionar las
solicitudes de ejercicio de derechos […]? En caso afirmativo, especifique […] el nombre del
procedimiento, la fecha de publicación, el alcance y una breve descripción […]

**Answer** — SÍ

**Justification**

Procedimento de Atendimento a Solicitações de Titulares, publicado en `[FECHA]`. Alcance: toda solicitud de ejercicio de derechos recibida por 4Shark, tanto en calidad de controladora como de operadora.

El procedimiento cubre la recepción por el canal público, la determinación del papel en que 4Shark trata el dato, la identificación del solicitante, el enrutamiento según el derecho ejercido, y la respuesta en las dos formas que la norma prevé — declaración simplificada inmediata, o declaración completa dentro del plazo legal.

Cuando la solicitud alcanza datos tratados por cuenta de un cliente, 4Shark actúa como operadora y la encamina al controlador con el apoyo técnico necesario. La ejecución recorre todos los entornos en que el titular pueda tener registro, y ninguna respuesta afirmando el atendimiento se emite antes de verificado el estado real de los datos.

**Notes** — the document name was **proposed rather than asked for**; handing the naming question back
to the engineer was the error, corrected in-session. The name follows the repository's sibling
convention (`Política de…`, `Plano de…`, `Acordo de…`) and the document was written as
`compliance/internal/procedimento-de-atendimento-a-solicitacoes-de-titulares.md` (PR #14). **No
mandatory format exists** — no standard prescribes the structure. What structures it is LGPD art. 18
(the nine rights, hence the flows to cover) and art. 19 (the two response forms and the fifteen-day
deadline); ISO/IEC 27701, already declared as a reference framework at 17.7, has data-subject-rights
controls but prescribes no format either. Content came from the internal erasure runbook, so the
document describes the real operation. The Portuguese title is kept inside the Spanish text, as with
the RoPA — it is a document title, not a term to translate. `dentro del plazo legal` carries no day
count, because fifteen days is the Brazilian figure and the document serves four countries. The
internal runbook is not named, per 15.3: naming an internal document in an external questionnaire
creates the expectation that it can be requested.

## 22.2

**Question** — ¿Su organización cuenta con un canal de comunicación disponible públicamente para que
los titulares de los datos puedan contactarla con el fin de ejercer los derechos otorgados por la
normativa aplicable en materia de protección de datos? En caso afirmativo, especifique en la columna
E qué canal(es) se encuentran disponibles y, en la columna F, proporcione un enlace al sitio web o
una captura de pantalla que evidencie el mecanismo de contacto.

**Answer** — SÍ

**Justification**

El canal es privacidade-dados@4shark.com.br, publicado en la Política de Privacidad, de acceso público, junto con la identificación del Encargado de Protección de Datos.

**Notes** — the personal name and the site URL were removed for the 17.4 reasons: the public policy
already carries both, and column F of the form is where the link evidence belongs. Repeating them in
column E adds nothing and spreads personal data across one more cell of a circulating document.

## 23.1

**Question** — ¿Su organización cuenta con empleados que hayan firmado un acuerdo de confidencialidad
que los obligue a no divulgar ninguna información […] de manera indefinida, incluso después de la
finalización de la relación laboral?

**Answer** — SÍ

**Justification**

Los colaboradores de 4Shark suscriben un acuerdo de confidencialidad que los obliga a no divulgar la información a la que tengan acceso durante la prestación de sus servicios. La obligación es de vigencia indefinida y subsiste tras la terminación de la relación.

**Notes** — `forma parte del conjunto de políticas internas formalmente aprobadas y suscritas` was
cut: the same formal-approval claim removed from four other items, and here it adds nothing, since
the question asks whether the agreement is signed and whether it survives termination, both already
stated. `todos los colaboradores` became `los colaboradores` — the universal is the kind of claim an
assessor tests by asking for the signature list, and the prompt does not require that force (it asks
whether the company has employees who signed).

## 23.2

**Question** — ¿Los empleados […] han recibido capacitación sobre sus obligaciones […]? En caso
afirmativo, especifique en la columna E la fecha de la capacitación y un resumen del contenido.

**Answer** — SÍ

**Justification**

La formación se imparte en la incorporación y se repite con periodicidad anual. La última sesión se realizó en `[FECHA]`.

El contenido comprende los principios de la normativa de protección de datos aplicable, las bases legales de tratamiento, los derechos de los titulares, las obligaciones específicas del operador, y el proceso de respuesta a incidentes.

**Notes** — this marker differs from every other one: **the date exists**. The `Registro de
Treinamentos LGPD` is in the engineer's Drive, records folder, modified in June; the last session
date is a lookup, not something that depends on publishing anything. The nominal LGPD citation was
removed in favour of `la normativa de protección de datos aplicable`, same discipline as the rest.
**Open for the engineer**: the date, and its interaction with the 12.1 confirmation — if the register
shows a gap longer than a year between sessions, the annual-cadence claim needs adjusting in both
items at once.

## 23.3

**Question** — ¿Los empleados […] reciben capacitación sobre las medidas técnicas y organizativas de
seguridad específicas que deben aplicar en el desempeño de sus funciones […]?

**Answer** — SÍ

**Justification**

La formación se imparte en la incorporación y se repite con periodicidad anual. La última sesión se realizó en `[FECHA]`.

El contenido abarca las prácticas que el colaborador aplica en su función: la gestión de credenciales y el uso de la bóveda corporativa, el acceso a la infraestructura por conexión cifrada con menor privilegio y elevación temporal sujeta a segundo factor, el reconocimiento de phishing e ingeniería social, y el procedimiento de reporte de incidentes.

**Notes** — the previous text opened straight into topics without saying **when** the training
happens, and the question asks for the date; the opening sentence was added, shared with 23.2 and
drawing on the same register. The difference against 23.2 is real and preserved: 23.2 covers **legal
obligations** (legal bases, data-subject rights, processor obligations), this covers **security
measures the person applies day to day**. Two blocks of the same session — repeating the date across
both is correct; repeating the content would be the defect. The VPN mention was genericised to
`conexión cifrada`.

## 23.4

**Question** — ¿Su organización realiza campañas periódicas de concienciación sobre la protección de
datos personales? En caso afirmativo, especifique […] las campañas realizadas y las programadas […]

**Answer** — SÍ (changed from `NO`)

**Justification**

La concienciación se realiza con periodicidad anual, mediante una sesión que alcanza a la totalidad de los colaboradores y queda registrada con fecha, tema, participantes y material utilizado. La próxima sesión sigue el mismo ciclo anual.

Se complementa con la discusión de escenarios de seguridad y de impacto sobre datos personales incorporada a la revisión que antecede cada nueva funcionalidad, lo que mantiene el tema en la rutina técnica y no solamente en el evento anual.

**Notes** — the prior `NO` said 4Shark runs no campaigns `en el formato de una organización de gran
porte` and then described what it does: **discloses company size** again, and argues with the
question instead of answering it. More importantly, **the question is about periodicity, not
format** — a recurring annual session reaching every collaborator, dated and recorded, is exactly a
periodic awareness action. Same reasoning that moved 17.8 from `N/A` to `NO`: refusing a verdict that
holds costs credibility and buys nothing. The answer fills the three fields column E asks for —
delivered, scheduled, content — inventing nothing.

## 23.5

**Question** — ¿Su organización […] ha comunicado su contenido de manera efectiva y cuenta con
controles de verificación implementados? En caso afirmativo, especifique […] cómo se ha comunicado
dicha información, incluyendo fechas, contenido […]

**Answer** — SÍ

**Justification**

Las políticas internas de privacidad y seguridad se comunican a los colaboradores en la incorporación y se suscriben por instrumento de acuse de conocimiento, uno por documento.

El control de verificación es la Matriz de Aplicabilidad, que define qué documento aplica a cada área y quién debe suscribirlo, de modo que la cobertura es verificable por comparación entre lo exigido y lo suscrito. La Política de Privacidad externa está publicada y es de acceso público.

**Notes** — the URL was removed as at 17.4 and 22.2 (column F carries link evidence). The substantive
change is explaining **why** the Applicability Matrix is the verification control: the prior text
asserted that it constitutes one and stopped, while the prompt highlights `controles de
verificación`. Stating the mechanism — it defines what each area must sign, and that definition is
what allows comparing required against signed — is what makes it a control rather than a document.
**No marker here despite the prompt mentioning dates**: `incluyendo fechas` is part of the
detailing, but communication is continuous at onboarding rather than a dated event.

## 24.1

**Question** — ¿Ha realizado su organización auditorías sobre el cumplimiento en materia de
protección de datos en los últimos 2 años? En caso afirmativo, especifique […] la(s) fecha(s), el
alcance y los resultados […]

**Answer** — NO

**Justification**

4Shark no ha realizado una auditoría formal de cumplimiento en protección de datos por un tercero independiente.

En el período se ejecutaron un test de intrusión por empresa independiente especializada, con la totalidad de los hallazgos remediados y validados en retest, y evaluaciones de seguridad y privacidad conducidas por clientes corporativos en sus procesos de diligencia debida, cuyos planes de mitigación fueron acordados y se encuentran en ejecución.

**Notes** — the `NO` stands: the question is about a data-protection compliance audit, and a
penetration test is not that, nor is a client assessment. Calling either one an audit would stretch
the term and is the easiest claim to knock down. The second paragraph stays because it shows **real
external scrutiny happened** in the period, with a result — and `la totalidad de los hallazgos
remediados y validados en retest` is the most concrete claim in this whole section; few suppliers can
say it. **Open for the engineer**: the prompt asks for dates and the text carries none. If the
pentest report and the client assessments are dated, adding the year strengthens at no cost.

## 24.2

**Question** — ¿Su organización ha implementado las medidas correctivas identificadas por las
auditorías, con revisiones periódicas de su eficacia?

**Answer** — SÍ

**Justification**

La totalidad de los hallazgos del test de intrusión fueron remediados y validados en un retest ejecutado por la misma empresa independiente. La validación por quien identificó el hallazgo es lo que confirma la eficacia de la corrección.

Los planes de mitigación acordados con clientes en sus procesos de diligencia debida se ejecutan con seguimiento de plazos, y cada ítem se verifica al cierre.

**Notes** — the addition is the sentence explaining **why the retest is the effectiveness check**. The
prompt highlights `revisiones periódicas de su eficacia`, and the prior text mentioned the retest
without saying what it proves: the same firm that found the flaw validates the fix, which is stronger
than any internal review and is precisely what the question looks for. What the answer deliberately
does **not** claim is a continuous review cadence, because none exists — the retest is a single event
per pentest, and inventing a cycle would be the fragile claim avoided throughout.

## 25.1

**Question** — ¿Ha sido su organización sancionada por incumplimiento […] en los últimos 5 años?

**Answer** — NO

**Justification**

4Shark no ha sido sancionada por incumplimiento de normativa de protección de datos.

**Notes** — the "ten years of operation with no breach" sentence was cut for the third time in the
questionnaire, and here the reason is the most direct of all: **it was not asked**. The item asks
about sanction; adding incident history answers a different question and creates, in writing, a
decade-long claim nobody can verify and against which any future incident will be read. `nunca` was
also removed — it extends the assertion beyond the five years the prompt delimits, with no gain. This
is the item where the negative is the complete and strong answer: nothing to compensate for, nothing
to explain. One sentence.

## 25.2

**Question** — ¿Su empresa o alguna empresa del grupo (si aplica) se encuentra actualmente
involucrada en algún procedimiento sancionador ante una Autoridad de Control […]?

**Answer** — NO

**Justification**

4Shark no está involucrada en ningún procedimiento sancionador ante autoridad de control u organismo competente.

**Notes** — `4Shark no integra un grupo empresarial` was cut, and **this cut is not stylistic: the
claim is false**. `legal-compliance-documents/PLAN.md:173` records four CNPJs — Tecnologia, Soluções
Financeiras, 4T and Incentive — and the document itself calls the structure fragmented. Asserting in
writing, in a questionnaire the client archives, that no corporate group exists contradicts 4Shark's
own internal documents and is the kind of statement a corporate due diligence disproves in minutes.
With the sentence gone the answer is true and complete, and the prompt's own `si aplica` permits not
entering the subject. **Links to the 16.4 pending confirmation**, which asserts no other group entity
accesses client data: the document reading suggests the fragmentation is fiscal and contractual
rather than access-related, but that is a reading and not the engineer's confirmation — and now two
items rest on the same fact.

## 26.1

**Question** — ¿Su organización cuenta con la certificación ISO 27001?

**Answer** — NO

**Justification**

4Shark no cuenta con certificación ISO 27001. Las prácticas y controles siguen ISO/IEC 27001 e ISO/IEC 27002 como marco de referencia, documentados en el conjunto de políticas internas de seguridad de la información.

**Notes** — `formalmente aprobadas por la dirección` removed for the sixth time, same signature-round
dependency; `con revisión anual prevista` removed as a future-tense promise about something not
asked. Uses item 17.7's exact formulation (`como marco de referencia`) because the two items state the
same fact and must state it identically — if one says "we follow ISO 27001" and the other "we adopt
aligned practices", the assessor reads inconsistency where there is none. Structurally the inverse of
25.1: there the negative sufficed alone, here it needs the complement, because the question is about
a certificate and its absence does not mean absence of control.

## 26.2

**Question** — ¿Su organización cuenta con alguna otra certificación relevante […]? En caso
afirmativo, especifique cuáles […]

**Answer** — NO

**Justification**

4Shark no cuenta con certificaciones propias. Los proveedores de infraestructura crítica sí las mantienen vigentes, con auditoría independiente y continua, conforme al criterio de selección establecido en la política de gestión de proveedores.

**Notes** — the enumeration of five providers with their certifications was cut for three reasons.
The list named five while the inventory that landed today holds thirteen, so it was born diverging
from the document. The attributed certifications were verified by nobody — the same reason the list
left 13.1 and 20.1. And the question is about **4Shark's own certifications**, not its providers':
enumerating theirs answers something else, with the side effect of looking like borrowed credentials.
What remains says the same in one sentence and points at the now-existing documented criterion; per
provider certifications live in the inventory.

## 27.1 — 27.8 (Artificial Intelligence section)

**Questions** — 27.1 DPIA on AI risks; 27.2 identification of applicable AI regulations; 27.3
compliance with obligations under those regulations; 27.4 ability to supply the logic applied by AI in
automated decisions; 27.5 human intervention in AI-produced results; 27.6 AI governance or management
system in the organisation; 27.7 designated AI officer; 27.8 ISO 42001 certification.

**Answer** — N/A (all eight)

**Justification** (identical text in all eight cells)

La plataforma entregada al cliente no utiliza Inteligencia Artificial en la prestación del servicio. El procesamiento es determinístico: cálculo de resultados según reglas de negocio configuradas por el cliente, sin modelos de aprendizaje automático ni inferencia estadística.

**Notes** — the section header conditions every item on AI being used in the provided service, which
it is not. Two cuts from the original boilerplate, applied to all eight. The final sentence quoting
the section instruction to justify the `N/A` was removed: column D already carries the verdict, and
explaining why `N/A` was chosen is the verdict-restatement pattern removed at the start of the
questionnaire. `No existen decisiones automatizadas con efectos sobre los titulares derivadas de IA`
was removed as redundant — with no AI there is no AI-derived decision, and the absence of automated
decisions with legal effect is already asserted at 18.4, where it is content in its own right. The
client name went (`entregada a Atento` → `entregada al cliente`), consistent with 16.5.

**Repetition here is correct**, the same exception taken at 19.2: eight different questions about a
premise that does not hold each receive the same statement of the premise, because the assessor reads
each row in isolation and each must stand alone.

**The engineer's decision on 27.6, 27.7 and 27.8**: those three ask about **the organisation**, not
the service — and 4Shark does use AI in development. The engineer chose to keep `N/A` with the
platform-scoped sentence, because the section header only requires an answer from those using AI in
the provided service, and the sentence asserts what is true about the platform while asserting
nothing about the organisation. Consistent with the 18.6 decision to keep AI-written code out of the
questionnaire. The alternative considered and rejected was answering `NO` on all three with an
explicit declaration of internal AI use, which is more transparent but opens three negatives that do
not exist today and brings into the questionnaire a subject the assessor did not ask about in that
scope.
