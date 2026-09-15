-- VKPI Colombia — auditoria COMPLETA de estrutura + dados (aceitacao). Base: COLBOGSQL58\MSSQL58_KPI
-- Sucede vkpi-validation-queries-colombia-20260908.sql. Acrescenta: cursor de paginacao (P*),
-- resolucao do join score->catalogo (J*), coluna de valor (VAL*). Mantem V1..V4 / INV* / D1..D2.
-- Rode em ordem, leia a coluna de veredito. A secao de DADOS so vale depois do reprocesso da base.
--
-- Coluna de indicador confirmada contra a base viva em 14-set: e NR_ID (float), NAO NR_INDICADOR.
-- J1 (join por NR_ID) = 0 orfaos; J2 (join por NR_INDICADOR) = 33079 orfaos (a base inteira),
-- porque NR_INDICADOR esta NULL em toda a score. O grao usa NR_ID.
--
-- Estado conhecido em 14-set: existe indice unico na PK NR_CHAVE_EMPRESA_MES_RE (coluna unica), e essa
-- chave e 1:1 com o grao de negocio (linhas = chaves = graos = 33079), entao a unicidade do grao esta
-- garantida na pratica. V1 da FAIL so porque procura o indice nas 4 colunas do grao, nao na chave -- e
-- uma distincao de forma, nao de unicidade. Abertos de verdade: V2 (coluna llave nao existe no catalogo),
-- V2b (catalogo e heap, NR_ID pode repetir), VAL1 (NR_NUMERADOR/NR_DENOMINADOR ainda na score).

-- ============================ ESTRUTURA ============================

-- INV1 — TODAS as colunas das duas tabelas (pega coluna adicionada, tipo trocado, quebra).
SELECT table_name, ordinal_position AS position, column_name, data_type,
       character_maximum_length AS max_length, numeric_precision, numeric_scale, is_nullable
FROM INFORMATION_SCHEMA.COLUMNS
WHERE table_name IN ('tb_dim_indicadores_score','tb_dim_indicadores')
ORDER BY table_name, ordinal_position;
GO

-- INV2 — TODOS os indices das duas tabelas, uma linha por indice com suas colunas.
SELECT tables.name AS tbl, indexes.name AS index_name, indexes.type_desc,
       indexes.is_unique, indexes.is_primary_key, indexes.is_unique_constraint,
       STUFF((SELECT ', ' + columns.name
              FROM sys.index_columns index_columns
              JOIN sys.columns columns ON columns.object_id=index_columns.object_id AND columns.column_id=index_columns.column_id
              WHERE index_columns.object_id=indexes.object_id AND index_columns.index_id=indexes.index_id
                AND index_columns.is_included_column=0
              ORDER BY index_columns.key_ordinal FOR XML PATH('')),1,2,'') AS key_columns
FROM sys.indexes indexes
JOIN sys.tables tables ON tables.object_id = indexes.object_id
WHERE tables.name IN ('tb_dim_indicadores_score','tb_dim_indicadores')
ORDER BY tables.name, indexes.index_id;
GO

-- INV3 — TODAS as FKs das duas tabelas.
SELECT OBJECT_NAME(foreign_keys.parent_object_id) AS table_name,
       foreign_keys.name AS constraint_name,
       COL_NAME(foreign_key_columns.parent_object_id, foreign_key_columns.parent_column_id) AS column_name,
       OBJECT_NAME(foreign_keys.referenced_object_id) AS referenced_table,
       COL_NAME(foreign_key_columns.referenced_object_id, foreign_key_columns.referenced_column_id) AS referenced_column
FROM sys.foreign_keys foreign_keys
JOIN sys.foreign_key_columns foreign_key_columns
  ON foreign_key_columns.constraint_object_id = foreign_keys.object_id
WHERE foreign_keys.parent_object_id IN (OBJECT_ID('dbo.tb_dim_indicadores_score'), OBJECT_ID('dbo.tb_dim_indicadores'))
ORDER BY table_name, constraint_name;
GO

-- ============================ VEREDITOS POR REQUISITO ============================

