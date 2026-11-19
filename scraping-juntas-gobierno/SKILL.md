---
name: scraping-juntas-gobierno
description: Descarga y analiza convocatorias y actas de Juntas de Gobierno Local (y, ampliando, plenos y otros órganos) de ayuntamientos españoles, empezando por Rivas Vaciamadrid. Usar cuando se pida actualizar sesiones, extraer los puntos del orden del día, cruzar convocatoria y acta, sacar adjudicaciones, importes, empresas adjudicatarias, prórrogas, subvenciones o sentencias, hacer OCR de actas escaneadas, o informar de qué documentación falta.
---

# Juntas de Gobierno Local: scraping y análisis en R

Esta skill descarga convocatorias y actas, extrae su texto (con OCR si el PDF es una imagen),
trocea los puntos del orden del día, cruza lo previsto con lo tratado y deja tablas en
markdown listas para analizar. Todo funciona sin APIs de pago: reglas y expresiones regulares.
El código no usa IA en tiempo de ejecución: la IA solo interpreta resultados y decide ajustes.

Requisitos: R >= 4.2 y los paquetes `dplyr, stringr, purrr, tibble, readr, httr2, rvest, xml2,
stringi, pdftools, tesseract` (y `tidyr` para `consultas.R`). Para el OCR hace falta el idioma
español de tesseract: `tesseract::tesseract_download("spa")`.

## Qué pasos sigue

1. **Listado** (`adaptador_rivas_jgl.R`): recorre el listado paginado de sesiones
   (`?fwp_paged=N`, filtro `?fwp_year=AAAA`) hasta `desde` y actualiza `indice.csv`
   (sesiones nuevas y cambios de título, tipo o URL).
2. **Descarga** (`actualizar_jgl.R`): visita la página de cada sesión que aún no se ha
   leído (o que tiene documentos en `falta`), lee los enlaces de los documentos **del HTML**
   y los clasifica en convocatoria / acta / otros; descarga lo que está en `pendiente`.
   El estado de cada documento queda en `indice.csv` (`falta`, `pendiente`, `descargado`,
   `ok`, `ocr_pendiente`, `enlace_roto`, `formato_no_pdf`, `error`).
3. **Texto** (`descargar_y_texto.R`): extrae el texto de los PDF sin OCR; si una página no
   tiene capa de texto, el documento queda `ocr_pendiente` y el OCR se hace con presupuesto
   (`max_ocr`), empezando por las actas más recientes. El resultado va a `texto/*.md`.
4. **Análisis** (`analisis.R`): trocea los puntos, cruza convocatoria y acta, clasifica por
   familia y tipo, extrae campos y escribe `sesiones/*.md`, `analisis/*.md` y `faltantes.md`.
   Esta etapa no usa red ni OCR: se puede repetir tantas veces como haga falta.

## Cuándo usar cada cosa

| El usuario pide... | Haz esto |
|---|---|
| Actualizar / descargar juntas | `actualizar_jgl()` (ver abajo) |
| Probar que todo funciona | `Rscript tests/probar_parsers.R` (sin red, con fixtures reales) |
| Ver qué falta | leer `datos/jgl-rivas/faltantes.md` |
| Analizar adjudicaciones, importes, empresas, prórrogas | `scripts/consultas.R` y `datos/jgl-rivas/analisis/contratos.md` |
| Qué se añadió o se quitó respecto a la convocatoria | `cambios_sobre_lo_previsto()` |
| Ver cómo están trocados los puntos de una sesión | `muestra_puntos("AAAA-MM-DD", n = 10:17)` |
| Seguir un contrato en el tiempo | `historial_expediente("NNNNN/AAAA")` |
| Un tipo de punto nuevo o un campo nuevo | `references/ampliar.md` y `references/tipos-de-punto.md` |
| Otro ayuntamiento u órgano (plenos) | `references/ampliar.md` (nuevo adaptador) |

## Uso básico

Los scripts se localizan solos: `actualizar_jgl.R` busca la carpeta `scripts/` de la skill
en las rutas habituales y, si no la encuentra, se le indica con una opción. No hay rutas
absolutas en el código.

```r
# desde la raíz del proyecto (la que contiene datos/ y la carpeta de la skill)
source("scraping-juntas-gobierno/scripts/actualizar_jgl.R", encoding = "UTF-8")  # carga todo, consultas incluidas

# o, si la skill está instalada en otra ruta:
options(jgl.scripts_dir = "<ruta>/scraping-juntas-gobierno/scripts")
source(file.path(getOption("jgl.scripts_dir"), "actualizar_jgl.R"), encoding = "UTF-8")

actualizar_jgl(desde = 2023)              # incremental: solo hace lo que falta
actualizar_jgl(desde = 2020)              # ampliar hacia atrás; lo ya hecho no se repite
actualizar_jgl(etapas = "analisis")       # recalcular tablas sin red ni OCR (tras cambiar reglas)
actualizar_jgl(max_ocr = 5)               # limitar el OCR por ejecución (es lento)
actualizar_jgl(max_ocr = Inf)             # hacer todo el OCR pendiente de una vez
estado_indice()                           # cuántos documentos hay en cada estado
rehacer_texto("862600256741", "convocatoria")   # descartar el texto de UN documento para rehacerlo (con OCR si procede)
actualizar_jgl(revisar_todas = TRUE)      # releer todas las páginas de sesión (tras corregir el adaptador)
actualizar_jgl(modo_listado = "anios")    # listado por año (?fwp_year) en lugar de por páginas (?fwp_paged)
```

