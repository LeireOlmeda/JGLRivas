# adaptador_rivas_jgl.R --------------------------------------------------------
# Todo lo que depende de la estructura concreta de rivasciudad.es.
# Si la web cambia, se corrige aquí y solo aquí (ver references/adaptador-rivas-jgl.md
# y references/registro_exploracion_rivas.md).
#
# Listado: HTML renderizado en servidor (FacetWP), 20 sesiones por página.
#   - Paginación: ?fwp_paged=N ; filtro por año: ?fwp_year=AAAA (combinables).
#   - Cada sesión es un <h2> enlazado a /evento/<categoría>/AAAA/MM/DD/.../<id>/
#   - La fecha se toma del TÍTULO (no del path, que es la fecha de publicación, ni del
#     campo "Fecha inicio" de la ficha, que no es fiable).
# Página de una sesión: los documentos están en div.m4p-event-inscripcion; los PDF
#   están en /wp-content/uploads/AAAA/MM/ con nombres no predecibles: se LEEN del HTML,
#   nunca se construyen.

# Listado ----------------------------------------------------------------------

.jgl_listado_url <- function(url_listado, pagina = NULL, anio = NULL) {
  pargs <- NULL
  if (!is.null(anio)) pargs <- c(pargs, paste0("fwp_year=", anio))
  if (!is.null(pagina) && pagina > 1) pargs <- c(pargs, paste0("fwp_paged=", pagina))
  if (is.null(pargs)) url_listado else paste0(url_listado, "?", paste(pargs, collapse = "&"))
}

# Lee un HTML del listado y devuelve las sesiones (solo Juntas de Gobierno).
extraer_sesiones_html <- function(html, url_pagina) {
  nodos <- rvest::html_elements(html, "h2 a")
  if (!length(nodos)) return(tibble::tibble(sesion_id = character(), fecha = as.Date(character()),
                                            titulo = character(), tipo = character(), url = character()))
  purrr::map_dfr(seq_along(nodos), function(i) {
    titulo <- str_squish(rvest::html_text2(nodos[[i]]))
    href <- rvest::html_attr(nodos[[i]], "href")
    if (is.na(href) || !nzchar(titulo)) return(NULL)
    tn <- norm_txt(titulo)
    if (!str_detect(tn, "junta de gobierno")) return(NULL)   # descarta plenos y agenda
    # URL absoluta
    up <- httr2::url_parse(href)
    if (is.null(up$scheme)) {
      base <- httr2::url_parse(url_pagina)
      href <- paste0(base$scheme, "://", base$hostname,
                     ifelse(startsWith(href, "/"), "", "/"), href)
    }
    # id: último segmento numérico largo de la URL
    id <- str_match(href, "/([0-9]{6,})/?$")[, 2]
    if (is.na(id)) return(NULL)
    # fecha: del título ("Junta de Gobierno Local de 19 de enero de 2023").
    fecha <- parse_fecha_es(titulo)
    # respaldo: fecha del path (es la de publicación, puede diferir)
    mp <- str_match(href, "/(20\\d{2})/(\\d{1,2})/(\\d{1,2})/")
    fecha_path <- if (is.na(mp[1, 1])) NA else as.Date(sprintf("%s-%02d-%02d", mp[,2], as.integer(mp[,3]), as.integer(mp[,4])))
    if (is.na(fecha)) fecha <- fecha_path
    if (is.na(fecha)) return(NULL)
    tipo <- if (str_detect(tn, "extraordinaria|constitutiva")) "extraordinaria" else "ordinaria"
    tibble::tibble(sesion_id = id, fecha = fecha, fecha_path = fecha_path,
                   titulo = titulo, tipo = tipo, url = href)
  })
}

