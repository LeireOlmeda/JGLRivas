# analisis.R -------------------------------------------------------------------
# Genera, a partir del índice y de los textos ya guardados (sin red ni OCR):
#   - sesiones/AAAA-MM-DD_<id>.md  (una sesión con sus puntos cruzados)
#   - analisis/puntos.md, contratos.md, subvenciones.md, judicial.md
#   - faltantes.md (lo que falta y las anomalías, regenerado en cada ejecución)

COLUMNS_PUNTOS <- c("sesion_id", "fecha", "tipo_sesion", "n_conv", "n_acta", "estado",
                    "cruce_metodo", "cruce_fiable", "cambio_orden", "expediente",
                    "familia", "tipo", "asunto", "votacion", "fuente_texto", "origen_ocr")
COLUMNS_CONTRATOS <- c("sesion_id", "fecha", "n_acta", "estado", "expediente", "tipo",
                       "tipo_objeto", "procedimiento", "lotes", "objeto", "importe_principal",
                       "importe_max", "importes", "iva", "adjudicatarios", "prorroga",
                       "prorroga_n", "prorroga_duracion", "fuente_texto", "origen_ocr", "revisar")
COLUMNS_SUBV <- c("sesion_id", "fecha", "n_acta", "estado", "expediente", "asunto",
                  "importe_principal", "importe_max", "importes", "beneficiarios",
                  "fuente_texto", "origen_ocr", "revisar")
COLUMNS_JUDICIAL <- c("sesion_id", "fecha", "n_acta", "estado", "cruce_metodo", "expediente",
                      "organo_judicial", "procedimiento_judicial", "n_procedimiento",
                      "sentencia_n", "sentencia_fecha", "recurrente", "acto_recurrido",
                      "sentido", "votacion", "resumen", "fuente_texto", "origen_ocr")

# Sesiones duplicadas (misma fecha y tipo): se usa la que tiene más documentos.
elegir_sesion <- function(ind) {
  dup_keys <- ind |>
    dplyr::filter(!is.na(fecha)) |>
    dplyr::group_by(fecha, tipo) |>
    dplyr::filter(dplyr::n() > 1) |>
    dplyr::ungroup()
  if (!nrow(dup_keys)) return(list(ind = ind, descartadas = NULL))
  buenos <- dup_keys |>
    dplyr::group_split() |>
    lapply(function(g) {
      g$ndocs <- rowSums(cbind(!is.na(g$pdf_convocatoria) | !is.na(g$pdf_acta),
                               g$estado_convocatoria == "ok", g$estado_acta == "ok"))
      g[which.max(g$ndocs), , drop = FALSE]
    }) |>
    dplyr::bind_rows()
  ids_buenos <- unique(buenos$sesion_id)
  descartadas <- dup_keys |> dplyr::filter(!sesion_id %in% ids_buenos)
  ind2 <- ind |> dplyr::filter(!sesion_id %in% descartadas$sesion_id)
  list(ind = ind2,
       descartadas = if (nrow(descartadas)) dplyr::select(descartadas, fecha, tipo, sesion_id,
                                                          estado_convocatoria, estado_acta, url) else NULL)
}

# Prepara una sesión ------------------------------------------------------------