Antes de la primera ejecución real, pasa un `user_agent` con un contacto de correo real
(`actualizar_jgl(user_agent = "jgl-analisis (R; contacto: tu@correo)")`). El valor por
defecto de `jgl_cfg()` es un marcador: **no lo dejes así en una ejecución contra la web**.

Si los datos no están en local (clon nuevo), el snapshot del release los restaura sin redescargar:

```r
restaurar_datos("https://github.com/LeireOlmeda/JGLRivas/releases/download/v1.0/datos-jgl-rivas.zip")
```

Los PDF originales no viajan en el repositorio; la skill los vuelve a descargar de la web.

## Condiciones de detención

Para antes de seguir y avisa al usuario (no inventes ni rellenes datos) cuando:

- El listado devuelve **0 sesiones** o muchas menos de las esperadas para el rango pedido:
  la web cambió de estructura. Ejecuta `diagnostico_listado()` y detente; no reintentes a ciegas.
  La skill ya comprueba la cobertura año a año y **para** si falta un año completo, en vez de
  guardar un índice incompleto.
- Un documento pasa a `enlace_roto` o `error` de forma repetida: no insistas más de una vez por
  ejecución ni cambies la URL a mano; revisa `notas` en `indice.csv` y `faltantes.md`.
- `robots.txt` o la web devuelven un bloqueo (403/429) o piden detener las peticiones: para.
- El OCR no está disponible (idioma `spa` ausente, tesseract falla): deja los documentos en
  `ocr_pendiente`, informa y no marques las tablas como definitivas.
- `cruce_fiable` es `FALSE` en una sesión: puedes publicar los datos, pero **no afirmes** que un
  punto se retiró o que es nuevo.
- La validación de una muestra no cuadra con el PDF (importes, empresas, fechas): para,
  anota la discrepancia en `validation/` y no des los datos por buenos.

## Reglas que hay que respetar siempre

1. **No repetir trabajo.** Nunca volver a descargar ni a hacer OCR de un documento cuyo estado en
   `indice.csv` sea `ok`. `forzar` solo si el usuario lo pide expresamente.
2. **Las URLs de los PDF se leen de la página de cada sesión; nunca se construyen.** Los nombres
   de fichero no siguen un patrón estable.
3. **Ser educado con el servidor**: pausas de 1 a 2,5 s, respetar `robots.txt`, un User-Agent con
   contacto. No paralelizar las peticiones.
4. **No tocar los originales** (`pdf/`, `texto/`): lo que se corrige son reglas y parsers, y las
   tablas se regeneran con `etapas = "analisis"`.
5. **Todo campo extraído es una propuesta.** Con OCR las cuantías y empresas pueden fallar: la
   columna `revisar` marca lo dudoso y `fuente_texto` indica si viene de convocatoria o acta.
   Al informar de resultados, decir cuántos puntos están marcados para revisión.
6. **Informar siempre de lo que falta** (`faltantes.md`): actas no publicadas, documentos con
   error, OCR pendiente, anomalías de troceo, huecos entre sesiones.
7. **Cruce convocatoria/acta**: `retirado` puede ser un punto realmente retirado, o un fallo del
   OCR o del troceo. No afirmar que se retiró sin revisar el texto del acta. El cruce ya intenta
   localizar el expediente en el texto del acta y, si lo encuentra, marca `en_acta_sin_trocear`
   (con el fragmento del acta para extraer datos). Si `cruce_fiable` es `FALSE`, el acta se troceó mal
   o se alineó por contenido (plantilla antigua de 2023 a mayo de 2024): `no_localizado` y
   `nuevo_dudoso` no permiten decir que un punto se retiró o es nuevo. Con `retirado` quedan los que
   de verdad no aparecen en un acta bien troceada. Antes de dar por retirado un punto, `muestra_expediente("NNNNN/AAAA")`.

## Decisiones éticas y legales

- **Términos de uso**: análisis de información municipal ya publicada por el ayuntamiento. El
  repositorio publica el **índice, los textos extraídos y las tablas derivadas** (documentos de
  trabajo) y **no redistribuye los PDF originales**: los únicos PDF incluidos son los de la
  muestra de validación, citados con su URL de origen. Si se quisiera publicar la colección
  completa de originales, haría falta permiso expreso del ayuntamiento.
