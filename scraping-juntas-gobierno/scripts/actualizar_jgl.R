# actualizar_jgl.R --------------------------------------------------------------
# Punto de entrada de la skill. Carga todos los scripts y ofrece:
#   actualizar_jgl(...)          → ejecución incremental completa (o por etapas)
#   rehacer_texto(...)           → descarta el texto de UN documento para rehacerlo
#   estado_indice()              → resumen de estados (en utils.R)
#   restaurar_datos(...)         → descarga un snapshot de datos desde un release
#
# Carga (portable, sin rutas fijas):
#   options(jgl.scripts_dir = "<ruta a los scripts de la skill>")   # opcional
#   source(file.path(getOption("jgl.scripts_dir", "scraping-juntas-gobierno/scripts"),
#                    "actualizar_jgl.R"), encoding = "UTF-8")

.jgl_dir_scripts <- function() {
  d <- getOption("jgl.scripts_dir")
  if (!is.null(d) && file.exists(file.path(d, "utils.R"))) return(normalizePath(d))
  cand <- c("scraping-juntas-gobierno/scripts",
            ".posit/assistant/skills/scraping-juntas-gobierno/scripts",
            "scripts")
  for (c in cand) if (file.exists(file.path(c, "utils.R"))) return(normalizePath(c))
  stop("No encuentro los scripts de la skill. Usa options(jgl.scripts_dir = '<carpeta de scripts>').")
}

jgl_cargar_scripts <- function(dir) {
  for (f in c("utils.R", "puntos.R", "descargar_y_texto.R", "adaptador_rivas_jgl.R",
              "cruce.R", "extraer.R", "analisis.R", "consultas.R")) {
    source(file.path(dir, f), encoding = "UTF-8")
  }
  invisible(TRUE)
}

jgl_cargar_scripts(.jgl_dir_scripts())

# restaurar_datos ---------------------------------------------------------------
# La fuente de los datos es la web del ayuntamiento. El snapshot de GitHub solo
# sirve para reactivar la skill sin redescargar los PDFs (p. ej. tras un clone).
#   restaurar_datos(url_zip)  # zip de datos publicado en el release del repositorio

restaurar_datos <- function(url_zip = getOption("jgl.zip_datos"), base_dir = "datos") {
  if (is.null(url_zip) || !nzchar(url_zip))
    stop("Indica la URL del zip de datos: restaurar_datos('https://github.com/<usuario>/<repo>/releases/download/...') ",
         "o options(jgl.zip_datos = '...').")
  destino <- tempfile(fileext = ".zip")
  message("Descargando snapshot de datos desde ", url_zip, " ...")
  utils::download.file(url_zip, destino, mode = "wb", quiet = TRUE)
  unzip(destino, exdir = base_dir)
  unlink(destino)
  if (!file.exists(file.path(base_dir, "jgl-rivas", "indice.csv")))
    stop("El zip no contiene jgl-rivas/indice.csv; comprueba el contenido del release.")
  message("Datos restaurados en ", file.path(base_dir, "jgl-rivas"))
  invisible(TRUE)
}

# Actualización principal ---------------------------------------------------------

