# R/validate.R ─────────────────────────────────────────────────────────────
# JSON DSL schema validation.
#
# Two-layer architecture:
#
#   Layer 1 — JSON Schema (inst/schema/table_spec_v1.json)
#     Validates structure, types, required fields, enum values, and identifier
#     patterns using jsonvalidate + ajv.  Requires jsonvalidate (Suggests).
#     Falls back to manual structural checks when unavailable.
#
#   Layer 2 — SR-1 identifier safety (always runs)
#     Re-validates every identifier that appears in generated R code.
#     Redundant when Layer 1 runs (schema already enforces patterns) but
#     guarantees security even without jsonvalidate installed.

#' Validate a JSON DSL table specification
#'
#' Two-layer validation:
#' \enumerate{
#'   \item \strong{JSON Schema} (\code{inst/schema/table_spec_v1.json}):
#'     structure, required fields, enum values, identifier patterns.
#'     Uses \pkg{jsonvalidate} + ajv when available; falls back to manual
#'     structural checks otherwise.
#'   \item \strong{SR-1 identifier safety} (always): re-checks every identifier
#'     that will appear in generated R code, ensuring injection is impossible
#'     regardless of which path ran in layer 1.
#' }
#'
#' @param json_spec  JSON string or path to a \code{.json} file.
#'
#' @return A named list:
#'   \describe{
#'     \item{\code{valid}}{Logical. \code{TRUE} if no errors were found.}
#'     \item{\code{errors}}{Character vector of error messages (empty when valid).}
#'     \item{\code{engine}}{Character. Validation engine used:
#'       \code{"jsonvalidate"}, \code{"manual"}, or \code{"none"}.}
#'   }
#'
#' @seealso \code{\link{kst_compile}}, \code{\link{kst_save}}
#'
#' @examples
#' spec <- '{
#'   "schema_version": "1.0",
#'   "table_spec": {
#'     "parameter":  { "age": { "variable": "AGE" } },
#'     "statistics": { "n": { "fun": "length" } },
#'     "groups":     { "by": ["TRT"] },
#'     "layout":     { "row_structure": "parameter_stat" }
#'   }
#' }'
#' kst_validate_spec(spec)
#'
#' @export
kst_validate_spec <- function(json_spec) {

  # ── Read JSON ──────────────────────────────────────────────────────────────
  json_spec <- tryCatch(
    read_json_spec(json_spec),
    error = function(e) structure(conditionMessage(e), class = "error_msg")
  )
  if (inherits(json_spec, "error_msg")) {
    return(list(valid = FALSE,
                errors = paste("File error:", json_spec),
                engine = "none"))
  }

  errors <- character(0)
  engine <- "manual"

  # ── Layer 1a: JSON Schema validation via jsonvalidate ─────────────────────
  schema_path <- system.file("schema", "table_spec_v1.json",
                             package = "ksTable", mustWork = FALSE)

  if (nchar(schema_path) > 0L &&
      requireNamespace("jsonvalidate", quietly = TRUE)) {

    schema <- paste(readLines(schema_path, warn = FALSE), collapse = "\n")
    res    <- tryCatch(
      jsonvalidate::json_validate(json_spec, schema,
                                  verbose = TRUE, engine = "ajv"),
      error = function(e) NULL   # ajv unavailable — fall through to manual
    )

    if (!is.null(res)) {
      engine <- "jsonvalidate"
      if (!isTRUE(res)) {
        errs <- attr(res, "errors")
        if (!is.null(errs) && nrow(errs) > 0L) {
          # Support both ajv v6 (dataPath) and ajv v8 (instancePath) error formats
          path <- if ("instancePath" %in% names(errs)) errs$instancePath
                  else if ("dataPath"    %in% names(errs)) errs$dataPath
                  else rep("", nrow(errs))
          errors <- c(errors,
                      paste0(ifelse(nzchar(path), path, "/"), ": ", errs$message))
        }
      }
    }
  }

  # ── Layer 1b: Manual structural checks (fallback when jsonvalidate absent) ─
  if (engine == "manual") {
    errors <- c(errors, validate_structure_manual(json_spec))
  }

  # ── Layer 2: SR-1 identifier safety (always runs) ─────────────────────────
  spec <- tryCatch(
    jsonlite::fromJSON(json_spec, simplifyVector = FALSE),
    error = function(e) NULL
  )
  if (!is.null(spec) && !is.null(spec$table_spec)) {
    errors <- c(errors, validate_identifiers(spec$table_spec))
    # Semantic denom rules (by ⊆ groups.by, args.denom conflict, etc.) —
    # not fully expressible in JSON Schema, so always run.
    errors <- c(errors, validate_denominator_rules(spec$table_spec))
  }

  list(valid  = length(errors) == 0L,
       errors = unique(errors),
       engine = engine)
}

