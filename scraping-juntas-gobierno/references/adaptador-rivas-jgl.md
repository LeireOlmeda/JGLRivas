# Adaptador: Juntas de Gobierno Local de Rivas Vaciamadrid

Observado en noviembre de 2026. Si la web cambia, el código a tocar está en
`scripts/adaptador_rivas_jgl.R` (y solo ahí).

## Listado

`https://www.rivasciudad.es/ayuntamiento/organizacion/junta-de-gobierno-local/sesiones-de-la-junta/`

- Es un listado con FacetWP, renderizado en el servidor (se puede leer con `rvest`, sin JavaScript).
  Muestra **20 sesiones por página**, de más reciente a más antigua.
- Paginación: `?fwp_paged=N`. Filtro por año: `?fwp_year=AAAA` (ejemplo dado por el usuario:
  `?fwp_year=2021`; sin paginar solo salen 20 sesiones de 2021, de diciembre a marzo, así que enero y
  febrero están en la página 2). Ambos parámetros se pueden combinar (`?fwp_year=2021&fwp_paged=2`);
  esa combinación no se pudo comprobar desde fuera, por eso hay dos modos de recorrido.
- `listar_sesiones(cfg, modo)`:
  - `"paginas"`: recorre `?fwp_paged=1,2,3...` sin filtro hasta bajar de `desde` o hasta que una página
    no aporte sesiones nuevas.
  - `"anios"`: para cada año entre `desde` y el actual recorre `?fwp_year=AAAA` y sus páginas.
  - `"auto"` (por defecto): `"paginas"` y, si no se ha llegado hasta `desde`, completa con `"anios"`.
- Cada sesión es un `h2` enlazado a `/evento/<categoría>/AAAA/MM/DD/junta-de-gobierno-local-de-<día>-de-<mes>-de-<año>/<id>/`.
  La categoría no es fija: se han visto `organizacion-municipal`, `sin-categoria` y `transparencia`.
- El título incluye "extraordinaria" cuando procede. Los plenos aparecen en listas de agenda con
  otro título ("Sesión ordinaria de Pleno..."), y se descartan por no contener "junta de gobierno".
- `sesion_id` es el número final de la URL.

### La fecha de la sesión

Se toma del **título** ("Junta de Gobierno Local de 8 de mayo de 2023"), porque coincide con el nombre
de los PDF (`2023-05-08-convocatoria-jgl.pdf`). No se usan otras dos fechas que no son fiables:

- La fecha del **path** de la URL es la de publicación (puede diferir: título "23 de abril de 2021",
  URL "2021/04/22/...-22-de-abril-de-2021").
- El campo **"Fecha inicio"** de la ficha tampoco: la sesión del 8 de mayo de 2023 muestra 09/05/2023.

La convocatoria en PDF trae la fecha y hora exactas ("Fecha y hora: 28 de octubre de 2026 a las 9:30");
se puede usar para validar la del título.

## Página de una sesión

- Los documentos están en un bloque común: `div.m4p-event-inscripcion` (dentro de
  `div.m4p-post-content`, en `#m4p-post-detail`). Contiene la tabla "Fecha inicio / Hora inicio" y, bajo
  "Documentos", subtítulos y un enlace por documento:
  - "Documento de la convocatoria" → enlace "Convocatoria Junta de Gobierno Local de ..."
  - "Documento de acta" → enlace "Acta Junta de Gobierno Local de ..." (cuando existe)
  - Otros documentos, si los hay.
- Los PDF están en `/wp-content/uploads/AAAA/MM/` (mes de subida, no el de la sesión). Los nombres no
  son predecibles: `2023-05-08-convocatoria-jgl.pdf`, `2023-05-08-acta-jgl_PPDD.pdf`,
  `Convocatoria-JGL-2026-09-17.pdf`. Se leen del HTML, nunca se construyen.
