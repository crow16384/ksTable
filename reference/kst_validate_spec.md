# Validate a JSON DSL table specification

Two-layer validation:

1.  **JSON Schema** (`inst/schema/table_spec_v1.json`): structure,
    required fields, enum values, identifier patterns. Uses
    jsonvalidate + ajv when available; falls back to manual structural
    checks otherwise.

2.  **SR-1 identifier safety** (always): re-checks every identifier that
    will appear in generated R code, ensuring injection is impossible
    regardless of which path ran in layer 1.

## Usage

``` r
kst_validate_spec(json_spec)
```

## Arguments

- json_spec:

  JSON string or path to a `.json` file.

## Value

A named list:

- `valid`:

  Logical. `TRUE` if no errors were found.

- `errors`:

  Character vector of error messages (empty when valid).

- `engine`:

  Character. Validation engine used: `"jsonvalidate"`, `"manual"`, or
  `"none"`.

## See also

[`kst_compile`](https://crow16384.github.io/ksTable/reference/kst_compile.md),
[`kst_save`](https://crow16384.github.io/ksTable/reference/kst_save.md)

## Examples

``` r
spec <- '{
  "schema_version": "1.0",
  "table_spec": {
    "parameter":  { "age": { "variable": "AGE" } },
    "statistics": { "n": { "fun": "length" } },
    "groups":     { "by": ["TRT"] },
    "layout":     { "row_structure": "parameter_stat" }
  }
}'
kst_validate_spec(spec)
#> $valid
#> [1] TRUE
#> 
#> $errors
#> character(0)
#> 
#> $engine
#> [1] "jsonvalidate"
#> 
```
