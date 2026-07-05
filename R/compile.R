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
#' @param metadata   Optional pre-extracted metadata list from
#'   \code{\link{kst_extract_metadata}}. When \code{NULL} (default) and the spec
#'   contains \code{groups.format} entries, metadata is extracted automatically
#'   when ksformat is installed.
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
  raw_json <- read_json_spec(json_spec)
  ts       <- jsonlite::fromJSON(raw_json, simplifyVector = FALSE)$table_spec

  # Auto-extract and apply ksformat group-variable metadata when
  # groups.format is present in the spec and ksformat is installed.
  # This converts raw codes to display labels and sets factor levels,
  # enabling formatted column headers and include_missing_levels = true.
  if (is.null(metadata) &&
      !is.null(ts$groups$format) &&
      requireNamespace("ksformat", quietly = TRUE)) {
    gvars <- unlist(ts$groups$by)
    fmap  <- as.list(ts$groups$format)          # variable -> ksformat name
    meta  <- kst_extract_metadata(data, gvars, format_map = fmap)
    data  <- kst_apply_metadata(data, meta)
  } else if (!is.null(metadata)) {
    data <- kst_apply_metadata(data, metadata)
  }

  code     <- compile_ts(ts)
  env      <- new.env(parent = envir)
  env$data <- data
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

#' Save a compiled table script to an R file
#'
#' Compiles the spec with \code{\link{kst_compile}} and writes the resulting
#' R script to a file with an informational header comment block.  The saved
#' file is a self-contained plain R script that can be read, reviewed, version-
#' controlled, or sourced directly.
#'
#' To execute the saved script:
#' \preformatted{
#' env      <- new.env(parent = environment())
#' env$data <- my_data
#' result   <- source("my_table.R", local = env)$value
#' }
#'
#' @param json_spec  JSON string or path to a \code{.json} file.
#' @param file       Output path (typically a \code{.R} file).
#' @param metadata   Optional metadata list; passed to
#'   \code{\link{kst_compile}} (currently unused by the compiler but reserved).
#' @param overwrite  Logical. If \code{FALSE} (default), stops when \code{file}
#'   already exists, protecting manually-edited scripts.
#'
#' @return The normalised absolute path to the written file, invisibly.
#'
#' @seealso \code{\link{kst_compile}}, \code{\link{kst_generate_table}}
#'
#' @examples
#' spec <- '{
#'   "schema_version": "1.0",
#'   "table_spec": {
#'     "id": "demo",
#'     "parameter":  { "age": { "variable": "AGE" } },
#'     "statistics": { "n": { "fun": "length" } },
#'     "groups":     { "by": ["TRT"] },
#'     "layout":     { "row_structure": "parameter_stat" }
#'   }
#' }'
#' tmp <- tempfile(fileext = ".R")
#' kst_save(spec, tmp)
#' cat(readLines(tmp), sep = "\n")
#'
#' @export
kst_save <- function(json_spec, file, metadata = NULL, overwrite = FALSE) {
  if (!overwrite && file.exists(file))
    stop("'", file, "' already exists. Use overwrite = TRUE to replace it.",
         call. = FALSE)

  raw_json <- read_json_spec(json_spec)
  ts       <- jsonlite::fromJSON(raw_json, simplifyVector = FALSE)$table_spec
  code     <- compile_ts(ts)

  ver   <- tryCatch(as.character(utils::packageVersion("ksTable")),
                    error = function(e) "?")
  fname <- basename(file)

  header <- c(
    paste0("# Generated by ksTable ", ver,
           "  (", format(Sys.time(), "%Y-%m-%d %H:%M"), ")"),
    paste0("# id:     ", ts$id    %||% "(none)"),
    paste0("# title:  ", ts$title %||% "(none)"),
    paste0("# layout: ", ts$layout$row_structure %||% "parameter_stat"),
    "#",
    "# Usage:",
    "#   env      <- new.env(parent = environment())",
    "#   env$data <- <your_data_frame>",
    paste0("#   result   <- source(\"", fname, "\", local = env)$value"),
    ""
  )

  writeLines(c(header, code), file)
  invisible(normalizePath(file))
}
