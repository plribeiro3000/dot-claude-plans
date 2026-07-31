/* ============================================================================
   Atento Colombia — VKPI
   Solución al punto 1: fecha de creación y fecha de actualización en la tabla
   de indicadores, más un procedimiento que crea o actualiza (MERGE) manteniendo
   esas dos fechas de forma automática.

   Servidor      : COLBOGSQL58\MSSQL58_KPI
   Tabla         : dbo.tb_dim_indicadores_score
   Elaborado por : 4Shark
   Fecha         : 2026-07-29

   El script es idempotente: puede ejecutarse más de una vez sin duplicar
   columnas, índices ni el procedimiento.

   Orden de ejecución: las secciones están numeradas y deben correrse en orden.
   La sección 0 es una verificación previa que NO modifica nada.
   ============================================================================ */


/* ----------------------------------------------------------------------------
   SECCIÓN 0 — Verificación previa (no modifica nada)

   La clave lógica de una fila es la combinación (NR_EMPRESA, NR_RE,
   NR_INDICADOR, DT_DATA): identifica de forma única el indicador de una persona
   en un período. El procedimiento de la sección 3 se apoya en esa clave, y la
   sección 2 crea un índice único sobre ella. Un índice único falla si ya
   existen duplicados, así que primero los buscamos. El resultado esperado es
   CERO filas.
   ---------------------------------------------------------------------------- */

SELECT
    NR_EMPRESA,
    NR_RE,
    NR_INDICADOR,
    DT_DATA,
    COUNT(*) AS cantidad_duplicados
FROM dbo.tb_dim_indicadores_score
GROUP BY NR_EMPRESA, NR_RE, NR_INDICADOR, DT_DATA
HAVING COUNT(*) > 1;
GO


/* ----------------------------------------------------------------------------
   SECCIÓN 1 — Columnas de fecha de creación y de actualización

   Se agregan dos columnas siguiendo la convención de nombres de la tabla
   (prefijo DT_ para fechas, igual que DT_DATA):

     DT_CREACION      — fecha en que la fila fue insertada por primera vez
     DT_ACTUALIZACION — fecha de la última modificación de la fila

   Se usa el tipo datetime, que almacena la marca de tiempo sin ninguna
   ambigüedad de formato (a diferencia del texto con separadores). El valor lo
   pone el servidor con GETUTCDATE() (hora UTC), no viene del proceso de
   carga.

   Las filas que ya existen no tienen marca de origen, así que reciben la fecha
   del momento de esta migración, con DT_CREACION = DT_ACTUALIZACION. Es lo más
   fiel posible para datos históricos sin rastro previo.
   ---------------------------------------------------------------------------- */

IF COL_LENGTH('dbo.tb_dim_indicadores_score', 'DT_CREACION') IS NULL
    ALTER TABLE dbo.tb_dim_indicadores_score ADD DT_CREACION datetime NULL;
GO

IF COL_LENGTH('dbo.tb_dim_indicadores_score', 'DT_ACTUALIZACION') IS NULL
    ALTER TABLE dbo.tb_dim_indicadores_score ADD DT_ACTUALIZACION datetime NULL;
GO

/* Relleno de las filas existentes: mismo valor en ambas columnas. */
DECLARE @ahora datetime = GETUTCDATE();

UPDATE dbo.tb_dim_indicadores_score
SET DT_CREACION      = @ahora,
    DT_ACTUALIZACION = @ahora
WHERE DT_CREACION IS NULL
   OR DT_ACTUALIZACION IS NULL;
GO

/* Una vez pobladas, se vuelven obligatorias y se les da un valor por defecto,
   de modo que cualquier INSERT hecho por fuera del procedimiento también quede
   marcado. */
ALTER TABLE dbo.tb_dim_indicadores_score ALTER COLUMN DT_CREACION      datetime NOT NULL;
GO
ALTER TABLE dbo.tb_dim_indicadores_score ALTER COLUMN DT_ACTUALIZACION datetime NOT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.default_constraints WHERE name = 'DF_indicadores_score_DT_CREACION')
    ALTER TABLE dbo.tb_dim_indicadores_score
        ADD CONSTRAINT DF_indicadores_score_DT_CREACION
        DEFAULT (GETUTCDATE()) FOR DT_CREACION;
GO

IF NOT EXISTS (SELECT 1 FROM sys.default_constraints WHERE name = 'DF_indicadores_score_DT_ACTUALIZACION')
    ALTER TABLE dbo.tb_dim_indicadores_score
        ADD CONSTRAINT DF_indicadores_score_DT_ACTUALIZACION
        DEFAULT (GETUTCDATE()) FOR DT_ACTUALIZACION;
GO

/* La actualización nunca puede ser anterior a la creación. */
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_indicadores_score_fechas')
    ALTER TABLE dbo.tb_dim_indicadores_score
        ADD CONSTRAINT CK_indicadores_score_fechas
        CHECK (DT_ACTUALIZACION >= DT_CREACION);
GO


