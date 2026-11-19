# extraer.R --------------------------------------------------------------------
# Clasificación de cada punto (familia y tipo) y extracción de campos:
# contratos (importe, adjudicatarios, prórrogas), subvenciones (beneficiarios) y
# judicial (órgano, sentencia, sentido...). Todo por reglas y expresiones regulares,
# aplicadas sobre el texto NORMALIZADO (norm_txt) o sobre el original según el campo.
# Las reglas se aplican en orden y gana la primera que coincide.

# Clasificación ----------------------------------------------------------------

reglas_tipo <- function() {
  dplyr::tribble(
    ~tipo, ~familia, ~rx,
    "aprobacion_acta", "institucional", "aprobacion (del )?acta",
    "plan_contratacion", "contratacion", "plan anual de contratacion|plan de contratacion",
    "judicial_asuntos", "judicial", "asuntos judiciales|asuntos juridicos",
    "judicial", "judicial", "sentencia|juzgado|tribunal|recurso de|procedimiento (ordinario|abreviado)|servicios juridicos|contencioso",
    "certificacion_obra", "obras", "certificacion(es)? de obra",
    "prorroga_convenio", "convenios", "prorroga.{0,40}convenio|convenio.{0,40}prorroga",
    "prorroga", "contratacion", "prorroga",
    "modificacion_contrato", "contratacion", "modifica(cion|do|da).{0,60}(contrato|contratacion|lote)",
    "incoacion_adjudicacion", "contratacion", "incoacion y adjudicacion",
    "ratificacion_decreto_contrato", "contratacion", "ratifica(cion|r).{0,40}decreto.{0,80}(contrato|contratacion|expediente)",
    "adjudicacion_contrato", "contratacion", "adjudica(cion|do|da|dos|das).{0,40}contrat",
    "incoacion_contrato", "contratacion", "incoacion.{0,40}contrat",
    "bases_concurso", "concursos_bases", "bases|concurso",
    "subvencion", "subvenciones", "ayuda|subvencion|premio|beca|bonificacion",
    "convenio", "convenios", "convenio",
    "urbanismo", "urbanismo", "ocupacion de dominio publico|proyecto de ejecucion|licencia",
    "ratificacion_decreto", "institucional", "ratifica(cion|r)",
    "dacion_cuentas", "institucional", "dacion de cuentas|datacion de cuentas",
    "otros", "otros", ".*"
  )
}

# Familia que se deduce del bloque de la convocatoria cuando el tipo es "otros".
familia_de_bloque <- function(bloque) {
  if (is.na(bloque)) return(NA_character_)
  b <- norm_txt(bloque)
  if (str_detect(b, "contratacion")) return("contratacion")
  if (str_detect(b, "convenio")) return("convenios")
  if (str_detect(b, "certificacion")) return("obras")
  if (str_detect(b, "subvencion|ayudas")) return("subvenciones")
  NA_character_
}

clasificar_tipo <- function(asunto, bloque = NA) {
  n <- norm_txt(asunto)
  r <- reglas_tipo()
  hit <- which(str_detect(n, r$rx))[1]
  if (is.na(hit)) return(c(tipo = "otros", familia = "otros"))
  tipo <- r$tipo[hit]; familia <- r$familia[hit]
  if (tipo == "otros") {
    fb <- familia_de_bloque(bloque)
    if (!is.na(fb)) familia <- fb
  }
  c(tipo = tipo, familia = familia)
}

# Importes ---------------------------------------------------------------------

# "12.345,67 euros" / "12.345,67 €" → 12345.67
parse_importe <- function(x) {
  if (is.na(x)) return(NA_real_)
  as.numeric(str_replace(str_remove_all(x, "\\."), ",", "."))
}

buscar_importes <- function(txt) {
  if (is.na(txt)) return(character())
  # con unidad monetaria detrás
  m1 <- str_match_all(txt, "(\\d{1,3}(?:\\.\\d{3})*,\\d{2})\\s*(?:euros?|eur|\\u20ac)")[[1]][, 2]
  # o precedido de palabra clave (importe, precio, total, adjudicación...)
  m2 <- str_match_all(txt, regex(
    "(importe|importes|maximo|presupuesto|valor estimado|valor|precio|coste|cuant[ií]a|adjudica(?:ci[oó]n|do|da)|gastos de ejecuci[oó]n)[^0-9\\u20ac]{0,40}(\\d{1,3}(?:\\.\\d{3})*,\\d{2})",
    ignore_case = TRUE))[[1]][, 3]
  v <- unique(c(m1, m2))
  v
}