-- V1 — indice unico no GRAO DE NEGOCIO {DT_DATA, NR_RE, NR_SERVIVIO_CODIGO, NR_ID}.
-- FAIL se o unico indice unico for a PK numa coluna surrogate/chave (ex.: NR_CHAVE_EMPRESA_MES_RE).
SELECT CASE WHEN EXISTS (
  SELECT 1 FROM sys.indexes i
  WHERE i.object_id = OBJECT_ID('dbo.tb_dim_indicadores_score') AND i.is_unique = 1
    AND (SELECT COUNT(*) FROM sys.index_columns ic
         WHERE ic.object_id=i.object_id AND ic.index_id=i.index_id AND ic.is_included_column=0) = 4
    AND (SELECT COUNT(*) FROM sys.index_columns ic
         JOIN sys.columns c ON c.object_id=ic.object_id AND c.column_id=ic.column_id
         WHERE ic.object_id=i.object_id AND ic.index_id=i.index_id AND ic.is_included_column=0
           AND (c.name IN ('DT_DATA','NR_RE','NR_ID') OR c.name LIKE 'NR_SERV%CODIGO')) = 4
) THEN 'PASS' ELSE 'FAIL' END AS v1_indice_unico_grao;
GO

-- V2 — coluna llave no catalogo tb_dim_indicadores: existe, texto, NOT NULL, com indice unico proprio.
SELECT CASE
  WHEN c.name IS NULL THEN 'FAIL: coluna llave NAO existe'
  WHEN c.is_nullable = 1 THEN 'FAIL: llave existe mas e NULLABLE'
  WHEN t.name NOT IN ('varchar','nvarchar','char','nchar') THEN 'FAIL: llave nao e texto (' + t.name + ')'
  WHEN NOT EXISTS (
    SELECT 1 FROM sys.indexes i
    JOIN sys.index_columns ic ON ic.object_id=i.object_id AND ic.index_id=i.index_id AND ic.is_included_column=0
    WHERE i.object_id=OBJECT_ID('dbo.tb_dim_indicadores') AND i.is_unique=1 AND ic.column_id=c.column_id
      AND (SELECT COUNT(*) FROM sys.index_columns ic2
           WHERE ic2.object_id=i.object_id AND ic2.index_id=i.index_id AND ic2.is_included_column=0)=1
  ) THEN 'FAIL: llave sem indice unico proprio'
  ELSE 'PASS' END AS v2_llave_catalogo
FROM (SELECT OBJECT_ID('dbo.tb_dim_indicadores') AS oid) d
LEFT JOIN sys.columns c ON c.object_id = d.oid AND c.name = 'llave'
LEFT JOIN sys.types t ON t.user_type_id = c.user_type_id;
GO

-- V2b — o catalogo tem QUALQUER indice unico em NR_ID? (o join precisa de NR_ID unico no catalogo)
SELECT CASE WHEN EXISTS (
  SELECT 1 FROM sys.indexes i
  JOIN sys.index_columns ic ON ic.object_id=i.object_id AND ic.index_id=i.index_id AND ic.is_included_column=0
  JOIN sys.columns c ON c.object_id=ic.object_id AND c.column_id=ic.column_id
  WHERE i.object_id=OBJECT_ID('dbo.tb_dim_indicadores') AND i.is_unique=1 AND c.name='NR_ID'
    AND (SELECT COUNT(*) FROM sys.index_columns ic2
         WHERE ic2.object_id=i.object_id AND ic2.index_id=i.index_id AND ic2.is_included_column=0)=1
) THEN 'PASS' ELSE 'FAIL: NR_ID nao e unico no catalogo (catalogo pode ter NR_ID repetido)' END AS v2b_nr_id_unico_catalogo;
GO

-- V3 — colunas de criacao/atualizacao em datetime (com hora), nunca date.
SELECT CASE
  WHEN COUNT(*) = 0 THEN 'FAIL: nenhuma coluna de criacao/atualizacao encontrada'
  WHEN SUM(CASE WHEN data_type IN ('datetime','datetime2') THEN 1 ELSE 0 END) = COUNT(*) THEN 'PASS'
  ELSE 'FAIL: existe coluna de criacao/atualizacao que nao e datetime' END AS v3_datas_datetime
FROM INFORMATION_SCHEMA.COLUMNS
WHERE table_name='tb_dim_indicadores_score'
  AND (column_name LIKE '%CREAT%' OR column_name LIKE '%MODIF%'
    OR column_name LIKE '%CREAC%' OR column_name LIKE '%ACTUALIZ%');
