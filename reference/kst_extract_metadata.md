# Extract variable metadata from a data frame

Reads factor levels (and optionally ksformat VALUE format labels) for
the specified variables. The returned metadata list can be passed to
[`kst_apply_metadata`](https://crow16384.github.io/ksTable/reference/kst_apply_metadata.md)
before evaluating generated code, enabling correct handling of
`include_missing_levels`.

## Usage

``` r
kst_extract_metadata(data, variables, use_ksformat = TRUE, format_map = list())
```

## Arguments

- data:

  Input data frame / tibble.

- variables:

  Character vector of variable names to extract metadata for.

- use_ksformat:

  Logical. Enable ksformat integration. Default `TRUE`. Ignored when
  `format_map` is empty.

- format_map:

  Named list mapping variable names to ksformat format names, e.g.
  `list(TRT01P = "trt_fmt")`. Drives level discovery and triggers
  code-to-label conversion in
  [`kst_apply_metadata`](https://crow16384.github.io/ksTable/reference/kst_apply_metadata.md).
  Use the same mapping as optional `groups.format` in the JSON DSL.

## Value

A named list, one entry per variable:

- `type`:

  Character. R class of the column.

- `levels`:

  Character vector of ordered display-string levels.

- `format_name`:

  Character or `NULL`. ksformat format name, used by
  [`kst_apply_metadata`](https://crow16384.github.io/ksTable/reference/kst_apply_metadata.md)
  to apply [`fput()`](https://rdrr.io/pkg/ksformat/man/fput.html).

## Details

Level discovery priority:

1.  **ksformat**: when a format name is supplied in `format_map`, the
    complete set of registered codes is retrieved via
    [`format_get()`](https://rdrr.io/pkg/ksformat/man/format_get.html),
    then converted to display labels via
    [`fput()`](https://rdrr.io/pkg/ksformat/man/fput.html). The labels
    (in registration order) become the factor levels.

2.  Existing factor levels (`levels(col)`).

3.  Sorted distinct non-NA values.

## Examples

``` r
if (FALSE) { # \dontrun{
library(ksformat)
fnew("A" = "Drug A", "P" = "Placebo", name = "trt_fmt")
meta <- kst_extract_metadata(adsl, "TRT01P",
                              format_map = list(TRT01P = "trt_fmt"))
meta$TRT01P$levels   # c("Drug A", "Placebo")
fclear()
} # }
```
