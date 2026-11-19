# cruce.R ----------------------------------------------------------------------
# Compara los puntos de la convocatoria con los del acta y decide el estado de cada
# uno: mantenido, retirado, nuevo, nuevo_urgencia, sin_acta, sin_convocatoria,
# en_acta_sin_trocear, no_localizado y nuevo_dudoso.
# - CRUCE_FIABLE = FALSE cuando el acta se troceó mal o se alineó por contenido
#   (plantilla antigua de 2023 a mayo de 2024): entonces `no_localizado` y
#   `nuevo_dudoso` NO permiten afirmar que un punto se retiró o es nuevo.
# - El expediente que aparece en el texto del acta pero que el troceo no aisló se
#   marca `en_acta_sin_trocear` y se guarda el fragmento del acta para extraer datos.

# ventana_expediente -----------------------------------------------------------

# Confusiones de OCR por carácter de destino: los caracteres del expediente
# pueden haber sido leídos como cualquiera de su clase.
.clase_ocr <- c("0" = "0Ooº°", "1" = "1lI|i", "2" = "2Zz", "3" = "3", "4" = "4Aa",
                "5" = "5Ss", "6" = "6Gb", "7" = "7Tt", "8" = "8B", "9" = "9gq",
                "/" = "/,.", "-" = "-. ")
.clase_de <- function(ch) {
  if (ch %in% names(.clase_ocr)) str_split(.clase_ocr[[ch]], "")[[1]] else ch
}

# Normaliza preservando la longitud (cada carácter se mapea 1:1) para poder
# buscar en la copia normalizada y recortar la ventana del texto original.
.norm_pos <- function(x) {
  x <- stringi::stri_trans_general(x, "Latin-ASCII")
  x <- str_to_lower(x)
  str_replace_all(x, "[^a-z0-9/ ]", " ")
}

# Busca un expediente ("48607/2026", o con sufijo "73/2020-CMAY") en texto plano
# tolerando errores típicos de OCR (O por 0, l por 1, espacios y puntos entre
# cifras). Devuelve una ventana del texto rodeando la coincidencia, o NA.
# `pn` (texto normalizado con posiciones preservadas) y `cand` (candidatos
# precalculados con .expediente_candidatos()) evitan recorrer el texto en cada llamada.
ventana_expediente <- function(plano, exp, n_chars = 1500, pn = NULL, cand = NULL) {
  if (is.na(plano) || !str_length(plano) || is.null(exp) || is.na(exp)) return(NA_character_)
  e <- str_remove_all(exp, "\\s")
  partes <- str_split(e, "-")[[1]]
  base <- partes[1]                                     # "NNNNN/AAAA"
  sufijo <- if (length(partes) > 1) partes[2] else ""   # p. ej. "CMAY"
  if (!str_detect(base, "^\\d{1,6}/\\d{4}$")) return(NA_character_)
  if (is.null(pn)) pn <- .norm_pos(plano)
  if (is.null(cand)) cand <- .expediente_candidatos(pn)
  base_n <- .norm_pos(base)

  # 1) coincidencia directa (canónica) sobre la copia normalizada
  loc <- str_locate(pn, fixed(base_n))
  ini <- loc[1, 1]; fin <- loc[1, 2]
  if (is.na(ini) && length(cand$chars)) {
    # 2) tolerante a OCR: comparación por caracteres con confusiones frecuentes
    chars_base <- str_split(base_n, "")[[1]]
    for (k in seq_along(cand$chars)) {
      a <- cand$chars[[k]]
      if (length(a) != length(chars_base)) next
      bien <- all(a == chars_base | vapply(seq_along(a), function(j) {
        a[j] %in% .clase_de(chars_base[j])
      }, logical(1)))
      if (bien) {
        if (nzchar(sufijo)) {
          cola <- .norm_pos(str_sub(pn, cand$loc[k, 2] + 1, cand$loc[k, 2] + 6))
          if (!str_detect(cola, fixed(str_to_lower(sufijo)))) next
        }
        ini <- cand$loc[k, 1]; fin <- cand$loc[k, 2]
        break
      }
    }
  }
  if (is.na(ini)) return(NA_character_)
  ini0 <- max(1, ini - 120)
  fin0 <- min(nchar(plano), fin + n_chars)
  str_squish(str_sub(plano, ini0, fin0))
}