preparar_sesion <- function(row, cfg) {
  pc <- tibble::tibble()
  pa <- NULL
  tc <- ta <- NA_character_
  if (!is.na(row$txt_convocatoria)) {
    f <- jgl_abs(cfg, row$txt_convocatoria)
    if (!is.na(f) && file.exists(f)) { tc <- leer_md_cuerpo(f); pc <- parse_convocatoria(tc)$puntos }
  }
  if (!is.na(row$txt_acta)) {
    f <- jgl_abs(cfg, row$txt_acta)
    if (!is.na(f) && file.exists(f)) { ta <- leer_md_cuerpo(f); pa <- parse_acta(ta) }
  }
  if (nrow(pc) == 0 && (is.null(pa) || nrow(pa$puntos) == 0)) return(NULL)
  cr <- cruzar_puntos(pc, pa, texto_acta_plano = if (!is.null(pa)) pa$texto_plano else "",
                      hay_acta = !is.na(ta))
  cr$familia <- NA_character_; cr$tipo <- NA_character_
  if (nrow(cr)) {
    cls <- str_split(vapply(seq_len(nrow(cr)), function(i) {
      clasificar_tipo(cr$asunto[i], cr$bloque[i]) |> paste(collapse = "\r")
    }, character(1)), "\r", simplify = TRUE)
    cr$familia <- cls[, 2]; cr$tipo <- cls[, 1]
    origen_ocr <- (cr$fuente_texto == "acta") & (row$metodo_acta %in% c("ocr", "mixto"))
    fils <- lapply(seq_len(nrow(cr)), function(i) {
      switch(cr$familia[i],
        "contratacion" = extraer_contratos(cr$texto_extra[i], cr$asunto[i], cr$familia[i], cr$tipo[i], origen_ocr[i]),
        "obras" = extraer_contratos(cr$texto_extra[i], cr$asunto[i], cr$familia[i], cr$tipo[i], origen_ocr[i]),
        "subvenciones" = extraer_subvencion(cr$texto_extra[i], cr$asunto[i], origen_ocr[i]),
        "judicial" = extraer_judicial(cr$texto_extra[i], origen_ocr[i]),
        list(revisar = FALSE))
    })
    extra <- dplyr::bind_rows(lapply(fils, as_tibble))
  } else extra <- NULL

  meta <- list(sesion_id = row$sesion_id, fecha = row$fecha, tipo_sesion = row$tipo,
               url = row$url, titulo = row$titulo,
               expediente_jgl = tryCatch({
                 if (is.na(tc)) NA_character_ else parse_convocatoria(tc)$cabecera$exp_sesion
               }, error = function(e) NA_character_),
               convocatoria = row$estado_convocatoria, acta = row$estado_acta,
               metodo_acta = row$metodo_acta,
               puntos_convocatoria = nrow(pc),
               puntos_acta = if (!is.null(pa)) nrow(pa$puntos) else 0L,
               troceo_acta = if (!is.null(pa)) pa$troceo else NA_character_,
               cruce_fiable = if (nrow(cr)) cr$cruce_fiable[1] else NA,
               exp_acta = if (!is.null(pa)) pa$puntos$expediente else character(0))
  list(puntos = cr, extra = extra, meta = meta)
}

# Sesión en markdown ------------------------------------------------------------

escribir_sesion_md <- function(pre, cfg) {
  p <- pre$meta
  pts <- pre$puntos
  cab <- list(sesion_id = p$sesion_id, fecha = p$fecha, tipo_sesion = p$tipo_sesion,
              expediente_jgl = p$expediente_jgl, url = p$url,
              convocatoria = p$convocatoria, acta = p$acta, metodo_acta = p$metodo_acta,
              puntos_convocatoria = p$puntos_convocatoria,
              puntos_acta = if (!is.na(p$acta) && p$acta == "ok") p$puntos_acta else NA,
              troceo_acta = p$troceo_acta, cruce_fiable = p$cruce_fiable,
              nuevos = sum(pts$estado %in% c("nuevo", "nuevo_urgencia", "nuevo_dudoso")),
              retirados = sum(pts$estado == "retirado"),
              en_acta_sin_trocear = sum(pts$estado == "en_acta_sin_trocear"))
  cuerpo <- c(paste0("# ", p$titulo), "",
              tabla_a_md(pts |> dplyr::select(n_conv, n_acta, estado, expediente, familia, tipo, asunto)))
  escribir_md(file.path(cfg$dir_sesiones, sprintf("%s_%s.md", p$fecha, p$sesion_id)), cab, cuerpo)
}