importes_numerico <- function(txt) {
  v <- buscar_importes(txt)
  x <- vapply(v, parse_importe, numeric(1))
  unique(x[!is.na(x)])
}

# Contratos --------------------------------------------------------------------

extraer_contratos <- function(txt, asunto, familia, tipo, origen_ocr) {
  out <- list(tipo_objeto = NA_character_, procedimiento = NA_character_, lotes = NA_character_,
              objeto = NA_character_, importe_principal = NA_real_, importe_max = NA_real_,
              importes = NA_character_, iva = NA_character_, adjudicatarios = NA_character_,
              prorroga = FALSE, prorroga_n = NA_character_, prorroga_duracion = NA_character_)
  if (is.na(txt)) return(out)
  n <- norm_txt(txt)

  # tipo de objeto: obra / servicio / suministro / mixto
  hay <- c(obra = "obra", servicio = "servicio(s)?", suministro = "suministro(s)?") |>
    vapply(function(r) str_detect(n, r), logical(1))
  out$tipo_objeto <- if (sum(hay) >= 2) "mixto"
    else if (hay[["obra"]]) "obra"
    else if (hay[["servicio"]]) "servicio"
    else if (hay[["suministro"]]) "suministro"
    else NA_character_

  # procedimiento (sobre texto normalizado)
  procs <- c("abierto simplificado", "negociado sin publicidad", "negociado con publicidad",
             "restringido", "concurso de proyectos", "negociado", "abierto", "menor")
  hit <- which(vapply(procs, function(r) str_detect(n, r), logical(1)))[1]
  if (!is.na(hit)) out$procedimiento <- procs[hit]

  # lotes: "3 lotes" o "lotes 3" o "lote nº 3"
  lo <- str_match(txt, regex("(\\d{1,2})\\s*lotes?\\b|\\blotes?\\s*(?:n[º°o*\\.]*\\s*)?(\\d{1,2})", ignore_case = TRUE))
  out$lotes <- if (!is.na(lo[1, 2])) lo[1, 2] else if (!is.na(lo[1, 3])) lo[1, 3] else NA_character_

  out$objeto <- truncar_md(asunto)

  imp <- importes_numerico(txt)
  if (length(imp)) {
    out$importes <- paste(sort(unique(round(imp, 1))), collapse = "; ")
    out$importe_max <- max(imp)
    # importe principal: el primero precedido de palabra clara; si no, el primero
    m <- str_match_all(txt, regex(
      "(importe|importes|maximo|presupuesto|valor estimado|precio|coste|cuant[ií]a|adjudica(?:ci[oó]n|do|da)|gastos de ejecuci[oó]n)[^0-9\\u20ac]{0,40}(\\d{1,3}(?:\\.\\d{3})*,\\d{2})",
      ignore_case = TRUE))[[1]]
    if (nrow(m)) out$importe_principal <- parse_importe(m[1, 3]) else out$importe_principal <- imp[1]
  }

  # IVA: porcentaje junto a "IVA" (se descartan otros porcentajes, p. ej. bajas)
  ivs <- str_match_all(txt, regex(
    "(\\d{1,2})\\s*%[^.;]{0,30}?iva|iva[^.;]{0,30}?(\\d{1,2})\\s*%",
    ignore_case = TRUE))[[1]]
  if (nrow(ivs)) {
    vals <- unique(stats::na.omit(c(ivs[, 2], ivs[, 3])))
    preferido <- vals[vals %in% c("21", "10", "4", "0")]
    out$iva <- if (length(preferido)) preferido[1] else vals[1]
  }

  # adjudicatarios: nombres con forma societaria
  out$adjudicatarios <- extraer_entidades(txt)

  # prórrogas
  out$prorroga <- str_detect(n, "prorroga")
  if (out$prorroga) {
    pn <- str_match(txt, regex("(primera|segunda|tercera|cuarta|quinta|sexta)\\s+pr[oó]rroga|pr[oó]rroga\\s+(primera|segunda|tercera|cuarta|quinta|sexta)",
                               ignore_case = TRUE))
    out$prorroga_n <- pn[1, 2] %||% if (!is.na(pn[1, 3])) pn[1, 3] else NA_character_
    pd <- str_match(txt, regex("pr[oó]rroga[^.;]{0,80}?(\\d{1,2}\\s*(a[ñn]os|meses))", ignore_case = TRUE))[1, 2]
    out$prorroga_duracion <- pd
  }

  # revisar: viene de OCR y falta importe o adjudicatario en una adjudicación
  es_adjudicacion <- familia == "contratacion" &&
    str_detect(tipo, "adjudicacion|incoacion_adjudicacion|ratificacion_decreto_contrato")
  out$revisar <- isTRUE(origen_ocr) && es_adjudicacion && (is.na(out$importe_principal) || is.na(out$adjudicatarios))
  out
}

