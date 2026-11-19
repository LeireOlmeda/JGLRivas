# probar_parsers.R ---------------------------------------------------------------
# Prueba los parsers SIN RED, contra fixtures reales guardados en tests/.
# Uso: Rscript tests/probar_parsers.R     (o source() desde R)

esta_r_interactiva <- interactive()
.fallo <- 0L
ok <- function(cond, mensaje) {
  if (isTRUE(cond)) { message("  OK: ", mensaje) } else { message("  FALLO: ", mensaje); .fallo <<- .fallo + 1L }
  invisible(cond)
}

# cargar solo lo necesario (offline)
.aqui <- (function() {
  a <- commandArgs(FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) return(normalizePath(dirname(f)))
  tryCatch(normalizePath("tests"), error = function(e) ".")
})()
dir_scripts <- getOption("jgl.scripts_dir",
                         file.path(dirname(.aqui), "scripts"))
if (!file.exists(file.path(dir_scripts, "utils.R")))
  dir_scripts <- normalizePath(file.path(.aqui, "..", "scripts"))
for (f in c("utils.R", "puntos.R", "cruce.R", "extraer.R"))
  source(file.path(dir_scripts, f), encoding = "UTF-8")

message("1) Convocatoria 2026-10-28 (esPublico, capa de texto)")
tc <- leer_md_cuerpo(file.path(.aqui, "fixture_convocatoria_2026-10-28.txt"))
pc <- parse_convocatoria(tc)
ok(nrow(pc$puntos) == 46, sprintf("46 puntos troceados (son %d)", nrow(pc$puntos)))
ok(setequal(pc$puntos$n, 1:46), "numeración completa 1..46")
ok(sum(!is.na(pc$puntos$expediente)) >= 35,
   sprintf("≥35 expedientes (son %d)", sum(!is.na(pc$puntos$expediente))))
ok(all(!is.na(pc$cabecera$fecha_hora)), "cabecera con fecha y hora")
tipos <- vapply(pc$puntos$asunto, function(a) clasificar_tipo(a)[["tipo"]], character(1))
ok(!all(tipos == "otros"), "clasificación no degrada todo a 'otros'")

message("2) Acta 2026-09-17 (OCR tesseract)")
ta <- leer_md_cuerpo(file.path(.aqui, "fixture_acta_2026-09-17.txt"))
pa <- parse_acta(ta)
ok(pa$troceo == "numeracion", sprintf("troceo por numeración (%s, %d puntos)",
                                      pa$troceo, nrow(pa$puntos)))
ok(nrow(pa$puntos) >= 40, sprintf("≥40 puntos (son %d)", nrow(pa$puntos)))
ok(mean(is.na(pa$puntos$expediente)) < 0.6,
   sprintf("<60%% de puntos sin expediente (los subbloques fundidos explican ~50%%; son %.0f%%)",
           100 * mean(is.na(pa$puntos$expediente))))

message("3) Cruce convocatoria/acta sobre las dos fuentes")
cr <- cruzar_puntos(pc$puntos, pa, texto_acta_plano = pa$texto_plano, hay_acta = TRUE)
ok(nrow(cr) > 0, "el cruce devuelve filas")
ok(all(cr$estado[!is.na(cr$n_conv) & !is.na(cr$n_acta)] == "mantenido"),
   "los pares emparejados quedan mantenidos")
ok(!any(is.na(cr$fuente_texto)), "fuente_texto siempre informada")

message("4) Extracción de campos")
ej <- which(!is.na(pa$puntos$expediente))[1]
ex <- extraer_contratos(pa$puntos$texto[ej], pa$puntos$asunto[ej], "contratacion",
                        "adjudicacion_contrato", origen_ocr = TRUE)
ok(is.list(ex), "extraer_contratos devuelve una lista de campos")

cat("\n")
if (.fallo == 0) {
  message("TODAS LAS PRUEBAS PASARON")
} else {
  message("PRUEBAS FALLIDAS: ", .fallo)
}
if (!esta_r_interactiva) quit(status = ifelse(.fallo == 0L, 0L, 1L))