# Recorre el listado y devuelve todas las sesiones desde cfg$desde.
listar_sesiones <- function(cfg, modo = c("auto", "paginas", "anios")) {
  modo <- match.arg(modo)
  res_paginas <- function(pag_from = 1, anio = NULL) {
    out <- list()
    vistos <- character()
    pag <- pag_from
    while (pag <= 80) {
      url <- .jgl_listado_url(cfg$url_listado, pagina = pag, anio = anio)
      s <- tryCatch(extraer_sesiones_html(jgl_html(url, cfg), url), error = function(e) NULL)
      if (is.null(s) || !nrow(s)) return(dplyr::bind_rows(out))
      nuevos <- s[!s$sesion_id %in% vistos, , drop = FALSE]
      if (!nrow(nuevos)) return(dplyr::bind_rows(out))     # la página repite contenido
      vistos <- c(vistos, nuevos$sesion_id)
      out[[pag]] <- nuevos
      if (min(nuevos$fecha) < cfg$desde) return(dplyr::bind_rows(out))
      pag <- pag + 1
    }
    dplyr::bind_rows(out)
  }
  por_anios <- function() {
    anios <- seq(Sys.Date() |> format("%Y") |> as.integer(), as.integer(format(cfg$desde, "%Y")))
    dplyr::bind_rows(lapply(anios, function(a) res_paginas(1, anio = a)))
  }
  ses <- switch(modo,
    paginas = res_paginas(),
    anios   = por_anios(),
    auto    = { s <- res_paginas()
                if (min(c(s$fecha, as.Date(NA)), na.rm = TRUE) > cfg$desde) s <- dplyr::bind_rows(s, por_anios())
                s }
  )
  # Control de cobertura: una página que falla no puede dejar un año entero fuera del
  # índice. Si falta un año, se reintenta con el filtro por año; si sigue faltando, se
  # detiene la ejecución en vez de guardar un índice incompleto.
  anios <- seq(as.integer(format(cfg$desde, "%Y")), as.integer(format(Sys.Date(), "%Y")))
  presentes <- function(x) unique(as.integer(format(x$fecha, "%Y")))
  for (a in setdiff(anios, presentes(ses))) {
    message("  Aviso: el listado no cubrió ", a, "; se reintenta con fwp_year=", a, " ...")
    s2 <- tryCatch(res_paginas(1, anio = a), error = function(e) NULL)
    if (!is.null(s2) && nrow(s2)) ses <- dplyr::bind_rows(ses, s2)
  }
  faltan <- setdiff(anios, presentes(ses))
  if (length(faltan)) {
    stop("El listado no devolvió sesiones para: ", paste(faltan, collapse = ", "),
         ". No se actualiza el índice para no dar por buena una cobertura incompleta. ",
         "Reintenta en unos minutos o revisa el listado con diagnostico_listado().",
         call. = FALSE)
  }
  ses[!duplicated(ses$sesion_id), , drop = FALSE] |> dplyr::arrange(dplyr::desc(fecha), sesion_id)
}
# Diagnóstico del listado (se invoca cuando el listado devuelve pocas sesiones).
diagnostico_listado <- function(cfg = jgl_cfg()) {
  leer <- function(args) {
    url <- .jgl_listado_url(cfg$url_listado, pagina = args$pag, anio = args$anio)
    s <- tryCatch(extraer_sesiones_html(jgl_html(url, cfg), url), error = function(e) NULL)
    if (is.null(s)) tibble::tibble(sesion_id = character(), fecha = as.Date(character())) else s
  }
  p1 <- leer(list(pag = 1)); p2 <- leer(list(pag = 2))
  an <- leer(list(pag = 1, anio = format(Sys.Date(), "%Y")))
  message("Página 1: ", nrow(p1), " sesiones (",
          if (nrow(p1)) paste0(min(p1$fecha), " a ", max(p1$fecha)) else "sin sesiones", ").")
  message("Página 2: ", nrow(p2), " sesiones.",
          if (nrow(p2) && nrow(p1) && setequal(p1$sesion_id, intersect(p1$sesion_id, p2$sesion_id)))
            " ATENCIÓN: repite las de la página 1; usa actualizar_jgl(modo_listado = 'anios')" else "")
  message("Filtro año actual: ", nrow(an), " sesiones.")
  invisible(TRUE)
}

# Página de una sesión ---------------------------------------------------------