# Entidades con forma societaria ("PACSA SERVICIOS URBANOS S.L.", "UTE", "S.A....")
# Se exige la forma con puntos (S.L., S.A., S.L.U....) para no confundir con siglas sueltas
# del texto OCR ("S L"); después se recorta el prefijo de la frase y se descartan nombres
# imposibles (más de 7 palabras).
extraer_entidades <- function(txt) {
  if (is.na(txt)) return(NA_character_)
  rx_entidad <- regex(
    paste0("([A-ZÁÉÍÓÚÜÑ][A-Za-zÁÉÍÓÚÜÑáéíóúüñ .,'´`\\-&º/0-9]{3,70}?)\\s*",
           "(S\\.\\s?L\\.\\s?U?\\.?|S\\.\\s?A\\.\\s?U?\\.?|S\\.\\s?A\\.\\s?R\\.\\s?L\\.|",
           "S\\.\\s?C\\.\\s?L\\.|S\\.\\s?P\\.\\s?E\\.|S\\.\\s?G\\.\\s?A\\.|S\\.\\s?A\\.\\s?D\\.|",
           "S\\.\\s?A\\.\\s?T\\.|S\\.\\s?Coop\\.?|S\\.\\s?L\\.\\s?N\\.E\\.|",
           "UTE|A\\.\\s?I\\.\\s?E\\.|Coop\\.|Cooperativa)"),
    ignore_case = FALSE)
  m <- str_match_all(txt, rx_entidad)[[1]]
  ents <- character()
  if (nrow(m)) {
    ents <- str_squish(paste(m[, 2], m[, 3])) |>
      str_remove("^[-:,;y] ") |>
      str_remove("^(la )?empresa(s)? ")
    # quedarse con lo que sigue a la última fórmula introductoria de la frase
    ents <- str_remove(ents, regex(
      "^.*(a la entidad|la entidad|a la empresa|la empresa|empresa|adjudicatari[oa]|a favor de|siendo|otorgad[oa] a)\\s+",
      ignore_case = TRUE))
    # descartar fragmentos que no son nombres
    bad <- str_detect(norm_txt(ents),
                      "^(el|la|los|las|del|de|que|y|con|para|por|que es|quien|importa|importe)") |
      (str_count(ents, "\\S+") > 7)
    ents <- ents[!bad & str_length(ents) > 4]
  }
  # patrón explícito: "adjudicataria ... X" cuando la forma societaria falla
  if (!length(ents)) {
    m2 <- str_match_all(txt, regex(
      "adjudicatari[oa](?:s?)(?:\\s+(?:la|del|de))*\\s+([A-ZÁÉÍÓÚÜÑ][^.\\n;]{5,90}?)(?=[.,;)\\n]| y |\\s(con|para|i)\\s)", ignore_case = FALSE))[[1]]
    if (nrow(m2)) ents <- str_squish(str_trim(m2[, 2]))
  }
  if (!length(ents)) return(NA_character_)
  paste(head(unique(ents), 5), collapse = "; ")
}

# Subvenciones -----------------------------------------------------------------

extraer_subvencion <- function(txt, asunto, origen_ocr) {
  out <- list(asunto = truncar_md(asunto), importe_principal = NA_real_, importe_max = NA_real_,
              importes = NA_character_, beneficiarios = NA_character_, revisar = FALSE)
  if (is.na(txt)) return(out)
  imp <- importes_numerico(txt)
  if (length(imp)) {
    out$importes <- paste(sort(unique(round(imp, 1))), collapse = "; ")
    out$importe_max <- max(imp)
    out$importe_principal <- imp[1]
  }
  m <- str_match_all(txt, regex(
    paste0("(asociaci[oó]n|club|fundaci[oó]n|federaci[oó]n|ampa|cooperativa|pe[ñn]a|hermandad|cofrad[ií]a)\\s+",
           "([A-ZÁÉÍÓÚÜÑ][^.;,]{2,70}?)(?=\\s+(?:por|de|y|con|al)\\b|[.;,]|$)"),
    ignore_case = TRUE))[[1]]
  if (nrow(m)) out$beneficiarios <- paste(head(unique(str_squish(m[, 3])), 6), collapse = "; ")
  out
}

