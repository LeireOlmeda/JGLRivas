# Juntas de Gobierno Local de Rivas Vaciamadrid: scraping asistido por IA

Skill de scraping y análisis para las **convocatorias y actas de la Junta de Gobierno
Local del Ayuntamiento de Rivas Vaciamadrid**, pensada para que un agente de IA
(OpenCode, Claude Code, Codex, Posit Assistant...) la ejecute como un procedimiento
verificable: descarga, extrae el texto (OCR si el PDF es una imagen), trocea los
puntos del orden del día, los cruza con el acta y publica tablas listas para auditar.

El scraper **no depende de la IA en cada ejecución**: todo son reglas y expresiones
regulares en R. El agente sirve para lanzar y supervisar; el resultado no depende del
modelo que lo invoque.

## Estructura

```
scraping-juntas-gobierno/        La skill
  SKILL.md                       Instrucciones para el agente (cuándo, pasos, límites)
  scripts/                       Código R del pipeline (sin IA en ejecución)
  references/                    Adaptador de la web, modelo de datos, cómo ampliar
  tests/                         Pruebas de parsers sin red (fixtures reales)
  validation/                    Diseño de validación, resultados y prueba de funcionamiento
datos/jgl-rivas/                 Snapshot de resultados de la ejecución
  indice.csv                     Estado de cada sesión y documento
  faltantes.md                   Qué falta y anomalías (regenerado en cada ejecución)
  texto/, sesiones/, analisis/   Textos extraídos y tablas
muestra-validacion/              PDFs de la muestra contrastada (solo esos originales)
```

## Arranque rápido

Requisitos: R ≥ 4.2 con `dplyr, stringr, purrr, tibble, readr, httr2, rvest, xml2,
stringi, pdftools, tesseract, tidyr`. Para el OCR hace falta el idioma español:
`tesseract::tesseract_download("spa")`.

```r
# desde la raíz del repositorio
source("scraping-juntas-gobierno/scripts/actualizar_jgl.R", encoding = "UTF-8")

actualizar_jgl(desde = 2023)            # ejecución incremental completa
actualizar_jgl(etapas = "analisis")     # recalcular tablas sin red ni OCR
estado_indice()                          # cuántos documentos hay en cada estado
```

Antes de la primera ejecución real, cambia el contacto en el User-Agent:

```r
actualizar_jgl(user_agent = "jgl-analisis-transparencia (R; contacto: tu@correo)")
```

Pruebas sin red (fixtures reales incluidos):

```sh
Rscript scraping-juntas-gobierno/tests/probar_parsers.R
```

## Datos y originales

- El repositorio versiona el **snapshot de resultados**: índice, textos extraídos,
  sesiones cruzadas, tablas de análisis y `faltantes.md`.
- Los PDF originales (162 documentos, ~1,6 GB) **no se redistribuyen** aquí: se
  descargan de la web del ayuntamiento con la propia skill. Los únicos PDF incluidos
  son los de la muestra de validación (`muestra-validacion/`), para que la revisión
  manual sea reproducible.
- Si necesitas reactivar una copia sin volver a descargar, usa el zip del release
  (incluye `texto/`, `sesiones/`, `analisis/` e `indice.csv`):

```r
restaurar_datos("https://github.com/LeireOlmeda/JGLRivas/releases/download/v1.0/datos-jgl-rivas.zip")
```

## Procedencia y estado

- Fuente: `https://www.rivasciudad.es/ayuntamiento/organizacion/junta-de-gobierno-local/sesiones-de-la-junta/`
  (HTML renderizado en servidor; no requiere JavaScript ni Playwright).
- El código se ha reconstruido en noviembre de 2026 a partir de la documentación de
  `references/` y del modelo de datos, y se ha **contrastado con los resultados de la
  ejecución original** (p. ej. el acta de 2026-09-17 vuelve a trocearse en 62 puntos y
  la convocatoria de 2026-10-28 en 46).
- Versión de los datos y resultados de validación: ver `scraping-juntas-gobierno/validation/`.

## Ética y legalidad

Uso interno para análisis de información municipal publicada. Se respeta `robots.txt`,
se mantiene un ritmo cortés (1-2,5 s entre peticiones) y no se difunden datos
personales. Los documentos íntegros no se redistribuyen; se publican el índice, los
textos derivados y los PDF de la muestra de validación. Detalle en
`scraping-juntas-gobierno/SKILL.md` (apartado «Decisiones éticas y legales»).
