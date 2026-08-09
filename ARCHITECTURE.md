# ksTable Architecture Document

**Version**: 2.1  
**Date**: 2026-08-09

---

## System Overview

```text
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
Calc/format functions are bare names in the generated code and resolve from
the eval environment parent chain.

---

## Public API

| Function | Role |
|----------|------|
| `kst_validate_spec(json_spec)` | JSON Schema (or manual) + SR-1 identifier walk |
| `kst_compile(json_spec)` | Validate then `compile_ts()` → `character(1)` script |
| `kst_save(json_spec, file, overwrite)` | Compile + header + write file |
| `kst_extract_metadata(data, variables, use_ksformat, format_map)` | Levels / formats |
| `kst_apply_metadata(data, metadata)` | `fput` + factor levels for `.drop = FALSE` |

`groups.format` in JSON is **documentation** for the intended `format_map`;
the compiler does not read it.

**Dependencies** (`DESCRIPTION`): dplyr, tidyr, jsonlite, ksformat (Imports);
jsonvalidate, glue, testthat, knitr, rmarkdown (Suggests).  
`template` formats need **glue** at eval time. Generated code uses `dplyr::` /
`tidyr::` / `ksformat::` explicitly.

---

## Generator (`R/compiler.R`)

```text
JSON → fromJSON → table_spec
  → assert_id / structural guards
  → layout$row_structure
       parameter_stat → gen_parameter_stat
       hierarchical   → gen_hierarchical (first param, first nested, first stat)
  → character script
```

**Emission pattern** (bare calls, not registries):

```r
dplyr::summarize(
  .value_raw = mean_sd(AGE, na.rm = TRUE),
  .groups    = "drop"
) |>
dplyr::mutate(
  .value     = vapply(.value_raw, format_mean_sd, character(1L)),
  .param     = "Age (years)",
  .stat      = "mean_sd",
  .value_raw = NULL
)
```

| `format.type` | Generated expression |
|---------------|----------------------|
| *(none)* | `as.character(.value_raw)` |
| `sprintf` | `sprintf("<pattern>", .value_raw)` |
| `custom` | `vapply(.value_raw, <fun>, character(1L))` |
| `template` | `vapply(..., glue::glue_data(...))` |
| `ksformat` | `ksformat::fput(.value_raw, "<format_name>")` |

**Output columns**

- `parameter_stat`: `.param`, `.stat`, then group columns (character values)
- `hierarchical`: `.parent`, `.is_child`, `.row_label`, `.stat`, then group columns

**SR-1**: identifiers via `assert_id()`; labels/patterns via `r_str()`.

---

## Data flow

### Compile

```text
json_spec → read_json_spec → kst_validate_spec (fail → stop)
          → fromJSON → compile_ts → R code string
```

### Execute (caller)

```text
optional: meta <- kst_extract_metadata(...); data <- kst_apply_metadata(data, meta)
code <- kst_compile(spec)
env <- new.env(parent = environment()); env$data <- data
result <- eval(parse(text = code), envir = env)
```

---

## Error handling

1. **JSON parse** — `jsonlite` errors
2. **Validation** — collected messages from `kst_validate_spec`, surfaced by compile/save
3. **Generator guards** — empty chunks after `apply_to`, missing hierarchical nested, etc.
4. **Runtime** — normal R errors inside `eval()` (missing columns, missing functions)
5. **ksformat** — metadata helpers **warn** on failure (do not swallow silently)

---

## Performance

Measured compile ~51–62 µs/call (demographics spec). Bottleneck is JSON parse.
Generated dplyr is equivalent to hand-written pipelines.

---

## Security (SR-1)

| Field | Use | Mitigation |
|-------|-----|------------|
| `parameter[].variable` / `variables[]` | symbol in summarize | `assert_id` |
| `statistics[].fun` / `format.fun` | bare call / vapply | `assert_id` |
| `groups.by[]` | group_by symbols | `assert_id` |
| `label`, `pattern` | string literals | `r_str` |

---

## Future (v1.1+)

Documented only — not implemented in 0.1.0:

- `shift_matrix`, `listing`
- Hierarchical nesting depth > 2; multi-statistic hierarchical
- Sort-before-format / DSL sort options
- Deeper auto-wiring of `groups.format` into metadata helpers

---

**Document Version**: 2.1 · **Last Updated**: 2026-08-09
