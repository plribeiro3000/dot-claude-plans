# Integración de KPIs Colombia — Estado de los requisitos y recomendaciones

**Documento técnico 4Shark · 31 de julio de 2026**

**Alcance:** la tabla de indicadores del VKPI, que es la única que la integración consume.

**Anexo:** `remediacion_vkpi_colombia.sql` — los scripts que implementan cada recomendación de este documento.

---

## Propósito de este documento

El 28 de julio compartimos un análisis técnico con los requisitos necesarios para integrar la base de KPIs. El 29 de julio acordamos los puntos en reunión, y quedó de su lado definir la estructura de la llave. El 30 de julio recibimos la maqueta con la propuesta.

Este documento revisa cada punto contra los datos de esa maqueta: qué quedó resuelto, qué falta, y para lo que falta, exactamente qué cambio lo cierra. El anexo trae ese cambio ya escrito en SQL.

Queremos avanzar y queremos entregar la estimación de esfuerzo. Con la estructura actual no podemos hacerlo con responsabilidad, y la razón es concreta: la tabla no tiene una llave que identifique una fila de manera única. Sobre una base así, cualquier plazo que diéramos sería un número puesto para responder a la pregunta, y el error aparecería recién en producción, sobre la nómina.

---

## Resumen de estado

| Punto | Estado |
|---|---|
| Llave que identifique una fila de manera única | **Abierto** |
| Definición del cálculo del valor del supervisor | **Abierto** |
| Columna de valor obligatoria | **Abierto** |
| Identificador único de la persona | Cerrado |
| Formato de `DT_DATA` sin ambigüedad de día/mes | Cerrado |
| Una sola columna con el valor del indicador | Cerrado |
| Fechas de creación y actualización por registro | Punto de atención |
| Tabla de metas | Postergado |

---

## 1. Requisitos abiertos

### 1.1 La llave propuesta no identifica una fila

La llave propuesta, `NR_CHAVE_EMPRESA_MES_RE`, combina período, persona y servicio. Validamos su composición fila por fila y es consistente, sin una sola divergencia:

```
NR_CHAVE_EMPRESA_MES_RE = DT_DATA + "-" + NR_RE + "-" + NR_SERVIVIO_CODIGO
```

El problema es de granularidad. Cada fila representa una combinación de persona, indicador y mes — `NR_ID` cambia de fila en fila, y una persona tiene en promedio 9,31 indicadores en el mes. Como la llave no incluye el indicador, se repite:

| Medición sobre la maqueta (60.924 filas) | Valor |
|---|---|
| Valores distintos de `NR_CHAVE_EMPRESA_MES_RE` | 6.547 |
| Llaves que aparecen más de una vez | **6.415 (98,0%)** |
| Máximo de filas bajo una misma llave | 19 |
| Pares persona-mes con un solo indicador | 132 de 6.547 |
| Filas duplicadas agregando `NR_ID` a la combinación | **0** |

Un ejemplo concreto de la maqueta:

```
20260501-128178-2242   →  AUSENTISMO
20260501-128178-2242   →  TMO            misma llave, tres registros distintos
20260501-128178-2242   →  Calidad
```

**El requisito** es que una fila sea identificable de manera única en la granularidad que consumimos: **período, persona, servicio e indicador**. Está verificado contra sus propios datos — con esa combinación, los duplicados bajan a cero en las 60.924 filas.

**Nuestra recomendación es resolverlo con un índice único compuesto, y no con una columna concatenada, porque la columna genera trabajo duplicado de los dos lados.**

Ustedes ya escriben período, persona, servicio e indicador, cada uno en su propia columna. Materializar además una columna que concatena esos mismos cuatro valores significa escribir la misma información dos veces: una vez en las columnas y otra vez en la cadena de texto. Y del lado nuestro el costo se repite en espejo — tendríamos que leer la columna concatenada, partirla para recuperar los cuatro componentes, y de todas formas leer las columnas originales para el resto del procesamiento.

Un índice único compuesto usa las columnas que ya existen, tal como están:

```sql
CREATE UNIQUE NONCLUSTERED INDEX UX_indicadores_score_periodo_persona_servicio_indicador
    ON dbo.tb_dim_indicadores_score (DT_DATA, NR_RE, NR_SERVIVIO_CODIGO, NR_ID);
```

Nadie escribe de más y nadie parte cadenas. El motor de base de datos resuelve la unicidad de forma nativa, que es para lo que está hecho, y desaparece un riesgo que la columna concatenada trae consigo: cualquier cambio futuro en el formato de la concatenación rompería en silencio a todos los que la consumen, y aquí no hay formato que mantener.

La decisión final es de ustedes, que son quienes operan la base. Lo que no puede faltar es la unicidad en esa granularidad: sin ella, nuestra carga incremental no distingue un indicador de otro y sobrescribe valores. En un proceso que alimenta remuneración variable eso no produce un error visible, produce un número equivocado que nadie nota.

