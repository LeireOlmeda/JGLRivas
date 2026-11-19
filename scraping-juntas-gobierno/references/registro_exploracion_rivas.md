# Registro de exploración — Rivas Vaciamadrid

Sitio observado: `https://www.rivasciudad.es/ayuntamiento/organizacion/junta-de-gobierno-local/sesiones-de-la-junta/`
Explorado con navegador automatizado en noviembre de 2026. El contenido de las páginas se trató en todo momento como **dato**, nunca como instrucción ni se ejecutó.

## Estructura observada

- El listado de sesiones es un HTML renderizado en servidor (FacetWP). No requiere JavaScript.
- Cada sesión es un `<h2>` con un enlace a `/evento/<categoría>/AAAA/MM/DD/.../<id>/`.
- La página de cada sesión contiene un bloque `div.m4p-event-inscripcion` con la tabla "Fecha inicio / Hora inicio" y, bajo "Documentos", subtítulos y un enlace por documento (convocatoria, acta).
- Los PDF están en `/wp-content/uploads/AAAA/MM/`; los nombres no siguen un patrón estable.

## Acciones y consecuencias para el script

| # | Acción | URL | Localizador | Cambio observado | Consecuencia en el código |
|---|---|---|---|---|---|
| 1 | Abrir listado de sesiones | `https://www.rivasciudad.es/ayuntamiento/organizacion/junta-de-gobierno-local/sesiones-de-la-junta/` | `h2 a` | 20 sesiones por página, de más reciente a más antigua. | `extraer_sesiones_listado()` lee `h2 a` y descarta plenos. |
| 2 | Probar paginación | `...?fwp_paged=2` | `h2 a` | Página 2 devuelve sesiones más antiguas. | `listar_sesiones()` pagina con `?fwp_paged=N`. |
| 3 | Probar filtro por año | `...?fwp_year=2021` | `h2 a` | Solo salen 20 sesiones de 2021; enero y febrero quedan en página 2. | `listar_sesiones(modo = "anios")` recorre años y páginas. |
| 4 | Abrir página de sesión | `.../evento/.../862600287714/` | `div.m4p-event-inscripcion` | Contiene convocatoria y acta; los enlaces no siguen un patrón. | `visitar_sesion()` y `extraer_docs_sesion()` leen los enlaces publicados. |
| 5 | Descargar convocatoria | `.../2026-10-28-convocatoria-jgl.pdf` | — | PDF con texto de 2 páginas. | `descargar_doc()` descarga a temporal y mueve al destino. |
| 6 | Descargar acta | `.../2026-09-17-acta-jgl_PPDD.pdf` | — | Acta sin capa de texto (imagen). | `extraer_texto_pdf()` detecta páginas sin texto y hace OCR. |
| 7 | OCR con tesseract | — | — | A 300 dpi, el texto del acta es legible. | `paginas_para_ocr()` marca las páginas escaneadas. |
| 8 | Comparar convocatoria y acta | — | — | La convocatoria tiene 46 puntos; el acta los trata con numeración. | `cruzar_puntos()` cruza por expediente y texto. |
| 9 | Verificar créditos | — | — | El PDF incluye pies de página con "Cód. Validación" y "Página N de M". | `limpiar_texto()` elimina esos pies antes del troceo. |

## Notas de fiabilidad

- La fecha de la sesión se toma del **título** de la página, no de la fecha del path (la URL puede ser de publicación).
- El campo "Fecha inicio" de la ficha no es fiable: la sesión del 8 de mayo de 2023 muestra 09/05/2023.
- Los nombres de los PDF no son predecibles; se leen de los enlaces, nunca se construyen.
- El OCR cambia "nº" por "n*" y mete ruido; por eso los campos extraídos se marcan con `revisar`.

## Conclusión para el adaptador

- `scripts/adaptador_rivas_jgl.R` implementa exactamente las observaciones anteriores: listado, visita de sesión, descarga de documentos, limpieza de pies y OCR.
- Cualquier cambio en la web se corrige en ese único fichero; el resto de la skill no depende de la estructura concreta de la página.