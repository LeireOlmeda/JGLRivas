# descargar_y_texto.R ---------------------------------------------------------
# Descarga de PDFs y extracción de texto (pdftools; OCR con tesseract si hace falta).

nombre_doc <- function(fecha, tipo, sesion_id, ext = "pdf") {
  sprintf("%s_%s_%s.%s", fecha, tipo, sesion_id, ext)
}

ext_url <- function(url) {
  tolower(tools::file_ext(str_remove(url, "[?#].*$")))
}

# Descarga a un temporal y solo entonces mueve al destino (no deja ficheros a medias).
descargar_doc <- function(url, destino, cfg) {
  dir.create(dirname(destino), recursive = TRUE, showWarnings = FALSE)
  tmp <- tempfile(fileext = ".part")
  on.exit(unlink(tmp), add = TRUE)
  jgl_get(url, cfg, path = tmp)
  if (!file.exists(tmp) || file.size(tmp) == 0) stop("descarga vacía")
  if (ext_url(url) %in% c("pdf", "")) {
    cab <- readBin(tmp, "raw", 5)
    if (!identical(cab, charToRaw("%PDF-"))) stop("el fichero descargado no parece un PDF")
  }
  file.copy(tmp, destino, overwrite = TRUE)
  invisible(destino)
}

# Texto -----------------------------------------------------------------------

# Palabras castellanas muy frecuentes: se usan para detectar páginas de OCR
# ilegible (proporción de palabras comunes frente a basura).
palabras_comunes <- c("de", "la", "que", "el", "en", "y", "a", "los", "del", "se",
  "las", "por", "un", "para", "con", "no", "una", "su", "al", "es", "lo", "como",
  "mas", "más", "pero", "le", "ya", "o", "este", "sí", "si", "porque", "esta",
  "entre", "cuando", "muy", "sin", "sobre", "también", "también", "hasta", "hay",
  "donde", "quien", "desde", "todo", "nos", "durante", "todos", "uno", "les",
  "ni", "contra", "otros", "ese", "eso", "ante", "ellos", "e", "esto", "mí",
  "antes", "algunos", "qué", "unos", "yo", "otro", "otras", "otra", "él", "tanto",
  "esa", "estos", "mucho", "quienes", "nada", "muchos", "cual", "poco", "ella",
  "estar", "estas", "algunas", "algo", "mi", "ser", "sus", "the", "expediente",
  "ayuntamiento", "rivas", "vaciamadrid", "decreto", "aprobacion", "consejal")

ocr_motor <- function(cfg) {
  disp <- tesseract::tesseract_info()$available
  if (!cfg$ocr_lang %in% disp) {
    stop("Falta el idioma '", cfg$ocr_lang, "' de tesseract. Instálalo con ",
         "tesseract::tesseract_download('", cfg$ocr_lang, "').")
  }
  tesseract::tesseract(cfg$ocr_lang)
}

# Diagnóstico por página (tras quitar pies de firma electrónica):
diagnostico_paginas <- function(paginas, cfg) {
  bind_rows(lapply(paginas, function(p) {
    s <- paste(limpiar_texto(p), collapse = " ")
    chars <- nchar(str_replace_all(s, "\\s", ""))
    letras <- nchar(str_replace_all(s, "[^[:alpha:]]", ""))
    palabras <- length(str_extract_all(s, "[[:alpha:]]{3,}")[[1]])
    tok <- str_to_lower(str_extract_all(s, "[[:alpha:]]+")[[1]])
    frac_comunes <- if (length(tok)) mean(tok %in% palabras_comunes) else 0
    vacia <- chars < cfg$min_chars_pagina
    basura <- !vacia && ((letras / chars) < 0.6 || (palabras < 15 && chars < 300) ||
                         (length(tok) >= 40 && frac_comunes < 0.08))
    tibble(vacia = vacia, basura = basura)
  }))
}