# Candidatos "num separadores año" de un texto normalizado, con sus caracteres
# ya separados (solo se calcula una vez por acta).
.expediente_candidatos <- function(pn) {
  loc <- str_locate_all(pn, "[0-9]{1,6}[ .,/]{0,2}[0-9]{4}")[[1]]
  if (!nrow(loc)) return(list(loc = loc, chars = list()))
  txt <- str_remove_all(str_sub(pn, loc[, 1], loc[, 2]), " ")
  list(loc = loc, chars = str_split(txt, "")[[1]])
}

# Similitud de asuntos ---------------------------------------------------------

# Tokens de comparación: palabras de 3+ letras ya normalizadas (sin acentos).
tokens_asunto <- function(x) {
  t <- str_extract_all(norm_txt(x), "[a-z]{3,}")[[1]]
  t[!t %in% c("del", "los", "las", "con", "por", "para", "que", "una", "uno",
              "sus", "sin", "tod", "the")]
}

# Proporción de tokens de `a` presentes en el conjunto de tokens `tb` (asimétrica).
similitud_sets <- function(ta, tb) {
  if (!length(ta) || !length(tb)) return(0)
  mean(ta %in% tb)
}

# Votación ---------------------------------------------------------------------

extraer_votacion <- function(txt) {
  if (is.na(txt) || !nzchar(txt)) return(NA_character_)
  m <- str_match(txt, regex(
    "(unanimidad\\s*/\\s*asentimiento|por\\s+unanimidad|unanimidad|mayor[ií]a\\s+(simple|absoluta)|un[aá]nim[ae])",
    ignore_case = TRUE))
  if (is.na(m[1, 1])) return(NA_character_)
  v <- norm_txt(m[1, 1])
  if (str_detect(v, "unanimidad asentimiento")) "Unanimidad/Asentimiento" else
  if (str_detect(v, "mayoria simple")) "Mayoría simple" else
  if (str_detect(v, "mayoria absoluta")) "Mayoría absoluta" else "Unanimidad/Asentimiento"
}

# Cruce ------------------------------------------------------------------------

