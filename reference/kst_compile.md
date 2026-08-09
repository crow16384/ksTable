# Compile a JSON DSL table spec to a plain R script

Reads a declarative JSON table specification, validates it (same checks
as
[`kst_validate_spec`](https://crow16384.github.io/ksTable/reference/kst_validate_spec.md)),
and generates a human-readable dplyr/tidyr R script. The script expects
a variable named `data` in its evaluation environment. Calc and format
functions referenced in the spec (e.g. `"fun": "count"`) are emitted as
bare calls and resolved from the same environment at runtime — no lists
to build, no registry to populate.

## Usage

``` r
kst_compile(json_spec)
```

## Arguments

- json_spec:

  JSON string or path to a `.json` file.

## Value

`character(1)` — a plain R script ready to be read, modified, saved, or
executed with `eval(parse(text = code), envir = env)`.

## Details

Metadata (factor levels, ksformat labels) is **not** applied during
compile. Use
[`kst_extract_metadata`](https://crow16384.github.io/ksTable/reference/kst_extract_metadata.md)
and
[`kst_apply_metadata`](https://crow16384.github.io/ksTable/reference/kst_apply_metadata.md)
on `data` before evaluating the script when `include_missing_levels` or
group-header formatting is needed. Optional `groups.format` entries in
the JSON are documentation for that pre-eval step (pass them as
`format_map`); the compiler does not read them.

## See also

[`kst_save`](https://crow16384.github.io/ksTable/reference/kst_save.md),
[`kst_validate_spec`](https://crow16384.github.io/ksTable/reference/kst_validate_spec.md),
[`kst_extract_metadata`](https://crow16384.github.io/ksTable/reference/kst_extract_metadata.md),
[`kst_apply_metadata`](https://crow16384.github.io/ksTable/reference/kst_apply_metadata.md)

## Examples

``` r
spec <- '{
  "schema_version": "1.0",
  "table_spec": {
    "parameter": { "age": { "variable": "AGE", "label": "Age (years)" } },
    "statistics": { "n": { "fun": "count" } },
    "groups": { "by": ["TRT"] },
    "layout": { "row_structure": "parameter_stat", "column_structure": "groups" }
  }
}'
cat(kst_compile(spec))
#> .raw <- data |>
#>   dplyr::group_by(TRT) |>
#>   dplyr::summarize(
#>     .c1 = count(AGE),
#>     .groups = "drop"
#>   )
#> 
#> .long <- .raw |>
#>   tidyr::pivot_longer(
#>     cols = c(.c1),
#>     names_to = ".cid",
#>     values_to = ".value"
#>   ) |>
#>   dplyr::mutate(
#>     .param = unname(c(".c1" = "Age (years)")[.cid]),
#>     .stat  = unname(c(".c1" = "n")[.cid]),
#>     .cid = NULL
#>   )
#> 
#> tidyr::pivot_wider(
#>   .long,
#>   id_cols     = c(.param, .stat),
#>   names_from  = c(TRT),
#>   values_from = .value
#> )
```
