# utils.R ---------------------------------------------------------------------
# Configuración, HTTP educado, índice de sesiones y lectura/escritura de .md
# Cargar siempre con source(..., encoding = "UTF-8").

suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
  library(purrr)
  library(tibble)
  library(readr)
})

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || is.na(a[1])) b else a

# Configuración ---------------------------------------------------------------

jgl_cfg <- function(base_dir = "datos/jgl-rivas",
                    url_listado = "https://www.rivasciudad.es/ayuntamiento/organizacion/junta-de-gobierno-local/sesiones-de-la-junta/",
                    desde = 2023,
                    pausa = c(1, 2.5),
                    dpi = 300,
                    ocr_lang = "spa",
                    min_chars_pagina = 80,
                    max_ocr = 20,
                    revisitar_dias = 3,
                    respetar_robots = TRUE,
                    user_agent = "jgl-analisis-transparencia (R; contacto: PON-AQUI-TU-EMAIL)") {
  if (!inherits(desde, "Date")) desde <- as.Date(paste0(desde, "-01-01"))
  list(
    base_dir = base_dir,
    url_listado = url_listado,
    desde = desde,
    pausa = pausa,
    dpi = dpi,
    ocr_lang = ocr_lang,
    min_chars_pagina = min_chars_pagina,
    max_ocr = max_ocr,
    revisitar_dias = revisitar_dias,
    respetar_robots = respetar_robots,
    user_agent = user_agent,
    indice = file.path(base_dir, "indice.csv"),
    dir_pdf = file.path(base_dir, "pdf"),
    dir_texto = file.path(base_dir, "texto"),
    dir_sesiones = file.path(base_dir, "sesiones"),
    dir_analisis = file.path(base_dir, "analisis")
  )
}

jgl_crear_dirs <- function(cfg) {
  for (d in c(cfg$base_dir, cfg$dir_pdf, cfg$dir_texto, cfg$dir_sesiones, cfg$dir_analisis)) {
    dir.create(d, recursive = TRUE, showWarnings = FALSE)
  }
  invisible(cfg)
}

# Ruta absoluta a partir de una ruta relativa a base_dir (las del índice).
jgl_abs <- function(cfg, rel) {
  ifelse(is.na(rel) | !nzchar(rel), NA_character_, file.path(cfg$base_dir, rel))
}

# Texto ----------------------------------------------------------------------

# Normaliza para comparar: minúsculas, sin acentos, sin signos.
norm_txt <- function(x) {
  x <- as.character(x)
  x <- stringi::stri_trans_general(x, "Latin-ASCII")
  x <- str_to_lower(x)
  x <- str_replace_all(x, "[^a-z0-9/ ]", " ")
  str_squish(x)
}

meses_es <- c(enero = 1, febrero = 2, marzo = 3, abril = 4, mayo = 5, junio = 6,
              julio = 7, agosto = 8, septiembre = 9, setiembre = 9, octubre = 10,
              noviembre = 11, diciembre = 12)

# "28 de octubre de 2026" -> Date
parse_fecha_es <- function(x) {
  m <- str_match(str_to_lower(x), "(\\d{1,2})\\s+de\\s+([[:alpha:]]+)\\s+de\\s+(\\d{4})")
  mes <- unname(meses_es[m[, 3]])
  iso <- ifelse(is.na(mes) | is.na(m[, 2]) | is.na(m[, 4]), NA_character_,
                sprintf("%s-%02d-%02d", m[, 4], as.integer(mes), as.integer(m[, 2])))
  as.Date(iso)
}

# HTTP educado ---------------------------------------------------------------

.jgl_env <- new.env(parent = emptyenv())

