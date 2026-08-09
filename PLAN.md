# ksTable Development Plan

**Project**: JSON DSL to Dplyr Code Generator for Clinical Tables  
**Date**: 2026-08-09  
**Status**: v0.1.0 usable — Phases 1–6 complete for two layouts; Phase 7 polish ongoing

## Overview

**Purpose**: Compile declarative JSON table specifications into dplyr/tidyr R
scripts that, when evaluated against `data`, produce pre-formatted tibbles for
ksTFL.

**Architecture** (actual):

```text
JSON → kst_validate_spec / kst_compile → R script
     → optional kst_extract_metadata + kst_apply_metadata
     → eval(new.env) → tibble → ksTFL
```

Calc/format functions are **bare names** in generated code (resolved from the
eval env). There is no `calc_fns` / `format_fns` registry.

---

## Core Concepts

### Function contracts

```r
# calc: column vector → scalar or named list
count   <- function(x) sum(!is.na(x))
mean_sd <- function(x) list(mean = mean(x, na.rm = TRUE), sd = sd(x, na.rm = TRUE))

# format (custom): raw value → character(1)
format_mean_sd <- function(x) sprintf("%.1f (%.2f)", x$mean, x$sd)
```

### Example JSON DSL

```json
{
  "schema_version": "1.0",
  "table_spec": {
    "parameter": {
      "age": { "variable": "AGE", "label": "Age (years)" }
    },
    "statistics": {
      "n": { "fun": "count" },
      "mean_sd": {
        "fun": "mean_sd",
        "format": { "type": "custom", "fun": "format_mean_sd" }
      }
    },
    "groups": { "by": ["TRT01P"], "include_missing_levels": true },
    "layout": { "row_structure": "parameter_stat", "column_structure": "groups" }
  }
}
```

---

## Development Phases

### Phase 1: JSON Schema & R Validator — DONE

- `inst/schema/table_spec_v1.json`, `kst_validate_spec()`, SR-1

### Phase 2: R code generator — DONE

- `parameter_stat`, `hierarchical` (2-level, first statistic)
- Bare-call emission; format types; `args`; `apply_to`

### Phase 3: Metadata extraction — DONE (caller-driven)

- `kst_extract_metadata` / `kst_apply_metadata` before eval
- `groups.format` documented as `format_map` hint (not auto-applied by compile)

### Phase 4: Format step codegen — DONE

### Phase 5: R package structure — DONE

- Exports: compile, save, validate, extract/apply metadata
- No `kst_generate_table`; no `format_helpers.R` required for v0.1

### Phase 6: Testing — DONE for v0.1 scope

- ~103 tests; demos for demography, lab, AE, ksformat

### Phase 7: Documentation & examples — DONE (honesty pass)

- README, ARCHITECTURE, DSL_EXAMPLE, NEWS, REQUIREMENTS aligned with code
- `inst/examples/`, CI workflow, `getting_started` vignette eval enabled

---

## Success metrics (v0.1)

- [x] Two layouts compile and eval on synthetic data
- [x] SR-1 injection rejected
- [x] Validate-before-compile
- [x] Docs match bare-call + pre-eval metadata model
- [ ] Full vignette `eval=TRUE` on CI with all Suggests
- [ ] Coverage tooling / published coverage %
- [ ] ksTFL handoff vignette

---

## Deferred to v1.1+ (Phase D — document only)

- Multi-stat hierarchical; nesting depth > 2
- `listing`, `shift_matrix`
- DSL sort options / sort-before-format
- Auto-apply `groups.format` inside a helper (still caller-driven compile)
- Query-plan optimization / C++ (rejected after PoC; stay pure R)

---

## Open design notes

- DSL versioning via `schema_version` (`"1.0"`)
- Denominators / distinct-subject counting remain user calc responsibility

**Last Updated**: 2026-08-09
