# comprobar.R ------------------------------------------------------------------
# Controles automáticos de validación (sin red ni OCR). Imprime las cifras que se
# citan en resultado_validacion.md. Uso:
#   Rscript validation/comprobar.R
#   (desde la raíz del repositorio; localiza los scripts de la skill solo)

.aqui <- (function() {
  a <- commandArgs(FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) return(normalizePath(dirname(f)))
  tryCatch(normalizePath("scraping-juntas-gobierno/validation"), error = function(e) ".")
})()
.dir_scripts <- getOption("jgl.scripts_dir",
                          normalizePath(file.path(.aqui, "..", "scripts")))
source(file.path(.dir_scripts, "actualizar_jgl.R"), encoding = "UTF-8")

cfg <- jgl_cfg()
ind <- leer_indice(cfg)
pts <- cargar_puntos(cfg$base_dir)
cts <- cargar_tabla("contratos", cfg$base_dir)
sub <- cargar_tabla("subvenciones", cfg$base_dir)
jud <- cargar_tabla("judicial", cfg$base_dir)

cat("== 1. Cobertura por año ==\n")
cob <- ind |>
  dplyr::mutate(anio = substr(fecha, 1, 4)) |>
  dplyr::group_by(anio) |>
  dplyr::summarise(n = dplyr::n(),
                   conv_ok = sum(estado_convocatoria == "ok", na.rm = TRUE),
                   acta_ok = sum(estado_acta == "ok", na.rm = TRUE),
                   sin_conv = sum(estado_convocatoria == "falta", na.rm = TRUE),
                   sin_acta = sum(estado_acta == "falta", na.rm = TRUE))
print(as.data.frame(cob), row.names = FALSE)

cat("\n== 2. Volumen de las tablas ==\n")
cat("puntos:", nrow(pts), "| contratos:", nrow(cts), "| subvenciones:", nrow(sub),
    "| judicial:", nrow(jud), "\n")
cat("Sesiones en el índice:", nrow(ind), "| sesiones analizadas:", length(unique(pts$sesion_id)), "\n")

cat("\n== 3. Duplicados ==\n")
# (a) clave de numeración: puede repetirse porque algunas convocatorias reinician la
# numeración en cada bloque (concursos, subvenciones, otros); no son duplicados reales
clave <- pts |>
  dplyr::filter(!is.na(n_conv) | !is.na(n_acta)) |>
  dplyr::select(sesion_id, n_conv, n_acta)
dup <- sum(duplicated(clave))
cat("Clave (sesion_id, n_conv, n_acta): filas", nrow(clave), "| repetidas:", dup,
    "(reinicios de numeración por bloque)\n")
# (b) clave de contenido: un duplicado real repite sesión, numeración, asunto y expediente
clave2 <- pts |>
  dplyr::filter(!is.na(n_conv) | !is.na(n_acta)) |>
  dplyr::select(sesion_id, n_conv, n_acta, asunto, expediente)
dup2 <- sum(duplicated(clave2))
cat("Clave de contenido (+ asunto y expediente): repetidas:", dup2, "\n")
# (c) filas idénticas en todas las columnas (fragmentos de acta con texto repetido)
cat("Filas idénticas en todas las columnas:", sum(duplicated(pts)), "\n")
cat("Fragmentos sin numeración (n_conv y n_acta NA):",
    sum(is.na(pts$n_conv) & is.na(pts$n_acta)), "\n")

cat("\n== 4. Campos ausentes en puntos (por origen) ==\n")
aus <- pts |>
  dplyr::group_by(origen_ocr) |>
  dplyr::summarise(n = dplyr::n(),
                   sin_expediente = round(mean(is.na(expediente)), 3),
                   sin_asunto = round(mean(is.na(asunto)), 3),
                   sin_votacion = round(mean(is.na(votacion)), 3))
print(as.data.frame(aus), row.names = FALSE)

cat("\n== 5. Campos económicos en contratos (por origen) ==\n")
aus2 <- cts |>
  dplyr::group_by(origen_ocr) |>
  dplyr::summarise(n = dplyr::n(),
                   sin_importe = round(mean(is.na(importe_principal)), 3),
                   sin_adjudicatario = round(mean(is.na(adjudicatarios)), 3),
                   revisar = round(mean(revisar %in% TRUE), 3))
print(as.data.frame(aus2), row.names = FALSE)

cat("\n== 6. Estados de los documentos en el índice ==\n")
print(as.data.frame(estado_indice(cfg$base_dir)), row.names = FALSE)

cat("\n== 7. Coherencia de fechas ==\n")
cat("Sesiones con fecha no ISO:", sum(!grepl("^\\d{4}-\\d{2}-\\d{2}$", ind$fecha), na.rm = TRUE), "\n")
cat("Rango:", min(ind$fecha, na.rm = TRUE), "a", max(ind$fecha, na.rm = TRUE), "\n")
