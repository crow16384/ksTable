# R/compiler.R -------------------------------------------------------------
# Internal DSL -> dplyr code generator.
# All functions are package-private; the public API lives in compile.R.
#
# Generated code is a plain R script that expects `data` to be bound in the
# evaluation environment.  Calc and format functions referenced in the JSON
# are emitted as bare function calls resolved from the same environment.
#
# Security (SR-1): every JSON-derived identifier is validated with assert_id();
# every label / pattern string is escaped with r_str() before code emission.

`%||%` <- function(x, y) if (is.null(x)) y else x

# Validate that a JSON field value is a safe R identifier.
# This is the primary code-injection prevention step.
assert_id <- function(x, field) {
  if (!grepl("^[A-Za-z.][A-Za-z0-9._]*$", x))
    stop(sprintf("'%s' is not a valid R identifier (field: %s)", x, field),
         call. = FALSE)
  x
}

# Wrap a plain string in double quotes, escaping \ and ".
r_str <- function(x) {
  x <- gsub("\\",  "\\\\", x, fixed = TRUE)
  x <- gsub('"',   '\\"',  x, fixed = TRUE)
  paste0('"', x, '"')
}

# Emit a group_by() pipe step with correct .drop handling.
gen_group_by <- function(vars, drop) {
  paste0("  dplyr::group_by(",
         paste(vars, collapse = ", "),
         if (!drop) ", .drop = FALSE" else "",
         ") |>")
}

# Serialize a statistics `"args"` object to an extra-arguments string that
# can be appended inside a function call.
#   JSON: { "na.rm": true, "digits": 2 }  ->  R: ", na.rm = TRUE, digits = 2"
# Argument names are validated (SR-1). Values are type-converted to R literals.
# Scalars become bare literals; multi-element arrays become c(...) so vector
# arguments (e.g. probs = c(0.25, 0.5, 0.75)) are emitted safely.
format_args <- function(args) {
  if (is.null(args) || length(args) == 0L) return("")
  nms   <- names(args)
  parts <- character(length(args))
  for (i in seq_along(args)) {
    k    <- assert_id(nms[[i]], paste0("args.", nms[[i]]))
    v    <- args[[i]]
    parts[[i]] <- paste0(k, " = ", r_literal(v))
  }
  paste0(", ", paste(parts, collapse = ", "))
}

# Convert an R value (scalar or vector) to an R literal string.
r_literal <- function(v) {
  if (is.null(v)) return("NULL")
  one <- function(x) {
    if (is.logical(x))   return(if (isTRUE(x)) "TRUE" else "FALSE")
    if (is.numeric(x))   return(format(x, digits = 15, scientific = FALSE, trim = TRUE))
    if (is.character(x)) return(r_str(x))
    as.character(x)
  }
  if (length(v) == 1L) return(one(v))
  paste0("c(", paste(vapply(v, one, character(1L)), collapse = ", "), ")")
}

# TRUE when the format spec expects a list-returning calc function.
# In that case the summarize result is wrapped in list() to form a list-column
# that the format step can unpack element-wise via vapply().
needs_list_wrap <- function(fmt) {
  !is.null(fmt) && (fmt$type %||% "") %in% c("custom", "template")
}

# TRUE when the statistic has an explicit format block in the JSON.
has_format <- function(s) !is.null(s$format) && !is.null(s$format$type)

# Generate a format expression for a raw-value symbol, or NULL when no format
# was specified (caller keeps the raw value - no silent as.character()).
gen_format_expr <- function(s, raw_sym = ".value_raw") {
  if (!has_format(s)) return(NULL)
  fmt <- s$format
  switch(fmt$type %||% "asis",
    sprintf  = sprintf('sprintf(%s, %s)', r_str(fmt$pattern %||% "%s"), raw_sym),
    custom   = {
      f <- assert_id(fmt$fun, "format.fun")
      sprintf('vapply(%s, %s, character(1L))', raw_sym, f)
    },
    template = {
      sprintf(
        'vapply(%s, function(.x) glue::glue_data(.x, %s), character(1L))',
        raw_sym, r_str(fmt$pattern %||% "{value}")
      )
    },
    ksformat = sprintf('ksformat::fput(%s, %s)', raw_sym, r_str(fmt$format_name %||% "")),
    NULL
  )
}

