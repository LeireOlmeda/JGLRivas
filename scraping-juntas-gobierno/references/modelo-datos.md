# Modelo de datos

Principio: lo que cuesta caro (descarga, OCR) se hace una vez y se guarda; lo que es barato
(troceo, cruce, clasificación, extracción de campos) se recalcula desde el texto guardado cada vez.

## `indice.csv` (una fila por sesión)

| Columna | Significado |
|---|---|
| `sesion_id` | Número final de la URL de la sesión (clave stable) |
| `fecha`, `titulo`, `tipo` | Fecha ISO, título de la página, `ordinaria` o `extraordinaria` |
| `url`, `modificado_web`, `visitada` | Página de la sesión, fecha de modificación según la web, última visita |
| `asistentes` | Nombres enlazados en la página de la sesión, separados por `; ` |
| `url_convocatoria`, `url_acta`, `otros_docs` | Enlaces leídos de la página (no construidos) |
| `pdf_*`, `txt_*` | Rutas relativas a `base_dir` del PDF y del texto extraído |
| `metodo_*` | `texto` (capa de texto), `ocr` o `mixto` |
| `estado_*` | `falta`, `pendiente`, `descargado`, `ocr_pendiente`, `ok`, `formato_no_pdf`, `enlace_roto` (HTTP 404), `error` |
| `notas` | Errores y avisos acumulados, separados por ` \| ` |

## `sesiones/AAAA-MM-DD_<id>.md`

Frontmatter YAML (sesion_id, fecha, tipo_sesion, expediente_jgl, estados, nº de puntos, nuevos,
retirados) y una tabla con los puntos ya cruzados.

## `analisis/puntos.md` (todos los puntos de todas las juntas)

`sesion_id, fecha, tipo_sesion, n_conv, n_acta, estado, cruce_metodo, cruce_fiable, cambio_orden,
expediente, familia, tipo, asunto, votacion, fuente_texto, origen_ocr`

- `estado`: `mantenido`, `retirado`, `nuevo`, `nuevo_urgencia`, `sin_acta`, `sin_convocatoria` y
  `en_acta_sin_trocear` (el expediente aparece en el texto del acta pero el troceo no lo aisló como punto;
  se usa un fragmento del acta alrededor del expediente), `no_localizado` y `nuevo_dudoso` (como
  `retirado` y `nuevo`, pero con `cruce_fiable = FALSE`: el acta se troceó mal o se alineó por contenido,
  y no se puede afirmar que el punto se retiró ni que es nuevo).
- `cruce_metodo`: cómo se emparejó el punto con el acta: `expediente`, `texto` (similitud), `orden`
  (el acta perdió la banda del punto y su cuerpo estaba pegado al anterior: se separa por los bloques
  "Hechos y fundamentos de derecho" y se empareja por posición entre dos puntos ya emparejados) o
  `contenido` (alineación en actas de plantilla antigua).
- `cruce_fiable`: `FALSE` si el acta tiene muy pocos puntos frente a la convocatoria o se alineó por
  contenido; `NA` si no hay acta.
- `n_conv` y `n_acta`: posición en cada documento. `cambio_orden` es `TRUE` si difiere.
- `expediente`: clave para seguir un asunto entre sesiones (`NNNNN/AAAA`, a veces con sufijo `-CMAY`).
- `familia`: `contratacion`, `obras`, `subvenciones`, `judicial`, `convenios`, `urbanismo`,
  `concursos_bases`, `institucional`, `otros`. `tipo` es el detalle (ver `tipos-de-punto.md`).
- `origen_ocr`: el texto del que sale el punto vino de OCR.

## `analisis/contratos.md`

`sesion_id, fecha, n_acta, estado, expediente, tipo, tipo_objeto (obra/servicio/suministro/mixto),
procedimiento, lotes, objeto, importe_principal, importe_max, importes, iva, adjudicatarios,
prorroga, prorroga_n, prorroga_duracion, fuente_texto, origen_ocr, revisar`

- Las convocatorias casi no traen importes ni empresas: esos campos salen sobre todo de las actas.
- `importe_principal` es el primer importe precedido de "importe", "precio", "total",
  "adjudicación"...; `importes` lista todos los detectados; `importe_max` el mayor.
- `revisar = TRUE`: viene de OCR y falta importe o adjudicatario en una adjudicación.

## `analisis/subvenciones.md` y `analisis/judicial.md`

Subvenciones: importes y `beneficiarios` (asociaciones, clubes, fundaciones...).
Judicial: `organo_judicial`, `procedimiento_judicial`, `n_procedimiento`, `sentencia_n`, `sentencia_fecha`, `recurrente`, `acto_recurrido`, `sentido`, `votacion` y `resumen`.

## `faltantes.md`

Se regenera en cada ejecución: resumen, sesiones sin convocatoria o sin acta (las de menos de
45 días se marcan como "reciente"), documentos con error u OCR pendiente, anomalías de troceo
y huecos de más de 21 días entre sesiones ordinarias.

## Leer las tablas desde R

```r
leer_tabla_md("datos/jgl-rivas/analisis/contratos.md")      # una tabla
leer_tablas_md("datos/jgl-rivas/sesiones")                   # todas las sesiones, con columna `archivo`
```