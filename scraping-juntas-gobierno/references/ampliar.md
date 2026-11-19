# Cómo ampliar la skill

## 1. Añadir un tipo de punto

En `scripts/extraer.R`, añadir una fila a `reglas_tipo()` **antes** de la regla más general que
podría capturarlo:

```r
"oferta_empleo", "personal", "oferta de empleo publico|bolsa de empleo|proceso selectivo",
```

Recalcular sin red ni OCR: `actualizar_jgl(etapas = "analisis")`. Se aplica a todas las sesiones.

## 2. Añadir un campo nuevo

1. Escribir una función que reciba el texto de un punto y devuelva un valor (o un tibble de una
   fila si son varios campos), por ejemplo `plazo_ejecucion_en(txt)`.
2. Llamarla en `enriquecer_cruce()` (en `extraer.R`) y añadir la columna en `escribir_tablas_analisis()`
   (en `analisis.R`) a la tabla que corresponda.
3. Recalcular con `etapas = "analisis"`.

## 3. Añadir una tabla de análisis nueva

En `escribir_tablas_analisis()` añadir un bloque igual a los existentes:
`todo |> filter(<condición>) |> transmute(<columnas>) |> d("mi_tabla.md", df = _)`.

## 4. Nuevos análisis

Funciones nuevas en `scripts/consultas.R` que partan de `cargar_tabla("contratos")` o
`cargar_puntos()`. Ejemplos ya incluidos: contratos por año, por área (palabras clave editables),
top de adjudicatarios, historial de un expediente, cambios sobre lo previsto, prórrogas.
Para "cómo varían contratos de un mismo concepto", agrupar por `objeto` normalizado
(`norm_txt(objeto)`) y comparar importes por año.

## 5. Plenos u otro ayuntamiento

La lógica específica de la web está aislada en un adaptador. Para uno nuevo:

1. Copiar `scripts/adaptador_rivas_jgl.R` a `adaptador_<ayuntamiento>_<organo>.R` y reescribir
   `listar_sesiones()` y `visitar_sesion()` para que devuelvan lo mismo (ver cabecera del fichero).
2. Si la plataforma de gestión es otra, comprobar `parse_convocatoria()`: la de Rivas sirve para
   convocatorias de esPublico Gestiona; otras plataformas pueden requerir otro `rx_punto_conv` o
   otras marcas de inicio y fin del orden del día.
3. Usar otro `base_dir` (por ejemplo `datos/pleno-rivas`) para no mezclar datos:
   `actualizar_jgl(base_dir = "datos/pleno-rivas", url_listado = "...")`.
   Si el adaptador cambia, sustituirlo en la lista de ficheros que carga `actualizar_jgl.R`.
4. Añadir `references/adaptador-<...>.md` con lo observado en la web.

Los plenos tienen mociones, ruegos y preguntas: probablemente hagan falta reglas de tipo nuevas
(`mocion`, `ruego`, `pregunta`) y que `bloque_acta()` reconozca esas secciones.

## 6. Si más adelante se quiere usar un modelo para extraer

Hoy todo es por reglas (sin coste). Si en el futuro se acepta un coste, la opción natural es dejar
las reglas como primera pasada y aplicar un modelo solo a los puntos con `revisar = TRUE`, guardando
el resultado en columnas aparte (`*_modelo`) para poder comparar con las reglas.
