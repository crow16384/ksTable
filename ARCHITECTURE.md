---
marp: false
---

# ksTable Architecture Document

**Version**: 2.0  
**Date**: 2026-07-05

---

## System Overview

```text
┌────────────────────────────────────────────────────────────────┐
│                          User Space                            │
│                                                                │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐        │
│  │ JSON DSL     │   │ Input Data   │   │ calc_fns /   │        │
│  │ Specification│   │ (tibble)     │   │ format_fns   │        │
│  └──────┬───────┘   └──────┬───────┘   └──────┬───────┘        │
│         │                  │                  │                │
└─────────┼──────────────────┼──────────────────┼────────────────┘
          │                  │                  │
          ▼                  │                  │
┌─────────────────────────────▼──────────────────▼────────────────┐
│                       ksTable Package                           │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                   R Layer (Public API)                   │   │
│  │                                                          │   │
│  │  kst_compile()          kst_validate_spec()              │   │
│  │  kst_generate_table()   kst_extract_metadata()           │   │
│  │                                                          │   │
│  └───────────────────────┬──────────────────────────────────┘   │
│                          │                                      │
│                          ▼                                      │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │             R Generator  (R/compiler.R)                  │   │
│  │                                                          │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐    │   │
│  │  │  Parser /    │→ │  Metadata    │→ │    Code      │    │   │
│  │  │  Validator   │  │  Resolver    │  │  Generator   │    │   │
│  │  │ (jsonlite)   │  │              │  │              │    │   │
│  │  └──────────────┘  └──────────────┘  └──────┬───────┘    │   │
│  │                                             │            │   │
│  │                                             ▼            │   │
│  │                                  [ R Code String ]       │   │
│  │                                                          │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────┬───────────────────────────────────┘
                              │
                              ▼
                      ┌───────────────┐
                      │  Generated    │
                      │  R Code       │
                      │  (dplyr/tidyr)│
                      └───────┬───────┘
                              │
                              ▼ [eval()]
                      ┌───────────────┐
                      │  Formatted    │
                      │  Tibble       │
                      │  (all strings)│
                      └───────┬───────┘
                              │
                              ▼
                      ┌───────────────┐
                      │   ksTFL       │
                      │   Rendering   │
                      └───────────────┘
```

---

## Component Details

### 1. R Layer (Public API)

**Location**: `R/*.R`

**Responsibilities**:

- User-facing interface
- Parameter validation (R-level)
- Metadata extraction from data frames
- `ksformat` package integration
- Generated code execution

**Key Functions**:

```r
kst_compile(json_spec, metadata = NULL)
```

- Validate JSON spec
- Extract metadata if not provided
- Call R generator
- Return R code string

```r
kst_generate_table(json_spec, data, calc_functions, format_functions = list(), ...)
```

- Extract metadata from data
- Compile spec to R code
- Execute generated code with `calc_functions` and `format_functions`
- Return formatted tibble

**`calc_functions`**: named list; keys match `"fun"` values in JSON `statistics`.
Functions receive a data vector and return raw numeric values or named lists.
**No string coercion in calc functions.**

**`format_functions`**: named list; keys match `"format.fun"` values in JSON.
Functions receive a raw value (or named list) and return a single character string.

```r
kst_validate_spec(json_spec)
```

- Parse JSON
- Validate against schema
- Return list: `list(valid = TRUE/FALSE, errors = character)`

```r
kst_extract_metadata(data, variables, use_ksformat = TRUE)
```

- Query ksformat for format metadata
- Extract factor levels (required for `.drop = FALSE` with `include_missing_levels`)
- Return metadata list

**Dependencies**:

- dplyr, tidyr, rlang (generated code environment)
- ksformat (format metadata)
- jsonlite (JSON parsing)

---

### 2. R Generator

**Location**: `R/compiler.R`

**Responsibilities**:

