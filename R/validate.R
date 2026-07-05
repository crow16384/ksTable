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
#' @seealso \code{\link{kst_compile}}, \code{\link{kst_generate_table}}
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

  # parameter: variable required
  for (pn in names(ts$parameter)) {
    p <- ts$parameter[[pn]]
    if (is.null(p$variable))
      errors <- c(errors, sprintf(
        "Missing required field: /table_spec/parameter/%s/variable", pn))
    if (!is.null(p$nested))
      for (cn in names(p$nested))
        if (is.null(p$nested[[cn]]$variable))
          errors <- c(errors, sprintf(
            "Missing required field: /table_spec/parameter/%s/nested/%s/variable",
            pn, cn))
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

  # parameter variables
  for (pn in names(ts$parameter)) {
    p <- ts$parameter[[pn]]
    if (!is.null(p$variable))
      safe(p$variable, paste0("parameter.", pn, ".variable"))
    if (!is.null(p$nested))
      for (cn in names(p$nested))
        if (!is.null(p$nested[[cn]]$variable))
          safe(p$nested[[cn]]$variable, paste0("nested.", cn, ".variable"))
  }

  # statistics: fun, format.fun, args keys
  for (sn in names(ts$statistics)) {
    s <- ts$statistics[[sn]]
    if (!is.null(s$fun))
      safe(s$fun, paste0("statistics.", sn, ".fun"))
    if (!is.null(s$format) && !is.null(s$format$fun))
      safe(s$format$fun, paste0("statistics.", sn, ".format.fun"))
    if (!is.null(s$args))
      for (k in names(s$args))
        safe(k, paste0("statistics.", sn, ".args.", k))
  }

  # groups$by
  if (!is.null(ts$groups$by))
    for (gv in ts$groups$by)
      safe(gv, "groups$by")

  errors
}

