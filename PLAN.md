# ksTable Development Plan

**Project**: JSON DSL to Dplyr Code Generator for Clinical Tables  
**Date**: 2026-07-05  
**Status**: Implementation Phase

## Overview

**Purpose**: Create an R package that reads declarative JSON table specifications, uses a pure-R generator to produce dplyr/tidyr R code, which when executed produces pre-formatted tibbles ready for ksTFL rendering.

**Architecture**:

```text
User JSON DSL → R Generator (compiler.R) → Generated R Code → Execution → Formatted Tibble → ksTFL
```

**Rendering Separation**: ksTable produces tibbles for further rendering with ksTFL package ("github.com/crow16384/ksTFL"), but rendering itself is out of scope for this package.

---

## Core Concepts

### DSL Design Principles

- **Declarative**: Describe desired output, compiler figures out transformations
- **Source-agnostic**: Works with any tibble/data.frame (not just ADaM datasets)
- **User-provided calculations**: Functions referenced by name in JSON
- **Metadata-driven**: Introspects ksformat, factor levels, distinct values
- **Hierarchical support**: Handles nested table structures (SOC → PT)

### Function Contracts

ksTable uses **two distinct function types**, passed as named lists:

```r
# calc_functions: receive a column vector, return raw numeric or named list
# key = "fun" value in JSON statistics
count   <- function(data) sum(!is.na(data))          # returns integer
mean_sd <- function(data) list(                      # returns named list
  mean = mean(data, na.rm = TRUE),
  sd   = sd(data,   na.rm = TRUE)
)

# format_functions: convert raw value to display string
# key = "format.fun" value in JSON statistics format spec
format_mean_sd <- function(x) sprintf("%.1f (%.2f)", x$mean, x$sd)
```

The generator calls `calc_fns` in `summarize()` and `format_fns` in `mutate()`. **No string coercion inside calc functions.**

### Example JSON DSL

```json
{
  "parameter": {
    "age": {
      "variable": "AGE"
    },
    "statistics": {
      "n": {
        "fun": "count"
      },
      "mean_sd": {
        "fun": "mean_sd"
      }
    },
    "groups": {
      "groups": "TRT",
      "include_missing_levels": "true"
    }
  }
}
```

---

## Development Phases

### Phase 1: JSON Schema & R Validator

**Objective**: Define the DSL schema and implement pure-R validation

#### 1.1 Design JSON Schema

- Parameter definitions (variables, labels, calc function references)
- Statistics specifications (calc function + optional format spec)
- Grouping/stratification (`by`, `include_missing_levels`)
- Row/column layouts (`parameter_stat`, `hierarchical`)
- Format specifications (`sprintf`, `custom`, `template`, `ksformat`)

**Deliverables**:

- `inst/schema/table_spec_v1.json` — JSON Schema definition
- Schema documentation in ARCHITECTURE.md

#### 1.2 Implement R-side Validator

*Depends on 1.1*

- Parse JSON with `jsonlite::fromJSON()`
- Validate required fields and types
- Validate identifier safety (SR-1 injection prevention via `assert_id()`)
- Return structured error list with JSON path and suggestion

**Deliverables**:

- `R/validate.R` — `kst_validate_spec(json_spec)` implementation
- Unit tests covering validation errors and injection rejection

---

### Phase 2: R Code Generator

**Objective**: Implement pure-R DSL → dplyr code generator

*Depends on Phase 1*

#### 2.1 Implement `parameter_stat` Layout

- Iterate over parameters × statistics combinations
- For each: generate `group_by |> summarize(.value_raw)` chunk
- Emit format step (`.value_raw` → `.value`, then `.value_raw = NULL`)
- Assemble with `bind_rows |> pivot_wider`
- `include_missing_levels`: emit `group_by(..., .drop = FALSE)`

**Deliverables**:

- `R/compiler.R` — `kst_compile()`, `gen_parameter_stat()`

#### 2.2 Implement `hierarchical` Layout

*Depends on 2.1*

- Generate parent-level `group_by |> summarize` chunk
- Generate child-level `group_by |> summarize` chunk
- Merge with `bind_rows`, sort by `.parent` then `.is_child`
- Assemble with `pivot_wider`

**Deliverables**:

- `R/compiler.R` — `gen_hierarchical()`

#### 2.3 Security: Identifier Sanitization (SR-1)

- `assert_id(x)`: validate all JSON-derived identifiers against `^[A-Za-z.][A-Za-z0-9._]*$`
- `r_str(x)`: escape `\` and `"` in all JSON-derived string literals
- Applied before every code emission

**Deliverables**:

- `assert_id()` and `r_str()` helpers in `R/compiler.R`
- Tests covering injection attempts for all field types

---

### Phase 3: Metadata Extraction

**Objective**: Extract and resolve data metadata for the generator