actualizar_jgl <- function(desde = NULL, max_ocr = NULL,
                           etapas = c("listado", "descarga", "texto", "analisis"),
                           modo_listado = c("auto", "paginas", "anios"),
                           revisar_todas = FALSE, base_dir = NULL, url_listado = NULL,
                           user_agent = NULL, forzar = FALSE) {
  modo_listado <- match.arg(modo_listado)
  etapas <- match.arg(etapas, several.ok = TRUE)
  if (!is.logical(forzar) && !identical(forzar, "descarga"))
    stop("forzar debe ser FALSE, TRUE o 'descarga'.")
  old <- jgl_cfg()
  cfg <- jgl_cfg(
    base_dir = base_dir %||% old$base_dir,
    url_listado = url_listado %||% old$url_listado,
    desde = desde %||% old$desde,
    max_ocr = max_ocr %||% old$max_ocr,
    user_agent = user_agent %||% old$user_agent)
  jgl_crear_dirs(cfg)
  ind <- leer_indice(cfg)
  ahora <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

  # --- etapa 1: listado -----------------------------------------------------------
  if ("listado" %in% etapas) {
    message("Etapa 1 (listado): recorriendo el listado de sesiones ...")
    ses <- listar_sesiones(cfg, modo = modo_listado)
    # el índice empieza en el año configurado: las sesiones anteriores no se registran
    ses <- ses |> dplyr::filter(!is.na(fecha), fecha >= cfg$desde)
    por_anio <- ses |> dplyr::mutate(anio = format(fecha, "%Y")) |>
      dplyr::count(anio) |> dplyr::arrange(anio)
    message("  Encontradas ", nrow(ses), " sesiones desde ", cfg$desde, " (",
            paste0(por_anio$anio, ": ", por_anio$n, collapse = ", "), ").")
    if (nrow(ses) == 0) {
      message("  ATENCIÓN: 0 sesiones. La web cambió de estructura o el listado no se paginó; ")
      message("  ejecuta diagnostico_listado() y detén la actualización si sigue sin funcionar.")
    }
    for (i in seq_len(nrow(ses))) {
      s <- ses[i, ]
      prev <- ind |> dplyr::filter(sesion_id == s$sesion_id)
      if (nrow(prev)) {
        if (prev$fecha[1] != format(s$fecha) || prev$titulo[1] != s$titulo ||
            prev$tipo[1] != s$tipo || prev$url[1] != s$url) {
          ind <- indice_upsert(ind, prev |>
            dplyr::mutate(fecha = format(s$fecha), titulo = s$titulo, tipo = s$tipo, url = s$url))
        }
      } else {
        fila <- fila_vacia()
        fila$sesion_id <- s$sesion_id; fila$fecha <- format(s$fecha)
        fila$titulo <- s$titulo; fila$tipo <- s$tipo; fila$url <- s$url
        fila$estado_convocatoria <- NA_character_
        fila$estado_acta <- NA_character_
        ind <- indice_upsert(ind, fila)
      }
    }
    ind <- guardar_indice(cfg, ind)
  }

  # --- etapa 2: visita de páginas de sesión y descarga de documentos ---------------
  if ("descarga" %in% etapas) {
    message("Etapa 2 (descarga): visitando sesiones y descargando documentos ...")
    ind <- leer_indice(cfg)
    for (i in seq_len(nrow(ind))) {
      r <- ind[i, ]
      if (is.na(r$fecha) || r$fecha < format(cfg$desde)) next
      hay_falta <- any(!is.na(r$estado_convocatoria) & r$estado_convocatoria == "falta",
                       !is.na(r$estado_acta) & r$estado_acta == "falta")
      falta_pendiente <- any(!is.na(r$estado_convocatoria) & r$estado_convocatoria == "pendiente",
                             !is.na(r$estado_acta) & r$estado_acta == "pendiente")
      sin_visitar <- is.na(r$visitada) || !nzchar(r$visitada %||% "")
      revisitar <- hay_falta && !sin_visitar &&
        difftime(Sys.Date(), as.Date(r$visitada), units = "days") >= cfg$revisitar_dias
      if (!(sin_visitar || revisitar || revisar_todas || falta_pendiente)) next

      v <- tryCatch(visitar_sesion(r$url, cfg), error = function(e) {
        message("  error visitando ", r$fecha, ": ", conditionMessage(e))
        NULL
      })
      if (is.null(v)) { ind[i, "notas"] <- anotar(r$notas, "error visitando la página de la sesión"); next }
      if (v$nivel == "pagina")
        ind[i, "notas"] <- anotar(ind[i, "notas"], "bloque de documentos no encontrado; leída la página entera")
      ind$asistentes[i] <- v$asistentes
      ind$modificado_web[i] <- v$modificado_web
      ndocs <- v$docs |> dplyr::filter(!is.na(doc))
      conv <- ndocs |> dplyr::filter(doc == "convocatoria"); act <- ndocs |> dplyr::filter(doc == "acta")
      otros <- ndocs |> dplyr::filter(is.na(doc))
      url_conv <- if (nrow(conv)) conv$url[1] else NA_character_
      url_acta <- if (nrow(act)) act$url[1] else NA_character_
      otros_docs <- if (nrow(otros)) paste(otros$url, collapse = " | ") else NA_character_

      actualizar_doc <- function(doc, url_nueva, col_url) {
        estado_col <- paste0("estado_", doc)
        actual <- ind[i, estado_col][[1]]
        if (identical(forzar, "descarga") || is.na(actual) ||
            actual %in% c("falta", "pendiente", "enlace_roto", "error", "formato_no_pdf")) {
          ind[[col_url]][i] <- url_nueva
          if (is.na(url_nueva)) {
            if (is.na(actual) || actual %in% c(NA_character_, "pendiente")) ind[i, estado_col][[1]] <- "falta"
          } else {
            pdf_rel <- file.path("pdf", format(as.Date(ind$fecha[i]), "%Y"),
                                 nombre_doc(ind$fecha[i], doc, ind$sesion_id[i], "pdf"))
            existe <- file.exists(jgl_abs(cfg, pdf_rel))
            if (existe) ind[[paste0("pdf_", doc)]][i] <- pdf_rel
            ind[i, estado_col][[1]] <- if (existe) "descargado" else "pendiente"
          }
        }
      }
      actualizar_doc("convocatoria", url_conv, "url_convocatoria")
      actualizar_doc("acta", url_acta, "url_acta")
      ind$otros_docs[i] <- otros_docs
      ind$visitada[i] <- ahora
      ind <- guardar_indice(cfg, ind)
    }

    # descarga de lo pendiente
    ind <- leer_indice(cfg)
    for (doc in c("convocatoria", "acta")) {
      col_est <- paste0("estado_", doc); col_url <- paste0("url_", doc); col_pdf <- paste0("pdf_", doc)
      pend <- which(ind[[col_est]] %in% c("pendiente") |
                    (identical(forzar, "descarga") && ind[[col_est]] %in% c("enlace_roto", "error", "formato_no_pdf")))
      for (i in pend) {
        r <- ind[i, ]
        destino_pdf <- file.path("pdf", format(as.Date(r$fecha), "%Y"),
                                 nombre_doc(r$fecha, doc, r$sesion_id, "pdf"))
        res <- tryCatch(descargar_doc(r[[col_url]], jgl_abs(cfg, destino_pdf), cfg),
                        error = function(e) e)
        if (inherits(res, "error")) {
          msg <- conditionMessage(res)
          estado <- if (grepl("404|Not Found", msg)) "enlace_roto"
                    else if (grepl("no parece un PDF", msg)) "formato_no_pdf"
                    else "error"
          ind[i, col_est][[1]] <- estado
          ind$notas[i] <- anotar(ind$notas[i], paste0(doc, ": ", msg, "."))
        } else {
          ind[[col_pdf]][i] <- destino_pdf
          ind[i, col_est][[1]] <- "descargado"
        }
        ind <- guardar_indice(cfg, ind)
      }
    }
    message("  Descarga terminada.")
  }

  # --- etapa 3: texto (extracción + OCR con presupuesto) ----------------------------
  if ("texto" %in% etapas) {
    message("Etapa 3 (texto): extrayendo texto de los PDF descargados ...")
    ind <- leer_indice(cfg)
    # OCR necesario: reexamina también textos sospechosos de material nuevo
    for (doc in c("convocatoria", "acta")) {
      col_est <- paste0("estado_", doc); col_txt <- paste0("txt_", doc)
      col_met <- paste0("metodo_", doc); col_pdf <- paste0("pdf_", doc)
      pendientes <- which(ind[[col_est]] == "descargado")
      for (i in pendientes) {
        r <- ind[i, ]
        pdf_abs <- jgl_abs(cfg, r[[col_pdf]])
        r2 <- tryCatch(extraer_texto_pdf(pdf_abs, cfg, permitir_ocr = FALSE), error = function(e) e)
        if (inherits(r2, "error")) {
          ind[i, col_est][[1]] <- "error"
          ind$notas[i] <- anotar(ind$notas[i], paste0(doc, ": ", conditionMessage(r2), "."))
          ind <- guardar_indice(cfg, ind)
          next
        }
        if (!r2$ocr_hecho) {
          ind[i, col_est][[1]] <- "ocr_pendiente"
        } else {
          rel <- file.path("texto", paste0(tools::file_path_sans_ext(basename(pdf_abs)), ".md"))
          front <- list(sesion_id = r$sesion_id, fecha = r$fecha, documento = doc,
                        fuente_pdf = r[[col_pdf]])
          guardar_texto_md(jgl_abs(cfg, rel), r2, front)
          ind[[col_txt]][i] <- rel
          ind[[col_met]][i] <- r2$metodo
          ind[i, col_est][[1]] <- "ok"
        }
        ind <- guardar_indice(cfg, ind)
      }

      budget <- cfg$max_ocr
      col_ocr <- which(ind[[col_est]] == "ocr_pendiente")
      # también: textos previos sospechosos con capa de texto original
      sospechosos <- which(ind[[col_est]] == "ok" & ind[[col_met]] == "texto" & !is.na(ind[[col_txt]]))
      for (i in sospechosos) {
        cuerpo <- tryCatch(leer_md_cuerpo(jgl_abs(cfg, ind[[col_txt]][i])), error = function(e) "")
        if (nzchar(cuerpo) && texto_doc_sospechoso(cuerpo, cfg)) {
          ind[i, col_est][[1]] <- "ocr_pendiente"
          ind$notas[i] <- anotar(ind$notas[i], paste0(doc, ": texto sospechoso, se rehace con OCR"))
        }
      }
      col_ocr <- which(ind[[col_est]] == "ocr_pendiente")
      col_ocr <- col_ocr[order(ind$fecha[col_ocr], decreasing = TRUE)]
      if (length(col_ocr)) {
        if (identical(budget, Inf) || is.infinite(budget)) budget <- length(col_ocr)
        if (budget == 0) {
          message(sprintf("  %d documentos necesitan OCR; presupuesto max_ocr = 0, quedan para la siguiente ejecución.", length(col_ocr)))
        }
        for (i in head(col_ocr, budget)) {
          r <- ind[i, ]
          pdf_abs <- jgl_abs(cfg, r[[col_pdf]])
          r2 <- tryCatch(extraer_texto_pdf(pdf_abs, cfg, permitir_ocr = TRUE), error = function(e) e)
          if (inherits(r2, "error")) {
            ind$notas[i] <- anotar(ind$notas[i], paste0(doc, ": OCR fallido: ", conditionMessage(r2)))
            ind <- guardar_indice(cfg, ind)
            next
          }
          rel <- file.path("texto", paste0(tools::file_path_sans_ext(basename(pdf_abs)), ".md"))
          front <- list(sesion_id = r$sesion_id, fecha = r$fecha, documento = doc,
                        fuente_pdf = r[[col_pdf]])
          guardar_texto_md(jgl_abs(cfg, rel), r2, front)
          ind[[col_txt]][i] <- rel
          ind[[col_met]][i] <- r2$metodo
          ind[i, col_est][[1]] <- "ok"
          ind <- guardar_indice(cfg, ind)
        }
        quedan <- sum(ind[[col_est]] == "ocr_pendiente")
        if (quedan > 0) message("  OCR pendiente para la siguiente ejecución: ", quedan, " documentos.")
      }
    }
  }

  # --- etapa 4: análisis -------------------------------------------------------------
  if ("analisis" %in% etapas) {
    message("Etapa 4 (análisis): parse, cruce y tablas ...")
    escribir_analisis(cfg)
  }

  invisible(readr::read_csv(cfg$indice, col_types = readr::cols(.default = readr::col_character()),
                            progress = FALSE))
}

