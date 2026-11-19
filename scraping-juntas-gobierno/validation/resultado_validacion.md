# Resultado de la validación

Ejecución de referencia: **18–19 de noviembre de 2026**, con
`actualizar_jgl(desde = 2023, max_ocr = Inf)` (12,3 min, con red y OCR) y un
recálculo posterior de las tablas (`escribir_analisis()`, 4 min, sin red).
Todas las cifras de este documento se obtienen con
`Rscript scraping-juntas-gobierno/validation/comprobar.R`.

## 1. Cobertura por año

| Año | Sesiones | Convocatorias con texto | Actas con texto | Actas sin publicar | Actas con enlace roto |
|---|---|---|---|---|---|
| 2023 | 20 | 20 | 17 | 2 | 1 |
| 2024 | 23 | 23 | 21 | 2 | 0 |
| 2025 | 25 | 25 | 22 | 3 | 0 |
| 2026 | 19 | 19 | 15 | 4 | 0 |
| **Total** | **87** | **87** | **75** | **11** | **1** |

- Las 87 convocatorias del periodo están en texto (87/87): el listado de la web no
  tiene huecos.
- De las 75 actas, 72 se obtuvieron por OCR, 2 con OCR parcial (`mixto`) y 1 tenía
  capa de texto utilizable. El acta de 2026-03-19 es el caso típico de OCR forzado:
  su PDF tiene una capa de texto, pero con la codificación rota (fuente sin mapa
  Unicode), así que el pipeline la descarta y aplica tesseract.
- Las 11 actas que faltan están detalladas en `datos/jgl-rivas/faltantes.md`: 4 son
  de 2026 y pueden estar pendientes de publicar; el resto se revisa en cada ejecución.
- El único enlace roto es el de la sesión de 2023-04-21.

## 2. Volumen y estructura

| Tabla | Filas |
|---|---|
| `analisis/puntos.md` | 4699 |
| `analisis/contratos.md` | 1559 |
| `analisis/subvenciones.md` | 213 |
| `analisis/judicial.md` | 700 |

- Sesiones en el índice: 87. Sesiones analizadas: **86**, porque la web publica dos
  páginas para la sesión de 2025-02-20 (`862600245795` y `862600248392`, esta última
  sin acta): el análisis se queda con la que tiene documentos.
- De los 4699 puntos, 4027 vienen de la convocatoria (con o sin acta), 219 son puntos
  numerados que solo aparecen en el acta y 453 son fragmentos del acta sin numeración
  (subbloques fundidos en el OCR; se listan con `n_acta = NA` para no perder contenido).
- Estados: `mantenido` 2719, `nuevo` 626, `nuevo_dudoso` 41, `nuevo_urgencia` 5,
  `retirado` 142, `en_acta_sin_trocear` 615, `sin_acta` 481, `no_localizado` 70.
- Método de cruce: `expediente` 1627, `texto` 986, `orden` 103, `contenido` 3, sin
  emparejar 1980 (incluye las 481 filas `sin_acta` y los fragmentos no numerados).

## 3. Duplicados

- **Clave de numeración** `(sesion_id, n_conv, n_acta)`: 16 repeticiones sobre 4246
  filas. No son duplicados reales: algunas convocatorias reinician la numeración en
  cada bloque (concursos y bases, subvenciones, otros), de modo que el mismo número
  aparece con asuntos distintos. Ejemplo: en la convocatoria de 2026-09-03 el número
  1 aparece en cuatro filas con familias distintas (convenios, subvenciones,
  concursos y bases, otros).
- **Clave de contenido** `(sesion_id, n_conv, n_acta, asunto, expediente)`: **0
  duplicados**.
- **Filas idénticas en todas las columnas**: 6 filas repetidas (11 implicadas: 4
  pares y un triplete) en cinco sesiones (2024-12-05, 2025-01-09, 2025-03-06,
  2025-04-23 y 2026-07-03). Son fragmentos de puntos judiciales que comparten el
  formulario «Hechos y Fundamentos de Derecho recogidos en los Informes…», sin
  expediente extraíble; el texto aparece entre 3 y 6 veces en cada acta, así que son
  posiciones distintas y no se deduplican.
- **Sesiones duplicadas**: 1 página duplicada descartada (2025-02-20). La ejecución
  original también analizó 86 sesiones, así que no hay pérdida de cobertura.

## 4. Campos ausentes

Puntos (`analisis/puntos.md`):

| Origen | Filas | Sin expediente | Sin asunto | Sin votación |
|---|---|---|---|---|
| Convocatoria (`origen_ocr = FALSE`) | 728 | 33,4 % | 0,1 % | 96,3 % |
| Acta OCR (`origen_ocr = TRUE`) | 3971 | 32,9 % | 0,0 % | 10,5 % |

- El expediente falta sobre todo en los puntos que no son de contratación o
  urbanismo (aprobación del acta anterior, daciones de cuenta, premios…) y en los
  fragmentos de acta sin número.
- La votación solo se extrae cuando el acta la recoge expresamente; las filas que
  provienen de la convocatoria no la tienen por definición (96,3 % de ausencias).

Contratos (`analisis/contratos.md`):

| Origen | Filas | Sin importe | Sin adjudicatario | Marcadas `revisar` |
|---|---|---|---|---|
| Convocatoria | 265 | 100 % | 94,3 % | 0 % |
| Acta OCR | 1294 | 23,5 % | 52,8 % | 19,6 % |

- La convocatoria anuncia el procedimiento, pero rara vez el importe y casi nunca el
  adjudicatario: esos datos aparecen en el acta. No es un fallo de extracción.
- En las actas OCR, el 19,6 % de las filas queda marcado `revisar`; los importes y
  adjudicatarios ausentes se concentran en tablas mal reconocidas y en puntos con
  varios lotes.