*Depends on Phase 2*

#### 3.1 Implement `kst_extract_metadata()`

- Query ksformat package for VALUE format metadata (levels, labels)
- Extract factor levels (required for `.drop = FALSE` with `include_missing_levels`)
- Fall back to `unique()` for character variables
- Return metadata list for compiler consumption

**Deliverables**:

- `R/metadata.R` — `kst_extract_metadata(data, variables, use_ksformat = TRUE)`
- Integration tests with ksformat package
- Tests for factor level extraction and missing-level handling

---

### Phase 4: Format Step Code Generation

**Objective**: Implement all format expression types in the generator

*Depends on Phase 2*

#### 4.1 Format Expression Generator

Generate the correct R expression for each format spec type:

| `format.type` | Generated expression |
|---------------|----------------------|
| *(none)* | `as.character(.value_raw)` |
| `"sprintf"` | `sprintf("<pattern>", .value_raw)` |
| `"custom"` | `vapply(.value_raw, format_fns[["<fun>"]], character(1L))` |
| `"template"` | `vapply(.value_raw, function(.x) glue::glue_data(.x, "<pattern>"), character(1L))` |
| `"ksformat"` | `ksformat::fput(.value_raw, "<name>")` |

**Deliverables**:

- `gen_format_expr()` in `R/compiler.R`
- `needs_list_wrap()` helper (determines when calc result needs `list()` wrapper)
- Tests for each format type with synthetic data

---

### Phase 5: R Package Structure

**Objective**: Complete R package structure

*Parallel with earlier phases*

#### 5.1 Setup R Package Skeleton

- DESCRIPTION with dependencies (`Depends: R (>= 4.1.0)`, no SystemRequirements)
- NAMESPACE configuration (generated by roxygen2)
- Package documentation structure

**Deliverables**:

- `DESCRIPTION` — Package metadata
- `NAMESPACE` — Exports
- `.Rbuildignore` — Build configuration
- `README.md` — Project overview

#### 5.2 Implement Public API

*Depends on Phases 1–4*

```r
kst_compile(json_spec, metadata = NULL) -> character
kst_generate_table(json_spec, data, calc_functions, format_functions = list(), ...) -> tibble
kst_validate_spec(json_spec) -> list(valid, errors)
kst_extract_metadata(data, variables, use_ksformat = TRUE) -> list
```

**Deliverables**:

- `R/compile.R` — `kst_compile()` and `kst_generate_table()`
- `R/validate.R` — `kst_validate_spec()`
- `R/metadata.R` — `kst_extract_metadata()`

#### 5.3 Write Common Format Helpers (optional)

```r
format_mean_sd(x)       # takes list(mean, sd) → "45.2 (11.4)"
format_n_pct(x)         # takes list(n, pct) → "160 (75.5)"
format_median_range(x)  # takes list(median, min, max)
```

**Deliverables**:

- `R/format_helpers.R` — Optional helper format functions
- Integration with ksformat package
- Examples in documentation

---

### Phase 6: Testing & Validation

**Objective**: Comprehensive test coverage

*Parallel with Phase 5*

#### 6.1 Write Unit Tests for R Generator

*Depends on Phases 1–4*

- Test JSON compilation for each layout type
- Test injection rejection for all identifier fields
- Test format expression generation for all format types
- Test metadata extraction and factor level handling

**Deliverables**:

- `tests/testthat/test-compile.R`
- `tests/testthat/test-validate.R`
- `tests/testthat/test-metadata.R`
- `tests/testthat/test-format.R`

#### 6.2 Write Integration Tests

*Depends on Phase 5 completion*

- Test end-to-end: JSON → tibble for each table type
- Test calc_functions + format_functions separation
- Test hierarchical table generation
- Test ksTFL handoff

**Deliverables**:

- `tests/testthat/test-generate.R`
- `tests/testthat/test-hierarchy.R`

#### 6.3 Create Example Table Specifications

*Depends on Phase 5 completion*

- Demographics table (age by treatment + gender)
- Adverse events table (SOC → PT hierarchy)
- Efficacy table (change from baseline by visit)

**Deliverables**:

- `inst/examples/demographics.json`
- `inst/examples/adverse_events.json`
- `inst/examples/efficacy.json`
- `inst/examples/laboratory.json`
- R scripts demonstrating each example

---

### Phase 7: Documentation & Examples

**Objective**: User-facing documentation

*Depends on Phase 6*

#### 7.1 Write Package Vignette

- Introduction to DSL concepts
- Simple example (demographics table)
- Complex example (hierarchical AE table)
- Integration with ksTFL workflow

**Deliverables**:

- `vignettes/getting_started.Rmd`
- `vignettes/dsl_reference.Rmd`
- `vignettes/advanced_features.Rmd`
- `vignettes/kstfl_integration.Rmd`