# ── Internal: manual structural checks (Layer 1b fallback) ────────────────────

validate_structure_manual <- function(json_spec) {
  errors <- character(0)

  spec <- tryCatch(
    jsonlite::fromJSON(json_spec, simplifyVector = FALSE),
    error = function(e) {
      errors <<- c(errors, paste0("JSON parse error: ", conditionMessage(e)))
      NULL
    }
  )
  if (is.null(spec)) return(errors)

  ts <- spec$table_spec
  if (is.null(ts))
    return(c(errors, "Missing required field: /table_spec"))

  # Required top-level sections
  for (field in c("parameter", "statistics", "groups", "layout")) {
    if (is.null(ts[[field]]))
      errors <- c(errors, sprintf("Missing required field: /table_spec/%s", field))
  }
  if (length(errors) > 0L) return(errors)

  # layout$row_structure
  rs <- ts$layout$row_structure
  if (is.null(rs)) {
    errors <- c(errors, "Missing required field: /table_spec/layout/row_structure")
  } else if (!rs %in% c("parameter_stat", "hierarchical")) {
    errors <- c(errors, sprintf(
      "/table_spec/layout/row_structure: '%s' must be one of [parameter_stat, hierarchical]", rs))
  }

  # groups$by
  if (is.null(ts$groups$by) || length(ts$groups$by) == 0L)
    errors <- c(errors, "Missing required field: /table_spec/groups/by")

  # statistics: fun required; format type + dependent field required
  for (sn in names(ts$statistics)) {
    s <- ts$statistics[[sn]]

    stat_allowed <- c("fun", "args", "apply_to", "format", "denominator")
    stat_extra   <- setdiff(names(s), stat_allowed)
    if (length(stat_extra) > 0L) {
      errors <- c(errors, sprintf(
        "/table_spec/statistics/%s: must NOT have additional properties: %s",
        sn, paste(stat_extra, collapse = ", ")))
    }

    if (is.null(s$fun))
      errors <- c(errors, sprintf(
        "Missing required field: /table_spec/statistics/%s/fun", sn))

    if (!is.null(s$format)) {
      ftype <- s$format$type
      if (is.null(ftype)) {
        errors <- c(errors, sprintf(
          "Missing required field: /table_spec/statistics/%s/format/type", sn))
      } else if (!ftype %in% c("sprintf", "custom", "template", "ksformat")) {
        errors <- c(errors, sprintf(
          "/table_spec/statistics/%s/format/type: '%s' must be one of [sprintf, custom, template, ksformat]",
          sn, ftype))
      } else {
        dep <- list(sprintf = "pattern", custom = "fun",
                    template = "pattern", ksformat = "format_name")[[ftype]]
        if (is.null(s$format[[dep]]))
          errors <- c(errors, sprintf(
            "Missing required field: /table_spec/statistics/%s/format/%s (required when type = '%s')",
            sn, dep, ftype))
      }
    }
  }

  # parameter: variable required (use [[]] to avoid $-partial-matching variable -> variables)
  for (pn in names(ts$parameter)) {
    p <- ts$parameter[[pn]]
    if (is.null(p[["variable"]]) && is.null(p[["variables"]]))
      errors <- c(errors, sprintf(
        "Missing required field: /table_spec/parameter/%s/variable or /variables", pn))
    if (!is.null(p$nested))
      for (cn in names(p$nested))
        if (is.null(p$nested[[cn]]$variable))
          errors <- c(errors, sprintf(
            "Missing required field: /table_spec/parameter/%s/nested/%s/variable",
            pn, cn))
  }

  errors
}

# ── Internal: denominator semantic rules (always runs) ────────────────────────
# Cross-field rules that JSON Schema cannot fully express (by ⊆ groups.by,
# args.denom conflict, external value required when by is set).

