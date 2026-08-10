# ksTable Architecture Document

**Version**: 2.1  
**Date**: 2026-08-09

------------------------------------------------------------------------

## System Overview

``` text
┌────────────────────────────────────────────────────────────────┐
│                          User Space                            │
│  JSON DSL   │   data frame   │   calc / format functions       │
└──────┬──────┴───────┬────────┴──────────────┬──────────────────┘
       │              │                       │
       ▼              │                       │
┌─────────────────────┼───────────────────────┼──────────────────┐
│  ksTable            │                       │                  │
│  kst_validate_spec  │                       │                  │
│  kst_compile / save │──► R script string    │                  │
│  kst_extract/apply_metadata ──► prepared data                  │
└─────────────────────┼───────────────────────┼──────────────────┘
                      │                       │
                      ▼                       ▼
               new.env(parent = ...) ; env$data <- data
               eval(parse(text = code), envir = env)
                      │
                      ▼
               formatted tibble (.param/.stat or hierarchical ids)
                      │
                      ▼
                    ksTFL
```

Compile validates the JSON and emits a script. Metadata (factor levels,
ksformat labels) is applied by the caller **before** eval when needed.
Calc/format functions are bare names in the generated code and resolve
from the eval environment parent chain.

------------------------------------------------------------------------

## Public API

| Function | Role |
|----|----|
| `kst_validate_spec(json_spec)` | JSON Schema (or manual) + SR-1 identifier walk |
| `kst_compile(json_spec)` | Validate then `compile_ts()` → `character(1)` script |
| `kst_save(json_spec, file, overwrite)` | Compile + header + write file |
| `kst_extract_metadata(data, variables, use_ksformat, format_map)` | Levels / formats |
| `kst_apply_metadata(data, metadata)` | `fput` + factor levels for `.drop = FALSE` |

`groups.format` in JSON is **documentation** for the intended
`format_map`; the compiler does not read it.

**Dependencies** (`DESCRIPTION`): dplyr, tidyr, jsonlite, ksformat
(Imports); jsonvalidate, glue, testthat, knitr, rmarkdown (Suggests).  
`template` formats need **glue** at eval time. Generated code uses
`dplyr::` / `tidyr::` / `ksformat::` explicitly.

------------------------------------------------------------------------

## Generator (`R/compiler.R`)

``` text
JSON → fromJSON → table_spec
  → assert_id / structural guards
  → layout$row_structure
       parameter_stat → build_calc_plan → single summarize + reshape
       hierarchical   → gen_hierarchical (first param, first nested, first stat)
  → character script
```

**`parameter_stat` emission** (one `group_by` + `summarize` for all
calcs):

``` r

.raw <- data |>
  dplyr::group_by(TRT01P) |>
  dplyr::summarize(
    .c1 = count(AGE),
    .c2 = list(mean_sd(AGE)),
    .groups = "drop"
  )

.long <- .raw |>
  dplyr::mutate(
    TRT01P = TRT01P,
    .c1 = sprintf("%d", .c1),
    .c2 = vapply(.c2, format_mean_sd, character(1L)),
    .keep = "none"
  ) |>
  tidyr::pivot_longer(cols = c(.c1, .c2), names_to = ".cid", values_to = ".value") |>
  dplyr::mutate(
    .param = unname(c(".c1" = "Age (years)", ".c2" = "Age (years)")[.cid]),
    .stat  = unname(c(".c1" = "n", ".c2" = "mean_sd")[.cid]),
    .cid = NULL
  )

tidyr::pivot_wider(.long, id_cols = c(.param, .stat), ...)
```

Temp columns `.c1`, `.c2`, … keep labels out of identifiers (SR-1).
Hierarchical still uses two `.chunks` passes (parent vs child group keys
differ).

| `format.type` | Generated expression (on `.cN` / `.value_raw`)            |
|---------------|-----------------------------------------------------------|
| *(none)*      | raw value kept (no `as.character`)                        |
| `sprintf`     | `sprintf("<pattern>", .cN)`                               |
| `custom`      | `vapply(.cN, <fun>, character(1L))`                       |
| `template`    | `vapply(.cN, function(.x) glue::glue_data(.x, ...), ...)` |
| `ksformat`    | `ksformat::fput(.cN, "<format_name>")`                    |

When some statistics use a character format and others do not,
unformatted siblings are coerced with
[`as.character()`](https://rdrr.io/r/base/character.html) only so
`bind_rows` can combine `.value`. Tables with no formats stay numeric.

**Output columns**

- `parameter_stat`: `.param`, `.stat`, then group columns (character
  values)
- `hierarchical`: `.parent`, `.is_child`, `.row_label`, `.stat`, then
  group columns

**SR-1**: identifiers via `assert_id()`; labels/patterns via `r_str()`.

------------------------------------------------------------------------

## Data flow

### Compile

``` text
json_spec → read_json_spec → kst_validate_spec (fail → stop)
          → fromJSON → compile_ts → R code string
```

### Execute (caller)

``` text
optional: meta <- kst_extract_metadata(...); data <- kst_apply_metadata(data, meta)
code <- kst_compile(spec)
env <- new.env(parent = environment()); env$data <- data
result <- eval(parse(text = code), envir = env)
```

------------------------------------------------------------------------

## Error handling

1.  **JSON parse** — `jsonlite` errors
2.  **Validation** — collected messages from `kst_validate_spec`,
    surfaced by compile/save
3.  **Generator guards** — empty chunks after `apply_to`, missing
    hierarchical nested, etc.
4.  **Runtime** — normal R errors inside
    [`eval()`](https://rdrr.io/r/base/eval.html) (missing columns,
    missing functions)
5.  **ksformat** — metadata helpers **warn** on failure (do not swallow
    silently)

------------------------------------------------------------------------

## Performance

Measured compile ~51–62 µs/call (demographics spec). Bottleneck is JSON
parse. Generated dplyr is equivalent to hand-written pipelines.

------------------------------------------------------------------------

## Security (SR-1)

| Field                                  | Use                 | Mitigation  |
|----------------------------------------|---------------------|-------------|
| `parameter[].variable` / `variables[]` | symbol in summarize | `assert_id` |
| `statistics[].fun` / `format.fun`      | bare call / vapply  | `assert_id` |
| `groups.by[]`                          | group_by symbols    | `assert_id` |
| `label`, `pattern`                     | string literals     | `r_str`     |

------------------------------------------------------------------------

## Future (v1.1+)

Documented only — not implemented in 0.2.0:

- `shift_matrix`, `listing`
- Hierarchical nesting depth \> 2; multi-statistic hierarchical
- Sort-before-format / DSL sort options
- Deeper auto-wiring of `groups.format` into metadata helpers

------------------------------------------------------------------------

**Document Version**: 2.1 · **Last Updated**: 2026-08-09