# Páginas que necesitan OCR: las de texto roto y las vacías (escaneadas), salvo una ÚLTIMA página
# casi vacía en un documento cuyo resto tiene texto normal (la hoja de firma).
paginas_para_ocr <- function(paginas, cfg) {
  d <- diagnostico_paginas(paginas, cfg)
  ocr <- d$basura | d$vacia
  n <- nrow(d)
  if (n >= 2 && d$vacia[n] && mean(!d$vacia[-n] & !d$basura[-n]) >= 0.6) ocr[n] <- FALSE
  ocr
}

# Sobre un texto ya guardado: ¿hay que rehacerlo con OCR? (se ignora la última página, que puede ser
# solo la firma). Sí si el 20 % o más de las páginas es ilegible, o si la mitad no tiene texto útil.
texto_doc_sospechoso <- function(cuerpo, cfg) {
  pags <- str_split(cuerpo, "<!-- pagina \\d+ -->")[[1]][-1]
  if (!length(pags)) return(FALSE)
  d <- diagnostico_paginas(pags, cfg)
  if (nrow(d) >= 2) d <- d[-nrow(d), ]
  mean(d$basura) >= 0.2 || mean(d$vacia | d$basura) >= 0.5
}

# Devuelve list(paginas, metodo, n_ocr, ocr_hecho).
#   metodo: "texto" (capa de texto), "ocr" (todas las páginas) o "mixto".
#   Si permitir_ocr = FALSE y hacen falta páginas OCR, no se hace y ocr_hecho = FALSE.
extraer_texto_pdf <- function(pdf, cfg, permitir_ocr = TRUE) {
  pags <- pdftools::pdf_text(pdf)
  sin <- paginas_para_ocr(pags, cfg)
  if (!any(sin)) {
    return(list(paginas = pags, metodo = "texto", n_ocr = 0L, ocr_hecho = TRUE))
  }
  if (!permitir_ocr) {
    return(list(paginas = pags, metodo = NA_character_, n_ocr = sum(sin), ocr_hecho = FALSE))
  }
  motor <- ocr_motor(cfg)
  idx <- which(sin)
  for (k in seq_along(idx)) {
    p <- idx[k]
    message(sprintf("    OCR página %d de %d (p. %d del PDF)", k, length(idx), p))
    img <- tempfile(fileext = ".png")
    pdftools::pdf_convert(pdf, format = "png", pages = p, filenames = img,
                          dpi = cfg$dpi, verbose = FALSE)
    pags[p] <- paste(tesseract::ocr(img, engine = motor), collapse = "\n")
    unlink(img)
  }
  list(paginas = pags, metodo = if (all(sin)) "ocr" else "mixto",
       n_ocr = length(idx), ocr_hecho = TRUE)
}

guardar_texto_md <- function(ruta, r, front) {
  cuerpo <- unlist(lapply(seq_along(r$paginas), function(i) {
    c(sprintf("<!-- pagina %d -->", i), r$paginas[[i]], "")
  }))
  escribir_md(ruta, c(front, list(metodo = r$metodo, paginas = length(r$paginas),
                                  paginas_ocr = r$n_ocr)), cuerpo)
}

leer_texto_md <- function(cfg, rel) {
  leer_md_cuerpo(jgl_abs(cfg, rel))
}

# Para calibrar parsers: imprime el comienzo del texto extraído de un acta o una convocatoria.
muestra_documento <- function(sesion = NULL, documento = c("acta", "convocatoria"),
                              base_dir = "datos/jgl-rivas", n_chars = 3500, pagina = NULL) {
  documento <- match.arg(documento)
  cfg <- jgl_cfg(base_dir = base_dir)
  col <- paste0("txt_", documento)
  ind <- leer_indice(cfg) |>
    filter(!is.na(.data[[col]])) |>
    arrange(desc(fecha))
  if (!is.null(sesion)) ind <- filter(ind, fecha == as.character(sesion) | sesion_id == as.character(sesion))
  if (!nrow(ind)) stop("No hay ", documento, " con texto para esa sesión.")
  txt <- leer_texto_md(cfg, ind[[col]][1])
  if (!is.null(pagina)) {
    trozos <- str_split(txt, "<!-- pagina \\d+ -->")[[1]]
    txt <- trozos[pagina + 1]
  }
  cat(toupper(documento), " de ", ind$fecha[1], " (sesion ", ind$sesion_id[1], ", método: ",
      ind[[paste0("metodo_", documento)]][1], ")\n\n", sep = "")
  cat(str_sub(txt, 1, n_chars), "\n")
  invisible(txt)
}

