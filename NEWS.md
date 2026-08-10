# News

## ksTable 0.2.0 (2026-08-10)

* CRAN-style hex sticker package logo; pkgdown favicons refreshed.
* `scripts/bump_version.R` — bump DESCRIPTION and sync README / PLAN /
  ARCHITECTURE / NEWS / vignette version lines (`--sync-only` supported).
* pkgdown site continues to read the version from DESCRIPTION automatically.
* **RStudio Addin** `kst_spec_builder()` — miniUI gadget with forms + JSON
  (two-way sync), validate / insert / save / compile. Suggests: shiny,
  miniUI, rstudioapi; optional shinyAce.

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
  Generator emits a **single** `group_by` + `summarize` (temp columns `.cN`),
  then format `mutate`, `pivot_longer`, and `pivot_wider`.
* `hierarchical` — parent + one nested child (e.g. SOC → PT); first statistic only;
  honors `include_missing_levels` via `.drop = FALSE`.

### Formats

* *(none)* → raw type kept (numeric/integer); no silent `as.character`
* `sprintf` / `custom` / `template` (requires Suggests **glue** at eval) / `ksformat`
* Mixing character formats with unformatted stats coerces the unformatted
  siblings only so `bind_rows` can build `.value`

### Denominators

* Optional `statistics.*.denominator` (`n`, `n_distinct`, `data_n`, `external`).
* Compiler resolves scalar `denom=` (prep `.kst_dK` + join when needed); calc
  function owns percent math. Rejects `args.denom` when `denominator` is set;
  `by` must be a subset of `groups.by`.

### Hardening (0.1 honesty pass)

* Validate-before-compile; fail on empty chunks / short `labels` padding;
  surface ksformat failures as warnings; docs aligned with bare-call codegen.
* Single-pass `parameter_stat` consolidation (no per-stat `.chunks`).

### Package contents

* `R/` — `compiler.R`, `compile.R`, `validate.R`, `metadata.R`
* `inst/schema/table_spec_v1.json`, `inst/examples/*.json`
* `man/figures/logo.png` — package logo (variants in `logo-variants/`)
* `demo/` — demography, laboratory, adverse_events, ksformat_integration
* `vignettes/` — getting_started, dsl_reference
* `tests/testthat/` — validate, compile, generate, metadata (incl. denominators)
* pkgdown site — `_pkgdown.yml`, `.github/workflows/pkgdown.yaml`
