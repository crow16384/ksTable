# News

## ksTable 0.1.0 (2026-08-09)

First usable release. Core DSL-to-dplyr compiler for two layouts.

### API

* `kst_compile(json_spec)` — validates the spec then emits a plain R script.
  Calc/format functions are bare calls resolved from the evaluation environment.
* `kst_save(json_spec, file, overwrite = FALSE)` — same codegen with a header.
* `kst_validate_spec(json_spec)` — JSON Schema (jsonvalidate/ajv when available)
  or manual structural checks, plus SR-1 identifier safety.
* `kst_extract_metadata()` / `kst_apply_metadata()` — pre-eval factor levels and
  ksformat labels. Compile does **not** apply metadata; optional JSON
  `groups.format` is documentation for the `format_map` argument.

### Layouts

* `parameter_stat` — one row per parameter × statistic; columns = group levels.
* `hierarchical` — parent + one nested child (e.g. SOC → PT); first statistic only;
  honors `include_missing_levels` via `.drop = FALSE`.

### Formats

* default → `as.character(.value_raw)`
* `sprintf` / `custom` / `template` (requires Suggests **glue** at eval) / `ksformat`

### Hardening (0.1 honesty pass)

* Validate-before-compile; fail on empty chunks / short `labels` padding;
  surface ksformat failures as warnings; docs aligned with bare-call codegen.

### Package contents

* `R/` — `compiler.R`, `compile.R`, `validate.R`, `metadata.R`
* `inst/schema/table_spec_v1.json`, `inst/examples/*.json`
* `demo/` — demography, laboratory, adverse_events, ksformat_integration
* `vignettes/` — getting_started, dsl_reference
* `tests/testthat/` — 103 tests (validate, compile, generate, metadata)
