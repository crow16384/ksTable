# R/metadata.R -------------------------------------------------------------
# Metadata extraction for the ksTable compiler.
#
# kst_extract_metadata() ensures that grouping variables are proper factors
# with the correct levels so that group_by(..., .drop = FALSE) works correctly
# when include_missing_levels = true is set in the spec.
# Apply with kst_apply_metadata() *before* evaluating generated code.
# Optional groups.format in the JSON is not applied by kst_compile(); pass the
# same mapping as format_map here.

#' Extract variable metadata from a data frame
#'
#' Reads factor levels (and optionally ksformat VALUE format labels) for the
#' specified variables. The returned metadata list can be passed to
#' \code{\link{kst_apply_metadata}} before evaluating generated code, enabling correct
#' handling of \code{include_missing_levels}.
#'
#' Level discovery priority:
#' \enumerate{
#'   \item \strong{ksformat}: when a format name is supplied in
#'     \code{format_map}, the complete set of registered codes is retrieved
#'     via \code{format_get()}, then converted to display labels via
#'     \code{fput()}.  The labels (in registration order) become the factor
#'     levels.
#'   \item Existing factor levels (\code{levels(col)}).
#'   \item Sorted distinct non-NA values.
#' }
#'
#' @param data         Input data frame / tibble.
#' @param variables    Character vector of variable names to extract metadata for.
#' @param use_ksformat Logical. Enable ksformat integration.
#'                     Default \code{TRUE}. Ignored when \code{format_map} is empty.
#' @param format_map   Named list mapping variable names to ksformat format names,
#'                     e.g. \code{list(TRT01P = "trt_fmt")}.  Drives level
#'                     discovery and triggers code-to-label conversion in
#'                     \code{\link{kst_apply_metadata}}. Use the same mapping as
#'                     optional \code{groups.format} in the JSON DSL.
#'
#' @return A named list, one entry per variable:
#'   \describe{
#'     \item{\code{type}}{Character. R class of the column.}
#'     \item{\code{levels}}{Character vector of ordered display-string levels.}
#'     \item{\code{format_name}}{Character or \code{NULL}. ksformat format name,
#'       used by \code{\link{kst_apply_metadata}} to apply \code{fput()}.}
#'   }
#'
#' @examples
#' \dontrun{
#' library(ksformat)
#' fnew("A" = "Drug A", "P" = "Placebo", name = "trt_fmt")
#' meta <- kst_extract_metadata(adsl, "TRT01P",
#'                               format_map = list(TRT01P = "trt_fmt"))
#' meta$TRT01P$levels   # c("Drug A", "Placebo")
#' fclear()
#' }
#'
#' @export
kst_extract_metadata <- function(data, variables, use_ksformat = TRUE,
                                  format_map = list()) {
  stopifnot(is.data.frame(data))

  result       <- vector("list", length(variables))
  names(result) <- variables

  for (v in variables) {
    if (!v %in% names(data)) {
      warning(sprintf("kst_extract_metadata: variable '%s' not found in data", v),
              call. = FALSE)
      next
    }

    col         <- data[[v]]
    levels      <- NULL
    format_name <- format_map[[v]]    # NULL when not supplied

    # 1. ksformat: format_get() retrieves the ks_format object;
    #    names(fmt$mappings) are the raw input codes (in registration order);
    #    fput() converts them to display labels which become the factor levels.
    #    The .missing label (if defined) is appended so NA values converted
    #    by fput() are included as a proper factor level.
    if (use_ksformat && !is.null(format_name)) {
      tryCatch({
        fmt_obj <- ksformat::format_get(format_name)
        codes   <- names(fmt_obj$mappings)
        labels  <- ksformat::fput(codes, fmt_obj)
        # Include .missing label so NA -> .missing is a valid factor level
        if (!is.null(fmt_obj$missing_label))
          labels <- c(labels, fmt_obj$missing_label)
        levels  <- labels
      }, error = function(e) {
        warning(sprintf(
          "kst_extract_metadata: ksformat failed for '%s' (format '%s'): %s",
          v, format_name, conditionMessage(e)
        ), call. = FALSE)
        NULL
      })
    }

    # 2. Existing factor levels
    if (is.null(levels) && is.factor(col))
      levels <- levels(col)

    # 3. Sorted distinct values
    if (is.null(levels))
      levels <- as.character(sort(unique(col[!is.na(col)])))

    result[[v]] <- list(
      type        = class(col)[[1L]],
      levels      = levels,
      format_name = format_name
    )
  }

  result
}

#' Apply extracted metadata to a data frame
#'
#' For each variable in \code{metadata}:
#' \enumerate{
#'   \item If a \code{format_name} is recorded (from \code{format_map} in
#'     \code{\link{kst_extract_metadata}}), applies \code{ksformat::fput()} to
#'     replace raw codes with display labels.
#'   \item Converts the column to an ordered factor with the levels from
#'     the metadata, including any levels absent from the data (required for
#'     \code{include_missing_levels = true} via \code{group_by(..., .drop = FALSE)}).
#' }
#'
#' Call this on \code{data} \strong{before} evaluating code from
#' \code{\link{kst_compile}}. Compile does not apply metadata.
#'
#' @param data      Input data frame.
#' @param metadata  List from \code{\link{kst_extract_metadata}}.
#'
#' @return The data frame with columns re-coded and re-levelled.
#'
#' @export
kst_apply_metadata <- function(data, metadata) {
  for (v in names(metadata)) {
    meta <- metadata[[v]]
    if (!v %in% names(data) || is.null(meta$levels)) next

    # Step 1: convert raw codes -> display labels via fput()
    if (!is.null(meta$format_name)) {
      tryCatch({
        data[[v]] <- ksformat::fput(data[[v]], meta$format_name)
      }, error = function(e) {
        warning(sprintf(
          "kst_apply_metadata: ksformat failed for '%s' (format '%s'): %s",
          v, meta$format_name, conditionMessage(e)
        ), call. = FALSE)
      })
    }

    # Step 2: set as ordered factor (levels include absent ones)
    data[[v]] <- factor(data[[v]], levels = meta$levels)
  }
  data
}