### 1.2 Falta definir cómo se calcula el valor del supervisor

En la reunión del 29 de julio quedó planteado que el valor del supervisor no se deriva igual que el del asesor: el del asesor es una división, y el del supervisor necesita un acumulado que no se puede reconstruir desde las filas de los asesores. Quedó de su lado enviarnos dos opciones para diferenciar el tipo de operación.

Esa definición sigue pendiente. No llegó en el correo, y la maqueta tampoco la responde: las filas de supervisor no están, así que no podemos deducir el criterio observando los datos. Los siete valores de `NM_CARGO_DESCRIPCION` presentes son todos de operación, y de los 229 supervisores nombrados en la columna de supervisor, 225 no tienen ninguna fila propia.

**Lo que necesitamos definir** es quién calcula el acumulado del supervisor y cómo llega hasta nosotros: si viene ya calculado en su propia fila, si viene separado en otra estructura, o si la expectativa es que lo calculemos nosotros.

**Nuestra posición es que el acumulado se calcule de su lado y llegue como una fila más**, con el identificador del propio supervisor y el valor ya resuelto, exactamente igual que la de un asesor. El motivo es que ese cálculo depende de la jerarquía, y la jerarquía que la plataforma 4Shark reconoce viene desde Simplex, que es su origen de registro. Si nosotros lo calculáramos recorriendo la jerarquía del VKPI, tendríamos dos sistemas afirmando el mismo hecho, mantenidos por procesos distintos y con cadencias distintas. Van a divergir, y el día que diverjan todos los números de supervisor quedan mal en silencio hasta que alguien audite una nómina.

Si la solución que ustedes ven es otra, necesitamos conocerla para poder dimensionar el trabajo, porque cambia lo que tenemos que construir.

### 1.3 La columna de valor tiene que ser obligatoria

La estructura de una sola columna de valor por fila es la correcta y es lo que necesitamos. Lo que falta es la restricción: la columna debe ser `NOT NULL`.

Un indicador sin valor no es un indicador — si la fila existe, existe porque hay una medición. Vale hacer la distinción porque no son lo mismo: **cero es un valor válido**, es simplemente un indicador que quedó en cero en el período, y no hay ningún inconveniente en enviarlo. Nulo no es un valor.

En la maqueta no encontramos valores vacíos; lo que pedimos es que la restricción exista en la tabla, para que no puedan aparecer.

Como referencia, del lado de la plataforma la Variable puede configurarse para asumir cero cuando no llega información, de modo que enviar la fila en cero es opcional para ustedes. Enviarla tampoco genera ningún inconveniente.

---

## 2. Puntos cerrados

### 2.1 Identificador de la persona

En la reunión del 29 de julio quedó confirmado que `NR_RE` es el código de Simplex que la plataforma ya recibe hoy para cada colaborador. Los datos de la maqueta son consistentes con esa definición: `NR_RE` es un código interno de cuatro a seis dígitos, en un rango de 3.433 a 129.053, distinto de la cédula en todas las filas, con 3.535 valores únicos y ninguno vacío.

**El requisito, de aquí en adelante, es que el identificador siga siendo uno solo.** Una persona tiene una identidad, y esa identidad es la que la resuelve contra el usuario en la plataforma. Si en algún momento el identificador cambiara, las filas históricas quedarían referenciadas por un valor y las nuevas por otro, y la continuidad de la persona se perdería justo donde importa: en su histórico de indicadores. Por eso no podemos trabajar con dos identificadores alternativos ni con una transición entre ellos.

De nuestro lado vamos a cruzar los 3.535 identificadores de la maqueta contra la base de Colombia para confirmar que todos resuelven a un usuario existente. Es una verificación nuestra, no un pedido.

### 2.2 Formato de `DT_DATA`

La columna llega en formato `yyyymmdd`, siempre día 01, lo que resuelve la ambigüedad de día y mes que motivó el pedido original. Lo damos por cerrado y lo tomamos como definitivo.

### 2.3 Una sola columna con el valor

La tabla trae un único valor por fila, sin columna de tipo de cálculo. Es la estructura que necesitamos: el valor llega resuelto y la plataforma lo consume tal cual. La interpretación de ese valor — si es porcentaje, conteo, duración — y su modo de cálculo se configuran del lado de 4Shark, al registrar cada Variable.

---

## 3. Punto de atención — las fechas de creación y actualización

Las columnas `DT_CREACION` y `DT_ACTUALIZACION` están presentes y traen fecha, así que la estructura es la que pedimos y podemos trabajar sobre ella. Observamos que ambas tienen un único valor constante, idéntico al milisegundo en las 60.924 filas, lo que es coherente con haber sido pobladas de una vez para construir la maqueta.

Lo que conviene garantizar, y por eso lo dejamos como recomendación de proceso, es que `DT_CREACION` se fije una sola vez al insertar la fila, y que `DT_ACTUALIZACION` se mueva únicamente cuando el valor cambió — una reescritura con el mismo valor no debería tocarla. Esa segunda condición es la que hace eficiente la carga incremental.