# -- Denominator helpers (statistics.*.denominator -> denom = ...) -----------

# Stable key for deduplicating identical denominator specs.
denom_fingerprint <- function(d) {
  if (is.null(d)) return(NULL)
  paste(
    c(
      d$type %||% "",
      d$variable %||% "",
      paste(unlist(d$by) %||% character(0), collapse = ","),
      d$distinct %||% "",
      d$name %||% "",
      d$value %||% ""
    ),
    collapse = "|"
  )
}

# TRUE when the denom needs a pre-agg / rename table joined onto `data`.
denom_needs_prep <- function(d) {
  if (is.null(d)) return(FALSE)
  type <- d$type %||% ""
  if (identical(type, "data_n")) return(TRUE)
  if (identical(type, "external") && !is.null(d$by) && length(d$by) > 0L)
    return(TRUE)
  FALSE
}

# Collect unique prep denoms from plan rows; assign .kst_d1, .kst_d2, ...
# Returns list of list(col, spec, by). Also annotates plan[[i]]$denom_col.
collect_denom_preps <- function(plan) {
  preps <- list()
  key_to_col <- list()
  next_i <- 0L

  for (i in seq_along(plan)) {
    d <- plan[[i]]$denominator
    if (!denom_needs_prep(d)) next
    key <- denom_fingerprint(d)
    if (!is.null(key_to_col[[key]])) {
      plan[[i]]$denom_col <- key_to_col[[key]]
      next
    }
    next_i <- next_i + 1L
    col <- paste0(".kst_d", next_i)
    key_to_col[[key]] <- col
    plan[[i]]$denom_col <- col
    by <- vapply(unlist(d$by), assert_id, character(1L),
                 field = "denominator.by")
    preps[[length(preps) + 1L]] <- list(col = col, spec = d, by = by)
  }

  list(plan = plan, preps = preps)
}

# Emit R lines that build one prep tibble named `col`.
gen_denom_prep_lines <- function(col, d, by) {
  type <- d$type %||% ""
  if (identical(type, "data_n")) {
    agg <- if (!is.null(d$distinct)) {
      paste0("dplyr::n_distinct(",
             assert_id(d$distinct, "denominator.distinct"), ")")
    } else {
      "dplyr::n()"
    }
    return(c(
      paste0(col, " <- data |>"),
      paste0("  dplyr::group_by(", paste(by, collapse = ", "), ") |>"),
      paste0("  dplyr::summarize(", col, " = ", agg, ', .groups = "drop")'),
      ""
    ))
  }
  if (identical(type, "external")) {
    name  <- assert_id(d$name, "denominator.name")
    value <- assert_id(d$value, "denominator.value")
    return(c(
      paste0(col, " <- ", name, " |>"),
      paste0("  dplyr::select(", paste(c(by, value), collapse = ", "), ") |>"),
      paste0("  dplyr::rename(", col, " = ", value, ")"),
      ""
    ))
  }
  stop("Internal error: unexpected prep denom type '", type, "'.", call. = FALSE)
}

# Emit left_join pipe steps for all prep tables (before group_by).
gen_denom_join_lines <- function(preps) {
  if (length(preps) == 0L) return(character(0))
  vapply(preps, function(p) {
    by_lit <- paste(vapply(p$by, r_str, character(1L)), collapse = ", ")
    paste0("  dplyr::left_join(", p$col, ", by = c(", by_lit, ")) |>")
  }, character(1L))
}

# R expression for denom= inside summarize (or NULL if no denominator).
gen_denom_expr <- function(d, denom_col = NULL) {
  if (is.null(d)) return(NULL)
  type <- d$type %||% ""
  switch(type,
    n = "dplyr::n()",
    n_distinct = paste0(
      "dplyr::n_distinct(",
      assert_id(d$variable, "denominator.variable"), ")"
    ),
    data_n = paste0("dplyr::first(", denom_col, ")"),
    external = {
      if (!is.null(d$by) && length(d$by) > 0L)
        paste0("dplyr::first(", denom_col, ")")
      else
        assert_id(d$name, "denominator.name")
    },
    stop("Unsupported denominator.type: '", type, "'", call. = FALSE)
  )
}