- Parse JSON DSL via `jsonlite::fromJSON()`
- Validate spec (required fields, identifier safety)
- Resolve metadata (factor levels, format names)
- Emit pipe-based dplyr/tidyr R code string

**Internal pipeline**:

```text
JSON string
  ↓ jsonlite::fromJSON()
R list (table spec)
  ↓ validate required fields, assert_id() on all identifiers
Validated spec
  ↓ dispatch on layout$row_structure
  ↓ for each parameter × statistic:
      emit summarize chunk (.value_raw = calc_fns[[fun]](var))
      emit format mutate  (.value = format_expr, .value_raw = NULL)
  ↓ emit bind_rows + pivot_wider assembly
R code string
```

**Compute / format separation**:

Every generated chunk follows this two-step pattern:

```r
# Step 1 — compute: raw numeric or list preserved
dplyr::summarize(
  .value_raw = calc_fns[["stat_fun"]](VARIABLE),   # scalar → plain column
  .groups    = "drop"
) |>
# Step 2 — format: convert to string, drop helper column
dplyr::mutate(
  .value     = <format_expression>,   # as.character() / sprintf() / vapply(format_fns...)
  .value_raw = NULL                   # drop before bind_rows
)
```

This separation preserves raw values for potential sorting before formatting.

**Format expressions by format spec type**:

| `format.type`  | Generated expression |
|----------------|----------------------|
| *(none)*       | `as.character(.value_raw)` |
| `"sprintf"`    | `sprintf("<pattern>", .value_raw)` |
| `"custom"`     | `vapply(.value_raw, format_fns[["<fun>"]], character(1L))` |
| `"template"`   | `vapply(.value_raw, function(.x) glue::glue_data(.x, "<pattern>"), character(1L))` |
| `"ksformat"`   | `ksformat::fput(.value_raw, "<format_name>")` |

**Supported layouts**:

| `row_structure`  | Description |
|------------------|-------------|
| `parameter_stat` | Rows = parameter × statistic; columns = groups |
| `hierarchical`   | Parent rows + child rows (e.g., SOC → PT); columns = groups |

**Security** (SR-1): All JSON fields used in generated code are sanitized:

