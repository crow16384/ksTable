# R/addin_spec_builder.R ───────────────────────────────────────────────────
# RStudio Addin launcher for the Spec Builder gadget.

#' Launch the ksTable Spec Builder (RStudio Addin)
#'
#' Opens a \pkg{miniUI} gadget with structured forms and a side-by-side JSON
#' editor for building a ksTable DSL specification. Requires Suggested packages
#' \pkg{shiny}, \pkg{miniUI}, and \pkg{rstudioapi}. Optional \pkg{shinyAce}
#' improves the JSON editor.
#'
#' @param spec Optional starting specification as an R list or JSON string.
#'   When \code{NULL}, uses the current RStudio selection if it is valid JSON,
#'   otherwise loads \code{inst/examples/demographics_age.json}.
#'
#' @return Invisibly, the final specification list when the gadget is closed
#'   with Done (or \code{NULL} if cancelled / unavailable).
#'
#' @examples
#' \dontrun{
#' kst_spec_builder()
#' }
#'
#' @export
kst_spec_builder <- function(spec = NULL) {
  missing <- character(0)
  for (pkg in c("shiny", "miniUI", "rstudioapi")) {
    if (!requireNamespace(pkg, quietly = TRUE))
      missing <- c(missing, pkg)
  }
  if (length(missing) > 0L) {
    stop(
      "ksTable Spec Builder requires Suggested packages: ",
      paste(missing, collapse = ", "),
      ".\nInstall with: install.packages(c(",
      paste(sprintf('"%s"', missing), collapse = ", "),
      "))",
      call. = FALSE
    )
  }

  if (is.null(spec)) {
    start <- spec_initial()
  } else if (is.character(spec)) {
    parsed <- json_to_spec(paste(spec, collapse = "\n"))
    if (!isTRUE(parsed$ok))
      stop("Invalid starting JSON: ", parsed$error, call. = FALSE)
    start <- parsed$spec
  } else if (is.list(spec)) {
    start <- spec
  } else {
    stop("'spec' must be NULL, a JSON string, or a list.", call. = FALSE)
  }

  app <- spec_builder_app(start_spec = start)
  shiny::runGadget(
    app,
    viewer = shiny::dialogViewer("ksTable Spec Builder", width = 1200, height = 800),
    stopOnCancel = TRUE
  )
}