# Rehacer un texto -----------------------------------------------------------------

# Descarta el texto de UN documento para que la siguiente ejecución lo rehaga
# (con OCR si la página lo requiere). Ej.: rehacer_texto("862600256741", "convocatoria")
rehacer_texto <- function(sesion_id, documento = c("convocatoria", "acta"), base_dir = "datos/jgl-rivas") {
  documento <- match.arg(documento)
  cfg <- jgl_cfg(base_dir = base_dir)
  ind <- leer_indice(cfg)
  i <- which(ind$sesion_id == sesion_id)
  if (!length(i)) stop("No hay ninguna sesión con sesion_id ", sesion_id)
  i <- i[1]
  col_txt <- paste0("txt_", documento)
  col_met <- paste0("metodo_", documento)
  col_est <- paste0("estado_", documento)
  if (!is.na(ind[[col_txt]][i])) unlink(jgl_abs(cfg, ind[[col_txt]][i]))
  ind[[col_txt]][i] <- NA_character_
  ind[[col_met]][i] <- NA_character_
  ind[i, col_est][[1]] <- if (!is.na(ind[[paste0("pdf_", documento)]][i])) "descargado" else "pendiente"
  guardar_indice(cfg, ind)
  message("Texto de ", documento, " de la sesión ", sesion_id, " descartado; se rehará en la siguiente ejecución.")
  invisible(TRUE)
}