# Tablas ------------------------------------------------------------------------

.escribir_tabla_md <- function(path, df, nombre) {
  escribir_md(path, list(descripcion = paste("Tabla generada por la skill;", nombre),
                         filas = nrow(df)), tabla_a_md(df))
}

# Faltantes ---------------------------------------------------------------------

escribir_faltantes <- function(cfg, ind, sesiones, n_duplicadas, descartadas_ids = character()) {
  desde <- format(cfg$desde, "%Y-%m-%d")
  hoy <- Sys.Date()
  # las páginas duplicadas descartadas no cuentan como documentación que falta
  ind_an <- ind |> dplyr::filter(!sesion_id %in% descartadas_ids)
  resumen <- tibble::tibble(
    concepto = c("Sesiones en el índice (desde el año de inicio)",
                 "Con convocatoria con texto", "Con acta con texto",
                 "Sin convocatoria", "Sin acta", "Actas obtenidas por OCR"),
    n = c(sum(!is.na(ind_an$fecha) & ind_an$fecha >= desde),
          sum(ind_an$estado_convocatoria == "ok", na.rm = TRUE),
          sum(ind_an$estado_acta == "ok", na.rm = TRUE),
          sum(ind_an$estado_convocatoria == "falta", na.rm = TRUE),
          sum(ind_an$estado_acta == "falta", na.rm = TRUE),
          sum(ind_an$metodo_acta %in% c("ocr", "mixto"), na.rm = TRUE)))

  sin_conv <- ind_an |> dplyr::filter(estado_convocatoria == "falta") |>
    dplyr::select(fecha, tipo, sesion_id, url)
  sin_acta <- ind_an |> dplyr::filter(estado_acta == "falta") |>
    dplyr::mutate(situacion = if_else(hoy - as.Date(fecha) <= 45,
                                      "reciente (puede estar pendiente de publicar)", "revisar")) |>
    dplyr::select(fecha, tipo, sesion_id, situacion, url, notas)
  prob <- purrr::map_dfr(c("convocatoria", "acta"), function(doc) {
    col <- paste0("estado_", doc)
    mal <- ind_an |> dplyr::filter(.data[[col]] %in% c("enlace_roto", "error", "formato_no_pdf",
                                                       "ocr_pendiente", "pendiente", "descargado"))
    if (!nrow(mal)) return(NULL)
    tibble::tibble(fecha = mal$fecha, documento = doc, estado = mal[[col]], notas = mal$notas)
  })
  anom <- purrr::map_dfr(sesiones, function(m) {
    pts <- m$puntos
    frac_sin_exp <- if (length(m$meta$exp_acta)) mean(is.na(m$meta$exp_acta)) else NA_real_
    tibble::tibble(sesion_id = m$meta$sesion_id, fecha = m$meta$fecha,
                   puntos_conv = m$meta$puntos_convocatoria, puntos_acta = m$meta$puntos_acta,
                   troceo_acta = m$meta$troceo_acta,
                   cruce_fiable = isFALSE(m$meta$cruce_fiable),
                   en_acta_sin_trocear = sum(pts$estado == "en_acta_sin_trocear"),
                   acta_sin_expediente = frac_sin_exp)
  }) |>
    dplyr::filter(
      troceo_acta != "numeracion" | cruce_fiable | puntos_acta < 0.8 * puntos_conv |
        en_acta_sin_trocear > 0 | (!is.na(acta_sin_expediente) & acta_sin_expediente > 0.3) |
        puntos_acta == 0)
  dup_fecha <- ind |>
    dplyr::filter(!is.na(fecha)) |>
    dplyr::group_by(fecha, tipo) |> dplyr::filter(dplyr::n() > 1) |>
    dplyr::ungroup() |>
    dplyr::select(fecha, tipo, sesion_id, estado_convocatoria, estado_acta, url) |>
    dplyr::arrange(fecha, sesion_id)
  ord <- ind |> dplyr::filter(!is.na(fecha), tipo == "ordinaria") |>
    dplyr::distinct(fecha) |> dplyr::arrange(fecha) |> dplyr::pull(fecha)
  huecos <- if (length(ord) > 1) {
    d <- as.Date(ord); dt <- as.integer(diff(d)); w <- which(dt > 21)
    tibble::tibble(desde = d[w], hasta = d[w + 1], dias = dt[w])
  } else tibble::tibble()

  cuerpo <- c("# Documentación que falta y anomalías",
              paste0("Desde ", desde, ". Se regenera en cada ejecución."),
              "", "## Resumen", "", tabla_a_md(resumen), "",
              "## Sesiones sin convocatoria", "",
              if (nrow(sin_conv)) tabla_a_md(sin_conv) else "Nada que señalar.", "",
              "## Sesiones sin acta", "",
              if (nrow(sin_acta)) tabla_a_md(sin_acta) else "Nada que señalar.", "",
              "## Documentos con problemas o pendientes", "",
              if (nrow(prob)) tabla_a_md(prob) else "Nada que señalar.", "",
              "## Anomalías de troceo (revisar el parser o el texto)", "",
              if (nrow(anom)) tabla_a_md(anom) else "Nada que señalar.", "",
              "## Fechas con más de una sesión en el índice (páginas duplicadas en la web: el análisis usa solo la que tiene más documentos)", "",
              if (nrow(dup_fecha)) tabla_a_md(dup_fecha) else "Nada que señalar.", "",
              "## Huecos de más de 21 días entre sesiones ordinarias (¿sesiones que no aparecen en el listado?)", "",
              if (nrow(huecos)) tabla_a_md(huecos) else "Nada que señalar.", "")
  escribir_md(file.path(cfg$base_dir, "faltantes.md"), list(), cuerpo)
}

