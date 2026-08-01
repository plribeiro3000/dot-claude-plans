# Integración de KPIs Colombia — Estado de los requisitos

**Documento técnico 4Shark · 31 de julio de 2026**

**Alcance:** la tabla de indicadores del VKPI, que es la única que la integración consume.
**Anexo:** `remediacion_vkpi_colombia.sql`

---

Revisamos la maqueta del 30 de julio contra los puntos que acordamos el 29. Tres quedaron cerrados y dos siguen abiertos. Este documento detalla los dos abiertos, y el anexo trae el script del único que tiene solución escrita.

Queremos entregar la estimación de esfuerzo, y no podemos hacerlo todavía: la tabla no tiene una llave que identifique una fila de manera única. Sobre esa base la integración no funciona, y cualquier plazo que diéramos sería un número que no podríamos sostener.

| Punto | Estado |
|---|---|
| Llave que identifique una fila de manera única | **Abierto** |
| Cómo se calcula el valor del supervisor | **Abierto** |
| Identificador único de la persona | Cerrado — `NR_RE`, el código de Simplex, confirmado en la reunión y consistente con los datos |
| Formato de `DT_DATA` | Cerrado — `yyyymmdd`, sin ambigüedad de día y mes |
| Una sola columna con el valor del indicador | Cerrado |
| Fechas de creación y actualización | Recomendación de proceso, no requisito |
| Tabla de metas | Postergado hasta cerrar indicadores |

---

## 1. La llave propuesta no identifica una fila

`NR_CHAVE_EMPRESA_MES_RE` combina período, persona y servicio, pero no incluye el indicador. Como cada fila es una combinación de persona, indicador y mes, y una persona tiene en promedio 9,31 indicadores mensuales, la llave se repite:

| Sobre las 60.924 filas de la maqueta | |
|---|---|
| Valores distintos de la llave | 6.547 |
| Llaves repetidas | **6.415 (98,0%)** |
| Máximo de filas bajo una misma llave | 19 |
| Duplicados agregando `NR_ID` | **0** |

```
20260501-128178-2242   →  AUSENTISMO
20260501-128178-2242   →  TMO            misma llave, tres registros distintos
20260501-128178-2242   →  Calidad
```

**El requisito** es unicidad en la granularidad que consumimos: período, persona, servicio e indicador. Verificado contra sus propios datos, con esa combinación los duplicados bajan a cero.

**Recomendamos un índice único compuesto, no una columna concatenada, porque la columna genera trabajo duplicado de los dos lados.** Ustedes ya escriben los cuatro valores, cada uno en su columna; materializar además una cadena con esos mismos valores es escribir la misma información dos veces. Y de nuestro lado el costo se repite en espejo: tendríamos que leer la cadena, partirla para recuperar los componentes, y de todas formas leer las columnas originales.

```sql
CREATE UNIQUE NONCLUSTERED INDEX UX_indicadores_score_periodo_persona_servicio_indicador
    ON dbo.tb_dim_indicadores_score (DT_DATA, NR_RE, NR_SERVIVIO_CODIGO, NR_ID);
```

Usa las columnas tal como están, lo resuelve el motor de forma nativa, y desaparece el riesgo de que un cambio de formato en la concatenación rompa en silencio a quien la consume. La decisión final es de ustedes; lo que no puede faltar es la unicidad, porque sin ella nuestra carga sobrescribe un indicador con otro — y en un proceso que alimenta remuneración variable eso no da error, da un número equivocado que nadie nota.

---

## 2. Falta definir cómo se calcula el valor del supervisor

En la reunión del 29 quedó planteado que el valor del supervisor no se deriva igual que el del asesor: necesita un acumulado que no se reconstruye desde las filas de los asesores. Quedó de su lado enviarnos dos opciones para diferenciar el tipo de operación.

Esa definición sigue pendiente, y la maqueta tampoco la responde: no trae filas de supervisor. Los siete cargos presentes son todos de operación, y de los 229 supervisores nombrados, 225 no tienen fila propia.

**Necesitamos saber quién calcula el acumulado y cómo llega hasta nosotros**: si viene ya calculado en su propia fila, si viene en otra estructura, o cuál es la solución que ustedes ven.

Nuestra posición es que llegue como una fila más, con el identificador del propio supervisor y el valor ya resuelto, igual que la de un asesor. El motivo es que ese cálculo depende de la jerarquía, y la jerarquía que la plataforma reconoce viene desde Simplex, que es su origen de registro. Si lo calculáramos recorriendo la jerarquía del VKPI, dos sistemas estarían afirmando el mismo hecho con procesos y cadencias distintas; van a divergir, y el día que diverjan todos los números de supervisor quedan mal en silencio.

Si la solución que ustedes ven es otra, necesitamos conocerla para dimensionar el trabajo, porque cambia lo que tenemos que construir.

---

## 3. Recomendación de proceso — las fechas

Las columnas de creación y actualización están y traen fecha, así que la estructura es la que pedimos. Lo que conviene garantizar es que la fecha de creación se fije una sola vez al insertar, y que la de actualización se mueva únicamente cuando el valor cambió.

Para no replicar esa regla en cada rutina que escribe en la tabla, el anexo entrega un procedimiento que recibe todas las columnas como parámetros y lo resuelve por su cuenta: inserta con ambas fechas si la fila no existe, actualiza valor y fecha si el valor cambió, y no toca nada si el valor es el mismo. Basta registrarlo y hacer que el proceso de carga lo invoque. Es el mismo mecanismo que usamos en nuestro integrador.

Una vez aplicada la estructura y en uso el procedimiento, recomendamos vaciar la tabla y recargarla desde cero, para que todo el contenido sea coherente con las reglas nuevas.

---

## 4. Qué necesitamos para poder estimar

Necesitamos que resuelvan los dos puntos y nos entreguen la base ya con los cambios aplicados, para hacer un análisis final sobre la estructura real. Con eso estimamos.

La confirmación de que lo van a hacer no nos alcanza, y no es desconfianza. Entre la intención y la implementación puede aparecer un impedimento que los lleve a resolverlo de otra manera — una decisión razonable de su lado, que sin embargo puede cambiar por completo lo que nosotros tenemos que construir. Si nos enteramos al conectarnos, la estimación que hayamos dado antes ya no sirve. Por eso necesitamos conocer la solución final, implementada, y no la intención.

Si eligen un camino distinto al recomendado no tenemos objeción, siempre que se cumplan los requisitos; solo pedimos que nos lo indiquen junto con la entrega. Ya tenemos una noción del trabajo que implica esta integración: lo que no podemos dimensionar es el efecto de definiciones que todavía no existen.

Las metas quedan como seguimiento posterior — no son requisito para avanzar con indicadores.

Quedamos con disposición para acompañar la ejecución del script en una sesión técnica conjunta, si eso acelera el cierre.