muestra_acta <- function(sesion = NULL, ...) muestra_documento(sesion, "acta", ...)
muestra_convocatoria <- function(sesion = NULL, ...) muestra_documento(sesion, "convocatoria", ...)

# Enseña el fragmento del acta que rodea a un expediente (en todas las actas, o solo en una).
muestra_expediente <- function(exp, sesion = NULL, base_dir = "datos/jgl-rivas", n_chars = 1500) {
  cfg <- jgl_cfg(base_dir = base_dir)
  ind <- leer_indice(cfg) |> filter(!is.na(txt_acta))
  if (!is.null(sesion)) ind <- filter(ind, fecha == as.character(sesion) | sesion_id == as.character(sesion))
  if (!nrow(ind)) stop("No hay actas con texto para esa selección.")
  plano <- function(k) paste(limpiar_texto(leer_texto_md(cfg, ind$txt_acta[k])), collapse = " ")
  hallado <- FALSE
  for (k in seq_len(nrow(ind))) {
    v <- ventana_expediente(plano(k), exp, n_chars)
    if (!is.na(v)) {
      hallado <- TRUE
      cat("== ", ind$fecha[k], " (sesion ", ind$sesion_id[k], ", método ", ind$metodo_acta[k], ") ==\n", v, "\n\n", sep = "")
    }
  }
  if (!hallado) {
    num <- str_extract(exp, "^\\d+")
    message("No aparece '", exp, "' ni con variantes de OCR. Se busca solo el número ", num, ":")
    rx <- regex(paste(strsplit(num, "")[[1]], collapse = "[ .]?"))
    for (k in seq_len(nrow(ind))) {
      p <- plano(k)
      loc <- str_locate_all(p, rx)[[1]]
      if (nrow(loc)) {
        hallado <- TRUE
        cat("== ", ind$fecha[k], " (sesion ", ind$sesion_id[k], ", método ", ind$metodo_acta[k], ") ==\n", str_sub(p, max(1L, loc[1, 1] - 200L), loc[1, 2] + 400L), "\n\n", sep = "")
      }
    }
    if (!hallado) message("Tampoco aparece el número solo: el expediente no está en el texto de las actas (o el OCR lo estropeó mucho).")
  }
  invisible(NULL)
}

# Compara punto a punto la convocatoria y el acta de una sesión, tal como los ve el parser.
# Uso: muestra_puntos("2026-05-07", n = 10:17)   (n = números de punto; sin n, todos)
muestra_puntos <- function(sesion, n = NULL, chars = 500, base_dir = "datos/jgl-rivas") {
  cfg <- jgl_cfg(base_dir = base_dir)
  f <- leer_indice(cfg) |> filter(fecha == as.character(sesion) | sesion_id == as.character(sesion))
  if (!nrow(f)) stop("Sesión no encontrada en el índice.")
  f <- f[1, ]
  mostrar <- function(titulo, p) {
    if (!is.null(n)) p <- p[p$n %in% n, ]
    cat("\n=====", titulo, "(", nrow(p), "puntos mostrados ) =====\n")
    for (k in seq_len(nrow(p))) {
      cat(sprintf("[%s] bloque: %s | expediente: %s\n%s\n\n", p$n[k], p$bloque[k], p$expediente[k],
                  str_trunc(p$texto[k], chars)))
    }
  }
  if (!is.na(f$txt_convocatoria)) {
    mostrar("CONVOCATORIA", parse_convocatoria(leer_texto_md(cfg, f$txt_convocatoria))$puntos)
  }
  if (!is.na(f$txt_acta)) {
    pa <- parse_acta(leer_texto_md(cfg, f$txt_acta))
    mostrar(paste0("ACTA (troceo: ", pa$troceo, ")"), pa$puntos)
  }
  invisible(NULL)
}
