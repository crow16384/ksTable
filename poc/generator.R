# poc/generator.R ─────────────────────────────────────────────────────────────
# Pure-R DSL → dplyr code generator  (Proof of Concept)
#
# Purpose  : determine whether C++23 is needed for the generation task.
# Coverage : parameter_stat + hierarchical row structures.
# Security : identifiers from JSON are validated; string labels are escaped.
# NOT production-ready: no optimiser, no metadata integration.

`%||%` <- function(x, y) if (is.null(x)) y else x

# Validates that a JSON field value can be used safely as an R identifier.
# This is the primary injection-prevention step.
assert_id <- function(x, field) {
  if (!grepl("^[A-Za-z.][A-Za-z0-9._]*$", x))
    stop(sprintf("'%s' is not a valid R identifier (field: %s)", x, field),
         call. = FALSE)
  x
}

# Wraps a plain string in double quotes, escaping \ and ".
r_str <- function(x) {
  x <- gsub("\\",  "\\\\", x, fixed = TRUE)
  x <- gsub('"',   '\\"',  x, fixed = TRUE)
  paste0('"', x, '"')
}

gen_group_by <- function(vars, drop) {
  paste0("  dplyr::group_by(",
         paste(vars, collapse = ", "),
         if (!drop) ", .drop = FALSE" else "",
         ") |>")
}

# Returns TRUE when the format spec expects a list-returning calc function.
# In that case the generator wraps the summarize result in list() to create
# a list-column so the format step can unpack named fields.
needs_list_wrap <- function(fmt) {
  !is.null(fmt) && (fmt$type %||% "") %in% c("custom", "template")
}

# Generates the R expression that converts .value_raw → .value (string).
# This is the format layer: calc_fns produce raw values, format_fns render them.
gen_format_expr <- function(s) {
  fmt <- s$format
  if (is.null(fmt)) return("as.character(.value_raw)")
  switch(fmt$type %||% "asis",
    sprintf  = sprintf('sprintf(%s, .value_raw)', r_str(fmt$pattern %||% "%s")),
    custom   = {
      f <- assert_id(fmt$fun, "format.fun")
      sprintf('vapply(.value_raw, format_fns[["%s"]], character(1L))', f)
    },
    template = {
      sprintf('vapply(.value_raw, function(.x) glue::glue_data(.x, %s), character(1L))',
              r_str(fmt$pattern %||% "{value}"))
    },
    ksformat = sprintf('ksformat::fput(.value_raw, %s)', r_str(fmt$format_name %||% "")),
    "as.character(.value_raw)"  # default
  )
}

# ─────────────────────────────────────────────────────────────────────────────

#' Compile a JSON DSL spec to an R code string.
#'
#' @param json_spec  JSON string (not a file path)
#' @return  character(1) — valid R code, ready for eval()
poc_compile <- function(json_spec) {
  spec <- jsonlite::fromJSON(json_spec, simplifyVector = FALSE)
  ts   <- spec$table_spec

  row_structure <- ts$layout$row_structure %||% "parameter_stat"

  lines <- switch(row_structure,
    parameter_stat = gen_parameter_stat(ts),
    hierarchical   = gen_hierarchical(ts),
    stop("Unsupported row_structure: '", row_structure, "'", call. = FALSE)
  )
  paste(lines, collapse = "\n")
}

#' Execute compiled code against data and calc functions.
#'
#' @param code        character(1) — from poc_compile()
#' @param data        data.frame / tibble
#' @param calc_fns    named list; names match "fun" values in JSON statistics.
#'                    Functions return raw numeric / list values — NOT strings.
#' @param format_fns  named list; names match "format.fun" values in JSON.
#'                    Functions convert a raw list element to a character string.
#' @return tibble
poc_execute <- function(code, data, calc_fns, format_fns = list()) {
  env             <- new.env(parent = parent.frame())
  env$.data       <- data
  env$calc_fns    <- calc_fns
  env$format_fns  <- format_fns
  eval(parse(text = code), envir = env)
}

# ── parameter_stat ────────────────────────────────────────────────────────────

