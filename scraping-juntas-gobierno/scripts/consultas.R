# consultas.R -------------------------------------------------------------------
# Consultas de análisis sobre las tablas de analisis/*.md.
# Requiere la skill cargada (source("scripts/actualizar_jgl.R", encoding="UTF-8"))
# y el paquete tidyr para algunos cálculos.

# Contratos por año ---------------------------------------------------------------

contratos_por_anio <- function(base_dir = "datos/jgl-rivas") {
  cts <- cargar_tabla("contratos", base_dir)
  res <- cts |>
    dplyr::mutate(anio = substr(fecha, 1, 4)) |>
    dplyr::group_by(anio) |>
    dplyr::summarise(n = dplyr::n(),
                     con_importe = sum(!is.na(importe_principal)),
                     importe_total = sum(importe_principal, na.rm = TRUE),
                     a_revisar = sum(revisar %in% TRUE))
  cat(tabla_a_md(res), sep = "\n")
  invisible(res)
}

# Top de adjudicatarios ------------------------------------------------------------

top_adjudicatarios <- function(n = 10, base_dir = "datos/jgl-rivas") {
  cts <- cargar_tabla("contratos", base_dir)
  res <- cts |>
    tidyr::separate_rows(adjudicatarios, sep = "; ") |>
    dplyr::filter(!is.na(adjudicatarios), nzchar(adjudicatarios),
                  !str_detect(norm_txt(adjudicatarios), "^(que|es|del|la|el)")) |>
    dplyr::group_by(adjudicatarios) |>
    dplyr::summarise(n = dplyr::n(), importe_total = sum(importe_principal, na.rm = TRUE)) |>
    dplyr::arrange(desc(n), desc(importe_total)) |>
    head(n)
  cat(tabla_a_md(res), sep = "\n")
  invisible(res)
}

# Prórrogas -------------------------------------------------------------------------

prorrogas_resumen <- function(base_dir = "datos/jgl-rivas") {
  cts <- cargar_tabla("contratos", base_dir)
  res <- cts |>
    dplyr::filter(prorroga %in% TRUE) |>
    dplyr::group_by(anio = substr(fecha, 1, 4)) |>
    dplyr::summarise(n_prorrogas = dplyr::n(),
                     duraciones = paste(sort(unique(prorroga_duracion[!is.na(prorroga_duracion)])),
                                        collapse = "; "))
  cat(tabla_a_md(res), sep = "\n")
  invisible(res)
}

# Historial de un expediente ----------------------------------------------------------

historial_expediente <- function(exp, base_dir = "datos/jgl-rivas") {
  pts <- cargar_puntos(base_dir)
  res <- pts |>
    dplyr::filter(!is.na(expediente),
                  norm_txt(expediente) == norm_txt(exp) |
                    str_detect(norm_txt(expediente), paste0("^", norm_txt(exp)))) |>
    dplyr::select(fecha, sesion_id, n_conv, n_acta, estado, tipo, asunto)
  if (!nrow(res)) { message("No aparece '", exp, "' en analisis/puntos.md"); return(invisible(res)) }
  cat(tabla_a_md(res), sep = "\n")
  invisible(res)
}

# Cambios sobre lo previsto -----------------------------------------------------------

cambios_sobre_lo_previsto <- function(sesion = NULL, base_dir = "datos/jgl-rivas") {
  pts <- cargar_puntos(base_dir)
  if (!is.null(sesion)) pts <- pts |> dplyr::filter(fecha == as.character(sesion))
  res <- pts |>
    dplyr::filter(estado %in% c("retirado", "nuevo", "nuevo_urgencia", "no_localizado", "nuevo_dudoso")) |>
    dplyr::group_by(fecha, estado) |> dplyr::count() |>
    dplyr::arrange(desc(fecha), estado)
  cat(tabla_a_md(res), sep = "\n")
  message("(los estados no_localizado y nuevo_dudoso son dudosos: el acta se troceó mal;",
          " no se puede afirmar que un punto se retirara o fuera nuevo)")
  invisible(res)
}
