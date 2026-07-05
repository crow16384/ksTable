# News

## ksTable 0.1.0 (2026-07-05)

First release. Core DSL-to-dplyr compiler and package infrastructure.

### New features

* `kst_compile(json_spec)` — compiles a JSON table specification to a
  plain, human-readable R script. Calc and format functions referenced in
  the spec are emitted as bare function calls resolved from the evaluation
  environment at runtime.

* `kst_generate_table(json_spec, data)` — end-to-end: compile + execute.
  Runs the generated script in an isolated `new.env(parent = envir)` so
  intermediate objects (`.chunks`, `.long`) never pollute the caller's
  workspace.

* `kst_validate_spec(json_spec)` — two-layer validation:
  1. JSON Schema (`inst/schema/table_spec_v1.json`, JSON Schema Draft-07)
     via `jsonvalidate` + ajv when installed; manual structural checks
     otherwise.
  2. SR-1 identifier safety: `assert_id()` on every JSON-derived symbol
     that appears in generated R code.

* `kst_extract_metadata(data, variables)` / `kst_apply_metadata(data, meta)`
  — factor level extraction and re-levelling for `include_missing_levels`.

### Supported layouts

* `parameter_stat` — one row per parameter × statistic; columns = group levels.
* `hierarchical` — parent rows + child rows (e.g., SOC → PT).

### Format types

* *(none)* → `as.character()` (default)
* `"sprintf"` → `sprintf(pattern, .value_raw)`
* `"custom"` → `vapply(.value_raw, format_fn, character(1L))`
* `"template"` → `vapply(.value_raw, glue::glue_data, character(1L))`
* `"ksformat"` → `ksformat::fput(.value_raw, format_name)`

### Extra function arguments from JSON

Statistics can specify `"args"` to pass extra parameters to any R function:

```json
{ "fun": "median", "args": { "na.rm": true }, "label": "Median" }
```

Generates: `.value_raw = median(AGE, na.rm = TRUE)`.

### Package contents

* `R/` — `compiler.R`, `compile.R`, `validate.R`, `metadata.R`
* `inst/schema/table_spec_v1.json` — formal JSON Schema
* `demo/` — `demography.R`, `laboratory.R`, `adverse_events.R`
* `vignettes/` — `getting_started.Rmd`, `dsl_reference.Rmd`
* `tests/testthat/` — 113 tests (validate, compile, generate)