gen_parameter_stat <- function(ts) {
  params   <- ts$parameter
  stats    <- ts$statistics
  gvars    <- vapply(ts$groups$by, assert_id, character(1L), field = "groups$by")
  inc_miss <- isTRUE(ts$groups$include_missing_levels)

  lines <- c(".chunks <- list()", "")
  idx   <- 1L

  for (pn in names(params)) {
    p   <- params[[pn]]
    var <- assert_id(p$variable, paste0("parameter.", pn, ".variable"))
    lbl <- r_str(p$label %||% var)

    for (sn in names(stats)) {
      s    <- stats[[sn]]
      fun  <- assert_id(s$fun, paste0("statistics.", sn, ".fun"))
      slbl <- r_str(s$label %||% sn)

      raw_expr <- if (needs_list_wrap(s$format)) {
        paste0('list(calc_fns[["', fun, '"]](' , var, "))")  # list-column for multi-field returns
      } else {
        paste0('calc_fns[["', fun, '"]](' , var, ")")        # scalar: integer, double, or character
      }
      fmt_expr <- gen_format_expr(s)

      lines <- c(lines,
        paste0(".chunks[[", idx, "L]] <- .data |>"),
        gen_group_by(gvars, drop = !inc_miss),
        "  dplyr::summarize(",
        paste0("    .value_raw  = ", raw_expr, ","),
        '    .groups     = "drop"',
        "  ) |>",
        "  dplyr::mutate(",
        paste0("    .value      = ", fmt_expr, ","),  # format layer: raw → string
        paste0("    .param      = ", lbl, ","),
        paste0("    .stat_label = ", slbl, ","),
        "    .value_raw  = NULL",                      # drop helper column
        "  )",
        ""
      )
      idx <- idx + 1L
    }
  }

  c(lines,
    ".long <- dplyr::bind_rows(.chunks)",
    "",
    "tidyr::pivot_wider(",
    "  .long,",
    "  id_cols     = c(.param, .stat_label),",
    paste0("  names_from  = c(", paste(gvars, collapse = ", "), "),"),
    "  values_from = .value",
    ")"
  )
}

# ── hierarchical ──────────────────────────────────────────────────────────────

gen_hierarchical <- function(ts) {
  params <- ts$parameter
  stats  <- ts$statistics
  gvars  <- vapply(ts$groups$by, assert_id, character(1L), field = "groups$by")

  pn         <- names(params)[[1L]]
  p          <- params[[pn]]
  parent_var <- assert_id(p$variable, paste0("parameter.", pn, ".variable"))

  child_n   <- names(p$nested)[[1L]]
  child_p   <- p$nested[[child_n]]
  child_var <- assert_id(child_p$variable, paste0("nested.", child_n, ".variable"))

  # Hierarchical tables typically show one formatted statistic per cell.
  sn   <- names(stats)[[1L]]
  s    <- stats[[sn]]
  fun  <- assert_id(s$fun, paste0("statistics.", sn, ".fun"))
  slbl <- r_str(s$label %||% sn)

  raw_expr_p <- if (needs_list_wrap(s$format)) {
    paste0('list(calc_fns[["', fun, '"]](' , parent_var, "))")
  } else {
    paste0('calc_fns[["', fun, '"]](' , parent_var, ")")
  }
  raw_expr_c <- if (needs_list_wrap(s$format)) {
    paste0('list(calc_fns[["', fun, '"]](' , child_var, "))")
  } else {
    paste0('calc_fns[["', fun, '"]](' , child_var, ")")
  }
  fmt_expr <- gen_format_expr(s)

  c(".chunks <- list()", "",
    paste0("# Parent level: ", parent_var),
    ".chunks[[1L]] <- .data |>",
    gen_group_by(c(gvars, parent_var), drop = TRUE),
    "  dplyr::summarize(",
    paste0("    .value_raw  = ", raw_expr_p, ","),
    '    .groups     = "drop"',
    "  ) |>",
    "  dplyr::mutate(",
    paste0("    .value      = ", fmt_expr, ","),
    paste0("    .parent     = ", parent_var, ","),
    paste0("    .row_label  = ", parent_var, ","),
    paste0("    .stat_label = ", slbl, ","),
    "    .is_child   = FALSE,",
    "    .value_raw  = NULL",
    "  )",
    "",
    paste0("# Child level: ", child_var),
    ".chunks[[2L]] <- .data |>",
    gen_group_by(c(gvars, parent_var, child_var), drop = TRUE),
    "  dplyr::summarize(",
    paste0("    .value_raw  = ", raw_expr_c, ","),
    '    .groups     = "drop"',
    "  ) |>",
    "  dplyr::mutate(",
    paste0("    .value      = ", fmt_expr, ","),
    paste0("    .parent     = ", parent_var, ","),
    paste0("    .row_label  = ", child_var, ","),
    paste0("    .stat_label = ", slbl, ","),
    "    .is_child   = TRUE,",
    "    .value_raw  = NULL",
    "  )",
    "",
    # .is_child FALSE < TRUE, so parent rows sort before child rows within each .parent
    ".long <- dplyr::bind_rows(.chunks) |>",
    "  dplyr::arrange(.parent, .is_child, .row_label)",
    "",
    "tidyr::pivot_wider(",
    "  .long,",
    "  id_cols     = c(.parent, .is_child, .row_label, .stat_label),",
    paste0("  names_from  = c(", paste(gvars, collapse = ", "), "),"),
    "  values_from = .value",
    ")"
  )
}