**La recomendación** es no replicar esa lógica en cada punto del código que escribe en la tabla, sino concentrarla en un procedimiento almacenado. El anexo lo entrega listo: recibe todas las columnas como parámetros y resuelve los tres casos — si la fila no existe la inserta con ambas fechas, si existe y el valor cambió actualiza el valor y la fecha de actualización, y si existe con el mismo valor no modifica nada. Basta registrarlo y hacer que el proceso de carga lo invoque en lugar de escribir directo en la tabla.

Es el mismo mecanismo que usamos en nuestro integrador, y evita que la garantía dependa de que cada rutina que toque la tabla se acuerde de aplicarla.

---

## 4. Recomendación — recarga limpia después de aplicar la estructura

Una vez aplicados los cambios de estructura y en funcionamiento el procedimiento de carga, recomendamos vaciar la tabla y volver a cargarla desde cero con los flujos ya corregidos.

El motivo es que los datos actuales fueron escritos bajo las reglas anteriores: sin la restricción de unicidad y sin la semántica de fechas por registro. Una recarga limpia garantiza que todo el contenido sea coherente con la estructura nueva, en lugar de convivir con un histórico escrito bajo reglas distintas.

---

## 5. Punto postergado — la tabla de metas

Durante el análisis identificamos que las metas encajan en este flujo, y quedó registrado que la definición de su plantilla estaba pendiente.

Lo dejamos como seguimiento posterior. No es un requisito para avanzar con los indicadores y preferimos no sumarlo al alcance actual: primero cerramos la integración de indicadores y después retomamos las metas con la atención que requieren.

Cuando lo retomemos, el criterio que ya conversamos se mantiene: tabla separada de la de indicadores, con su propio par de fechas. Indicador y meta cambian con cadencias distintas, y si comparten fila comparten par de fechas, con lo cual la fecha de actualización deja de indicar cuál de los dos cambió.

---

## 6. Cómo trabaja la plataforma 4Shark

Estas definiciones explican por qué los requisitos anteriores tienen la forma que tienen.

**Consumimos una sola tabla.** Las demás tablas del VKPI son de uso interno de ustedes y no forman parte de la integración.

**La jerarquía se mantiene con un único origen.** La plataforma ya recibe desde Simplex la identidad de cada persona, su cargo y su responsable. Por eso 4Shark no consume las columnas de supervisor, gerente, gestor, cargo ni estado del empleado de la tabla de KPIs. Lo dejamos explícito para evitar que en el futuro se intente conciliar información por esas columnas: en el momento en que las dos fuentes difieran, cualquier conciliación produciría un resultado incorrecto sin señal de error.

**Un valor final por fila.** El modelo consume un valor único por combinación de persona, indicador y período. Cualquiera que sea el tipo de operación de origen — suma, división, acumulado — debe resolverse antes de que la fila llegue a nosotros. No sumamos numeradores y denominadores entre filas, no promediamos y no agregamos hacia arriba en la jerarquía.

**Las Variables se configuran en la plataforma.** El equipo funcional las registra en 4Shark, y ahí se define su tipo de dato y su modo de cálculo. No creamos Variables automáticamente a partir de la base de KPIs. Si llega un indicador cuya Variable no está registrada, la API lo rechaza, el rechazo aparece en el informe de integración, les avisamos, y una vez registrada reenviamos la información.

---

## 7. Qué necesitamos para poder estimar

El anexo contiene los scripts en orden de ejecución, cada uno con su consulta de verificación previa. La sección final reúne las consultas de aceptación que ejecutamos sobre la base para dar por cerrada la remediación, de modo que el resultado se pueda comprobar del lado de ustedes antes de avisarnos.

Necesitamos una de estas dos respuestas.

**Que confirmen que van a implementar la estructura recomendada.** Con esa confirmación empezamos a planificar de inmediato, porque ya conocemos la estructura destino: está definida en este documento y escrita en el anexo. La estimación sale rápido porque no hay nada que descubrir.

**O que nos indiquen cómo van a cubrir cada requisito, si prefieren resolverlo de otra manera.** Es una alternativa legítima y no tenemos objeción a que la implementación sea distinta mientras se cumplan los requisitos. Lo que necesitamos que quede claro es que en ese caso la estimación llega después: tenemos que esperar a que la nueva estructura esté implementada, revisarla, y recién entonces dimensionar el trabajo. La forma que elijan cambia lo que tenemos que construir de nuestro lado, y por eso la decisión nos condiciona directamente.

Lo que no podemos hacer es estimar sobre la estructura actual, donde los registros se duplican bajo la llave propuesta. No es una cuestión de preferencia técnica: sobre esa base la integración no funciona.

Quedamos con disposición para acompañar la ejecución de los scripts en una sesión técnica conjunta, si eso acelera el cierre.