cruzar_puntos <- function(pc, pa, texto_acta_plano = NULL, hay_acta = !is.null(pa)) {
  # pc: puntos de la convocatoria (parse_convocatoria$puntos)
  # pa: lista que devuelve parse_acta (puntos + troceo + texto_plano)
  pa_pts <- if (!is.null(pa)) pa$puntos else tibble::tibble(
    n = integer(), bloque = character(), texto = character(), expediente = character(),
    decreto = character(), lotes = character(), asunto = character(), subbloque = integer())
  texto_plano <- if (!is.null(texto_acta_plano)) texto_acta_plano else
    if (!is.null(pa)) pa$texto_plano else ""

  n_conv <- nrow(pc); n_acta <- nrow(pa_pts)
  # fiabilidad: el acta debe trocearse por numeración y tener suficientes puntos
  cruce_fiable <- if (hay_acta && n_conv > 0)
    (!is.null(pa) && pa$troceo != "marcadores") && (n_acta >= 0.5 * n_conv) else NA

  filas <- list()
  add_fila <- function(nconv, nacta, estado, metodo, expediente, asunto, votacion,
                       fuente, texto_extra, bloque = NA_character_, subbloque = 0L) {
    filas[[length(filas) + 1]] <<- tibble::tibble(
      n_conv = as.integer(nconv), n_acta = as.integer(nacta), estado = estado,
      cruce_metodo = metodo, cruce_fiable = cruce_fiable, expediente = expediente,
      asunto = asunto, votacion = votacion, fuente_texto = fuente,
      texto_extra = texto_extra, bloque = bloque, subbloque = as.integer(subbloque))
  }
  finalizar <- function() {
    filas <- dplyr::bind_rows(filas)
    # cambio de orden: entre los pares emparejados, ¿coincide el orden de n_conv y n_acta?
    emp <- filas |> dplyr::filter(estado == "mantenido", !is.na(n_conv), !is.na(n_acta))
    if (nrow(emp) > 1) {
      emp <- emp |> dplyr::arrange(n_conv) |>
        dplyr::mutate(rk_conv = dplyr::row_number()) |>
        dplyr::arrange(n_acta) |>
        dplyr::mutate(rk_acta = dplyr::row_number()) |>
        dplyr::mutate(cambio = rk_conv != rk_acta) |>
        dplyr::select(n_conv, cambio)
      filas <- filas |>
        dplyr::left_join(emp, by = "n_conv") |>
        dplyr::mutate(cambio_orden = !is.na(cambio) & cambio,
                      cambio = NULL) |>
        dplyr::relocate(cambio_orden, .after = cruce_fiable)
    } else {
      filas$cambio_orden <- FALSE
    }
    filas |>
      dplyr::arrange(ifelse(is.na(n_conv), Inf, n_conv), ifelse(is.na(n_acta), Inf, n_acta)) |>
      dplyr::select(n_conv, n_acta, estado, cruce_metodo, cruce_fiable, cambio_orden,
                    expediente, asunto, votacion, fuente_texto, texto_extra, bloque, subbloque)
  }

  # --- sin acta (o acta que no dio puntos) -----------------------------------------
  if (n_acta == 0) {
    for (i in seq_len(n_conv)) {
      if (!hay_acta) {
        add_fila(pc$n[i], NA_integer_, "sin_acta", NA_character_, pc$expediente[i],
                 pc$asunto[i], NA_character_, "convocatoria", pc$texto[i], pc$bloque[i])
      } else {
        # el acta está publicada pero el troceo no aisló nada
        add_fila(pc$n[i], NA_integer_, "no_localizado", NA_character_, pc$expediente[i],
                 pc$asunto[i], NA_character_, "convocatoria", pc$texto[i], pc$bloque[i])
      }
    }
    return(finalizar())
  }
  # --- sin convocatoria --------------------------------------------------------------
  if (n_conv == 0) {
    for (j in seq_len(n_acta)) {
      add_fila(NA_integer_, pa_pts$n[j], "sin_convocatoria", NA_character_,
               pa_pts$expediente[j], pa_pts$asunto[j],
               extraer_votacion(pa_pts$texto[j]), "acta", pa_pts$texto[j],
               pa_pts$bloque[j], pa_pts$subbloque[j] %||% 0L)
    }
    return(finalizar())
  }

  # --- 1. match por expediente --------------------------------------------------------
  # texto del acta normalizado una sola vez (posiciones preservadas) y tokens por punto
  pn_acta <- .norm_pos(texto_plano)
  cand_acta <- .expediente_candidatos(pn_acta)
  tok_acta <- lapply(pa_pts$texto, function(x) unique(tokens_asunto(x)))
  tok_conv <- lapply(pc$asunto, tokens_asunto)
  exp_a <- norm_txt(pa_pts$expediente)
  usados_acta <- rep(FALSE, n_acta)
  conv_matched <- rep(FALSE, n_conv)
  nacta_de_conv <- rep(NA_real_, n_conv); names(nacta_de_conv) <- as.character(pc$n)
  metodo_de_conv <- rep(NA_character_, n_conv); names(metodo_de_conv) <- as.character(pc$n)
  texto_acta_de_conv <- rep(NA_character_, n_conv); names(texto_acta_de_conv) <- as.character(pc$n)
  # acta n -> n_conv (para el emparejamiento por orden entre puntos ya emparejados)
  conv_de_acta <- rep(NA_integer_, n_acta); names(conv_de_acta) <- as.character(pa_pts$n)
  # en actas troceadas por expediente (plantilla antigua sin numeración) el emparejamiento
  # por similitud es una alineación por contenido, no por texto fiable
  metodo_similitud <- if (!is.null(pa) && identical(pa$troceo, "expediente")) "contenido" else "texto"

  for (i in seq_len(n_conv)) {
    ei <- norm_txt(pc$expediente[i])
    if (is.na(ei) || !nzchar(ei)) next
    ok <- which(!usados_acta & !is.na(exp_a) & nzchar(exp_a) &
                  (exp_a == ei | startsWith(exp_a, ei) | startsWith(ei, exp_a)))
    if (length(ok)) {
      k <- ok[1]
      usados_acta[k] <- TRUE; conv_matched[i] <- TRUE
      idx <- as.character(pc$n[i])
      nacta_de_conv[idx] <- pa_pts$n[k]
      metodo_de_conv[idx] <- "expediente"
      texto_acta_de_conv[idx] <- pa_pts$texto[k]
      conv_de_acta[as.character(pa_pts$n[k])] <- pc$n[i]
    }
  }

  # --- 2. match por texto en lo no emparejado ------------------------------------------
  # Solo contra puntos del acta CON número: los subbloques (n = NA) se emparejan por
  # orden en el paso 3; emparejarlos por similitud daría un n_acta vacío.
  for (i in which(!conv_matched)) {
    if (is.na(pc$asunto[i]) || nchar(norm_txt(pc$asunto[i])) < 12) next
    cand <- which(!usados_acta & !is.na(pa_pts$n))
    if (!length(cand)) break
    scores <- vapply(cand, function(k) similitud_sets(tok_conv[[i]], tok_acta[[k]]), numeric(1))
    b <- which.max(scores)
    if (scores[b] >= 0.7) {
      k <- cand[b]
      usados_acta[k] <- TRUE; conv_matched[i] <- TRUE
      idx <- as.character(pc$n[i])
      nacta_de_conv[idx] <- pa_pts$n[k]
      metodo_de_conv[idx] <- metodo_similitud
      texto_acta_de_conv[idx] <- pa_pts$texto[k]
      conv_de_acta[as.character(pa_pts$n[k])] <- pc$n[i]
    }
  }

  # --- 3. match por ORDEN para subbloques fundidos -------------------------------------
  # Los subbloques tiene n = NA (son fragmentos sin banda del punto anterior); se emparejan
  # con el hueco de convocatoria que queda entre los puntos ya emparejados que los rodean.
  anclas <- which(usados_acta & !is.na(pa_pts$n))
  conv_sobrantes <- which(!conv_matched & (is.na(pc$expediente) | pc$expediente == ""))
  for (j in setdiff(seq_len(n_acta), which(usados_acta))) {
    if ((pa_pts$subbloque[j] %||% 0L) == 0L) next
    prev <- max(c(-Inf, anclas[anclas < j]))
    nxt <- min(c(Inf, anclas[anclas > j]))
    cn_prev <- if (is.finite(prev)) {
      v <- conv_de_acta[as.character(pa_pts$n[prev])]; if (is.na(v)) -Inf else v
    } else -Inf
    cn_next <- if (is.finite(nxt)) {
      v <- conv_de_acta[as.character(pa_pts$n[nxt])]; if (is.na(v)) Inf else v
    } else Inf
    if (cn_prev >= cn_next) next
    hueco <- conv_sobrantes[pc$n[conv_sobrantes] > cn_prev & pc$n[conv_sobrantes] < cn_next]
    if (length(hueco)) {
      i <- hueco[1]
      idx <- as.character(pc$n[i])
      conv_matched[i] <- TRUE
      nacta_de_conv[idx] <- NA_real_          # el subbloque no tiene número en el acta
      metodo_de_conv[idx] <- "orden"
      texto_acta_de_conv[idx] <- pa_pts$texto[j]
      conv_sobrantes <- setdiff(conv_sobrantes, i)
      usados_acta[j] <- TRUE
    }
  }

  # --- filas de la convocatoria ---------------------------------------------------------
  for (i in seq_len(n_conv)) {
    idx <- as.character(pc$n[i])
    if (conv_matched[i]) {
      add_fila(pc$n[i], nacta_de_conv[idx], "mantenido", metodo_de_conv[idx],
               pc$expediente[i], pc$asunto[i],
               extraer_votacion(texto_acta_de_conv[idx]), "acta",
               texto_acta_de_conv[idx], pc$bloque[i])
    } else {
      frag <- ventana_expediente(texto_plano, pc$expediente[i], 900, pn = pn_acta, cand = cand_acta)
      if (!is.na(pc$expediente[i]) && nzchar(pc$expediente[i]) && !is.na(frag)) {
        add_fila(pc$n[i], NA_integer_, "en_acta_sin_trocear", NA_character_,
                 pc$expediente[i], pc$asunto[i], extraer_votacion(frag), "acta",
                 paste(pc$asunto[i], frag, sep = " "), pc$bloque[i])
      } else {
        est <- if (isFALSE(cruce_fiable)) "no_localizado" else "retirado"
        add_fila(pc$n[i], NA_integer_, est, NA_character_, pc$expediente[i],
                 pc$asunto[i], NA_character_, "convocatoria", pc$texto[i], pc$bloque[i])
      }
    }
  }

  # --- puntos del acta sin pareja: nuevos (o nuevos dudosos) -----------------------------
  # Incluye los fragmentos sin banda (subbloques, n = NA): son contenido del acta que no
  # tiene punto en la convocatoria; se marcan como nuevos con n_acta vacío.
  for (j in which(!usados_acta)) {
    urg <- !is.na(pa_pts$bloque[j]) && norm_txt(pa_pts$bloque[j]) == "urgencia"
    est <- if (urg) "nuevo_urgencia"
    else if (isFALSE(cruce_fiable)) "nuevo_dudoso"
    else "nuevo"
    exp_j <- pa_pts$expediente[j]
    asj <- pa_pts$asunto[j]
    if (is.na(asj) || !nzchar(asj)) asj <- str_squish(str_trunc(pa_pts$texto[j], 240))
    add_fila(NA_integer_, pa_pts$n[j], est, NA_character_, exp_j, asj,
             extraer_votacion(pa_pts$texto[j]), "acta", pa_pts$texto[j],
             pa_pts$bloque[j], pa_pts$subbloque[j] %||% 0L)
  }

  finalizar()
}