# Append ", denom = <expr>" (and any literal args) for a calc call.
format_call_extras <- function(args, denom_expr = NULL) {
  paste0(
    if (!is.null(denom_expr)) paste0(", denom = ", denom_expr) else "",
    format_args(args)
  )
}

# Expand parameter_stat into ordered calc rows (one per param x var x stat).
# Each row becomes a temporary column `.cN` in a single summarize().
build_calc_plan <- function(ts) {
  params <- ts$parameter
  stats  <- ts$statistics
  plan   <- list()
  idx    <- 0L

  for (pn in names(params)) {
    p <- params[[pn]]

    # Support "variables" (array) as well as the legacy "variable" (scalar).
    # Use [[]] to prevent $-partial-matching of "variable" -> "variables".
    vars_raw <- p[["variables"]] %||% list(p[["variable"]])
    labels_src <- p[["labels"]]
    if (is.null(labels_src)) {
      labels_raw <- lapply(vars_raw, function(v) p[["label"]] %||% v)
    } else {
      labels_raw <- lapply(seq_along(vars_raw), function(i) {
        if (i <= length(labels_src) && !is.null(labels_src[[i]]) &&
            nzchar(as.character(labels_src[[i]])))
          labels_src[[i]]
        else
          vars_raw[[i]]
      })
    }

    for (vi in seq_along(vars_raw)) {
      var <- assert_id(vars_raw[[vi]], paste0("parameter.", pn, ".variable"))
      lbl <- as.character(labels_raw[[vi]] %||% var)

      for (sn in names(stats)) {
        s <- stats[[sn]]

        # apply_to: skip this stat for parameters not listed.
        apply_to <- unlist(s$apply_to)
        if (!is.null(apply_to) && length(apply_to) > 0L &&
            !pn %in% apply_to && !vars_raw[[vi]] %in% apply_to) next

        idx <- idx + 1L
        plan[[idx]] <- list(
          cid         = paste0(".c", idx),
          param_label = lbl,
          stat_key    = sn,
          var         = var,
          fun         = assert_id(s$fun, paste0("statistics.", sn, ".fun")),
          args        = s$args,
          format      = s$format,
          list_wrap   = needs_list_wrap(s$format),
          denominator = s$denominator,
          denom_col   = NULL,
          stat_spec   = s
        )
      }
    }
  }

  plan
}

# -- Layout generators ------------------------------------------------------

