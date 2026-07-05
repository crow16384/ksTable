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

# Serialize a statistics "args" JSON object to extra R call arguments.
#   { "na.rm": true, "digits": 2 }  →  ", na.rm = TRUE, digits = 2"
format_args <- function(args) {
  if (is.null(args) || length(args) == 0L) return("")
  nms   <- names(args)
  parts <- character(length(args))
  for (i in seq_along(args)) {
    k    <- assert_id(nms[[i]], paste0("args.", nms[[i]]))
    v    <- args[[i]]
    rval <- if (is.logical(v))     { if (v) "TRUE" else "FALSE"
             } else if (is.null(v))    { "NULL"
             } else if (is.numeric(v)) { as.character(v)
             } else if (is.character(v)) { r_str(v)
             } else { as.character(v) }
    parts[[i]] <- paste0(k, " = ", rval)
  }
  paste0(", ", paste(parts, collapse = ", "))
}

# Returns TRUE when the format spec expects a list-returning calc function.
# In that case the generator wraps the summarize result in list() to create
# a list-column so the format step can unpack named fields.
needs_list_wrap <- function(fmt) {
  !is.null(fmt) && (fmt$type %||% "") %in% c("custom", "template")
}

# Generates the format expression for the .value column.
# Every statistic has a formatter; when no format spec is given the default
# formatter is as.character(). All formatters return character, so bind_rows
# across chunks is always type-safe.
gen_format_expr <- function(s) {
  fmt <- s$format
  if (is.null(fmt)) return("as.character(.value_raw)")  # default formatter
  switch(fmt$type %||% "asis",
    sprintf  = sprintf('sprintf(%s, .value_raw)', r_str(fmt$pattern %||% "%s")),
    custom   = {
      f <- assert_id(fmt$fun, "format.fun")
      sprintf('vapply(.value_raw, %s, character(1L))', f)
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

#' Compile a JSON DSL spec to a plain R script (character string).
#'
#' The returned string is a self-contained script that assumes \code{data}
#' is bound in the evaluation environment. The user can step through it
#' interactively, inspect intermediate objects (\code{.chunks}, \code{.long}),
#' or execute the whole thing with \code{eval(parse(text = code))}.
#'
#' @param json_spec  JSON string (not a file path)
#' @return  character(1) — a plain R script
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

      extra    <- format_args(s$args)
      raw_expr <- if (needs_list_wrap(s$format)) {
        paste0("list(", fun, "(", var, extra, "))")  # list-column for multi-field returns
      } else {
        paste0(fun, "(", var, extra, ")")             # scalar: integer, double, or character
      }
      fmt_expr <- gen_format_expr(s)

      lines <- c(lines,
        paste0(".chunks[[", idx, "L]] <- data |>"),
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

  extra      <- format_args(s$args)
  raw_expr_p <- if (needs_list_wrap(s$format)) {
    paste0("list(", fun, "(", parent_var, extra, "))")
  } else {
    paste0(fun, "(", parent_var, extra, ")")
  }
  raw_expr_c <- if (needs_list_wrap(s$format)) {
    paste0("list(", fun, "(", child_var, extra, "))")
  } else {
    paste0(fun, "(", child_var, extra, ")")
  }
  fmt_expr <- gen_format_expr(s)

  c(".chunks <- list()", "",
    paste0("# Parent level: ", parent_var),
    ".chunks[[1L]] <- data |>",
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
    ".chunks[[2L]] <- data |>",
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
    "# parent rows (.is_child = FALSE) sort before child rows within each .parent",
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
