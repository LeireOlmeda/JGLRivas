# Tipos de punto y campos extraídos

La clasificación se hace con `reglas_tipo()` en `scripts/extraer.R`. Los patrones se aplican sobre
el texto **normalizado** (minúsculas, sin acentos, sin signos) y gana la primera regla que
coincide. Orden actual:

| tipo | familia | Qué detecta |
|---|---|---|
| `aprobacion_acta` | institucional | "Aprobación del acta..." |
| `plan_contratacion` | contratacion | Plan Anual de Contratación |
| `judicial_asuntos` | judicial | "Asuntos judiciales y administrativos relacionados" (punto fijo del orden del día) |
| `judicial` | judicial | sentencia, juzgado, tribunal, recurso, procedimiento ordinario/abreviado, "Servicios Jurídicos" |
| `certificacion_obra` | obras | certificación(es) de obra |
| `prorroga_convenio` / `prorroga` | convenios / contratacion | prórroga |
| `modificacion_contrato` | contratacion | modificación + contrato/contratación/lote |
| `incoacion_adjudicacion` | contratacion | "Incoación y Adjudicación" |
| `ratificacion_decreto_contrato` | contratacion | ratificación de decreto sobre un contrato |
| `adjudicacion_contrato` | contratacion | adjudicación + contrato |
| `incoacion_contrato` | contratacion | incoación de expediente de contratación |
| `bases_concurso` | concursos_bases | "bases" o "concurso" (bases de licitación, de ayudas, concursos de disfraces...) |
| `subvencion` | subvenciones | ayudas, subvenciones, premios, becas, bonificaciones |
| `convenio` | convenios | convenios |
| `urbanismo` | urbanismo | ocupación de dominio público, proyecto de ejecución, licencias |
| `ratificacion_decreto` | institucional | ratificación de decreto (sin contrato) |
| `dacion_cuentas` | institucional | dación de cuentas |
| `otros` | otros | lo demás (si el bloque es CONTRATACIÓN o CONVENIOS, la familia se deduce del bloque) |

Observaciones tomados de la convocatoria del 28-10-2026:

- "Adjudicación de las ayudas..." es una **subvención**, no un contrato: por eso `adjudicacion_contrato`
  exige la palabra "contrat" tras "adjudicación" y va antes que `subvencion`.
- Los "premios" y "bonificaciones" se agrupan con las subvenciones; si el análisis necesita
  separarlos, añadir una regla `premio` antes de `subvencion`.
- Las "Daciones de cuentas de Servicios Jurídicos" se clasifican como judiciales.

## Campos por familia

- **Contratos y obras**: `tipo_objeto` (obra, servicio, suministro, mixto), `procedimiento`
  (abierto, abierto simplificado, negociado sin publicidad, menor, restringido, concurso de
  proyectos), `lotes`, `objeto`, `importe_principal`, `importe_max`, `importes`, `iva`,
  `adjudicatarios` (nombres con forma societaria: S.L., S.A., S.L.U., S. Coop., UTE...),
  `prorroga`, `prorroga_n` (primera, segunda...), `prorroga_duracion` ("2 años", "6 meses").
- **Subvenciones**: importes y `beneficiarios` (Asociación, Club, Fundación, Federación, AMPA,
  Cooperativa...).
- **Judicial** (pensado para las "Dación de cuentas Servicios Jurídicos" de las actas de 2026):
  `organo_judicial` ("Sección de lo Contencioso... del Tribunal de Instancia de Madrid"),
  `procedimiento_judicial` y `n_procedimiento` ("Procedimiento Abreviado 557/2024"), `sentencia_n` y
  `sentencia_fecha`, `recurrente` ("interpuesto por ..."), `acto_recurrido` ("contra el Decreto ..."),
  `sentido` (estimatoria, desestimatoria, estimación parcial, inadmisión, archivo, allanamiento,
  desistimiento), `votacion` y `resumen` (primeros 500 caracteres tras "Hechos y fundamentos de
  derecho"). El OCR cambia "nº" por "n*" y mete ruido: todo es aproximado.
- **Votación** (todas las familias): `votacion` es el "Tipo de votación" que figura en la banda del
  punto en el acta (por ejemplo "Unanimidad/Asentimiento").

## Límites conocidos

- Los importes se detectan por la forma "12.345,67 euros" o "€". El OCR puede cambiar cifras:
  por eso existe la columna `revisar` y el texto original se conserva.
- Las empresas sin forma societaria (comunidades de bienes, autónomos, fundaciones adjudicatarias)
  no se detectan como adjudicatarios.
- Los nombres de empresa con minúsculas iniciales o con OCR deficiente se pierden o se cortan.
- Un punto con varios lotes puede tener varios importes y adjudicatarios mezclados en una fila.