# puntos.R --------------------------------------------------------------------
# Convierte el texto de una convocatoria o un acta en una tabla de puntos.
# Cada punto: n, bloque, texto, expediente, decreto, lotes, asunto.
# El parser de convocatoria está probado contra el formato real de Rivas
# (plataforma esPublico Gestiona). El de acta es PROVISIONAL: calibrar con
# muestra_acta() cuando se tenga texto OCR real (ver references/).

# Limpieza ---------------------------------------------------------------------

limpiar_texto <- function(txt) {
  if (is.na(txt)) return(character())
  l <- str_split(txt, "\r?\n")[[1]]
  l <- str_trim(l)
  l <- l[!str_detect(l, "^<!-- pagina \\d+ -->$")]
  pie <- regex(paste0("^(c[oó]d\\.? ?validaci[oó]n|verificaci[oó]n:|",
                      "documento firmado electr[oó]nicamente|p[aá]gina \\d+ de \\d+$)"),
               ignore_case = TRUE)
  l <- l[!str_detect(l, pie)]
  l[nzchar(l)]
}

valor_tras <- function(l, rx) {
  r <- regex(rx, ignore_case = TRUE)
  i <- which(str_detect(l, r))[1]
  if (is.na(i)) return(NA_character_)
  resto <- str_trim(str_remove(l[i], r))
  if (nzchar(resto)) resto else if (i < length(l)) l[i + 1] else NA_character_
}

# Troceo -----------------------------------------------------------------------
# Un punto empieza en una línea con "N." / "N.-" / "N)". Con OCR algunos números salen
# mal o faltan, y en el texto hay líneas que empiezan por un número sin ser un punto.
# Por eso no se exige una numeración estrictamente correlativa: de todas las líneas
# candidatas se elige la CADENA CRECIENTE MÁS LARGA (con saltos de hasta `max_salto`
# números, p. ej. 1,2,4,5 si el 3 no se leyó) que empiece cerca del 1. Una cabecera de
# bloque (p. ej. URGENCIA) permite que la numeración se reinicie.

trocear_puntos <- function(l, rx_punto, f_bloque = function(x) NA_character_,
                           max_salto = 6L, max_inicio = 5L) {
  vacio <- tibble(n = integer(), bloque = character(), texto = character())
  if (!length(l)) return(vacio)
  rx <- regex(rx_punto, ignore_case = TRUE)
  b <- vapply(l, f_bloque, character(1), USE.NAMES = FALSE)
  m <- str_match(l, rx)
  num <- suppressWarnings(as.integer(m[, 2]))
  cand <- which(!is.na(num) & is.na(b))
  k <- length(cand)
  if (k == 0) return(vacio)
  nums <- num[cand]
  hdrs <- cumsum(!is.na(b))[cand]

  best <- integer(k)
  prev <- rep(NA_integer_, k)
  for (j in seq_len(k)) {
    nj <- nums[j]
    if (nj <= max_inicio) best[j] <- 1L
    if (j > 1) {
      ii <- seq_len(j - 1)
      d <- nj - nums[ii]
      ok <- best[ii] > 0L & ((d >= 1L & d <= max_salto) | (hdrs[j] > hdrs[ii] & nj <= max_inicio))
      if (any(ok)) {
        ci <- ii[ok]
        bi <- ci[max(which(best[ci] == max(best[ci])))]
        if (best[bi] + 1L > best[j]) {
          best[j] <- best[bi] + 1L
          prev[j] <- bi
        }
      }
    }
  }
  if (max(best) == 0L) return(vacio)
  j <- max(which(best == max(best)))
  cadena <- j
  while (!is.na(prev[j])) {
    j <- prev[j]
    cadena <- c(j, cadena)
  }
  inicios <- cand[cadena]
  finales <- c(inicios[-1] - 1L, length(l))
  bloque_de <- function(pos) {
    h <- which(!is.na(b) & seq_along(b) < pos)
    if (length(h)) b[max(h)] else NA_character_
  }
  res <- lapply(seq_along(inicios), function(t) {
    idx <- inicios[t]:finales[t]
    idx <- idx[is.na(b[idx]) & idx != inicios[t]]
    partes <- c(m[inicios[t], ncol(m)], l[idx])
    partes <- partes[!str_detect(norm_txt(partes), "^no hay asuntos")]
    tibble(n = num[inicios[t]], bloque = bloque_de(inicios[t]),
           texto = str_squish(paste(partes, collapse = " ")))
  })
  bind_rows(res)
}