validate_denominator_rules <- function(ts) {
  errors <- character(0)
  if (is.null(ts) || is.null(ts$statistics)) return(errors)

  gby <- unlist(ts$groups$by)

  for (sn in names(ts$statistics)) {
    s <- ts$statistics[[sn]]
    if (is.null(s$denominator)) next

    if (!is.null(s$args) && "denom" %in% names(s$args))
      errors <- c(errors, sprintf(
        "/table_spec/statistics/%s: cannot set both denominator and args.denom", sn))

    d <- s$denominator
    dtype <- d$type
    if (is.null(dtype)) {
      errors <- c(errors, sprintf(
        "Missing required field: /table_spec/statistics/%s/denominator/type", sn))
      next
    }
    if (!dtype %in% c("n", "n_distinct", "data_n", "external")) {
      errors <- c(errors, sprintf(
        "/table_spec/statistics/%s/denominator/type: '%s' must be one of [n, n_distinct, data_n, external]",
        sn, dtype))
      next
    }
    if (dtype == "n_distinct" && is.null(d$variable))
      errors <- c(errors, sprintf(
        "Missing required field: /table_spec/statistics/%s/denominator/variable", sn))
    if (dtype == "data_n" && (is.null(d$by) || length(d$by) == 0L))
      errors <- c(errors, sprintf(
        "Missing required field: /table_spec/statistics/%s/denominator/by", sn))
    if (dtype == "external" && is.null(d$name))
      errors <- c(errors, sprintf(
        "Missing required field: /table_spec/statistics/%s/denominator/name", sn))
    if (dtype == "external" &&
        !is.null(d$by) && length(d$by) > 0L && is.null(d$value))
      errors <- c(errors, sprintf(
        "Missing required field: /table_spec/statistics/%s/denominator/value (required when denominator.by is set)",
        sn))

    dby <- unlist(d$by)
    if (!is.null(dby) && length(dby) > 0L && !is.null(gby)) {
      bad <- setdiff(dby, gby)
      if (length(bad) > 0L)
        errors <- c(errors, sprintf(
          "/table_spec/statistics/%s/denominator/by: %s not in groups.by",
          sn, paste(bad, collapse = ", ")))
    }
  }

  errors
}

# ── Internal: SR-1 identifier safety (Layer 2, always runs) ───────────────────

validate_identifiers <- function(ts) {
  errors <- character(0)
  safe   <- function(x, field)
    tryCatch(assert_id(x, field),
             error = function(e) errors <<- c(errors, conditionMessage(e)))

  if (is.null(ts)) return(errors)

  # parameter variables (use [[]] to avoid $-partial-matching variable -> variables)
  for (pn in names(ts$parameter)) {
    p <- ts$parameter[[pn]]
    if (!is.null(p[["variable"]]))
      safe(p[["variable"]], paste0("parameter.", pn, ".variable"))
    # validate each entry in the variables array
    if (!is.null(p[["variables"]]))
      for (vv in p[["variables"]])
        safe(vv, paste0("parameter.", pn, ".variables[]"))
    if (!is.null(p$nested))
      for (cn in names(p$nested))
        if (!is.null(p$nested[[cn]]$variable))
          safe(p$nested[[cn]]$variable, paste0("nested.", cn, ".variable"))
  }

  # statistics: fun, format.fun, args keys, denominator identifiers
  for (sn in names(ts$statistics)) {
    s <- ts$statistics[[sn]]
    if (!is.null(s$fun))
      safe(s$fun, paste0("statistics.", sn, ".fun"))
    if (!is.null(s$format) && !is.null(s$format$fun))
      safe(s$format$fun, paste0("statistics.", sn, ".format.fun"))
    if (!is.null(s$args))
      for (k in names(s$args))
        safe(k, paste0("statistics.", sn, ".args.", k))
    if (!is.null(s$denominator)) {
      d <- s$denominator
      if (!is.null(d$variable))
        safe(d$variable, paste0("statistics.", sn, ".denominator.variable"))
      if (!is.null(d$distinct))
        safe(d$distinct, paste0("statistics.", sn, ".denominator.distinct"))
      if (!is.null(d$name))
        safe(d$name, paste0("statistics.", sn, ".denominator.name"))
      if (!is.null(d$value))
        safe(d$value, paste0("statistics.", sn, ".denominator.value"))
      if (!is.null(d$by))
        for (bv in d$by)
          safe(bv, paste0("statistics.", sn, ".denominator.by"))
    }
  }

  # groups$by
  if (!is.null(ts$groups$by))
    for (gv in ts$groups$by)
      safe(gv, "groups$by")

  errors
}

