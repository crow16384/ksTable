# R/spec_builder_helpers.R -------------------------------------------------
# Package-private helpers for the Spec Builder addin (JSON <-> list).

# Pretty-print a DSL list to a JSON string.
spec_to_json <- function(spec_list) {
  stopifnot(is.list(spec_list))
  as.character(
    jsonlite::toJSON(
      spec_list,
      auto_unbox = TRUE,
      null = "null",
      pretty = TRUE,
      digits = NA
    )
  )
}

# Parse JSON text to a DSL list (simplifyVector = FALSE).
# Returns list(ok=, spec=, error=).
json_to_spec <- function(text) {
  text <- paste(text %||% "", collapse = "\n")
  if (!nzchar(trimws(text)))
    return(list(ok = FALSE, spec = NULL, error = "JSON is empty."))
  spec <- tryCatch(
    jsonlite::fromJSON(text, simplifyVector = FALSE),
    error = function(e) e
  )
  if (inherits(spec, "error"))
    return(list(ok = FALSE, spec = NULL, error = conditionMessage(spec)))
  if (!is.list(spec) || is.null(spec$table_spec))
    return(list(ok = FALSE, spec = NULL,
                error = "JSON must be an object with a 'table_spec' field."))
  list(ok = TRUE, spec = spec, error = NULL)
}

# Minimal empty-but-validish starter (still needs fun/variable filled for compile).
spec_empty <- function() {
  list(
    schema_version = "1.0",
    table_spec = list(
      id = "my_table",
      title = "",
      parameter = list(
        age = list(variable = "AGE", label = "Age")
      ),
      statistics = list(
        n = list(fun = "length")
      ),
      groups = list(
        by = list("TRT01P"),
        include_missing_levels = FALSE
      ),
      layout = list(
        row_structure = "parameter_stat",
        column_structure = "groups"
      )
    )
  )
}

# Load a named example from inst/examples/<name>.json (name without .json).
spec_from_example <- function(name) {
  stopifnot(is.character(name), length(name) == 1L)
  name <- sub("\\.json$", "", name)
  path <- system.file("examples", paste0(name, ".json"),
                      package = "ksTable", mustWork = FALSE)
  if (!nzchar(path) || !file.exists(path))
    stop("Unknown example: '", name, "'.", call. = FALSE)
  raw <- paste(readLines(path, warn = FALSE), collapse = "\n")
  parsed <- json_to_spec(raw)
  if (!isTRUE(parsed$ok))
    stop("Failed to parse example '", name, "': ", parsed$error, call. = FALSE)
  parsed$spec
}

# List available example basenames (no .json).
spec_list_examples <- function() {
  dir <- system.file("examples", package = "ksTable", mustWork = FALSE)
  if (!nzchar(dir) || !dir.exists(dir)) return(character(0))
  sub("\\.json$", "", list.files(dir, pattern = "\\.json$"))
}

# Validate JSON text or a list; always returns kst_validate_spec-shaped list.
spec_validate_live <- function(text_or_list) {
  json <- if (is.character(text_or_list)) {
    paste(text_or_list, collapse = "\n")
  } else {
    spec_to_json(text_or_list)
  }
  kst_validate_spec(json)
}

# Best-effort: read current RStudio selection as JSON text, or NULL.
spec_selection_text <- function() {
  if (!requireNamespace("rstudioapi", quietly = TRUE)) return(NULL)
  if (!isTRUE(rstudioapi::isAvailable())) return(NULL)
  ctx <- tryCatch(rstudioapi::getActiveDocumentContext(), error = function(e) NULL)
  if (is.null(ctx)) return(NULL)
  sel <- ctx$selection
  if (is.null(sel) || length(sel) < 1L) return(NULL)
  txt <- sel[[1L]]$text
  if (!nzchar(trimws(txt %||% ""))) return(NULL)
  txt
}

# Initial spec for the gadget: selection -> demographics_age example -> empty.
spec_initial <- function() {
  sel <- spec_selection_text()
  if (!is.null(sel)) {
    parsed <- json_to_spec(sel)
    if (isTRUE(parsed$ok)) return(parsed$spec)
  }
  ex <- tryCatch(spec_from_example("demographics_age"), error = function(e) NULL)
  if (!is.null(ex)) return(ex)
  spec_empty()
}