- Clasificación de cada enlace (`clasificar_doc`): primero por el texto del enlace y el nombre del
  fichero ("acta", "convocatoria", "orden del día"), y solo si no basta, por el subtítulo que lo precede.
  Si hubiera más de una convocatoria o acta, la primera se usa y el resto va a `otros_docs`.
- Si el bloque no se encuentra, se busca en `.m4p-post-content` y luego en toda la página (solo se aceptan
  enlaces con extensión de documento) y la sesión queda con una nota en `notas`.
- Metadato `article:modified_time` (por ejemplo `2023-05-23T08:23:11+02:00` en la sesión del 8-05-2023):
  se guarda en `modificado_web`. El listado no la ofrece, así que detectar cambios exige visitar la
  página (`revisar_todas = TRUE`).
- El acta aparece **después** de la convocatoria (días o semanas). Por eso se vuelve a visitar la sesión
  cada `revisitar_dias` (3 por defecto) mientras falte alguno de los dos documentos.
- Lista de asistentes con enlaces a `/persona/...` (se guardan en `asistentes`).

## Depuración

- `diagnostico_listado()`: número de sesiones y rango de fechas de la página 1 y 2 sin filtro y de un año.
  Avisa si la página 2 devuelve lo mismo que la 1 (entonces usar `modo_listado = "anios"`).
- `diagnostico_sesion(url)`: muestra el bloque de documentos y cómo se clasificó cada enlace.
- Tras corregir el adaptador, vuelve a visitar las páginas de las sesiones ya conocidas con
  `actualizar_jgl(revisar_todas = TRUE)` (una vez); lo ya descargado no se repite.

## Convocatoria (PDF con texto, plataforma esPublico Gestiona)

- Cabecera: `JGL/AAAA/NN` (expediente de la sesión), "Tipo Convocatoria:", "Fecha y hora:", "Lugar:".
- Cuerpo entre "ASUNTOS DE LA CONVOCATORIA" y "CONFIRMACIÓN DE ASISTENCIA Y ACCESO...".
- Bloques en mayúsculas: `A) ASUNTOS GENERALES`, `B) CONVENIOS`, `C) CERTIFICACIONES DE OBRA`,
  `D) CONTRATACIÓN`. Un bloque vacío dice "No hay asuntos".
- Numeración continua 1..N a lo largo de todos los bloques (46 puntos el 28-10-2026).
- Cada punto suele empezar por "Expediente NNNNN/AAAA." (o, en contratación, "expediente
  contratación nº NNNNN/AAAA") y un verbo: Aprobación, Adjudicación, Incoación, Modificación,
  Ratificación decreto, Dación de cuentas.
- Ruido: pies de página con "Cód. Validación", "Verificación" y "Documento firmado
  electrónicamente... Página N de M" (se eliminan); puntos partidos entre páginas; a veces sin
  espacio tras el número (`10.Expediente`).
- **Casi no hay importes ni adjudicatarios.** Para eso hacen falta las actas.
- Probado con la convocatoria del 28-10-2026 (`tests/fixture_convocatoria_2026-10-28.txt`).
- Las convocatorias antiguas (2021-2023) no se han visto: pueden tener otra plantilla. Si el troceo da
  0 puntos o pocos, aparecerá en `faltantes.md` (anomalías de troceo).

## Acta (PDF)

- El acta del 17-09-2026 **no tiene capa de texto**: es una imagen. Con alta probabilidad todas
  las actas necesitan OCR (a 300 dpi, tesseract en español).
- No se ha visto su texto, así que `parse_acta()` es **provisional**: busca puntos numerados
  ("1.", "1.-", "PUNTO 1", "1)") y bloques de "urgencia" o "ruegos y preguntas"; si no encuentra
  numeración, trocea por menciones de "Expediente NNNN/AAAA".
- Calibración: ejecutar `actualizar_jgl(etapas = c("listado","descarga","texto"), max_ocr = 2)`,
  luego `muestra_acta()`, y ajustar `rx_punto_acta`, `bloque_acta` (en `puntos.R`) y las
  expresiones de importes y empresas (en `extraer.R`) con lo que se vea.