jgl_robots_permite <- function(url, cfg) {
  p <- httr2::url_parse(url)
  key <- paste0("robots_", p$hostname)
  if (is.null(.jgl_env[[key]])) {
    robots_url <- paste0(p$scheme, "://", p$hostname, "/robots.txt")
    txt <- tryCatch(
      httr2::resp_body_string(jgl_get(robots_url, cfg, comprobar_robots = FALSE)),
      error = function(e) NA_character_
    )
    dis <- character()
    if (is.na(txt)) {
      warning("No se pudo leer robots.txt de ", p$hostname, "; se continúa con precaución.")
    } else {
      l <- str_trim(str_split(txt, "\r?\n")[[1]])
      l <- l[!str_detect(l, "^#")]
      en_estrella <- FALSE
      for (x in l) {
        if (str_detect(x, regex("^user-agent:", ignore_case = TRUE))) {
          en_estrella <- str_detect(x, regex("^user-agent:\\s*\\*\\s*$", ignore_case = TRUE))
        } else if (en_estrella && str_detect(x, regex("^disallow:", ignore_case = TRUE))) {
          d <- str_trim(str_remove(x, regex("^disallow:", ignore_case = TRUE)))
          if (nzchar(d) && !str_detect(d, "\\*")) dis <- c(dis, d)  # se ignoran reglas con comodín
        }
      }
    }
    .jgl_env[[key]] <- dis
  }
  ruta <- p$path
  if (is.null(ruta) || !nzchar(ruta)) ruta <- "/"
  !any(startsWith(ruta, .jgl_env[[key]]))
}

jgl_get <- function(url, cfg, path = NULL, comprobar_robots = TRUE) {
  if (comprobar_robots && isTRUE(cfg$respetar_robots) && !jgl_robots_permite(url, cfg)) {
    stop("robots.txt no permite acceder a: ", url)
  }
  Sys.sleep(runif(1, cfg$pausa[1], cfg$pausa[2]))
  req <- httr2::request(url) |>
    httr2::req_user_agent(cfg$user_agent) |>
    httr2::req_timeout(60) |>
    httr2::req_retry(max_tries = 3, backoff = function(i) 5)
  if (is.null(path)) httr2::req_perform(req) else httr2::req_perform(req, path = path)
}

jgl_html <- function(url, cfg) {
  resp <- jgl_get(url, cfg)
  xml2::read_html(httr2::resp_body_string(resp, encoding = "UTF-8"))
}

# Índice ---------------------------------------------------------------------
# Una fila por sesión. Estados de documento (estado_convocatoria / estado_acta):
#   falta          la página de la sesión no enlaza el documento
#   pendiente      hay enlace, aún sin descargar
#   descargado     PDF descargado, sin texto todavía
#   ocr_pendiente  PDF escaneado; falta OCR (se hace en la siguiente ejecución)
#   ok             PDF descargado y texto extraído
#   formato_no_pdf el documento no es PDF
#   enlace_roto    la web enlaza el documento pero da 404 (no se reintenta salvo forzar = "descarga")
#   error          fallo (ver columna notas)

indice_cols <- c("sesion_id", "fecha", "titulo", "tipo", "url", "modificado_web", "visitada",
                 "asistentes", "url_convocatoria", "url_acta", "otros_docs",
                 "pdf_convocatoria", "pdf_acta", "txt_convocatoria", "txt_acta",
                 "metodo_convocatoria", "metodo_acta",
                 "estado_convocatoria", "estado_acta", "notas")

indice_vacio <- function() {
  as_tibble(setNames(rep(list(character()), length(indice_cols)), indice_cols))
}

# Una fila con todas las columnas del índice en NA.
fila_vacia <- function() {
  as_tibble(setNames(rep(list(NA_character_), length(indice_cols)), indice_cols))
}

leer_indice <- function(cfg) {
  if (!file.exists(cfg$indice)) return(indice_vacio())
  ind <- read_csv(cfg$indice, col_types = cols(.default = col_character()), na = c("", "NA"),
                  progress = FALSE)
  for (c in setdiff(indice_cols, names(ind))) ind[[c]] <- NA_character_
  ind[, indice_cols]
}

guardar_indice <- function(cfg, indice) {
  indice <- indice |> mutate(across(everything(), as.character)) |> arrange(desc(fecha), sesion_id)
  write_csv(indice, cfg$indice, na = "")
  invisible(indice)
}

indice_upsert <- function(indice, fila) {
  fila <- fila |> mutate(across(everything(), as.character))
  indice |>
    filter(sesion_id != fila$sesion_id) |>
    bind_rows(fila[, indice_cols])
}

