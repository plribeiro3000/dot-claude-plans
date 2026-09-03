"""Build the Spanish technical-review PDF for the Atento Mexico VKPI delivery.

Content is client-facing (forwardable to Atento Mexico), so the strings are in
Spanish per the Language Policy; code and comments stay in English.
"""
import os

from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import mm
from reportlab.platypus import (
    SimpleDocTemplate,
    Paragraph,
    Spacer,
    Table,
    TableStyle,
    ListFlowable,
    ListItem,
    Preformatted,
)

output_path = os.path.expanduser(
    "~/Downloads/revision_tecnica_vkpi_atento_mexico_20260902.pdf"
)

navy = colors.HexColor("#1f3a5f")
grey = colors.HexColor("#555555")
light = colors.HexColor("#eef2f7")

styles = getSampleStyleSheet()
title_style = ParagraphStyle(
    "TitleStyle", parent=styles["Title"], fontSize=18, textColor=navy, spaceAfter=4
)
subtitle_style = ParagraphStyle(
    "SubtitleStyle", parent=styles["Normal"], fontSize=10.5, textColor=grey, spaceAfter=2
)
section_style = ParagraphStyle(
    "SectionStyle",
    parent=styles["Heading2"],
    fontSize=12.5,
    textColor=navy,
    spaceBefore=14,
    spaceAfter=6,
)
label_style = ParagraphStyle(
    "LabelStyle", parent=styles["Normal"], fontSize=10.5, textColor=navy, spaceAfter=1
)
body_style = ParagraphStyle(
    "BodyStyle",
    parent=styles["Normal"],
    fontSize=10.5,
    leading=15,
    alignment=TA_LEFT,
    spaceAfter=6,
)
bullet_style = ParagraphStyle(
    "BulletStyle", parent=body_style, spaceAfter=2
)
code_style = ParagraphStyle(
    "CodeStyle",
    parent=styles["Code"],
    fontName="Courier",
    fontSize=9,
    leading=12,
    textColor=colors.HexColor("#1a1a1a"),
    backColor=light,
    borderColor=colors.HexColor("#c8d2de"),
    borderWidth=0.5,
    borderPadding=6,
    spaceBefore=4,
    spaceAfter=8,
)

story = []
story.append(Paragraph("Revision tecnica de la estructura entregada", title_style))
story.append(
    Paragraph("Integracion VKPI &mdash; Atento Mexico", subtitle_style)
)
story.append(
    Paragraph(
        "Tabla <b>dbo.tbl_VKPI_incentivos</b> (base dbIndicadoresAt, servidor "
        "MXDCQSIMBVP003)",
        subtitle_style,
    )
)
story.append(Paragraph("Revision del 2 de septiembre de 2026 &mdash; Equipo 4Shark", subtitle_style))
story.append(Spacer(1, 10))

story.append(
    Paragraph(
        "Revisamos la estructura de la tabla entregada el 2 de septiembre, "
        "directamente sobre la base. La entrega todavia no cumple lo acordado "
        "para habilitar la integracion. A continuacion cada punto: lo que se "
        "pidio, lo que se implemento, por que no cumple y la correccion requerida.",
        body_style,
    )
)

summary_rows = [
    ["Punto", "Estado"],
    ["1. Columna llave (clave de variable)", "No implementada"],
    ["2. Identificador de persona (carnet)", "Incorrecto (usa RFC)"],
    ["3. Indice unico compuesto (y limpieza de la base)", "Falta / requerida"],
    ["4. Fecha del periodo (varias columnas)", "Indicar cual usamos"],
]
summary_table = Table(summary_rows, colWidths=[110 * mm, 60 * mm])
summary_table.setStyle(
    TableStyle(
        [
            ("BACKGROUND", (0, 0), (-1, 0), navy),
            ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
            ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
            ("FONTSIZE", (0, 0), (-1, -1), 10),
            ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, light]),
            ("GRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#c8d2de")),
            ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
            ("TOPPADDING", (0, 0), (-1, -1), 5),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
            ("LEFTPADDING", (0, 0), (-1, -1), 8),
        ]
    )
)
story.append(Spacer(1, 4))
story.append(summary_table)


def add_block(label, text):
    story.append(Paragraph("<b>%s</b>" % label, label_style))
    story.append(Paragraph(text, body_style))


def add_section(title, blocks):
    story.append(Paragraph(title, section_style))
    for label, text in blocks:
        add_block(label, text)


def add_code(label, code):
    story.append(Paragraph("<b>%s</b>" % label, label_style))
    story.append(Preformatted(code, code_style))