- Identifiers (`variable`, `fun`, `by` items): validated with `^[A-Za-z.][A-Za-z0-9._]*$`
- String literals (`label`, `pattern`): escaped (`\` → `\\`, `"` → `\"`)

---

## Data Flow

### Compilation Flow

```text
JSON DSL (character string)
  ↓
[jsonlite::fromJSON()] → R list
  ↓
[Validator] → check required fields, identifier safety
  ↓
[Metadata resolver] → factor levels, ksformat metadata
  ↓
[Code Generator] → R code string (character(1))
  ↓
Return to caller
```

### Execution Flow

```text
R code string
  ↓
[Create eval environment]
  env$.data       ← input data frame
  env$calc_fns    ← calc_functions list (raw-value producers)
  env$format_fns  ← format_functions list (string renderers)
  ↓
[eval(parse(text = code), envir = env)]
  ↓
[dplyr pipeline: group_by → summarize → mutate → bind_rows → pivot_wider]
  ↓
Formatted tibble (all value columns are character)
  ↓
Return to user
```

---

## Memory Management

All memory is managed by R's garbage collector. Code generation produces short-lived character vectors and lists, collected immediately after the code string is returned. No manual allocation or finalizers are required.

---

## Error Handling

### Error Categories

1. **JSON Parse Errors** — `jsonlite::fromJSON()` propagates as an R error with message and position.

2. **Validation Errors** — schema violations, unsafe identifiers, missing required fields. Reported as R errors with JSON path and suggestion.

3. **Runtime Errors** — wrong return type from a calc function, missing data columns, type mismatches. R's normal error propagation from inside `eval()`.

### Error Reporting Strategy

**Principle**: fail fast, name the JSON path, suggest the fix.

**Example**:

```text
Error in kst_compile():
  Validation failed at /table_spec/statistics/mean_sd/fun:
    'mean sd' is not a valid R identifier.
    Function names must match ^[A-Za-z.][A-Za-z0-9._]*$.
    
  Suggestion: rename the key in calc_functions to 'mean_sd'.
```

---

## Performance Considerations

### Compilation

**Measured**: ~51–62 µs per call (demographics spec, 10,000 iterations, Apple Silicon).

The bottleneck is `jsonlite::fromJSON()`. String assembly for the R code output is sub-microsecond. No caching is planned for v1.0 — at < 100 µs the overhead is immaterial.

### Runtime

Generated code is equivalent to hand-written dplyr. Each statistic performs one `group_by |> summarize` pass; results are assembled with `bind_rows |> pivot_wider`. No redundant passes.

### Memory

Only distinct values and factor levels are read from the data during metadata extraction. The data frame is passed by reference into the eval environment and processed in-place by dplyr.

**Target**: < 100 MB peak for typical clinical tables.

---

## Testing Strategy

### R Tests (testthat)

- **Compilation**: JSON → code string for each layout; verify generated code is syntactically valid
- **Security**: injection attempts rejected for every identifier field
- **Metadata**: ksformat integration, factor level extraction
- **Execution**: end-to-end JSON → formatted tibble for each example table type
- **Hierarchical**: parent/child row ordering, correct value assignment

### Integration Tests

**Covered in v1.0**:

- Demographics table (`parameter_stat`, single group variable)
- Demographics table (`parameter_stat`, 2-way stratification)
- AE table (`hierarchical`, SOC → PT)
- Efficacy table (`parameter_stat`, visit × treatment groups)

**Verification**:

- Generated code is valid R
- Output matches expected values on known synthetic data
- All value columns are `character` type
- ksTFL `create_table()` accepts output without modification

---

## Build System

**Tools**: standard R package tools — `devtools`, `roxygen2`, `testthat`.

**No compiled code.** Pure R package. No `src/` directory, no `Makevars`, no `SystemRequirements`.

**DESCRIPTION** (key fields):

```text
Depends: R (>= 4.1.0)
Imports:
    dplyr (>= 1.1.0),
    tidyr (>= 1.3.0),
    rlang (>= 1.1.0),
    jsonlite (>= 1.8.0),
    ksformat (>= 0.7.0)
Suggests:
    testthat (>= 3.0.0),
    knitr,
    rmarkdown
```

---

## Security Considerations

### Code Injection (SR-1)

**Risk**: A JSON field value interpolated into generated R code contains R operators, function calls, or metacharacters that alter execution.

**Attack surface** (all fields that appear in generated code):

| Field | Used as | Mitigation |
|-------|---------|------------|
| `parameter[].variable` | bare R symbol in `summarize()` | `assert_id()` |
| `statistics[].fun` | `calc_fns[["..."]]` key | `assert_id()` |
| `statistics[].format.fun` | `format_fns[["..."]]` key | `assert_id()` |
| `groups[].by[]` | bare R symbol in `group_by()` | `assert_id()` |
| `label`, `pattern` | R string literal in `mutate()` | `r_str()` escape |

**`assert_id(x)`**: rejects anything not matching `^[A-Za-z.][A-Za-z0-9._]*$`.
**`r_str(x)`**: escapes `\` and `"` before embedding in double-quoted R strings.

Both functions are implemented in `R/compiler.R` and applied to every field before any code is emitted.

---

## Future Enhancements

### v1.1

- `shift_matrix` row structure (cross-tabulation of two categorical variables)
- `listing` table type (unaggregated subject-level rows)
- Hierarchical nesting depth > 2
- Sort-before-format step (sort on `.value_raw`, then format)

### v2.0

- Interactive DSL builder (Shiny app)
- Template library (common clinical table patterns)
- DSL macro system (reusable spec components)
- Compiled code caching (hash-based invalidation)
- Parallel execution of independent groups

---

**Document Version**: 2.0  
**Last Updated**: 2026-07-05