# Judicial ---------------------------------------------------------------------

extraer_judicial <- function(txt, origen_ocr) {
  out <- list(organo_judicial = NA_character_, procedimiento_judicial = NA_character_,
              n_procedimiento = NA_character_, sentencia_n = NA_character_,
              sentencia_fecha = NA_character_, recurrente = NA_character_,
              acto_recurrido = NA_character_, sentido = NA_character_, resumen = NA_character_)
  if (is.na(txt)) return(out)
  t <- str_replace_all(txt, "\\s+", " ")
  og <- str_match(t, regex(paste0(
    "(juzgado de (?:lo|los|la)\\s+[a-záéíóúüñ\\- ]{3,60}(?:n[º°o*\\.]*\\s*\\d{1,3})?|",
    "secci[oó]n\\s+\\d{1,2}\\s*de lo\\s+[a-záéíóúüñ\\- ]{3,60}|",
    "tribunal (?:superior de justicia|supremo)[a-záéíóúüñ \\-]{0,45})"), ignore_case = TRUE))[1, 1]
  if (!is.na(og)) out$organo_judicial <- str_squish(str_trunc(og, 90, "right", ""))
  np <- str_match(t, regex(
    "procedimiento\\s+(abreviado|ordinario|monitorio|penal|contencioso[- ]administrativo|expropiatorio)\\s*[nº°o*\\.]*\\s*(\\d{1,6}\\s*/\\s*\\d{2,4})",
    ignore_case = TRUE))
  if (!is.na(np[1, 1])) out$n_procedimiento <- paste0("Procedimiento ", cap_título(np[1, 2]), " ", str_remove(np[1, 3], "\\s"))
  sn <- str_match(t, regex("sentencia\\s+(?:n[º°o*\\.]*\\s*)?(\\d{1,6}\\s*/\\s*\\d{2,4})", ignore_case = TRUE))[1, 2]
  out$sentencia_n <- if (!is.na(sn)) str_remove(sn, "\\s") else NA_character_
  sf <- str_match(t, regex("sentencia[^.;]{0,50}?fecha (\\d{1,2}[/-]\\d{1,2}[/-]\\d{2,4})", ignore_case = TRUE))[1, 2]
  out$sentencia_fecha <- sf
  rec <- str_match(t, regex("interpuesto por\\s+([A-ZÁÉÍÓÚÜÑ][^.]{2,110}?)(?=\\s+contra|[.;]|\\s+i )", ignore_case = TRUE))[1, 2]
  out$recurrente <- if (!is.na(rec)) str_squish(str_trunc(str_trim(rec), 120, "right", "...")) else NA_character_
  ar <- str_match(t, regex(
    "contra (?:el|la)\\s+(decreto|resoluci[oó]n|acuerdo|acta|liquidaci[oó]n|ordenanza|liquidaci[oó]n tributaria)[^.]{0,110}",
    ignore_case = TRUE))[1, 1]
  out$acto_recurrido <- if (!is.na(ar)) str_squish(str_trunc(ar, 140, "right", "...")) else NA_character_
  n <- norm_txt(txt)
  sentidos <- c("estimacion parcial" = "estimación parcial",
                "estima parcialmente" = "estimación parcial",
                "estimar parcialmente" = "estimación parcial",
                "en parte estimatoria" = "estimación parcial",
                "allanamiento" = "allanamiento",
                "desistimiento" = "desistimiento",
                "inadmision" = "inadmisión",
                "desestimatoria" = "desestimatoria",
                "desestima" = "desestimatoria",
                "estimatoria" = "estimatoria",
                "estima el recurso" = "estimatoria",
                "estima la demanda" = "estimatoria",
                "se acuerda el archivo|sobreseimiento" = "archivo")
  hit <- which(vapply(sentidos, function(r) str_detect(n, r), logical(1)))[1]
  if (!is.na(hit)) out$sentido <- sentidos[hit]
  rz <- str_match(t, regex("hechos\\s+y\\s+fundamentos\\s+de\\s+derecho\\s*:?(.+)", ignore_case = TRUE))[1, 2]
  out$resumen <- if (!is.na(rz)) truncar_md(str_squish(rz), 500) else truncar_md(t, 500)
  out
}

cap_título <- function(x) {
  if (is.na(x)) return(NA_character_)
  paste0(toupper(substr(x, 1, 1)), substr(x, 2, nchar(x)))
}
