# R/compile.R ──────────────────────────────────────────────────────────────
# Public API: kst_compile() and kst_generate_table().

#' Compile a JSON DSL table spec to a plain R script
#'
#' Reads a declarative JSON table specification and generates a human-readable
#' dplyr/tidyr R script. The script expects a variable named \code{data} in its
#' evaluation environment. Calc and format functions referenced in the spec (e.g.
#' \code{"fun": "count"}) are emitted as bare calls and resolved from the same
#' environment at runtime — no lists to build, no registry to populate.
#'
#' @param json_spec  JSON string or path to a \code{.json} file.
#' @param metadata   Optional metadata list from \code{\link{kst_extract_metadata}}.
#'                   Currently reserved for future use (ignored).
#'
#' @return \code{character(1)} — a plain R script ready to be read, modified,
#'   saved, or executed with \code{eval(parse(text = code), envir = env)}.
#'
#' @seealso \code{\link{kst_generate_table}}, \code{\link{kst_validate_spec}}
#'
#' @examples
#' spec <- '{
#'   "schema_version": "1.0",
#'   "table_spec": {
#'     "parameter": { "age": { "variable": "AGE", "label": "Age (years)" } },
#'     "statistics": { "n": { "fun": "count", "label": "n" } },
#'     "groups": { "by": ["TRT"] },
#'     "layout": { "row_structure": "parameter_stat", "column_structure": "groups" }
#'   }
#' }'
#' cat(kst_compile(spec))
#'
#' @export
kst_compile <- function(json_spec, metadata = NULL) {
  json_spec <- read_json_spec(json_spec)
  spec      <- jsonlite::fromJSON(json_spec, simplifyVector = FALSE)
  compile_ts(spec$table_spec)
}

#' Generate a formatted table from a JSON DSL spec and a data frame
#'
#' Compiles the spec with \code{\link{kst_compile}}, then evaluates the
#' generated script in an isolated environment whose parent is the caller's
#' frame. This means any calc and format functions defined in the calling
#' environment (or any parent, including attached packages) are automatically
#' visible to the generated code.
#'
#' Intermediate objects (\code{.chunks}, \code{.long}) are created inside the
#' isolated environment and do not pollute the caller's workspace.
#'
#' @param json_spec  JSON string or path to a \code{.json} file.
#' @param data       Input data frame / tibble. Must contain all column names
#'                   referenced in the spec as \code{variable} and \code{by}.
#' @param metadata   Optional metadata list from \code{\link{kst_extract_metadata}}.
#' @param envir      Environment used to resolve calc / format functions.
#'                   Defaults to the caller's frame so that any locally-defined
#'                   functions are visible without explicit passing.
#'
#' @return A tibble with all display-value columns as \code{character}.
#'   Layout columns (\code{.param}, \code{.stat_label} for \code{parameter_stat};
#'   \code{.parent}, \code{.is_child}, \code{.row_label}, \code{.stat_label} for
#'   \code{hierarchical}) identify each row.
#'
#' @seealso \code{\link{kst_compile}}, \code{\link{kst_validate_spec}}
#'
#' @examples
#' \dontrun{
#' # Define calc / format functions in the current environment
#' count   <- function(data) sum(!is.na(data))
#' mean_sd <- function(data) list(mean = mean(data, na.rm = TRUE),
#'                                sd   = sd(data,   na.rm = TRUE))
#' format_mean_sd <- function(x) sprintf("%.1f (%.2f)", x$mean, x$sd)
#'
#' result <- kst_generate_table(spec, adsl)
#' }
#'
#' @export
kst_generate_table <- function(json_spec, data, metadata = NULL,
                               envir = parent.frame()) {
  code <- kst_compile(json_spec, metadata = metadata)

  # Isolated environment: calc/format functions visible via parent chain;
  # intermediate objects (.chunks, .long) stay out of the caller's workspace.
  env       <- new.env(parent = envir)
  env$data  <- data

  eval(parse(text = code), envir = env)
}

# ── Internal helpers ───────────────────────────────────────────────────────

# Accept a JSON string or a file path; always return a JSON string.
read_json_spec <- function(x) {
  stopifnot(is.character(x), length(x) == 1L)
  if (!startsWith(trimws(x), "{")) {
    if (!file.exists(x))
      stop("json_spec does not look like a JSON string and the path '",
           x, "' does not exist.", call. = FALSE)
    x <- paste(readLines(x, warn = FALSE), collapse = "\n")
  }
  x
}