# Alternativa cuando el acta no se deja trocear por numeración: un punto por cada
# mención de "Expediente NNNN/AAAA".
trocear_por_expediente <- function(l) {
  plano <- paste(l, collapse = " ")
  rx <- regex(paste0("(?:expediente|expte\\.?|exp\\.)(?:\\s+de)?(?:\\s+contrataci[oó]n)?\\s*",
                     "(?:n[º°o\\.]*\\s*)?\\d{1,6}\\s?/\\s?\\d{4}"), ignore_case = TRUE)
  m <- str_locate_all(plano, rx)[[1]]
  if (!nrow(m)) return(tibble(n = integer(), bloque = character(), texto = character()))
  ini <- m[, 1]
  fin <- c(ini[-1] - 1L, nchar(plano))
  tibble(n = seq_along(ini), bloque = NA_character_,
         texto = str_squish(str_sub(plano, ini, fin)))
}

# Campos básicos por punto -----------------------------------------------------

rx_exp <- paste0("(?i)(?:expediente|expte\\.?|exp\\.)(?:\\s+de)?(?:\\s+contrataci[oó]n)?\\s*",
                 "(?:n[º°o\\.]*\\s*)?(\\d{1,6}\\s?/\\s?\\d{4}(?:-[A-Za-z]{2,8})?)")
rx_exp_prefijo <- paste0("(?i)^expediente\\s+(?:n[º°o\\.]*\\s*)?\\d{1,6}/\\d{4}(?:-[A-Za-z]{2,8})?",
                         "(?:\\s*-\\s*lote\\s*\\d+)?\\s*[\\.\\-:]*\\s*")

enriquecer_puntos_basico <- function(p) {
  if (nrow(p) == 0) {
    return(p |> mutate(expediente = character(), decreto = character(),
                       lotes = character(), asunto = character()))
  }
  p |> mutate(
    expediente = str_remove_all(str_match(texto, rx_exp)[, 2], "\\s"),
    decreto = str_match(texto, "(?i)decreto[^0-9]{0,60}?n[º°o\\.]*\\s*(\\d{1,6}/\\d{1,6})")[, 2],
    lotes = str_match(texto, "(?i)lotes?\\s+(?:n[º°o\\.]*\\s*)?(\\d+(?:\\s*(?:,|y|e)\\s*\\d+)*)")[, 2],
    asunto = str_squish(str_remove(texto, rx_exp_prefijo))
  )
}

# Convocatoria -----------------------------------------------------------------

rx_punto_conv <- "^(\\d{1,3})\\s*[\\.\\-\u2013\u2014)]+\\s*(?!\\d)(.*)$"

bloque_conv <- function(x) {
  m <- str_match(x, "^([A-Z])\\)\\s+(.+)$")
  if (!is.na(m[1, 1]) && x == str_to_upper(x)) paste0(m[1, 2], ") ", m[1, 3]) else NA_character_
}

parse_convocatoria <- function(txt) {
  l <- limpiar_texto(txt)
  plano <- paste(l, collapse = "\n")
  cab <- list(
    exp_sesion = str_extract(plano, "[A-Z]{2,5}/\\d{4}/\\d+"),
    tipo_convocatoria = valor_tras(l, "^tipo convocatoria:?"),
    fecha_hora = valor_tras(l, "^fecha y hora:?"),
    lugar = valor_tras(l, "^lugar:?")
  )
  ini <- which(str_detect(l, regex("^asuntos de la convocatoria", ignore_case = TRUE)))[1]
  fin <- which(str_detect(l, regex("^confirmaci[oó]n de asistencia", ignore_case = TRUE)))[1]
  ini <- if (is.na(ini)) 0L else ini
  fin <- if (is.na(fin)) length(l) + 1L else fin
  cuerpo <- if (fin - 1L >= ini + 1L) l[(ini + 1L):(fin - 1L)] else character()
  p <- trocear_puntos(cuerpo, rx_punto_conv, bloque_conv)
  list(cabecera = cab, puntos = enriquecer_puntos_basico(p))
}

# Acta (provisional) -----------------------------------------------------------

rx_punto_acta <- paste0("^(?:punto\\s+(?:n[º°o\\.]*\\s*)?)?(\\d{1,3})\\s*[ºª°]?\\s*",
                        "[\\.\\-\u2013\u2014):]+\\s*(?!\\d)(.*)$")

bloque_acta <- function(x) {
  n <- norm_txt(x)
  if (str_detect(n, "^(asuntos? )?urgent|^urgencias?\\b|^asuntos? no incluidos|^por razones? de urgencia")) {
    return("URGENCIA")
  }
  if (str_detect(n, "^ruegos y preguntas")) return("RUEGOS Y PREGUNTAS")
  NA_character_
}