add_section(
    "1. Falta la columna llave (la clave de la variable de 4Shark)",
    [
        (
            "Lo que se pidio",
            "Una columna de texto obligatoria que guarde la clave exacta con la "
            "que cada variable fue registrada en la plataforma 4Shark. Esa clave "
            "se repite de forma natural para muchas personas y periodos: todas "
            "las filas de un mismo indicador y periodo comparten la misma llave. "
            "Es el puente entre los dos sistemas.",
        ),
        (
            "Lo que encontramos",
            "En la tabla no existe ninguna columna que contenga la clave de la "
            "variable de 4Shark. La columna NK_KEY no es esa clave: es un "
            "identificador de fila generado automaticamente (un hash de DT_DATE, "
            "RFC e id_VKP; 1616 valores distintos en 1616 filas), con otro proposito "
            "(evitar registros duplicados, cosa que tampoco logra; ver punto 3), no "
            "la clave de la variable.",
        ),
        (
            "Por que no cumple",
            "Sin la columna con la clave de la variable, ninguna fila puede "
            "relacionarse con la variable registrada en 4Shark, y la integracion no "
            "puede resolver a que variable pertenece cada resultado.",
        ),
        (
            "Correccion",
            "Agregar la columna llave (texto, obligatoria) que la carga poblara con "
            "la clave de la variable de 4Shark, la misma para todas las filas de ese "
            "indicador y periodo. El valor lo entrega la plataforma al registrar la "
            "variable. NK_KEY puede permanecer si cumple otro proposito de su lado, "
            "pero no sustituye a la llave ni forma parte del indice unico.",
        ),
    ],
)

story.append(Paragraph("<b>Ejemplo de como debe verse la columna llave</b>", label_style))
story.append(
    Paragraph(
        "La llave se repite: es la misma para todas las filas de un mismo "
        "indicador, sin importar la persona ni el periodo. Una persona con varios "
        "indicadores tiene varias filas, cada una con la clave de su indicador.",
        body_style,
    )
)
example_rows = [
    ["Persona (carnet)", "llave (clave 4Shark)", "Resultado", "Periodo"],
    ["53433", "calidad", "0.92", "2026-08-01"],
    ["53433", "csat", "0.85", "2026-08-01"],
    ["64195", "calidad", "0.88", "2026-08-01"],
    ["64195", "csat", "0.79", "2026-08-01"],
]
example_table = Table(
    example_rows, colWidths=[40 * mm, 48 * mm, 30 * mm, 34 * mm]
)
example_table.setStyle(
    TableStyle(
        [
            ("BACKGROUND", (0, 0), (-1, 0), navy),
            ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
            ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
            ("FONTSIZE", (0, 0), (-1, -1), 9.5),
            ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, light]),
            ("GRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#c8d2de")),
            ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
            ("TOPPADDING", (0, 0), (-1, -1), 4),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
            ("LEFTPADDING", (0, 0), (-1, -1), 6),
        ]
    )
)
story.append(Spacer(1, 2))
story.append(example_table)
story.append(Spacer(1, 3))
story.append(
    Paragraph(
        "Ejemplo ilustrativo. Los valores de la llave ('calidad', 'csat') "
        "representan la clave con la que cada variable se registra en 4Shark; el "
        "valor exacto es el que entrega la plataforma al registrarla. Las columnas "
        "id_VKP, DT_DATE y RFC no participan en este valor.",
        ParagraphStyle("Caption", parent=body_style, fontSize=9, textColor=grey),
    )
)

add_code(
    "Codigo para agregar la columna llave (la carga la puebla con la clave de la variable)",
    "ALTER TABLE dbo.tbl_VKPI_incentivos\n"
    "ADD llave VARCHAR(100) NULL;\n"
    "-- La carga (ETL) escribe en 'llave' la clave con que cada variable se\n"
    "-- registro en 4Shark (la misma para todas las filas del indicador y periodo).\n"
    "-- Cuando este poblada en todas las filas, cambiarla a NOT NULL.",
)

add_section(
    "2. El identificador de persona debe ser el carnet, no el RFC",
    [
        (
            "Lo acordado",
            "En reuniones anteriores ya se confirmo que la persona se identifica "
            "por el carnet (Empleado_Carnet del Simplex), y asi resuelve 4Shark a "
            "cada persona. Ustedes mismos indicaron la columna correspondiente.",
        ),
        (
            "Lo que se implemento",
            "La llave primaria de la tabla utiliza RFC (identificador fiscal).",
        ),
        (
            "Por que no cumple",
            "El RFC no es el carnet acordado. Si la persona se resuelve por un "
            "identificador distinto al que usa la plataforma, los indicadores no "
            "llegan al destinatario correcto.",
        ),
        (
            "Correccion",
            "Usar el carnet ya acordado (Empleado_Carnet; en esta tabla, la columna "
            "NR_RE), no el RFC.",
        ),
    ],
)