- **robots.txt**: se respeta el archivo `robots.txt` del sitio (`/wp-admin/` está bloqueado; los
  caminos usados están permitidos). Si un día la web cambia sus reglas, la skill detiene la
  ejecución y reporta el incumplimiento.
- **Privacidad**: los PDFs ya incorporan filtros previos por parte de la Secretaría del
  Ayuntamiento; no se capturan datos personales no publicados. Los nombres de asistentes se
  guardan tal como aparecen en la web, sin enmascaramiento adicional, y no se usan para perfilar
  personas.
- **Credenciales**: `user_agent` debe incluir un contacto real (email); no se guardan cookies ni
  contraseñas. El contacto se usa únicamente para identificar la ejecución ante el ayuntamiento.
- **Datos sensibles**: los campos extraídos por OCR se marcan con `revisar` y `fuente_texto`. No
  se publican los valores sin marcar `revisar` como definitivos.
- **Trazabilidad**: cada fila conserva `sesion_id`, `fuente_texto` y `origen_ocr`; cada documento
  conserva su `url` y su ruta local en `indice.csv`, de modo que cualquier cifra se puede
  reconstruir desde el PDF de origen.

## Flujo cuando algo falla

- **El listado devuelve pocas sesiones**: `diagnostico_listado()` compara páginas y años. El listado
  pagina con `?fwp_paged=N` y filtra con `?fwp_year=AAAA`; `actualizar_jgl(modo_listado = "anios")`
  fuerza el recorrido por años. Los números de sesiones por año salen en el mensaje de la etapa 1.
- **Faltan documentos que sí están en la web**: `diagnostico_sesion(url)` muestra el bloque de documentos
  (`div.m4p-event-inscripcion`) y cómo se clasificó cada enlace. Después de corregir el adaptador,
  ejecutar una vez `actualizar_jgl(revisar_todas = TRUE)` para volver a leer las páginas ya conocidas.
- **El acta se trocea mal** (pocos puntos frente a la convocatoria, 0 puntos, `troceo_acta = expediente`
  o `en_acta_sin_trocear` en `faltantes.md`): ejecutar `muestra_documento("<fecha o sesion_id>", "acta")` (o `"convocatoria"`) para ver
  el texto extraído y `muestra_expediente("NNNNN/AAAA")` para ver un punto concreto. Ajustar `rx_punto_acta`
  y `bloque_acta` en `scripts/puntos.R` y recalcular con `actualizar_jgl(etapas = "analisis")`.
  El troceo ya tolera huecos y números mal leídos (cadena creciente más larga); si aun así falla,
  mirar cómo empiezan realmente los puntos en el texto OCR.
- **OCR muy lento o fallido**: bajar `dpi` (p. ej. 200) o `max_ocr`; comprobar el idioma con
  `tesseract::tesseract_info()$available`.
- **Error en un documento**: queda `error` en `indice.csv` con el motivo en `notas`; se reintenta en
  la siguiente ejecución. No borrar el índice.
- **Un cambio de reglas no debe romper lo anterior**: antes de dar por buena una modificación,
  `Rscript tests/probar_parsers.R` y `actualizar_jgl(etapas = "analisis")`.

## Dónde está cada cosa

- `scripts/`: `utils.R` (configuración, HTTP, índice, markdown), `adaptador_rivas_jgl.R` (estructura
  de la web), `descargar_y_texto.R` (descarga y PDF→texto/OCR), `puntos.R` (troceo), `cruce.R`
  (convocatoria↔acta), `extraer.R` (tipos y campos), `analisis.R` (tablas), `consultas.R` y el
  orquestador `actualizar_jgl.R`.
- `datos/jgl-rivas/indice.csv`: estado de cada sesión y documento (único fichero que no es .md).
- `datos/jgl-rivas/sesiones/AAAA-MM-DD_<id>.md`: una sesión con sus puntos cruzados.
- `datos/jgl-rivas/analisis/*.md`: `puntos`, `contratos`, `subvenciones`, `judicial` (leer con `leer_tabla_md()`).
- `datos/jgl-rivas/texto/*.md`: texto extraído de cada PDF, con marcas `<!-- pagina N -->`.
- `datos/jgl-rivas/pdf/AAAA/`: originales (excluidos de git).
- `references/`: `modelo-datos.md`, `adaptador-rivas-jgl.md`, `tipos-de-punto.md`, `ampliar.md`, `registro_exploracion_rivas.md`.
- `tests/`: `probar_parsers.R` y fixtures reales de convocatoria y acta; se ejecutan sin red.
- `validation/`: `validacion.md` (diseño), `prueba_funcionamiento.md` (ejecución real) y
  `resultado_validacion.md` (cifras y contrastes).
- `muestra-validacion/` (en la raíz del repositorio): los PDF de la muestra contrastada.
