-- VKPI Colombia — auditoria de ESTRUTURA (aceitacao). Base: COLBOGSQL58\MSSQL58_KPI
-- Metadados puros (sys.* / INFORMATION_SCHEMA): nao depende de dados nem de nome de coluna chutado.
-- V1..V4 = veredito PASS/FAIL por item que reclamamos. INV* = estrutura completa das duas tabelas.
-- Rode em ordem; leia a coluna "veredito". A secao de DADOS no fim so vale depois do reprocesso.

-- V1 — indice unico no GRAO DE NEGOCIO {DT_DATA, NR_RE, NR_SERVIVIO_CODIGO, NR_ID}
-- (robusto a grafia do programa: casa NR_SERV%CODIGO). FAIL se o unico indice unico for a PK no surrogate.
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

-- V3 — colunas de criacao/atualizacao em datetime (com hora), nunca date.
-- Descobre por padrao de nome (CREAT/MODIF/CREAC/ACTUALIZ), nao assume DT_CREATED vs DT_CREACION.
SELECT CASE
  WHEN COUNT(*) = 0 THEN 'FAIL: nenhuma coluna de criacao/atualizacao encontrada'
  WHEN SUM(CASE WHEN data_type IN ('datetime','datetime2') THEN 1 ELSE 0 END) = COUNT(*) THEN 'PASS'
  ELSE 'FAIL: existe coluna de criacao/atualizacao que nao e datetime' END AS v3_datas_datetime
FROM INFORMATION_SCHEMA.COLUMNS
WHERE table_name='tb_dim_indicadores_score'
  AND (column_name LIKE '%CREAT%' OR column_name LIKE '%MODIF%'
    OR column_name LIKE '%CREAC%' OR column_name LIKE '%ACTUALIZ%');
GO

-- V4 — integridade referencial: FK de score.NR_ID para o catalogo.
SELECT CASE WHEN EXISTS (
  SELECT 1 FROM sys.foreign_keys WHERE parent_object_id = OBJECT_ID('dbo.tb_dim_indicadores_score')
) THEN 'PASS: existe FK' ELSE 'FAIL: sem FK score -> catalogo' END AS v4_fk;
GO

-- INV1 — TODAS as colunas das duas tabelas (pega coluna adicionada, tipo trocado, quebra).
SELECT table_name, ordinal_position AS position, column_name, data_type,
       character_maximum_length AS max_length, numeric_precision, numeric_scale, is_nullable
FROM INFORMATION_SCHEMA.COLUMNS
WHERE table_name IN ('tb_dim_indicadores_score','tb_dim_indicadores')
ORDER BY table_name, ordinal_position;
GO

-- INV2 — TODOS os indices das duas tabelas, uma linha por indice com suas colunas concatenadas.
-- Esta e a evidencia direta do V1/V2: veja is_unique e key_columns.
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

-- ===== DADOS — so depois do reprocesso; nao decide a estrutura =====

-- D1 — duplicata no grao (sem indice unico nada impede). PASSA: zero linhas.
SELECT DT_DATA, NR_RE, NR_SERVIVIO_CODIGO, NR_ID, COUNT(*) AS occurrences
FROM dbo.tb_dim_indicadores_score
GROUP BY DT_DATA, NR_RE, NR_SERVIVIO_CODIGO, NR_ID
HAVING COUNT(*) > 1
ORDER BY occurrences DESC;
GO

-- D2 — score cujo NR_ID nao existe no catalogo. PASSA: 0.
SELECT COUNT(*) AS orphan_score_rows
FROM dbo.tb_dim_indicadores_score AS score
LEFT JOIN dbo.tb_dim_indicadores AS catalogue ON catalogue.NR_ID = score.NR_ID
WHERE catalogue.NR_ID IS NULL;
GO
