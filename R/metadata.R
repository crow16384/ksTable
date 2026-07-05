# R/metadata.R ─────────────────────────────────────────────────────────────
# Metadata extraction for the ksTable compiler.
#
# kst_extract_metadata() ensures that grouping variables are proper factors
# with the correct levels so that group_by(..., .drop = FALSE) works correctly
# when include_missing_levels = true is set in the spec.

#' Extract variable metadata from a data frame
#'
#' Reads factor levels (and optionally ksformat VALUE format labels) for the
#' specified variables. The returned metadata list is passed to
#' \code{\link{kst_compile}} / \code{\link{kst_generate_table}} and is used
#' to set up factor levels before the generated script runs, enabling correct
#' handling of \code{include_missing_levels}.
#'
#' Priority for level discovery:
#' \enumerate{
#'   \item ksformat VALUE format metadata (if \code{use_ksformat = TRUE} and the
#'         ksformat package is installed and a format is registered for the variable)
#'   \item Existing factor levels (\code{levels(col)})
#'   \item Sorted distinct non-NA values (\code{sort(unique(col[!is.na(col)]))})
#' }
#'
#' @param data         Input data frame / tibble.
#' @param variables    Character vector of variable names to extract metadata for.
#' @param use_ksformat Logical. Query ksformat for VALUE format metadata.
#'                     Default \code{TRUE}; silently ignored if ksformat is not installed.
#'
#' @return A named list, one entry per variable:
#'   \describe{
#'     \item{\code{type}}{Character. R class of the column (e.g. \code{"factor"}).}
#'     \item{\code{levels}}{Character vector of ordered levels.}
#'     \item{\code{format}}{Character or \code{NULL}. ksformat format name if found.}
#'   }
#'
#' @examples
#' \dontrun{
#' adsl <- tibble::tibble(
#'   TRT = factor(c("A", "B"), levels = c("Placebo", "Drug A", "Drug B"))
#' )
#' meta <- kst_extract_metadata(adsl, "TRT")
#' meta$TRT$levels  # "Placebo" "Drug A" "Drug B"
#' }
#'
#' @export
kst_extract_metadata <- function(data, variables, use_ksformat = TRUE) {
  stopifnot(is.data.frame(data))

  result <- vector("list", length(variables))
  names(result) <- variables

  has_ksformat <- use_ksformat &&
    requireNamespace("ksformat", quietly = TRUE)

  for (v in variables) {
    if (!v %in% names(data)) {
      warning(sprintf("kst_extract_metadata: variable '%s' not found in data", v),
              call. = FALSE)
      next
    }

    col    <- data[[v]]
    levels <- NULL
    fmt    <- NULL

    # 1. Try ksformat
    if (has_ksformat) {
      fmt <- tryCatch(
        ksformat::fget(v),   # returns format name if registered
        error = function(e) NULL
      )
      if (!is.null(fmt)) {
        levels <- tryCatch(
          names(ksformat::flevels(fmt)),
          error = function(e) NULL
        )
      }
    }

    # 2. Factor levels
    if (is.null(levels) && is.factor(col)) {
      levels <- levels(col)
    }

    # 3. Distinct values
    if (is.null(levels)) {
      levels <- as.character(sort(unique(col[!is.na(col)])))
    }

    result[[v]] <- list(
      type   = class(col)[[1L]],
      levels = levels,
      format = fmt
    )
  }

  result
}

#' Apply extracted metadata to a data frame
#'
#' Converts grouping variables to ordered factors using the levels from
#' \code{\link{kst_extract_metadata}}. This is required for
#' \code{include_missing_levels = true} to work correctly via
#' \code{group_by(..., .drop = FALSE)}.
#'
#' @param data      Input data frame.
#' @param metadata  List from \code{\link{kst_extract_metadata}}.
#'
#' @return The data frame with factor variables re-levelled.
#'
#' @export
kst_apply_metadata <- function(data, metadata) {
  for (v in names(metadata)) {
    meta <- metadata[[v]]
    if (v %in% names(data) && !is.null(meta$levels)) {
      data[[v]] <- factor(data[[v]], levels = meta$levels)
    }
  }
  data
}
