#' @keywords internal
"_PACKAGE"

# The following imports ensure dplyr and tidyr are available at runtime.
# The generated R scripts emitted by kst_compile() use these packages via
# explicit :: notation; they must be installed for the generated code to run.

#' @importFrom dplyr group_by summarize mutate bind_rows arrange
#' @importFrom tidyr pivot_wider
NULL
