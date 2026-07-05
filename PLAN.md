# ksTable Development Plan

**Project**: JSON DSL to Dplyr Code Generator for Clinical Tables  
**Date**: 2026-07-01  
**Status**: Planning Phase

## Overview

**Purpose**: Create an R package that reads declarative JSON table specifications, uses a C++23 compiler to generate optimized dplyr/tidyr R code, which when executed produces pre-formatted tibbles ready for ksTFL rendering.

**Architecture**:

```text
User JSON DSL → C++23 Compiler → Generated R Code → Execution → Formatted Tibble → ksTFL
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

### Calculation Function Contract

```r
# Simple contract - function takes only data parameter
function(data) {
  # data can be vector or tibble
  # user processes data and returns results
  # compiler handles grouping and assembly
}
```

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

### Phase 1: Core DSL Schema & Parser (Foundational)

**Objective**: Establish JSON schema and parsing infrastructure

#### 1.1 Design JSON Schema for Table Specifications

- Parameter definitions (variables, labels, analysis functions)
- Statistics specifications (calculation function references)
- Grouping/stratification (with missing level handling)
- Row/column structure (hierarchical support)
- Format specifications (ksformat integration, templates, custom)

**Deliverables**:

- `inst/schema/table_spec_v1.json` - JSON schema definition
- Documentation of schema structure

#### 1.2 Implement C++ JSON Parser

*Parallel with 1.1*

- Parse DSL into C++ data structures using Boost.JSON
- Validate schema with helpful error messages
- Handle nested parameters for hierarchical tables

**Deliverables**:

- `src/compiler/parser.hpp` - Parser interface
- `src/compiler/parser.cpp` - Parser implementation
- Unit tests for parser

#### 1.3 Write JSON Schema Validator

*Depends on 1.1*

- Comprehensive error messages for malformed JSON
- Suggest corrections for common mistakes
- Validate function references exist

**Deliverables**:

- `src/compiler/validator.hpp` - Validator interface
- `src/compiler/validator.cpp` - Validator implementation
- Test cases for validation errors

---

### Phase 2: Metadata Introspection System

**Objective**: Dynamic metadata resolution from data

*Parallel with Phase 1*

#### 2.1 Design Metadata Resolution Strategy

- Priority: ksformat metadata → factor levels → distinct values
- Handle missing levels (include_missing_levels flag)
- Support multi-way stratification

**Deliverables**:

- Architecture document for metadata resolution
- Decision tree for resolution priority

#### 2.2 Implement R-side Metadata Extraction

*Depends on 2.1*

```r
extract_metadata(data, spec)
```

- Discover variable types, levels, formats
- Query ksformat for format metadata
- Build metadata JSON for compiler

**Deliverables**:
- `R/metadata.R` - Metadata extraction functions
- Integration with ksformat package
- Unit tests

#### 2.3 Implement C++ Metadata Consumer

*Depends on 2.1, 2.2*

- Parse metadata JSON
- Use metadata to generate level-specific code
- Handle dynamic runtime introspection

**Deliverables**:

- `src/compiler/metadata.hpp` - Metadata structures
- `src/compiler/metadata.cpp` - Metadata consumer
- Integration tests with R-side extraction

---

### Phase 3: Code Generation Engine

**Objective**: Generate optimized dplyr/tidyr R code

*Depends on Phase 1, Phase 2.1*

#### 3.1 Design R Code AST (Abstract Syntax Tree)

- dplyr pipe chain representation
- group_by, summarize, mutate nodes
- Nested operations for hierarchical tables

**Deliverables**:

- `src/compiler/ast.hpp` - AST data structures
- Documentation of AST design

#### 3.2 Implement Dplyr Code Generator

*Depends on 3.1*

- Generate pipe-based dplyr code (%>% chains)
- Optimize query plans (eliminate redundant operations)
- Handle multi-way grouping

**Deliverables**:

- `src/compiler/codegen.hpp` - Code generator interface
- `src/compiler/codegen.cpp` - Code generator implementation
- `src/compiler/optimizer.cpp` - Query plan optimizer

#### 3.3 Implement Formatting Code Generator

*Depends on 3.1, 3.2*

- Generate ksformat calls for value formatting
- Generate template string interpolation
- Generate custom format function calls
- Combine multiple values (e.g., mean_sd = "120.5 (14.2)")

**Deliverables**:

- `src/compiler/format_gen.cpp` - Format code generator
- Integration with ksformat patterns
- Examples of generated formatting code

#### 3.4 Implement Hierarchical Table Assembly

*Depends on 3.1, 3.2, 3.3*

- Generate code for parent/child row relationships
- Handle nested grouping (SOC → PT)
- Deduplicate parent rows, indent child rows

**Deliverables**:

- `src/compiler/hierarchy.cpp` - Hierarchical table generator
- Support for arbitrary nesting depth (initially 2 levels)
- Tests for nested structures

---

### Phase 4: Calculation Function Integration

**Objective**: Integrate user-provided calculation functions

*Parallel with Phase 3*

#### 4.1 Design Calculation Function Contract

```r
# Standard signature
function(data) -> result
```

- Data can be vector or tibble
- Return value can be scalar, vector, or tibble
- Document contract in vignette

**Deliverables**:

- Contract specification document
- Examples of compliant functions

#### 4.2 Implement Function Dispatch System

*Depends on 4.1*

- Compiler generates calls to user functions
- Handle different return types
- Error handling for missing functions

**Deliverables**:

- `R/dispatch.R` - Function registration and dispatch
- `src/compiler/function_call.cpp` - Function call generation
- Error handling tests

#### 4.3 Implement Result Assembly

*Depends on 4.1, 4.2*

- Compiler generates code to collect results from all groups
- Assemble into final tibble structure
- Apply row/column ordering

**Deliverables**:

- Assembly code generation logic
- Integration tests with multiple functions
- Performance benchmarks

---

### Phase 5: R Package Structure

**Objective**: Complete R package with Rcpp integration

*Parallel with earlier phases*

#### 5.1 Setup R Package Skeleton

- DESCRIPTION with dependencies
- NAMESPACE configuration
- Rcpp integration boilerplate
- Package documentation structure

**Deliverables**:

- `DESCRIPTION` - Package metadata
- `NAMESPACE` - Exports
- `.Rbuildignore` - Build configuration
- `README.md` - Project overview

#### 5.2 Implement Rcpp Wrappers

*Depends on Phase 3 completion*

```r
kst_compile(json_spec, metadata) -> R code string
kst_generate_table(json_spec, data, calc_functions) -> tibble
```

**Deliverables**:

- `src/RcppExports.cpp` - Auto-generated bindings
- `R/compile.R` - Main compilation interface
- `R/generate.R` - Table generation wrapper

#### 5.3 Write Helper Functions

*Depends on 5.2*

```r
kst_validate_spec(json_spec)
kst_extract_metadata(data, variables)
kst_register_calc(name, fn)
```

**Deliverables**:

- `R/validate.R` - Validation helpers
- `R/metadata.R` - Metadata helpers (from 2.2)
- `R/registry.R` - Function registration
- Documentation for all functions

#### 5.4 Write R-side Formatting Utilities

*Depends on 3.3*

```r
format_mean_sd(mean, sd, digits)
format_n_pct(n, pct)
format_median_range(median, min, max)
```

**Deliverables**:

- `R/format.R` - Common formatting functions
- Integration with ksformat package
- Examples in documentation

---

### Phase 6: Testing & Validation

**Objective**: Comprehensive test coverage

*Parallel with Phase 5*

#### 6.1 Write Unit Tests for C++ Compiler

*Depends on Phase 3 completion*

- Test JSON parsing and validation
- Test code generation for simple cases
- Test optimization passes

**Deliverables**:

- `tests/cpp/test_parser.cpp` - Parser tests
- `tests/cpp/test_codegen.cpp` - Code generation tests
- `tests/cpp/test_optimizer.cpp` - Optimization tests
- Test runner configuration

#### 6.2 Write Integration Tests for R Package

*Depends on Phase 5 completion*

- Test end-to-end: JSON → tibble
- Test metadata introspection
- Test calculation function dispatch
- Test hierarchical table generation

**Deliverables**:

- `tests/testthat/test-compile.R`
- `tests/testthat/test-metadata.R`
- `tests/testthat/test-generate.R`
- `tests/testthat/test-hierarchy.R`
- `tests/testthat/test-format.R`

#### 6.3 Create Example Table Specifications

*Depends on Phase 5 completion*

- Demographics table (age by treatment + gender)
- Adverse events table (SOC → PT hierarchy)
- Efficacy table (change from baseline by visit)
- Laboratory shift table (baseline → post-baseline)

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

- **dplyr** - Data manipulation (generated code uses this)
- **tidyr** - Data reshaping (pivoting, nesting)
- **rlang** - Tidy evaluation (for dynamic code generation)
- **ksformat** - Value formatting (integration)
- **jsonlite** - JSON parsing in R (validation, metadata)
- **Rcpp** - C++ integration

**C++ Libraries**:

- **Boost.JSON** - JSON parsing in C++
- **fmt** - String formatting
- **range-v3** - Modern ranges for code generation
- **Boost** (various) - Utilities

### Build System

- **Rcpp** for R/C++ interface
- **C++23** standard
- Standard R package build tools

### File Structure

```text
ksTable/
├── DESCRIPTION              # Package metadata
├── NAMESPACE                # Exports
├── README.md                # Overview
├── NEWS.md                  # Version history
├── LICENSE                  # GPL-3 or MIT
├── .Rbuildignore           # Build configuration
├── R/                       # R source files
│   ├── compile.R           # Main API
│   ├── generate.R          # Table generation
│   ├── metadata.R          # Metadata extraction
│   ├── format.R            # Formatting utilities
│   ├── validate.R          # Validation helpers
│   ├── registry.R          # Function registration
│   └── RcppExports.R       # Auto-generated
├── src/                     # C++ source files
│   ├── compiler/           # Compiler components
│   │   ├── parser.hpp
│   │   ├── parser.cpp
│   │   ├── validator.hpp
│   │   ├── validator.cpp
│   │   ├── ast.hpp
│   │   ├── codegen.hpp
│   │   ├── codegen.cpp
│   │   ├── optimizer.cpp
│   │   ├── format_gen.cpp
│   │   ├── hierarchy.cpp
│   │   ├── metadata.hpp
│   │   ├── metadata.cpp
│   │   └── function_call.cpp
│   ├── rcpp_interface.cpp  # Rcpp bindings
│   ├── RcppExports.cpp     # Auto-generated
│   └── Makevars            # Build configuration
├── inst/                    # Installed files
│   ├── schema/             # JSON schemas
│   │   └── table_spec_v1.json
│   └── examples/           # Example DSL files
│       ├── demographics.json
│       ├── adverse_events.json
│       ├── efficacy.json
│       └── laboratory.json
├── tests/                   # Tests
│   ├── testthat/           # R tests
│   │   ├── test-compile.R
│   │   ├── test-metadata.R
│   │   ├── test-generate.R
│   │   ├── test-hierarchy.R
│   │   └── test-format.R
│   └── cpp/                # C++ tests
│       ├── test_parser.cpp
│       ├── test_codegen.cpp
│       └── test_optimizer.cpp
├── vignettes/              # Documentation
│   ├── getting_started.Rmd
│   ├── dsl_reference.Rmd
│   ├── advanced_features.Rmd
│   └── kstfl_integration.Rmd
└── man/                    # Generated documentation
```

---

## Verification Criteria

### JSON DSL Validation

✓ Create sample DSL for demographics table (age, sex by treatment)  
✓ Run `ks_validate_spec(json_spec)` - should pass without errors  
✓ Introduce errors (typos, missing fields) - should produce helpful messages  

### Code Generation

✓ Compile demographics DSL: `code <- ks_compile(json_spec, metadata)`  
✓ Review generated R code - should be readable dplyr chains  
✓ Check for expected operations: `group_by(TRT)`, `summarize(n = count(AGE))`  
✓ Verify formatting logic included: `mutate(mean_sd = format_mean_sd(mean, sd))`  

### End-to-End Execution

✓ Load sample dataset: `adsl <- tibble(USUBJID, AGE, TRT, SEX)`  
✓ Define calculation function: `count <- function(data) length(data)`  
✓ Generate table: `result <- ks_generate_table(json_spec, adsl, list(count = count))`  
✓ Verify output structure: tibble with formatted string columns  
✓ Verify all values are formatted strings (ready for ksTFL)  
✓ Pass to ksTFL: `create_table(result) %>% write_doc("demo.docx")`  

### Metadata Introspection

✓ Create data with factor: `data <- tibble(TRT = factor(c("A", "B"), levels = c("A", "B", "C")))`  
✓ Extract metadata: `meta <- ks_extract_metadata(data, "TRT")`  
✓ Verify includes missing level "C"  
✓ Generate table with `include_missing_levels = true` - should have row for "C" with 0 count  

### Hierarchical Tables

✓ Create AE data: `ae <- tibble(SOC, PT, USUBJID, ...)`  
✓ Define nested parameter in JSON: `"parameter": {"soc": {"nested": "pt"}}`  
✓ Generate table - verify SOC rows followed by indented PT rows  
✓ Verify parent rows deduplicated (SOC appears once per category)  

### Optimization

✓ Create DSL with redundant operations (multiple group_by on same variables)  
✓ Compile with optimization enabled  
✓ Examine generated code - redundant operations should be eliminated  
✓ Verify result correctness unchanged  

### ksformat Integration

✓ Define ksformat VALUE format: `fnew("A" = "Active", "P" = "Placebo", name = "trt")`  
✓ Reference in DSL: `"groups": {"groups": "TRT", "format": "trt"}`  
✓ Generate table - verify treatment labels use ksformat ("Active", not "A")  
✓ Verify metadata extraction discovers ksformat levels  

---

## Key Design Decisions

### 1. DSL is Declarative

**Decision**: Describe desired output, not transformations  
**Rationale**: Easier for users, enables optimization  
**Trade-off**: Harder compiler implementation  

### 2. Simple Function Contract

**Decision**: Functions take only `data`, return results  
**Rationale**: Easy to understand, compiler handles grouping  
**Trade-off**: Less flexible than complex signatures  

### 3. C++ Compiler for Optimization

**Decision**: Not just code generation - also optimize query plans  
**Rationale**: Justifies C++ complexity vs pure R  
**Trade-off**: More complex build process  

### 4. Multiple Format Methods

**Decision**: Support ksformat, templates, custom functions  
**Rationale**: Maximum flexibility for users  
**Trade-off**: More complex implementation  

### 5. Dynamic Metadata Introspection

**Decision**: Generated code adapts to runtime data  
**Rationale**: More flexible than static compilation  
**Trade-off**: Slightly slower than static (negligible)  

### 6. Pipe-Based Generated Code

**Decision**: Use %>% chains in generated code  
**Rationale**: Most readable for users reviewing/debugging  
**Trade-off**: Slightly more verbose than nested calls  

### 7. Rcpp for C++/R Integration

**Decision**: Use standard Rcpp approach  
**Rationale**: Well-documented, reliable, standard  
**Trade-off**: None - this is the standard way  

### 8. Boost.JSON not nlohmann/json

**Decision**: Use Boost.JSON for JSON parsing  
**Rationale**: User specified Boost, may have existing dependency  
**Trade-off**: Larger dependency footprint  

### 9. Hierarchical Table Support

**Decision**: First-class support for nested structures  
**Rationale**: Critical for clinical tables (AE, conmeds)  
**Trade-off**: Increased complexity  

### 10. Phase-Based Implementation

**Decision**: Clear phases with dependencies  
**Rationale**: Allows parallel work, clear milestones  
**Trade-off**: Requires careful coordination  

---

## Open Questions & Future Considerations

### 1. DSL Versioning

**Question**: How to handle DSL schema evolution?  
**Recommendation**: Include schema version in JSON, compiler checks compatibility  
**Priority**: Medium - address in Phase 1  

### 2. Code Caching

**Question**: Should generated code be cached?  
**Recommendation**: Optional caching with hash-based invalidation  
**Priority**: Low - optimization for future versions  

### 3. Error Handling Strategy

**Question**: How to report errors in user calculation functions?  
**Recommendation**: Try-catch wrapper with informative context  
**Priority**: High - address in Phase 4  

### 4. Performance Targets

**Question**: What is acceptable compile time?  
**Recommendation**: < 1 second for simple tables, < 10 seconds for complex  
**Priority**: Medium - benchmark in Phase 6  

### 5. Multi-Level Nesting Depth

**Question**: How deep should hierarchical tables go?  
**Recommendation**: Start with 2 levels (SOC→PT), generalize later if needed  
**Priority**: Low - v1.0 supports 2 levels  

### 6. Column Ordering

**Question**: How to control output column order?  
**Recommendation**: DSL specifies column order explicitly  
**Priority**: High - address in Phase 1 schema design  

### 7. Row Ordering

**Question**: How to control output row order?  
**Recommendation**: DSL specifies sort variables and direction  
**Priority**: High - address in Phase 1 schema design  

### 8. Missing Data Handling

**Question**: How to handle NA values in grouping variables?  
**Recommendation**: Configurable per variable (include/exclude/separate)  
**Priority**: Medium - address in Phase 2  

### 9. Large Dataset Handling

**Question**: Memory limits for metadata introspection?  
**Recommendation**: Stream distinct values, don't load full data into memory  
**Priority**: Medium - optimization for large datasets  

### 10. R Version Compatibility

**Question**: What minimum R version?  
**Recommendation**: R ≥ 4.1 (native pipe |>, better C++ integration)  
**Priority**: High - specify in DESCRIPTION  

---

## Success Metrics

### Functional Completeness

- [ ] All phases completed
- [ ] All verification criteria passed
- [ ] Example tables generate correctly
- [ ] Integration with ksTFL works seamlessly

### Code Quality

- [ ] > 80% test coverage
- [ ] No memory leaks in C++ code
- [ ] Pass CRAN checks
- [ ] Documentation complete and accurate

### Performance

- [ ] Compile time < 1 sec for simple tables
- [ ] Compile time < 10 sec for complex tables
- [ ] Generated code efficient (no obvious redundancy)
- [ ] Memory usage reasonable for large datasets

### Usability

- [ ] Clear error messages
- [ ] Examples in documentation work
- [ ] Vignettes are comprehensive
- [ ] Community feedback is positive

---

## Timeline Estimate

**Phase 1**: 2-3 weeks  
**Phase 2**: 1-2 weeks (parallel)  
**Phase 3**: 3-4 weeks  
**Phase 4**: 2-3 weeks (parallel with Phase 3)  
**Phase 5**: 2-3 weeks (parallel with later phases)  
**Phase 6**: 2-3 weeks (parallel)  
**Phase 7**: 1-2 weeks  

**Total**: Approximately 8-12 weeks for v1.0 release

---

## References

- **CDISC ARS**: [https://cdisc-org.github.io/analysis-results-standard/]
- **LinkML**: [https://linkml.io/]
- **ksTFL**: [https://github.com/crow16384/ksTFL]
- **ksformat**: [https://github.com/crow16384/ksformat]
- **PharmaSUG Paper**: [https://pharmasug.org/proceedings/japan2024/PharmaSUG-Japan-2024-02.pdf]

---

**Document Version**: 1.0  
**Last Updated**: 2026-07-01  
**Status**: Approved for Implementation