anotar <- function(notas, nuevo) {
  if (is.na(nuevo) || !nzchar(nuevo)) return(notas)
  if (is.na(notas) || !nzchar(notas)) return(nuevo)
  if (str_detect(notas, fixed(nuevo))) return(notas)
  paste(notas, nuevo, sep = " | ")
}

# Markdown --------------------------------------------------------------------

md_celda <- function(x) {
  x <- as.character(x)
  x[is.na(x)] <- ""
  x <- str_replace_all(x, "\\s*[\r\n]+\\s*", " ")
  str_replace_all(x, "\\|", "\\\\|")
}

tabla_a_md <- function(df) {
  cab <- paste0("| ", paste(names(df), collapse = " | "), " |")
  sep <- paste0("|", paste(rep(" --- |", ncol(df)), collapse = ""))
  if (nrow(df) == 0) return(c(cab, sep))
  celdas <- lapply(df, md_celda)
  filas <- paste0("| ", do.call(paste, c(unname(celdas), sep = " | ")), " |")
  c(cab, sep, filas)
}

yaml_val <- function(v) {
  if (is.null(v) || length(v) == 0) return("null")
  v <- v[[1]]
  if (is.na(v)) return("null")
  if (is.numeric(v) || is.logical(v)) return(tolower(as.character(v)))
  paste0('"', str_replace_all(as.character(v), '(["\\\\])', "\\\\\\1"), '"')
}

escribir_md <- function(path, front = list(), cuerpo = character()) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  fm <- if (length(front)) {
    c("---", paste0(names(front), ": ", vapply(front, yaml_val, character(1))), "---", "")
  } else character()
  writeLines(enc2utf8(c(fm, cuerpo)), path, useBytes = TRUE)
  invisible(path)
}

# Devuelve el cuerpo de un .md sin el frontmatter, como un único texto.
leer_md_cuerpo <- function(path) {
  l <- readLines(path, warn = FALSE, encoding = "UTF-8")
  if (length(l) && l[1] == "---") {
    cierre <- which(l == "---")[2]
    if (!is.na(cierre)) l <- l[-seq_len(cierre)]
  }
  paste(l, collapse = "\n")
}

# Lee la primera tabla markdown de un fichero y devuelve un tibble.
leer_tabla_md <- function(path) {
  l <- readLines(path, warn = FALSE, encoding = "UTF-8")
  t <- l[str_detect(l, "^\\|")]
  if (length(t) < 2) return(tibble())
  trocear <- function(x) {
    x <- str_remove(x, "^\\|")
    x <- str_remove(x, "\\|\\s*$")
    p <- str_split(x, "(?<!\\\\)\\|")[[1]]
    str_replace_all(str_trim(p), "\\\\\\|", "|")
  }
  filas <- map(t, trocear)
  cab <- filas[[1]]
  datos <- filas[-c(1, 2)]
  if (!length(datos)) return(as_tibble(setNames(rep(list(character()), length(cab)), cab)))
  m <- do.call(rbind, lapply(datos, function(f) { length(f) <- length(cab); f }))
  colnames(m) <- cab
  df <- as_tibble(m)
  suppressMessages(type_convert(df, na = c("", "NA")))
}

# Lee y une todas las tablas .md de una carpeta (añade la columna `archivo`).
leer_tablas_md <- function(dir, patron = "\\.md$") {
  fs <- list.files(dir, pattern = patron, full.names = TRUE)
  map_dfr(fs, function(f) {
    t <- leer_tabla_md(f)
    if (nrow(t)) t$archivo <- basename(f)
    t
  })
}

# Resumen rápido del estado de los documentos: cuántos hay en cada estado.
estado_indice <- function(base_dir = "datos/jgl-rivas") {
  ind <- leer_indice(jgl_cfg(base_dir = base_dir))
  bind_rows(
    count(ind, documento = "acta", estado = estado_acta),
    count(ind, documento = "convocatoria", estado = estado_convocatoria)
  ) |> arrange(documento, desc(n))
}

# Trunca un texto para las tablas markdown con puntos suspensivos.
truncar_md <- function(x, n = 250) {
  x <- as.character(x)
  out <- ifelse(is.na(x) | nchar(x) <= n, x, paste0(str_sub(x, 1, n - 3), "..."))
  out
}