# parameter_stat: single group_by + summarize, optional format mutate with
# .keep = "none", pivot_longer to (.param, .stat), pivot_wider on groups.
gen_parameter_stat <- function(ts) {
  by <- ts$groups$by
  if (is.null(by) || length(by) == 0L)
    stop("groups.by must be a non-empty array of column names.", call. = FALSE)
  gvars    <- vapply(by, assert_id, character(1L), field = "groups$by")
  inc_miss <- isTRUE(ts$groups$include_missing_levels)

  if (is.null(ts$parameter) || length(ts$parameter) == 0L)
    stop("parameter map must be non-empty.", call. = FALSE)
  if (is.null(ts$statistics) || length(ts$statistics) == 0L)
    stop("statistics map must be non-empty.", call. = FALSE)

  plan <- build_calc_plan(ts)
  if (length(plan) == 0L)
    stop("No statistics chunks generated. Check that 'parameter' and ",
         "'statistics' are non-empty and that 'apply_to' does not exclude ",
         "every parameter.", call. = FALSE)

  collected <- collect_denom_preps(plan)
  plan  <- collected$plan
  preps <- collected$preps

  # Prep tables for data_n / keyed external denoms
  prep_lines <- unlist(lapply(preps, function(p)
    gen_denom_prep_lines(p$col, p$spec, p$by)), use.names = FALSE)

  cids <- vapply(plan, `[[`, character(1L), "cid")

  # summarize: one expression per plan row (raw values only)
  sum_lines <- character(length(plan))
  for (i in seq_along(plan)) {
    row   <- plan[[i]]
    dexpr <- gen_denom_expr(row$denominator, row$denom_col)
    extra <- format_call_extras(row$args, dexpr)
    raw   <- if (row$list_wrap) {
      paste0("list(", row$fun, "(", row$var, extra, "))")
    } else {
      paste0(row$fun, "(", row$var, extra, ")")
    }
    sum_lines[[i]] <- paste0("    ", row$cid, " = ", raw, ",")
  }

  gvars_csv <- paste(gvars, collapse = ", ")

  fmt_exprs <- lapply(plan, function(row)
    gen_format_expr(row$stat_spec, raw_sym = row$cid))
  needs_format <- any(!vapply(fmt_exprs, is.null, logical(1L)))

  # Named-vector maps from temp ids -> labels / stat keys
  param_map <- paste0(
    "c(",
    paste(vapply(plan, function(row) {
      paste0(r_str(row$cid), " = ", r_str(row$param_label))
    }, character(1L)), collapse = ", "),
    ")"
  )
  stat_map <- paste0(
    "c(",
    paste(vapply(plan, function(row) {
      paste0(r_str(row$cid), " = ", r_str(row$stat_key))
    }, character(1L)), collapse = ", "),
    ")"
  )

  # Optional: one mutate(.keep = "none") to format (and unify types if needed)
  format_block <- NULL
  if (needs_format) {
    keep_gvars <- vapply(gvars, function(g) paste0("    ", g, " = ", g, ","),
                         character(1L))
    fmt_lines <- character(length(plan))
    for (i in seq_along(plan)) {
      row <- plan[[i]]
      expr <- fmt_exprs[[i]]
      if (is.null(expr))
        expr <- paste0("as.character(", row$cid, ")")
      fmt_lines[[i]] <- paste0("    ", row$cid, " = ", expr, ",")
    }
    format_block <- c(
      "  dplyr::mutate(",
      keep_gvars,
      fmt_lines,
      '    .keep = "none"',
      "  ) |>"
    )
  }

  c(prep_lines,
    ".raw <- data |>",
    gen_denom_join_lines(preps),
    gen_group_by(gvars, drop = !inc_miss),
    "  dplyr::summarize(",
    sum_lines,
    '    .groups = "drop"',
    "  )",
    "",
    if (is.null(format_block)) {
      ".long <- .raw |>"
    } else {
      c(".long <- .raw |>", format_block)
    },
    "  tidyr::pivot_longer(",
    paste0("    cols = c(", paste(cids, collapse = ", "), "),"),
    '    names_to = ".cid",',
    '    values_to = ".value"',
    "  ) |>",
    "  dplyr::mutate(",
    paste0("    .param = unname(", param_map, "[.cid]),"),
    paste0("    .stat  = unname(", stat_map, "[.cid]),"),
    "    .cid = NULL",
    "  )",
    "",
    "tidyr::pivot_wider(",
    "  .long,",
    "  id_cols     = c(.param, .stat),",
    paste0("  names_from  = c(", gvars_csv, "),"),
    "  values_from = .value",
    ")"
  )
}