# Clasifica un enlace de documento por el texto del enlace y el nombre del fichero,
# y solo si no basta, por el subtítulo que lo precede.
clasificar_doc <- function(texto_enlace = "", fichero = "", subtitulo = "") {
  ids <- norm_txt(paste(texto_enlace, fichero, sep = " "))
  if (str_detect(ids, "acta")) return("acta")
  if (str_detect(ids, "convocatoria|orden del dia")) return("convocatoria")
  s <- norm_txt(subtitulo)
  if (str_detect(s, "acta")) return("acta")
  if (str_detect(s, "convocatoria|orden del dia")) return("convocatoria")
  NA_character_
}

.jgl_es_doc <- function(href) {
  ext <- ext_url(href)
  !is.na(ext) && (ext %in% c("pdf", "doc", "docx", "odt", "") || !nzchar(ext))
}

# Visita la página de una sesión y devuelve una lista con los documentos y metadatos.
visitar_sesion <- function(url, cfg) {
  html <- jgl_html(url, cfg)
  # fecha de modificación de la página (para detectar actas publicadas después)
  mod <- rvest::html_element(html, 'meta[property="article:modified_time"]')
  modificado_web <- if (!is.na(mod)) rvest::html_attr(mod, "content") else NA_character_

  # bloque de documentos: m4p-event-inscripcion → m4p-post-content → toda la página
  nivel <- "bloque"
  b <- rvest::html_elements(html, ".m4p-event-inscripcion")
  if (!length(b)) { b <- rvest::html_elements(html, ".m4p-post-content"); nivel <- "contenido" }
  if (!length(b)) { b <- html; nivel <- "pagina" }
  b <- b[[1]]

  enlaces <- rvest::html_elements(b, "a[href]")
  docs <- purrr::map_dfr(seq_along(enlaces), function(i) {
    href <- rvest::html_attr(enlaces[[i]], "href")
    if (is.na(href)) return(NULL)
    up <- httr2::url_parse(href)
    if (is.null(up$scheme)) {
      base <- httr2::url_parse(url)
      href <- paste0(base$scheme, "://", base$hostname,
                     ifelse(startsWith(href, "/"), "", "/"), href)
    }
    if (!.jgl_es_doc(href)) return(NULL)
    texto <- str_squish(rvest::html_text2(enlaces[[i]]))
    fichero <- str_remove(basename(str_remove(href, "[?#].*$")), "\\?.*$")
    sub <- tryCatch(str_squish(rvest::html_text2(rvest::html_element(
      enlaces[[i]], xpath = "preceding::*[self::h3 or self::h4 or self::strong or self::b][1]"))),
      error = function(e) "")
    sub <- if (is.null(sub) || is.na(sub)) "" else sub
    tibble::tibble(texto = texto, fichero = fichero, subtitulo = sub, url = href)
  })
  docs$doc <- vapply(seq_len(nrow(docs)), function(k)
    clasificar_doc(docs$texto[k], docs$fichero[k], docs$subtitulo[k]), character(1))

  # asistentes: enlaces a /persona/
  per <- rvest::html_elements(html, 'a[href*="/persona/"]')
  asistentes <- unique(str_squish(rvest::html_text2(per)))
  asistentes <- asistentes[nzchar(asistentes)]

  titulo_pagina <- tryCatch(str_squish(rvest::html_text2(rvest::html_element(html, "h1"))),
                            error = function(e) NA_character_)
  list(url = url, nivel = nivel, docs = docs, asistentes = paste(asistentes, collapse = "; "),
       modificado_web = modificado_web, titulo_pagina = titulo_pagina)
}

# Diagnóstico de una sesión concreta: muestra el bloque y cómo se clasificó cada enlace.
diagnostico_sesion <- function(url, cfg = jgl_cfg()) {
  v <- visitar_sesion(url, cfg)
  message("Bloque usado: ", v$nivel, " | asistentes: ", v$asistentes,
          " | modified_time: ", v$modificado_web %||% "(no)")
  print(v$docs[, c("doc", "texto", "fichero")])
  invisible(v)
}
