# Launch the ksTable Spec Builder (RStudio Addin)

Opens a miniUI gadget with structured forms and a side-by-side JSON
editor for building a ksTable DSL specification. Requires Suggested
packages shiny, miniUI, and rstudioapi. Optional shinyAce improves the
JSON editor.

## Usage

``` r
kst_spec_builder(spec = NULL)
```

## Arguments

- spec:

  Optional starting specification as an R list or JSON string. When
  `NULL`, uses the current RStudio selection if it is valid JSON,
  otherwise loads `inst/examples/demographics_age.json`.

## Value

Invisibly, the final specification list when the gadget is closed with
Done (or `NULL` if cancelled / unavailable).

## Examples

``` r
if (FALSE) { # \dontrun{
kst_spec_builder()
} # }
```