# hierarchical: parent rows + child rows (e.g., SOC -> PT), columns = group levels.
# v0.1 limitation: first parameter, first nested child, first statistic only.
gen_hierarchical <- function(ts) {
  params <- ts$parameter
  stats  <- ts$statistics
  gvars  <- vapply(ts$groups$by, assert_id, character(1L), field = "groups$by")
  inc_miss <- isTRUE(ts$groups$include_missing_levels)

  if (is.null(params) || length(params) == 0L)
    stop("hierarchical layout requires at least one parameter.", call. = FALSE)
  if (is.null(stats) || length(stats) == 0L)
    stop("hierarchical layout requires at least one statistic.", call. = FALSE)

  pn         <- names(params)[[1L]]
  p          <- params[[pn]]
  # Use [[]] access to avoid $-partial-matching "variable" against "variables".
  parent_var <- assert_id(p[["variable"]], paste0("parameter.", pn, ".variable"))

  if (is.null(p$nested) || length(p$nested) == 0L)
    stop("hierarchical layout requires parameter '", pn,
         "' to have a 'nested' child.", call. = FALSE)

  child_n   <- names(p$nested)[[1L]]
  child_p   <- p$nested[[child_n]]
  child_var <- assert_id(child_p[["variable"]], paste0("nested.", child_n, ".variable"))

  if (length(stats) > 1L)
    warning("hierarchical layout uses only the first statistic ('",
            names(stats)[[1L]], "'); ", length(stats) - 1L,
            " other statistic(s) ignored.", call. = FALSE)

  sn   <- names(stats)[[1L]]   # hierarchical: one stat per cell
  s    <- stats[[sn]]
  fun  <- assert_id(s$fun, paste0("statistics.", sn, ".fun"))
  skey <- r_str(sn)

  # Denom prep (same field as parameter_stat; shared across parent/child chunks)
  denom_col <- NULL
  preps <- list()
  if (denom_needs_prep(s$denominator)) {
    denom_col <- ".kst_d1"
    by <- vapply(unlist(s$denominator$by), assert_id, character(1L),
                 field = "denominator.by")
    preps <- list(list(col = denom_col, spec = s$denominator, by = by))
  }
  prep_lines <- unlist(lapply(preps, function(p)
    gen_denom_prep_lines(p$col, p$spec, p$by)), use.names = FALSE)
  join_lines <- gen_denom_join_lines(preps)

  dexpr      <- gen_denom_expr(s$denominator, denom_col)
  extra      <- format_call_extras(s$args, dexpr)
  raw_expr_p <- if (needs_list_wrap(s$format)) paste0("list(", fun, "(", parent_var, extra, "))") else paste0(fun, "(", parent_var, extra, ")")
  raw_expr_c <- if (needs_list_wrap(s$format)) paste0("list(", fun, "(", child_var,  extra, "))") else paste0(fun, "(", child_var,  extra, ")")
  fmt_expr   <- gen_format_expr(s)
  # Keep raw type when no format is specified.
  value_expr <- if (is.null(fmt_expr)) ".value_raw" else fmt_expr

  c(prep_lines,
    ".chunks <- list()", "",
    paste0("# Parent level: ", parent_var),
    ".chunks[[1L]] <- data |>",
    join_lines,
    gen_group_by(c(gvars, parent_var), drop = !inc_miss),
    "  dplyr::summarize(",
    paste0("    .value_raw  = ", raw_expr_p, ","),
    '    .groups     = "drop"',
    "  ) |>",
    "  dplyr::mutate(",
    paste0("    .value      = ", value_expr, ","),
    paste0("    .parent     = ", parent_var, ","),
    paste0("    .row_label  = ", parent_var, ","),
    paste0("    .stat = ", skey, ","),
    "    .is_child   = FALSE,",
    "    .value_raw  = NULL",
    "  )",
    "",
    paste0("# Child level: ", child_var),
    ".chunks[[2L]] <- data |>",
    join_lines,
    gen_group_by(c(gvars, parent_var, child_var), drop = !inc_miss),
    "  dplyr::summarize(",
    paste0("    .value_raw  = ", raw_expr_c, ","),
    '    .groups     = "drop"',
    "  ) |>",
    "  dplyr::mutate(",
    paste0("    .value      = ", value_expr, ","),
    paste0("    .parent     = ", parent_var, ","),
    paste0("    .row_label  = ", child_var, ","),
    paste0("    .stat = ", skey, ","),
    "    .is_child   = TRUE,",
    "    .value_raw  = NULL",
    "  )",
    "",
    "# .is_child: FALSE < TRUE, so parent rows sort before child rows within .parent",
    ".long <- dplyr::bind_rows(.chunks) |>",
    "  dplyr::arrange(.parent, .is_child, .row_label)",
    "",
    "tidyr::pivot_wider(",
    "  .long,",
    "  id_cols     = c(.parent, .is_child, .row_label, .stat),",
    paste0("  names_from  = c(", paste(gvars, collapse = ", "), "),"),
    "  values_from = .value",
    ")"
  )
}

# -- Internal compile entry-point -------------------------------------------

# Compile a parsed table spec to a plain R script string.
# Called by the public kst_compile(); separated to allow future caching.
compile_ts <- function(ts) {
  if (is.null(ts) || !is.list(ts))
    stop("table_spec is missing or not an object.", call. = FALSE)

  row_structure <- ts$layout$row_structure %||% "parameter_stat"

  lines <- switch(row_structure,
    parameter_stat = gen_parameter_stat(ts),
    hierarchical   = gen_hierarchical(ts),
    stop("Unsupported row_structure: '", row_structure, "'", call. = FALSE)
  )

  paste(lines, collapse = "\n")
}