- En subvenciones, `beneficiarios` puede faltar aunque el importe esté bien extraído:
  el texto nombra el proyecto y remite a los anexos. No se marca como error.

## 5. Muestra contrastada con la fuente

Los PDF de la muestra están en `muestra-validacion/` y su procedencia en
`muestra-validacion/LEEME.md`.

| # | Sesión y punto | Comprobado en la fuente | Extraído | Resultado |
|---|---|---|---|---|
| 1 | Convocatoria 2026-10-28 (`862600287714`), punto 23 | PDF con capa de texto: «Ratificación decreto … nº 3400/2026 … adjudicación, expediente contratación nº 48607/2026 … arrendamiento …» | `n_conv = 23`, `tipo = adjudicacion_contrato`, `expediente = 48607/2026`, `estado = sin_acta` (el acta aún no está publicada) | Coincide texto y expediente |
| 2 | Acta 2026-03-19 (`862600271737`), punto 29 | PDF escaneado, págs. 38-39 (verificadas visualmente): «hasta un importe máximo de 168.880,05 € […] importe total de 204.344,86 € IVA incluido», adjudicataria KYOCERA DOCUMENT SOLUTIONS | `n_acta = 29`, `importe_principal = 168.880,05`, `iva = 21`, `adjudicatarios = KYOCERA DOCUMENT SOLUTIONS S.A.`; `expediente = NA` (el número 51316/2025 aparece en el asunto, no en la columna) | Importe y adjudicataria correctos; la ejecución original guardaba 28.424 € (precio unitario mal interpretado) |
| 3 | Acta 2023-02-03 (`862600198461`), subvenciones | PDF con capa de texto: «Subvención de 115.279,53 € … BIORRESIDUOS» y «Subvención de 193.819,50 € … PUNTOS LIMPIOS» | Subvenciones con `importe_principal` 115.279,53 y 193.819,50, `importe_max` 128.088,37 y 215.355,00, estado `nuevo_urgencia`, `expediente = NA`; las filas de convocatoria 990/2023 y 3989/2023 quedan `en_acta_sin_trocear` | Importes correctos; el enlace convocatoria-acta queda incompleto (limitación conocida) |

Nota del punto 2: la capa de texto del acta está corrupta, por lo que la comprobación
se hizo sobre las páginas renderizadas y sobre el texto OCR que produce la skill; los
cuatro datos clave (expediente, importe máximo, total con IVA y adjudicataria) están
en `datos/jgl-rivas/texto/2026-03-19_acta_862600271737.md`.

## 6. Comparación con la ejecución original (junio de 2026)

La ejecución original también analizó 86 sesiones. Las diferencias son de
representación y de reglas, no de cobertura:

| Concepto | Original | Reconstruida |
|---|---|---|
| Puntos | 4535 | 4699 |
| — de la convocatoria | 4027 | 4027 |
| — solo del acta, numerados | 320 | 219 |
| — fragmentos del acta sin numerar | 188 | 453 |
| Contratos | 1502 | 1559 |
| Subvenciones | 193 | 213 |
| Judicial | 680 | 700 |

Estados:

| Estado | Original | Reconstruida |
|---|---|---|
| `mantenido` | 2938 | 2719 |
| `en_acta_sin_trocear` | 348 | 615 |
| `nuevo` | 468 | 626 |
| `nuevo_dudoso` | 36 | 41 |
| `nuevo_urgencia` | 4 | 5 |
| `retirado` | 181 | 142 |
| `no_localizado` | 79 | 70 |
| `sin_acta` | 481 | 481 |

Método de cruce: `expediente` 1619 → 1627, `texto` 894 → 986, `orden` 330 → 103,
`contenido` 95 → 3.

Lectura de las diferencias:

- **Filas de convocatoria idénticas (4027)**: la cobertura y el troceo de las
  convocatorias no cambian.
- **+265 fragmentos sin numerar / −101 puntos del acta numerados**: el troceo de las
  actas reparte el mismo contenido de otra forma (subbloques fundidos por el OCR).
  Es la causa principal del +164 total; no se pierde contenido, cambia su forma.
- **Enlace convocatoria-acta menos completo en actas antiguas**: `orden` baja de 330 a
  103 y `contenido` de 95 a 3, mientras `en_acta_sin_trocear` sube de 348 a 615. En
  las actas de 2023-2024 con numeración perdida, la reconstrucción solo alinea los
  subbloques dentro de puntos numerados; la ejecución original alineaba además por
  posición. **Es la limitación conocida más importante**: el punto sigue existiendo
  con su asunto de convocatoria, pero el enlace con el acta queda sin resolver.
- **Tipos y familias**: `contratacion` 1337 → 1391, `judicial` 680 → 700,
  `concursos_bases` 199 → 242, `subvenciones` 193 → 213. Las reglas se alinearon con
  la ejecución original (`judicial_asuntos`, `bases|concurso`, descarte de bajas de
  IVA del 32 %) y se corrigieron casos que la original clasificaba mal.
- **Importes**: el contraste manual corrigió el caso de 2026-03-19 (28.424 € →
  168.880,05 €); la extracción actual conserva el importe principal, el máximo y el
  IVA, y marca `revisar` cuando no hay confianza.

## 7. Reproducción

```sh
Rscript scraping-juntas-gobierno/tests/probar_parsers.R      # parsers, sin red
Rscript scraping-juntas-gobierno/validation/comprobar.R      # cifras de este documento
```

Y, para rehacer los datos desde cero:

```r
source("scraping-juntas-gobierno/scripts/actualizar_jgl.R", encoding = "UTF-8")
actualizar_jgl(desde = 2023, max_ocr = Inf,
               user_agent = "jgl-analisis-transparencia (R; contacto: tu@correo)")
```