/* ----------------------------------------------------------------------------
   SECCIÓN 2 — Índice único sobre la clave lógica

   Garantiza que no puedan existir dos filas para el mismo indicador de la misma
   persona en el mismo período. Es además el requisito que hace seguro el MERGE
   de la sección 3: sin unicidad garantizada, un MERGE podría intentar actualizar
   la misma fila más de una vez.

   Si la sección 0 devolvió filas, hay que resolver esos duplicados antes de
   ejecutar esta sección; de lo contrario la creación del índice fallará.
   ---------------------------------------------------------------------------- */

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_indicadores_score_clave_logica')
    CREATE UNIQUE INDEX UX_indicadores_score_clave_logica
        ON dbo.tb_dim_indicadores_score (NR_EMPRESA, NR_RE, NR_INDICADOR, DT_DATA);
GO


/* ----------------------------------------------------------------------------
   SECCIÓN 3 — Procedimiento guardar_indicador_score (crea o actualiza)

   Un solo procedimiento resuelve los dos casos con un MERGE, exactamente como
   lo hace el integrador 4Shark en su propio esquema:

     - Si la fila NO existe (según la clave lógica) → la inserta, y marca
       DT_CREACION = DT_ACTUALIZACION = ahora.
     - Si la fila YA existe y algún valor cambió → la actualiza, y mueve solo
       DT_ACTUALIZACION = ahora (DT_CREACION queda intacta).
     - Si la fila ya existe y nada cambió → no toca la fila, y por lo tanto
       DT_ACTUALIZACION tampoco se mueve. Esto es lo que hace confiable la
       lectura incremental: la fecha de actualización cambia solo cuando el dato
       cambió de verdad.

   La comparación de cambios usa EXCEPT, que trata los NULL de forma segura (dos
   NULL se consideran iguales), evitando falsas actualizaciones.

   HOLDLOCK protege contra condiciones de carrera si dos cargas tocaran la misma
   fila al mismo tiempo.

   Los parámetros de las columnas de puntuación (NM_FAIXA, FL_SCORE, NM_QUARTIL,
   NR_SCORE, NM_EMPLEADO_ACTIVO) son opcionales porque hoy llegan vacíos; se
   dejan disponibles por si en el futuro se poblaran.
   ---------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE dbo.guardar_indicador_score
    @NR_EMPRESA                int,
    @NR_RE                     int,
    @NR_INDICADOR              int,
    @DT_DATA                   date,
    @NR_NUMERADOR              float,
    @NR_DENOMINADOR            float,
    @NR_CHAVE_EMPRESA_MES_RE   bigint       = NULL,
    @NR_CHAVE_EMPRESA_DIA_RE   bigint       = NULL,
    @NR_LLAVE_CUARTIL          varchar(8000) = NULL,
    @NR_SERVIVIO_CODIGO        int          = NULL,
    @NR_CHAVE_METAS_MES_RE     varchar(8000) = NULL,
    @NM_FAIXA                  varchar(8000) = NULL,
    @FL_SCORE                  int          = NULL,
    @NM_QUARTIL                varchar(8000) = NULL,
    @NR_SCORE                  int          = NULL,
    @NM_EMPLEADO_ACTIVO        varchar(8000) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ahora datetime = GETUTCDATE();

    MERGE INTO dbo.tb_dim_indicadores_score WITH (HOLDLOCK) AS destino
    USING (
        SELECT
            @NR_EMPRESA              AS NR_EMPRESA,
            @NR_RE                   AS NR_RE,
            @NR_INDICADOR            AS NR_INDICADOR,
            @DT_DATA                 AS DT_DATA,
            @NR_NUMERADOR            AS NR_NUMERADOR,
            @NR_DENOMINADOR          AS NR_DENOMINADOR,
            @NR_CHAVE_EMPRESA_MES_RE AS NR_CHAVE_EMPRESA_MES_RE,
            @NR_CHAVE_EMPRESA_DIA_RE AS NR_CHAVE_EMPRESA_DIA_RE,
            @NR_LLAVE_CUARTIL        AS NR_LLAVE_CUARTIL,
            @NR_SERVIVIO_CODIGO      AS NR_SERVIVIO_CODIGO,
            @NR_CHAVE_METAS_MES_RE   AS NR_CHAVE_METAS_MES_RE,
            @NM_FAIXA                AS NM_FAIXA,
            @FL_SCORE                AS FL_SCORE,
            @NM_QUARTIL              AS NM_QUARTIL,
            @NR_SCORE                AS NR_SCORE,
            @NM_EMPLEADO_ACTIVO      AS NM_EMPLEADO_ACTIVO
    ) AS origen
    ON  destino.NR_EMPRESA   = origen.NR_EMPRESA
    AND destino.NR_RE        = origen.NR_RE
    AND destino.NR_INDICADOR = origen.NR_INDICADOR
    AND destino.DT_DATA      = origen.DT_DATA

    WHEN MATCHED AND EXISTS (
        SELECT destino.NR_NUMERADOR, destino.NR_DENOMINADOR,
               destino.NR_CHAVE_EMPRESA_MES_RE, destino.NR_CHAVE_EMPRESA_DIA_RE,
               destino.NR_LLAVE_CUARTIL, destino.NR_SERVIVIO_CODIGO,
               destino.NR_CHAVE_METAS_MES_RE, destino.NM_FAIXA,
               destino.FL_SCORE, destino.NM_QUARTIL,
               destino.NR_SCORE, destino.NM_EMPLEADO_ACTIVO
        EXCEPT
        SELECT origen.NR_NUMERADOR, origen.NR_DENOMINADOR,
               origen.NR_CHAVE_EMPRESA_MES_RE, origen.NR_CHAVE_EMPRESA_DIA_RE,
               origen.NR_LLAVE_CUARTIL, origen.NR_SERVIVIO_CODIGO,
               origen.NR_CHAVE_METAS_MES_RE, origen.NM_FAIXA,
               origen.FL_SCORE, origen.NM_QUARTIL,
               origen.NR_SCORE, origen.NM_EMPLEADO_ACTIVO
    ) THEN
        UPDATE SET
            destino.NR_NUMERADOR            = origen.NR_NUMERADOR,
            destino.NR_DENOMINADOR          = origen.NR_DENOMINADOR,
            destino.NR_CHAVE_EMPRESA_MES_RE = origen.NR_CHAVE_EMPRESA_MES_RE,
            destino.NR_CHAVE_EMPRESA_DIA_RE = origen.NR_CHAVE_EMPRESA_DIA_RE,
            destino.NR_LLAVE_CUARTIL        = origen.NR_LLAVE_CUARTIL,
            destino.NR_SERVIVIO_CODIGO      = origen.NR_SERVIVIO_CODIGO,
            destino.NR_CHAVE_METAS_MES_RE   = origen.NR_CHAVE_METAS_MES_RE,
            destino.NM_FAIXA                = origen.NM_FAIXA,
            destino.FL_SCORE                = origen.FL_SCORE,
            destino.NM_QUARTIL              = origen.NM_QUARTIL,
            destino.NR_SCORE                = origen.NR_SCORE,
            destino.NM_EMPLEADO_ACTIVO      = origen.NM_EMPLEADO_ACTIVO,
            destino.DT_ACTUALIZACION        = @ahora

    WHEN NOT MATCHED THEN
        INSERT (NR_EMPRESA, NR_RE, NR_INDICADOR, DT_DATA,
                NR_NUMERADOR, NR_DENOMINADOR,
                NR_CHAVE_EMPRESA_MES_RE, NR_CHAVE_EMPRESA_DIA_RE,
                NR_LLAVE_CUARTIL, NR_SERVIVIO_CODIGO, NR_CHAVE_METAS_MES_RE,
                NM_FAIXA, FL_SCORE, NM_QUARTIL, NR_SCORE, NM_EMPLEADO_ACTIVO,
                DT_CREACION, DT_ACTUALIZACION)
        VALUES (origen.NR_EMPRESA, origen.NR_RE, origen.NR_INDICADOR, origen.DT_DATA,
                origen.NR_NUMERADOR, origen.NR_DENOMINADOR,
                origen.NR_CHAVE_EMPRESA_MES_RE, origen.NR_CHAVE_EMPRESA_DIA_RE,
                origen.NR_LLAVE_CUARTIL, origen.NR_SERVIVIO_CODIGO, origen.NR_CHAVE_METAS_MES_RE,
                origen.NM_FAIXA, origen.FL_SCORE, origen.NM_QUARTIL, origen.NR_SCORE, origen.NM_EMPLEADO_ACTIVO,
                @ahora, @ahora);
END
GO


/* ----------------------------------------------------------------------------
   SECCIÓN 4 — Ejemplos de uso

   La misma llamada sirve para crear y para actualizar. La segunda vez con el
   mismo valor no mueve DT_ACTUALIZACION; con un valor distinto, sí.
   ---------------------------------------------------------------------------- */

/* Crea (o actualiza) el indicador 270 de la persona 121994, empresa 1, mayo 2026 */
-- EXEC dbo.guardar_indicador_score
--     @NR_EMPRESA        = 1,
--     @NR_RE             = 121994,
--     @NR_INDICADOR      = 270,
--     @DT_DATA           = '2026-05-01',
--     @NR_NUMERADOR      = 0.846280991735537,
--     @NR_DENOMINADOR    = 567.439102564103,
--     @NR_SERVIVIO_CODIGO = 2117;

/* Verificación */
-- SELECT NR_EMPRESA, NR_RE, NR_INDICADOR, DT_DATA,
--        NR_NUMERADOR, NR_DENOMINADOR, DT_CREACION, DT_ACTUALIZACION
-- FROM dbo.tb_dim_indicadores_score
-- WHERE NR_EMPRESA = 1 AND NR_RE = 121994 AND NR_INDICADOR = 270 AND DT_DATA = '2026-05-01';
