# Validación de la skill scraping-juntas-gobierno

Este documento describe los controles de calidad que se ejecutan tras cada actualización y los que se usan en la muestra contrastada con la fuente. Todos los cálculos leen de los archivos `.md` y `indice.csv` ya guardados; no requieren red ni OCR.

## 1. Cobertura

Comparar el número de sesiones en el índice con las sesiones encontradas en el listado de la web.

- Total de sesiones en `indice.csv`.
- Sesiones con convocatoria en texto (`estado_convocatoria == "ok"`).
- Sesiones con acta en texto (`estado_acta == "ok"`).
- Sesiones sin convocatoria y sin acta (registradas en `faltantes.md`).
- Desglose por año: sesiones con convocatoria / acta por cada año desde `desde`.

Resultado esperado: cobertura estable o creciente entre ejecuciones. Los huecos de más de 21 días entre sesiones ordinarias aparecen en `faltantes.md` como "Huecos de más de 21 días".

## 2. Duplicados

Cada punto de `analisis/puntos.md` debe tener una clave única compuesta por `sesion_id` + `n_conv` + `n_acta`. Los subbloques sin `n_acta` se identifican con `expediente`.

- Duplicados en `(sesion_id, n_conv, n_acta)`: pueden aparecer repeticiones cuando la convocatoria reinicia la numeración en cada bloque (concursos y bases, subvenciones, otros). Por eso el control decisivo es la **clave de contenido**: `(sesion_id, n_conv, n_acta, asunto, expediente)`, que debe dar 0.
- Filas idénticas en todas las columnas: se revisan una a una. En la ejecución actual son fragmentos de acta sin numeración ni expediente cuyo texto es un formulario repetido (puntos judiciales); corresponden a posiciones distintas del acta y no se deduplican.
- Duplicados en `expediente` dentro de una misma sesión: contados, no duplicados forzados.
- Sesiones duplicadas en el índice (misma `fecha` y `tipo`): el análisis usa solo la que tiene más documentos; el resto se ignora y se reporta en `faltantes.md`.

## 3. Campos ausentes

Contar `NA` / vacíos en las columnas clave de `analisis/puntos.md`:

| Columna | ¿Permite NA? | Observación |
|---|---|---|
| `sesion_id` | No | Identificador estable de la sesión |
| `fecha` | No | Fecha ISO de la sesión |
| `expediente` | Sí | El punto 1 de la convocatoria (acta anterior) no tiene expediente |
| `familia` | No | Siempre se asigna |
| `tipo` | No | Siempre se asigna |
| `asunto` | No | Texto del punto |
| `fuente_texto` | No | `acta` o `convocatoria` |
| `votacion` | Sí | Solo si el acta la recoge |

En `analisis/contratos.md` y `analisis/subvenciones.md` sí se revisan los campos económicos:

| Columna | ¿Permite NA? | Observación |
|---|---|---|
| `importe_principal` | Sí | Muy común en OCR; se marca `revisar` |
| `adjudicatarios` | Sí | Muy común en OCR; se marca `revisar` |
| `beneficiarios` | Sí | En subvenciones; solo si el texto los nombra |

Se debe reportar el porcentaje de campos ausentes desglosado por método de extracción (`origen_ocr == TRUE` vs `FALSE`). Los campos ausentes con `origen_ocr == TRUE` son aceptables si están marcados `revisar`.

## 4. Muestra contrastada con la fuente

Seleccionar al menos 3 puntos de al menos 2 sesiones distintas (una reciente y una antigua) y comparar manualmente:

| # | Sesión | Tipo de punto | Expediente | Fuente (PDF/Web) | Coincidencia |
|---|---|---|---|---|---|
| 1 | 2026-10-28 | Adjudicación | 48607/2026 | Convocatoria 28-10-2026 | Sí |
| 2 | 2026-03-19 | Adjudicación (rectificación) | 51316/2025 | Acta 19-03-2026, pág. 39 | Texto sí; importe corregido (ver nota) |
| 3 | 2023-02-03 | Subvención | — | Acta 03-02-2023 | Revisar OCR |

Nota del punto 2: la página 39 del acta dice «hasta un importe máximo de 168.880,05 € […] lo que hace un
importe total de 204.344,86 € IVA incluido». La tabla de la ejecución original guardaba 28.424 € (un
precio unitario por página impresa, 0,028424 €, mal interpretado). El contraste manual con el PDF es
justamente lo que detecta este tipo de error: el dato automático es una **propuesta**, no un hecho.

Para cada punto:

1. Abrir el PDF original o la página de sesión (enlace en `indice.csv`).
2. Leer el texto del punto en la fuente.
3. Leer el texto extraído en `texto/<fecha>_<tipo>_<sesion_id>.md` o en `sesiones/<fecha>_<sesion_id>.md`.
4. Comprobar que el `asunto`, el `expediente` y el importe (si hay) coinciden. Cualquier diferencia se anota en `faltantes.md` o en `notas` del índice.

## 5. Script de comprobación automática

Desde R, con `utils.R` cargado:

```r
cfg <- jgl_cfg()
ind <- leer_indice(cfg)

# Cobertura por año
ind |>
  mutate(anio = format(as.Date(fecha), "%Y")) |>
  group_by(anio) |>
  summarise(
    n = n(),
    conv_ok = sum(estado_convocatoria == "ok"),
    acta_ok = sum(estado_acta == "ok")
  )

# Duplicados en puntos (clave de numeración; se excluyen las filas sin n_conv y sin n_acta,
# que son fragmentos de acta agrupados por expediente)
pts <- cargar_puntos()
clave <- pts |> filter(!is.na(n_conv) | !is.na(n_acta)) |> select(sesion_id, n_conv, n_acta)
sum(duplicated(clave))

# Clave de contenido: es la que debe dar 0
clave_contenido <- pts |> filter(!is.na(n_conv) | !is.na(n_acta)) |>
  select(sesion_id, n_conv, n_acta, asunto, expediente)
sum(duplicated(clave_contenido))

# Campos ausentes por origen OCR
pts |>
  group_by(origen_ocr) |>
  summarise(
    n = n(),
    sin_expediente = mean(is.na(expediente)),
    sin_asunto = mean(is.na(asunto))
  )

# Campos económicos en contratos
cts <- cargar_tabla("contratos")
cts |>
  group_by(origen_ocr) |>
  summarise(
    n = n(),
    sin_importe = mean(is.na(importe_principal)),
    sin_adjudicatario = mean(is.na(adjudicatarios)),
    marcados_revisar = mean(revisar %in% TRUE)
  )
```

Los resultados de esta comprobación se guardan en `validation/resultado_validacion.md` (o similar) y se comentan en `faltantes.md`.