# Análisis completo -------------------------------------------------------------

# Calcula las sesiones (parse + cruce + extracción). Es la parte lenta.
calcular_sesiones <- function(cfg, ind) {
  sesiones <- lapply(seq_len(nrow(ind)), function(i) {
    tryCatch(preparar_sesion(ind[i, ], cfg), error = function(e) {
      message("  AVISO: error analizando la sesión ", ind$fecha[i], ": ", conditionMessage(e))
      NULL
    })
  })
  names(sesiones) <- ind$sesion_id
  sesiones[!vapply(sesiones, is.null, logical(1))]
}

# Escribe tablas, sesiones y faltantes a partir de las sesiones ya calculadas.
volcar_analisis <- function(cfg, sesiones, ind_bruto, n_duplicadas = 0L,
                            descartadas_ids = character()) {
  t0 <- Sys.time()
  pts_list <- lapply(sesiones, function(m) {
    p <- m$puntos
    if (!nrow(p)) return(NULL)
    out <- p |> dplyr::select(-texto_extra, -bloque, -subbloque) |>
      dplyr::mutate(asunto = truncar_md(asunto))
    out$sesion_id <- m$meta$sesion_id
    out$fecha <- m$meta$fecha
    out$tipo_sesion <- m$meta$tipo_sesion
    out$origen_ocr <- (out$fuente_texto == "acta") & (m$meta$metodo_acta %in% c("ocr", "mixto"))
    out[, COLUMNS_PUNTOS]
  })
  pts <- dplyr::bind_rows(pts_list) |>
    dplyr::arrange(fecha, ifelse(is.na(n_conv), Inf, n_conv), ifelse(is.na(n_acta), Inf, n_acta))

  tablas <- purrr::map(sesiones, function(m) {
    base <- tibble::tibble(
      sesion_id = m$meta$sesion_id, fecha = m$meta$fecha,
      n_acta = m$puntos$n_acta, estado = m$puntos$estado,
      cruce_metodo = m$puntos$cruce_metodo, expediente = m$puntos$expediente,
      familia = m$puntos$familia, tipo = m$puntos$tipo,
      votacion = m$puntos$votacion,
      fuente_texto = m$puntos$fuente_texto,
      origen_ocr = (m$puntos$fuente_texto == "acta") & (m$meta$metodo_acta %in% c("ocr", "mixto")))
    if (!is.null(m$extra) && nrow(m$extra) == nrow(base)) dplyr::bind_cols(m$extra, base) else base
  })
  todo <- dplyr::bind_rows(tablas)
  if (!nrow(todo)) {
    todo <- as_tibble(setNames(rep(list(logical(0)), length(unique(c(
      COLUMNS_CONTRATOS, COLUMNS_SUBV, COLUMNS_JUDICIAL)))),
      unique(c(COLUMNS_CONTRATOS, COLUMNS_SUBV, COLUMNS_JUDICIAL))))
  }

  contratos <- todo |> dplyr::filter(familia %in% c("contratacion", "obras"))
  contratos <- contratos[, COLUMNS_CONTRATOS] |>
    dplyr::arrange(fecha, ifelse(is.na(n_acta), Inf, n_acta))
  subvenciones <- todo |> dplyr::filter(familia == "subvenciones")
  subvenciones <- subvenciones[, COLUMNS_SUBV] |>
    dplyr::arrange(fecha, ifelse(is.na(n_acta), Inf, n_acta))
  judicial <- todo |> dplyr::filter(familia == "judicial")
  judicial <- judicial[, COLUMNS_JUDICIAL] |>
    dplyr::arrange(fecha, ifelse(is.na(n_acta), Inf, n_acta))

  for (m in sesiones) escribir_sesion_md(m, cfg)
  .escribir_tabla_md(file.path(cfg$dir_analisis, "puntos.md"), pts, "puntos.md")
  .escribir_tabla_md(file.path(cfg$dir_analisis, "contratos.md"), contratos, "contratos.md")
  .escribir_tabla_md(file.path(cfg$dir_analisis, "subvenciones.md"), subvenciones, "subvenciones.md")
  .escribir_tabla_md(file.path(cfg$dir_analisis, "judicial.md"), judicial, "judicial.md")
  escribir_faltantes(cfg, ind_bruto, sesiones, n_duplicadas, descartadas_ids)

  message(sprintf("Análisis: %d sesiones (%d descartadas duplicadas), %d puntos, %d contratos, %d subvenciones, %d juzgados, %.1f s",
                  length(sesiones), n_duplicadas, nrow(pts), nrow(contratos),
                  nrow(subvenciones), nrow(judicial),
                  as.numeric(difftime(Sys.time(), t0, units = "secs"))))
  invisible(list(puntos = pts, contratos = contratos, subvenciones = subvenciones,
                 judicial = judicial, sesiones = sesiones))
}

escribir_analisis <- function(cfg = jgl_cfg()) {
  ind_bruto <- leer_indice(cfg)
  sel <- elegir_sesion(ind_bruto)
  ind <- sel$ind |>
    dplyr::filter(!is.na(fecha), fecha >= cfg$desde)
  n_duplicadas <- if (!is.null(sel$descartadas)) nrow(sel$descartadas) else 0L
  ids_descartadas <- if (!is.null(sel$descartadas)) sel$descartadas$sesion_id else character()
  sesiones <- calcular_sesiones(cfg, ind)
  volcar_analisis(cfg, sesiones, ind_bruto, n_duplicadas, ids_descartadas)
}

# Lectores ----------------------------------------------------------------------

cargar_puntos <- function(base_dir = "datos/jgl-rivas") {
  leer_tabla_md(file.path(base_dir, "analisis", "puntos.md"))
}

cargar_tabla <- function(nombre, base_dir = "datos/jgl-rivas") {
  leer_tabla_md(file.path(base_dir, "analisis", paste0(nombre, ".md")))
}