#### 7.2 Write Function Documentation

- All exported R functions documented with roxygen2
- Examples for each function
- Cross-references between related functions

**Deliverables**:

- Complete roxygen2 documentation in all R files
- Generated man/ pages
- pkgdown site configuration

#### 7.3 Create README with Quick Start Guide

- Installation instructions
- Basic workflow example
- Link to vignettes
- Link to resources (CDISC ARS, LinkML, ksTFL, ksformat)

**Deliverables**:

- `README.md` - Quick start and overview
- `NEWS.md` - Version history
- `CONTRIBUTING.md` - Contribution guidelines

---

## Technical Architecture

### Dependencies

**R Packages**:

- **dplyr** — Data manipulation (generated code uses this)
- **tidyr** — Data reshaping (`pivot_wider`, nesting)
- **rlang** — Tidy evaluation
- **ksformat** — Value formatting integration
- **jsonlite** — JSON parsing

**No compiled code. No C++ libraries. No Rcpp.**

### Build System

- Standard R package tools (`devtools`, `roxygen2`, `testthat`)
- `R CMD check` passes with no `src/` directory

### File Structure

```text
ksTable/
├── DESCRIPTION              # Package metadata
├── NAMESPACE                # Exports (roxygen2)
├── README.md                # Overview
├── NEWS.md                  # Version history
├── LICENSE                  # GPL-3 or MIT
├── .Rbuildignore            # Build configuration
├── R/                       # R source files
│   ├── compile.R            # kst_compile() + kst_generate_table()
│   ├── compiler.R           # R code generator (gen_parameter_stat, gen_hierarchical)
│   ├── validate.R           # kst_validate_spec()
│   ├── metadata.R           # kst_extract_metadata()
│   └── format_helpers.R     # Optional: format_mean_sd(), etc.
├── inst/                    # Installed files
│   ├── schema/              # JSON schemas
│   │   └── table_spec_v1.json
│   └── examples/            # Example DSL files
│       ├── demographics.json
│       ├── adverse_events.json
│       └── efficacy.json
├── tests/
│   └── testthat/
│       ├── test-compile.R
│       ├── test-validate.R
│       ├── test-metadata.R
│       ├── test-generate.R
│       ├── test-hierarchy.R
│       └── test-format.R
├── vignettes/
│   ├── getting_started.Rmd
│   ├── dsl_reference.Rmd
│   ├── advanced_features.Rmd
│   └── kstfl_integration.Rmd
└── man/                     # Generated documentation
```

---

## Verification Criteria

### JSON DSL Validation

✓ Create sample DSL for demographics table (age, sex by treatment)  
✓ Run `kst_validate_spec(json_spec)` — should pass without errors  
✓ Introduce errors (typos, missing fields) — should produce helpful messages with JSON path  

### Code Generation

✓ Compile demographics DSL: `code <- kst_compile(json_spec)`  
✓ Review generated R code — should be readable `|>` pipe chains  
✓ Verify expected structure: `group_by(TRT) |> summarize(.value_raw = calc_fns[["count"]](AGE))`  
✓ Verify format step: `mutate(.value = as.character(.value_raw))`  

### End-to-End Execution

✓ Load sample dataset: `adsl <- tibble(USUBJID, AGE, TRT, SEX)`  
✓ Define calc function: `count <- function(data) sum(!is.na(data))`  
✓ Define format function: `format_mean_sd <- function(x) sprintf("%.1f (%.2f)", x$mean, x$sd)`  
✓ Generate table: `result <- kst_generate_table(json_spec, adsl, list(count=count), list(format_mean_sd=format_mean_sd))`  
✓ Verify output: tibble with all character value columns  
✓ Pass to ksTFL: `create_table(result) |> write_doc("demo.docx")`  

### Metadata Introspection

✓ Create data with factor: `data <- tibble(TRT = factor(c("A", "B"), levels = c("A", "B", "C")))`  
✓ Extract metadata: `meta <- kst_extract_metadata(data, "TRT")`  
✓ Verify includes missing level "C"  
✓ Generate table with `include_missing_levels = true` — should have row for "C" with zero count  

### Hierarchical Tables

✓ Create AE data: `ae <- tibble(AESOC, AEDECOD, TRT01P, ...)`  
✓ Define nested parameter in JSON: `"soc": {"variable": "AESOC", "nested": {"pt": {"variable": "AEDECOD"}}}`  
✓ Generate table — verify SOC parent rows followed by PT child rows  

### Security (SR-1)

✓ Attempt injection: `"variable": "AGE); system('rm -rf /')"`  
✓ Verify `kst_validate_spec()` / `kst_compile()` reject with informative error  

### ksformat Integration

✓ Define ksformat VALUE format: `fnew("A" = "Active", "P" = "Placebo", name = "trt")`  
✓ Reference in DSL: `"groups": {"by": ["TRT"], "format": {"TRT": "trt"}}`  
✓ Verify treatment labels use ksformat labels in output  