# El OCR confunde a veces la letra O con la cero en el número del punto ("1O.-" -> "10.-").
corregir_numero_ocr <- function(x) {
  m <- str_match(x, "^([0-9Oo]{1,3})(\\s*[\\.\\-\u2013\u2014):]+.*)$")
  tiene_digito <- !is.na(m[, 2]) & str_detect(m[, 2], "[0-9]")
  ifelse(tiene_digito, paste0(chartr("Oo", "00", m[, 2]), m[, 3]), x)
}

# Puntos "fundidos": con OCR a veces se pierde la banda (número + expediente + título) de un punto y
# su cuerpo queda pegado al texto del punto anterior. Cada punto tiene UN bloque "Hechos y
# fundamentos de derecho:"; si un bloque numerado contiene varios, se parte en subbloques. El primero
# conserva el número y el expediente del punto; los demás quedan sin número ni expediente
# (n = NA, subbloque > 0) y se emparejan después con la convocatoria por orden (ver cruce.R).
dividir_bloques_multiples <- function(p) {
  if (!nrow(p)) return(mutate(p, subbloque = integer()))
  rx <- regex("hechos\\s+y\\s+fundamentos\\s+de\\s+derecho", ignore_case = TRUE)
  bind_rows(lapply(seq_len(nrow(p)), function(r) {
    pos <- str_locate_all(p$texto[r], rx)[[1]][, 1]
    if (length(pos) < 2) return(mutate(p[r, ], subbloque = 0L))
    ini <- c(1L, pos[-1])
    fin <- c(pos[-1] - 1L, nchar(p$texto[r]))
    tibble(n = c(p$n[r], rep(NA_integer_, length(ini) - 1L)), bloque = p$bloque[r],
           texto = str_squish(str_sub(p$texto[r], ini, fin)), subbloque = seq_along(ini) - 1L)
  }))
}

# Plantilla antigua de actas (2023 - mayo 2024): el OCR no capta la banda con el número y el
# título de cada punto; solo salen los bloques "Hechos y fundamentos de derecho:" y
# "Resolución:". Cada punto es [Hechos]? + Resolución: un "Resolución:" empieza punto nuevo
# solo si el marcador anterior también era "Resolución:" (punto sin "Hechos").
marcadores_acta <- function(l) {
  hechos <- str_detect(l, regex("^hechos\\s+y\\s+fundamentos", ignore_case = TRUE))
  resol <- str_detect(l, regex("^resoluci[oó]n\\s*:", ignore_case = TRUE))
  idx <- which(hechos | resol)
  if (!length(idx)) return(integer())
  es_h <- hechos[idx]
  inicio <- logical(length(idx))
  previo_h <- FALSE
  for (t in seq_along(idx)) {
    if (es_h[t]) {
      inicio[t] <- TRUE
      previo_h <- TRUE
    } else {
      inicio[t] <- !previo_h
      previo_h <- FALSE
    }
  }
  idx[inicio]
}

trocear_por_marcadores <- function(l, inicios) {
  finales <- c(inicios[-1] - 1L, length(l))
  tibble(n = seq_along(inicios), bloque = NA_character_,
         texto = vapply(seq_along(inicios), function(t) str_squish(paste(l[inicios[t]:finales[t]], collapse = " ")),
                        character(1)))
}

parse_acta <- function(txt, modo = c("auto", "marcadores")) {
  modo <- match.arg(modo)
  l <- corregir_numero_ocr(limpiar_texto(txt))
  if (modo == "marcadores") {
    ini <- marcadores_acta(l)
    p <- if (length(ini) >= 3) trocear_por_marcadores(l, ini) else
      tibble(n = integer(), bloque = character(), texto = character())
    pb <- mutate(enriquecer_puntos_basico(p), subbloque = 0L)
    if (nrow(pb)) pb$expediente <- NA_character_   # el expediente de la banda se perdió: no fiarse del primero que aparezca
    return(list(puntos = pb, troceo = "marcadores", texto_plano = paste(l, collapse = " ")))
  }
  f_bloque <- function(x) {
    b <- bloque_conv(x)
    if (!is.na(b)) b else bloque_acta(x)
  }
  p <- trocear_puntos(l, rx_punto_acta, f_bloque)
  troceo <- "numeracion"
  if (nrow(p) == 0) {
    p <- trocear_por_expediente(l)
    troceo <- "expediente"
  }
  p <- if (troceo == "numeracion") dividir_bloques_multiples(p) else mutate(p, subbloque = 0L)
  pb <- enriquecer_puntos_basico(p)
  if (nrow(pb)) pb$expediente[pb$subbloque > 0] <- NA_character_   # subbloques sin banda: sin expediente propio
  list(puntos = pb, troceo = troceo, texto_plano = paste(l, collapse = " "))
}