GO

-- VAL1 — coluna de valor: RESULTADO existe e o par numerador/denominador SUMIU (single value).
SELECT
  MAX(CASE WHEN column_name='RESULTADO' THEN 1 ELSE 0 END)     AS tem_resultado,
  MAX(CASE WHEN column_name LIKE 'NR_NUMERAD%' THEN 1 ELSE 0 END)   AS ainda_tem_numerador,
  MAX(CASE WHEN column_name LIKE 'NR_DENOMINAD%' THEN 1 ELSE 0 END) AS ainda_tem_denominador
FROM INFORMATION_SCHEMA.COLUMNS
WHERE table_name='tb_dim_indicadores_score';
GO

-- ============================ CURSOR DE PAGINACAO ============================

-- P1 — a coluna do cursor (a PK de coluna unica): tipo e nullability. Precisa NOT NULL e ordenavel.
SELECT c.name AS coluna_cursor, t.name AS tipo, c.max_length, c.is_nullable, c.is_identity
FROM sys.columns c
JOIN sys.types t ON t.user_type_id = c.user_type_id
WHERE c.object_id = OBJECT_ID('dbo.tb_dim_indicadores_score')
  AND c.name = 'NR_CHAVE_EMPRESA_MES_RE';
GO

-- P2 — o cursor e UNICO por linha (obrigatorio pra keyset)? linhas == chaves distintas => cursor valido.
-- graos == linhas confirma que o cursor tambem e 1:1 com o grao de negocio (nao ha duplicata de grao).
SELECT
  COUNT(*) AS linhas,
  COUNT(DISTINCT NR_CHAVE_EMPRESA_MES_RE) AS chaves_distintas,
  COUNT(DISTINCT CONCAT(DT_DATA,'|',NR_RE,'|',NR_SERVIVIO_CODIGO,'|',NR_ID)) AS graos_distintos
FROM dbo.tb_dim_indicadores_score;
GO

-- ============================ JOIN score -> catalogo ============================

-- J1 — orfaos usando score.NR_ID = catalogo.NR_ID (o join CORRETO, 0 orfaos em 14-set). PASSA: 0.
SELECT COUNT(*) AS orfaos_por_NR_ID
FROM dbo.tb_dim_indicadores_score AS score
LEFT JOIN dbo.tb_dim_indicadores AS catalogue ON catalogue.NR_ID = score.NR_ID
WHERE catalogue.NR_ID IS NULL;
GO

-- J2 — diagnostico: orfaos usando score.NR_INDICADOR = catalogo.NR_ID.
-- Em 14-set deu 33079 (a base inteira), porque NR_INDICADOR esta NULL. Confirma que NR_ID e o join.
SELECT COUNT(*) AS orfaos_por_NR_INDICADOR
FROM dbo.tb_dim_indicadores_score AS score
LEFT JOIN dbo.tb_dim_indicadores AS catalogue ON catalogue.NR_ID = score.NR_INDICADOR
WHERE catalogue.NR_ID IS NULL;
GO

-- ============================ DADOS — so depois do reprocesso ============================

-- D1 — duplicata no grao {DT_DATA, NR_RE, NR_SERVIVIO_CODIGO, NR_ID}. PASSA: zero linhas.
SELECT DT_DATA, NR_RE, NR_SERVIVIO_CODIGO, NR_ID, COUNT(*) AS ocorrencias
FROM dbo.tb_dim_indicadores_score
GROUP BY DT_DATA, NR_RE, NR_SERVIVIO_CODIGO, NR_ID
HAVING COUNT(*) > 1
ORDER BY ocorrencias DESC;
GO

-- D2 — mesmo grao com RESULTADO conflitante (dois valores diferentes na mesma linha logica). PASSA: 0.
SELECT DT_DATA, NR_RE, NR_SERVIVIO_CODIGO, NR_ID, COUNT(DISTINCT RESULTADO) AS valores_distintos
FROM dbo.tb_dim_indicadores_score
GROUP BY DT_DATA, NR_RE, NR_SERVIVIO_CODIGO, NR_ID
HAVING COUNT(DISTINCT RESULTADO) > 1
ORDER BY valores_distintos DESC;
GO