---

## Key Design Decisions

### 1. DSL is Declarative

**Decision**: Describe desired output, not transformations  
**Rationale**: Easier for users, enables code generation  
**Trade-off**: Generator must handle all transformation logic  

### 2. Two Function Types (calc + format)

**Decision**: `calc_functions` return raw values; `format_functions` render to strings  
**Rationale**: Separates concerns; preserves values for potential pre-format sorting  
**Trade-off**: Users write two function lists instead of one  

### 3. Pure R Generator

**Decision**: `R/compiler.R` generates dplyr code via string assembly; no C++  
**Rationale**: Pure-R PoC measured at ~62 µs/call — C++ overhead (30–120 s build) is not justified  
**Trade-off**: None identified for current scope  

### 4. Multiple Format Methods

**Decision**: Support `sprintf`, `custom`, `template`, `ksformat` format types  
**Rationale**: Maximum flexibility for users  
**Trade-off**: More format expression branches in generator  

### 5. Runtime Metadata Resolution

**Decision**: Generated code adapts to runtime data (factors with `.drop = FALSE`)  
**Rationale**: More flexible than static compilation; `kst_extract_metadata` ensures factor levels  
**Trade-off**: Requires correct factor setup before calling `kst_generate_table`  

### 6. Native Pipe (`|>`) in Generated Code

**Decision**: Use `|>` (R ≥ 4.1) in generated code  
**Rationale**: No magrittr dependency; cleaner generated code  
**Trade-off**: Requires R ≥ 4.1  

### 7. Hierarchical Table Support

**Decision**: First-class support for nested structures (SOC → PT)  
**Rationale**: Critical for clinical tables (AEs, concomitant medications)  
**Trade-off**: More complex code generation path  

### 8. Explicit `calc_functions` List (no global registry)

**Decision**: User passes `calc_functions = list(...)` to `kst_generate_table()`; no `kst_register_calc()`  
**Rationale**: Explicit, testable, no hidden global state  
**Trade-off**: Users must pass the list on every call (trivial)  

### 9. indent/visual-formatting Out of Scope

**Decision**: ksTable does not emit indentation, colors, or visual formatting metadata  
**Rationale**: All rendering is ksTFL's responsibility  
**Trade-off**: None — clean separation of concerns  

---

## Open Questions & Future Considerations

### 1. DSL Versioning

**Question**: How to handle DSL schema evolution?  
**Recommendation**: Include schema version in JSON; validator checks compatibility  
**Priority**: Medium — address in Phase 1  

### 2. Error Handling in Calc Functions

**Question**: How to report errors thrown inside user calc functions?  
**Recommendation**: Let R's normal error propagation surface them with stack trace from `eval()` context  
**Priority**: Low — natural R behaviour is sufficient  

### 3. Multi-Level Nesting

**Question**: How deep should hierarchical tables go?  
**Recommendation**: v1.0 supports 2 levels (SOC→PT); generalise to n levels in v1.1  
**Priority**: Low  

---

## Success Metrics

### Functional Completeness

- [ ] All phases completed
- [ ] All verification criteria passed
- [ ] Example tables generate correctly
- [ ] Integration with ksTFL works seamlessly

### Code Quality

- [ ] > 80% test coverage
- [ ] Pass `R CMD check` with no notes
- [ ] Documentation complete and accurate
- [ ] No known injection vulnerabilities (SR-1 audit)

### Performance

- [ ] Compile time < 500 µs for simple tables (measured)
- [ ] Generated code efficient (no obviously redundant passes)
- [ ] Memory usage reasonable for large datasets

### Usability

- [ ] Clear error messages with JSON path + suggestion
- [ ] Examples in documentation work
- [ ] Vignettes are comprehensive

---

## Timeline Estimate

**Phase 1** (Schema + Validator): 1 week  
**Phase 2** (R Generator): 2 weeks  
**Phase 3** (Metadata): 1 week  
**Phase 4** (Format step): 1 week  
**Phase 5** (Package structure): 1 week  
**Phase 6** (Testing): 1–2 weeks  
**Phase 7** (Documentation): 1 week  

**Total**: approximately 8 weeks for v1.0 release

---

## References

- **CDISC ARS**: [https://cdisc-org.github.io/analysis-results-standard/]
- **LinkML**: [https://linkml.io/]
- **ksTFL**: [https://github.com/crow16384/ksTFL]
- **ksformat**: [https://github.com/crow16384/ksformat]
- **PharmaSUG Paper**: [https://pharmasug.org/proceedings/japan2024/PharmaSUG-Japan-2024-02.pdf]

---

**Document Version**: 2.0  
**Last Updated**: 2026-07-05  
**Status**: Implementation Ready
