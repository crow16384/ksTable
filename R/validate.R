# R/validate.R ─────────────────────────────────────────────────────────────
# JSON DSL schema validation.

#' Validate a JSON DSL table specification
#'
#' Parses and validates the spec without generating any code. Returns a list
#' with a logical \code{valid} flag and a \code{errors} character vector.
#' Useful for giving early, informative feedback to users before they attempt
#' to compile or run a table.
#'
#' Validation checks:
#' \itemize{
#'   \item JSON parses without error
#'   \item Required top-level sections are present (\code{parameter},
#'         \code{statistics}, \code{groups}, \code{layout})
#'   \item All \code{variable} and \code{fun} values are valid R identifiers
#'         (SR-1 injection prevention)
#'   \item \code{groups$by} values are valid R identifiers
#' }
#'
#' @param json_spec  JSON string or path to a \code{.json} file.
#'
#' @return A named list:
#'   \describe{
#'     \item{\code{valid}}{Logical. \code{TRUE} if no errors were found.}
#'     \item{\code{errors}}{Character vector of error messages (empty when valid).}
#'   }
#'
#' @examples
#' spec <- '{"schema_version":"1.0","table_spec":{"parameter":{},"statistics":{},
#'            "groups":{"by":["TRT"]},"layout":{"row_structure":"parameter_stat"}}}'
#' kst_validate_spec(spec)
#'
#' @export
kst_validate_spec <- function(json_spec) {
  json_spec <- tryCatch(read_json_spec(json_spec),
                        error = function(e) { structure(conditionMessage(e), class = "error_msg") })

  errors <- character(0)

  if (inherits(json_spec, "error_msg")) {
    return(list(valid = FALSE, errors = paste("File error:", json_spec)))
  }

  # 1. Parse JSON
  spec <- tryCatch(
    jsonlite::fromJSON(json_spec, simplifyVector = FALSE),
    error = function(e) {
      errors <<- c(errors, paste0("JSON parse error: ", conditionMessage(e)))
      NULL
    }
  )
  if (is.null(spec)) return(list(valid = FALSE, errors = errors))

  ts <- spec$table_spec
  if (is.null(ts)) {
    return(list(valid = FALSE,
                errors = "Missing required field: /table_spec"))
  }

  # 2. Required sections
  for (field in c("parameter", "statistics", "groups", "layout")) {
    if (is.null(ts[[field]]))
      errors <- c(errors, sprintf("Missing required field: /table_spec/%s", field))
  }
  if (length(errors) > 0L) return(list(valid = FALSE, errors = errors))

  # 3. Validate parameter identifiers (SR-1)
  for (pn in names(ts$parameter)) {
    p <- ts$parameter[[pn]]
    if (is.null(p$variable)) {
      errors <- c(errors, sprintf(
        "Missing required field: /table_spec/parameter/%s/variable", pn))
    } else {
      tryCatch(
        assert_id(p$variable, paste0("parameter.", pn, ".variable")),
        error = function(e) errors <<- c(errors, conditionMessage(e))
      )
    }
    # Validate nested parameters
    if (!is.null(p$nested)) {
      for (cn in names(p$nested)) {
        cp <- p$nested[[cn]]
        if (is.null(cp$variable)) {
          errors <- c(errors, sprintf(
            "Missing required field: /table_spec/parameter/%s/nested/%s/variable", pn, cn))
        } else {
          tryCatch(
            assert_id(cp$variable, paste0("nested.", cn, ".variable")),
            error = function(e) errors <<- c(errors, conditionMessage(e))
          )
        }
      }
    }
  }

  # 4. Validate statistic fun identifiers (SR-1)
  for (sn in names(ts$statistics)) {
    s <- ts$statistics[[sn]]
    if (is.null(s$fun)) {
      errors <- c(errors, sprintf(
        "Missing required field: /table_spec/statistics/%s/fun", sn))
    } else {
      tryCatch(
        assert_id(s$fun, paste0("statistics.", sn, ".fun")),
        error = function(e) errors <<- c(errors, conditionMessage(e))
      )
    }
    # Validate format.fun if present
    if (!is.null(s$format) && !is.null(s$format$fun)) {
      tryCatch(
        assert_id(s$format$fun, paste0("statistics.", sn, ".format.fun")),
        error = function(e) errors <<- c(errors, conditionMessage(e))
      )
    }
  }

  # 5. Validate group-by identifiers (SR-1)
  if (!is.null(ts$groups$by)) {
    for (gv in ts$groups$by) {
      tryCatch(
        assert_id(gv, "groups$by"),
        error = function(e) errors <<- c(errors, conditionMessage(e))
      )
    }
  } else {
    errors <- c(errors, "Missing required field: /table_spec/groups/by")
  }

  list(valid = length(errors) == 0L, errors = errors)
}
