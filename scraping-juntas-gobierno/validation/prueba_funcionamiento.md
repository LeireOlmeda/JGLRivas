# Prueba de funcionamiento

Esta prueba comprueba tres cosas: que el código arranca en una máquina limpia, que
reproduce los resultados documentados y que la revisión manual detecta errores reales.

## 1. Entorno

| Elemento | Versión |
|---|---|
| Sistema | Windows 11 |
| R | 4.5.0 |
| tesseract (vía `tesseract`) | 5.3.2, idiomas `spa`, `eng`, `osd` |
| Paquetes | `dplyr`, `stringr`, `purrr`, `tibble`, `readr`, `httr2`, `rvest`, `xml2`, `stringi`, `pdftools`, `tesseract`, `tidyr` |
| Repositorio | `datos/jgl-rivas/` con el snapshot de textos (los PDF de 1,6 GB no se versionan) |

Antes de la ejecución se pasa un `user_agent` real con un contacto, como pide el
apartado ético de `SKILL.md`.

## 2. Qué se ejecutó

| Fecha | Comando | Duración | Red |
|---|---|---|---|
| 18/11/2026 23:05 | `actualizar_jgl(desde = 2023, max_ocr = Inf, user_agent = ...)` | 12,3 min | Sí (listado, descarga, texto y análisis) |
| 19/11/2026 10:08 | `escribir_analisis()` (recálculo de tablas) | 4 min | No |
| 19/11/2026 10:30 | `actualizar_jgl(desde = 2023, etapas = "listado")` | 1-2 min | Sí (solo listado) |
| 19/11/2026 10:40 | `Rscript scraping-juntas-gobierno/tests/probar_parsers.R` | < 2 min | No |
| 19/11/2026 10:45 | `Rscript scraping-juntas-gobierno/validation/comprobar.R` | segundos | No |

La pasada completa no volvió a descargar ni a hacer OCR de nada: ningún PDF ni texto
cambió de fecha de modificación, y los estados del índice no cambiaron (75 actas `ok`,
11 `falta`, 1 `enlace_roto`). El tiempo se fue en recorrer las páginas de sesión, el
parseo y el cruce. Es el comportamiento incremental que promete la skill.

## 3. Pruebas de parser

```
1) Convocatoria 2026-10-28 (esPublico, capa de texto)
  OK: 46 puntos troceados (son 46)
  OK: numeración completa 1..46
  OK: ≥35 expedientes (son 45)
  OK: cabecera con fecha y hora
  OK: clasificación no degrada todo a 'otros'
2) Acta 2026-09-17 (OCR tesseract)
  OK: troceo por numeración (numeracion, 62 puntos)
  OK: ≥40 puntos (son 62)
  OK: <60% de puntos sin expediente (los subbloques fundidos explican ~50%; son 50%)
3) Cruce convocatoria/acta sobre las dos fuentes
  OK: el cruce devuelve filas
  OK: los pares emparejados quedan mantenidos
  OK: fuente_texto siempre informada
4) Extracción de campos
  OK: extraer_contratos devuelve una lista de campos
TODAS LAS PRUEBAS PASARON
```

Los dos casos de calibración son los mismos que se usaron al reconstruir el código:
la convocatoria de 2026-10-28 debe dar 46 puntos y el acta de 2026-09-17, 62.

## 4. Pasada completa con red

Salida real de la ejecución (18/11/2026):

```
Etapa 1 (listado): recorriendo el listado de sesiones ...
  Encontradas 99 sesiones desde 2023-01-01 (2022: 12, 2023: 20, 2024: 23, 2025: 25, 2026: 19).
Etapa 2 (descarga): visitando sesiones y descargando documentos ...
  Descarga terminada.
Etapa 3 (texto): extrayendo texto de los PDF descargados ...
Etapa 4 (análisis): parse, cruce y tablas ...
Análisis: 86 sesiones (1 descartadas duplicadas), 4699 puntos, 1559 contratos, 213 subvenciones, 700 juzgados

Duración: 12.3 min
```

En esa pasada el listado incluía 12 sesiones de 2022; el índice se limita al año de
inicio, así que quedó con 87 sesiones. La comprobación posterior del listado, ya con
el filtro corregido (ver §7), devuelve directamente las 87:

```
Etapa 1 (listado): recorriendo el listado de sesiones ...
  Encontradas 87 sesiones desde 2023-01-01 (2023: 20, 2024: 23, 2025: 25, 2026: 19).

== ESTADO DEL ÍNDICE ==
    documento      estado  n
        acta          ok 75
        acta       falta 11
        acta enlace_roto  1
convocatoria          ok 87
```

## 5. Comprobación automática

`Rscript scraping-juntas-gobierno/validation/comprobar.R` imprime las cifras que se
citan en `resultado_validacion.md`. Resumen de la última ejecución:

- Cobertura: 87 sesiones, 87 convocatorias con texto, 75 actas con texto.
- Volumen: 4699 puntos, 1559 contratos, 213 subvenciones, 700 judiciales.
- Duplicados por clave de contenido: 0; filas idénticas: 6 repetidas (11 implicadas)
  en fragmentos judiciales sin expediente de cinco sesiones, que corresponden a
  posiciones distintas del acta.
- Campos ausentes en puntos: expediente 33 % (convocatoria) y 33 % (OCR); asunto
  0,1 % y 0,0 %; votación 96,3 % y 10,5 %.
- Contratos: sin importe 100 % en convocatoria y 23,5 % en OCR; sin adjudicatario
  94,3 % y 52,8 %; marcados `revisar` 0 % y 19,6 %.
- Fechas: todas en ISO, de 2023-01-19 a 2026-11-12.

## 6. Contraste manual con la fuente

Se eligieron tres puntos de dos actas y una convocatoria, se abrieron los PDF de
`muestra-validacion/` y se compararon con las filas de las tablas. El detalle está en
`resultado_validacion.md` (§5). Resultado:

- **2026-10-28, punto 23**: texto y expediente 48607/2026 correctos.
- **2026-03-19, punto 29**: importe principal 168.880,05 €, total con IVA 204.344,86 €
  y adjudicataria KYOCERA; la fila que guardaba la ejecución original (28.424 €) era
  un precio unitario mal interpretado.
- **2023-02-03, subvenciones**: importes 115.279,53 € y 193.819,50 € correctos; el
  enlace con los puntos de la convocatoria queda incompleto (acta de plantilla antigua).

Las páginas 38-39 del acta de 2026-03-19 se renderizaron y se leyeron visualmente,
porque ese PDF tiene la capa de texto corrupta; los mismos cuatro datos están en el
texto OCR que guarda la skill.

## 7. Incidencias encontradas durante la prueba

Estas incidencias son parte del resultado: la validación sirve para encontrarlas.

1. **Importe mal extraído en la ejecución original** (2026-03-19): 28.424 € en lugar
   de 168.880,05 €. Se corrigió la extracción de importes y se documentó en
   `validacion.md`; la fila actual guarda el importe principal, el máximo y el IVA.
2. **El listado podía dejar un año fuera sin avisar**: durante la comprobación, una
   página que fallaba hacía que el índice se quedara sin 2023 y la ejecución seguía
   como si nada. Ahora la skill reintenta ese año con `?fwp_year=AAAA` y, si sigue
   faltando, **se detiene** con un mensaje explícito en vez de guardar un índice
   incompleto.
3. **Filtro del año de inicio comparaba mal**: se comparaba el año (`"2023"`) con la
   fecha completa (`"2023-01-01"`), lo que descartaba todas las sesiones de 2023. Se
   cambió por una comparación de fechas y el listado devuelve las 87 sesiones.
4. **Página duplicada de 2025-02-20**: la web publica dos páginas para la misma
   sesión; el análisis usa la que tiene documentos y la otra no cuenta como acta
   pendiente en `faltantes.md`.

## 8. Limitaciones que quedan

- En actas de 2023-2024 con la numeración perdida por el OCR, el enlace
  convocatoria-acta es menos completo que en la ejecución original (615 filas
  `en_acta_sin_trocear` frente a 348; `orden` 103 frente a 330). El punto no se
  pierde, pero su estado en el acta queda sin resolver.
- Los importes y adjudicatarios de actas OCR siguen necesitando revisión: el 19,6 %
  de las filas queda marcado `revisar`.
- Las actas recientes pueden tardar semanas en publicarse; `faltantes.md` las marca
  como «reciente» durante 45 días y luego como «revisar».