add_code(
    "Codigo para verificar que el carnet (NR_RE) este disponible como identificador",
    "-- Debe devolver 0: el carnet tiene que estar poblado en todas las filas\n"
    "SELECT COUNT(*) AS filas_sin_carnet\n"
    "FROM dbo.tbl_VKPI_incentivos\n"
    "WHERE NR_RE IS NULL;",
)

add_section(
    "3. Falta el indice unico compuesto; por eso hay duplicados y hay que limpiar la base",
    [
        (
            "Lo que necesitamos",
            "Un indice unico compuesto sobre fecha + persona (carnet) + llave. Es la "
            "unica forma de garantizar un solo valor consolidado por persona, "
            "indicador y periodo. Es un requisito, no una recomendacion opcional.",
        ),
        (
            "Por que no existe hoy",
            "La llave primaria quedo sobre (DT_DATE, RFC, NK_KEY), que no impide "
            "ningun duplicado: NK_KEY es unica por fila (incluye id_VKP), asi que la "
            "restriccion se satisface siempre. Ademas usa RFC en lugar del carnet y "
            "NK_KEY en lugar de la clave de la variable.",
        ),
        (
            "La consecuencia: duplicados que obligan a limpiar la base",
            "Sin ese indice, la base ya tiene el mismo grano repetido con valores en "
            "conflicto (ej. RE 53433, % Ausentismo, 20260801, con valores 0 y 0.565), "
            "y para el comisionamiento el calculo queda ambiguo. Por eso, ademas de "
            "crear el indice, hay que vaciar la tabla y volver a poblarla despues de "
            "tener la estructura correcta: los datos que estan hoy no se pueden "
            "integrar.",
        ),
    ],
)

story.append(
    Paragraph(
        "<b>Codigo a ejecutar</b> (con la columna llave ya con la clave de la "
        "variable y la persona por el carnet): limpiar, crear el indice sobre la "
        "tabla vacia, y solo entonces repoblar.",
        label_style,
    )
)
index_and_clean_sql = (
    "TRUNCATE TABLE dbo.tbl_VKPI_incentivos;\n"
    "\n"
    "CREATE UNIQUE INDEX UX_tbl_VKPI_incentivos_grano\n"
    "ON dbo.tbl_VKPI_incentivos (DT_DATE, NR_RE, llave);\n"
    "\n"
    "-- Repoblar UNICAMENTE despues de lo anterior."
)
story.append(Preformatted(index_and_clean_sql, code_style))

add_section(
    "4. La fecha del periodo: indiquen cual columna usamos",
    [
        (
            "Situacion",
            "El periodo aparece en varias columnas: AnoMes (texto, '2026-08'), "
            "DT_DATA (entero, 20260801) y DT_DATE (datetime).",
        ),
        (
            "Lo que necesitamos de ustedes",
            "Que nos indiquen cual columna es la fecha del periodo que debemos usar, "
            "y que sea una columna de tipo fecha (date), no la del mes (AnoMes, "
            "texto). Usaremos siempre esa columna, tal cual esta, y registraremos en "
            "el log el valor exacto que leemos.",
        ),
        (
            "Responsabilidad",
            "Cualquier discrepancia entre las columnas, o un valor incorrecto en la "
            "columna que indiquen, queda de su lado. No reconciliamos entre columnas: "
            "leemos la que nos senalen y guardamos su valor.",
        ),
    ],
)

story.append(Paragraph("Lo que quedo correcto", section_style))
correct_items = [
    "Resultados: un unico valor final por fila.",
    "Fecha de compilacion: en el primer dia del periodo (20260801). Solo se cargo "
    "agosto; se confirmara el comportamiento de indicadores semanales y diarios "
    "cuando existan.",
]
story.append(
    ListFlowable(
        [ListItem(Paragraph(item, bullet_style), leftIndent=10) for item in correct_items],
        bulletType="bullet",
        start="square",
    )
)

story.append(Spacer(1, 12))
story.append(
    Paragraph(
        "Quedamos con total disposicion para una sesion tecnica corta y cerrar "
        "estos puntos con rapidez.",
        body_style,
    )
)

doc = SimpleDocTemplate(
    output_path,
    pagesize=A4,
    leftMargin=20 * mm,
    rightMargin=20 * mm,
    topMargin=18 * mm,
    bottomMargin=18 * mm,
    title="Revision tecnica VKPI Atento Mexico",
    author="4Shark",
)
doc.build(story)
print("PDF written to %s" % output_path)
