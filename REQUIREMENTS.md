# ksTable Requirements Document

**Date**: 2026-07-05  
**Version**: 2.0

------------------------------------------------------------------------

## Project Scope

### In Scope

✓ JSON DSL for declarative table specifications  
✓ Pure-R generator producing dplyr/tidyr R code  
✓ Metadata helpers (ksformat, factors, distinct values) applied by
caller before eval  
✓ User-provided calculation functions (bare names in generated code)  
✓ Multi-way stratification and grouping  
✓ Hierarchical table structures (parent/child rows, 2-level in v0.1)  
✓ Multiple formatting methods (ksformat, templates, custom, sprintf)  
✓ Integration with ksTFL for rendering (output shape)  
✓ Integration with ksformat for value formatting

### Out of Scope

✗ DOCX rendering (handled by ksTFL)  
✗ Statistical calculations (user provides these)  
✗ Data validation (assumes clean input)  
✗ ADaM dataset specifics (generic for any tibble)  
✗ GUI or interactive table builder  
✗ Real-time table updates  
✗ Database connectivity  
✗ Query plan optimization / C++ compiler (rejected after pure-R PoC)

------------------------------------------------------------------------

## User Requirements

### UR-1: Declarative Table Specification

**Description**: Users shall define tables using declarative JSON
describing desired output  
**Rationale**: Easier than imperative code, enables optimization  
**Acceptance**: JSON DSL clearly describes table structure without
specifying transformations

### UR-2: Source Data Flexibility

**Description**: System shall accept any tibble/data.frame as input (not
just ADaM)  
**Rationale**: Generality - not limited to clinical trial datasets  
**Acceptance**: System works with arbitrary data structures

### UR-3: User Calculation Functions

**Description**: Users shall provide R functions for statistical
calculations  
**Rationale**: Users know their domain, system can’t anticipate all
calculations  
**Acceptance**: Functions referenced in JSON are called correctly

### UR-4: Metadata-Driven Code Generation

**Description**: Users shall prepare grouping metadata (factor levels,
ksformat labels) before evaluating compiled code when missing levels or
formatted headers are required  
**Rationale**: Tables adapt to data (new treatment arms, missing levels)
via runtime factors  
**Acceptance**: `kst_extract_metadata` / `kst_apply_metadata` plus
`include_missing_levels` produce complete group columns

### UR-5: Hierarchical Tables

**Description**: System shall support nested table structures (e.g., SOC
→ PT)  
**Rationale**: Common in clinical tables (adverse events, concomitant
medications)  
**Acceptance**: Parent rows deduplicated, child rows indented/grouped

### UR-6: ksformat Integration

**Description**: System shall integrate with ksformat for value
formatting  
**Rationale**: Leverage existing formatting infrastructure  
**Acceptance**: Can reference ksformat VALUE formats in DSL

### UR-7: ksTFL Integration

**Description**: Generated tibbles shall be ready for ksTFL rendering  
**Rationale**: ksTable produces data, ksTFL renders it  
**Acceptance**: ksTFL `create_table()` works without modification

### UR-8: Readable Generated Code

**Description**: Generated R code shall be human-readable  
**Rationale**: Users need to review/debug generated code  
**Acceptance**: Uses pipe chains, descriptive variable names

### UR-9: Performance

**Description**: Generated code shall execute efficiently  
**Rationale**: Users expect fast table generation even for large
datasets  
**Acceptance**: Compilation \< 1 ms; execution comparable to
hand-written dplyr

### UR-10: Clear Error Messages

**Description**: System shall provide helpful error messages  
**Rationale**: Users need guidance when specs are malformed  
**Acceptance**: Errors indicate problem and suggest fix

------------------------------------------------------------------------

## Functional Requirements

### FR-1: JSON Parsing

**Description**: Parse JSON DSL into R data structures  
**Input**: JSON string or file path  
**Output**: Parsed specification as R list  
**Validation**: Valid JSON matching schema  
**Error Handling**: Syntax errors, schema violations

### FR-2: Schema Validation

**Description**: Validate JSON against defined schema  
**Input**: Parsed JSON object  
**Output**: Validation result (pass/fail with errors)  
**Rules**: Required fields present, types correct, references valid  
**Error Handling**: List all validation errors with line numbers

### FR-3: Metadata Extraction

**Description**: Extract metadata from input data  
**Input**: Data frame, variable names  
**Output**: Metadata JSON (types, levels, formats)  
**Priority**: ksformat → factor levels → distinct values  
**Error Handling**: Missing variables, type mismatches

### FR-4: Code Generation

**Description**: Generate dplyr/tidyr R code from DSL  
**Input**: Parsed spec, metadata  
**Output**: R code string  
**Style**: Pipe-based (%\>% chains)  
**Optimization**: Eliminate redundant operations

### FR-5: Function Dispatch

**Description**: Generate calls to user calculation functions  
**Input**: Function references in DSL  
**Output**: R code calling functions with correct arguments  
**Contract**: `function(data) -> result`  
**Error Handling**: Missing functions, wrong signatures

### FR-6: Result Assembly

**Description**: Generate code to assemble results into tibble  
**Input**: Individual group results  
**Output**: Combined tibble with proper structure  
**Ordering**: Rows and columns as specified in DSL  
**Formatting**: All values formatted as strings

### FR-7: Hierarchical Table Generation

**Description**: Generate code for nested table structures  
**Input**: Nested parameter specification  
**Output**: Tibble with parent/child relationships  
**Features**: Deduplication, indentation metadata  
**Depth**: Initially 2 levels, extensible

### FR-8: Format Code Generation

**Description**: Generate formatting code for values  
**Methods**: ksformat calls, template strings, custom functions  
**Input**: Format specifications in DSL  
**Output**: R code formatting values  
**Integration**: Works with ksformat package

### FR-9: Missing Level Handling

**Description**: Include missing factor levels if specified  
**Input**: `include_missing_levels` flag  
**Source**: ksformat metadata or factor levels  
**Output**: Rows for all levels, even if count = 0  
**Error Handling**: No metadata available

### FR-10: Multi-way Stratification

**Description**: Support grouping by multiple variables  
**Input**: List of grouping variables  
**Output**: Results for all combinations  
**Ordering**: As specified or alphabetical  
**Missing**: Configurable handling of NA groups

------------------------------------------------------------------------

## Non-Functional Requirements

### NFR-1: Performance - Compilation Time

**Requirement**: \< 1 second for simple tables, \< 10 seconds for
complex  
**Rationale**: Fast enough for interactive use  
**Measurement**: Benchmark on standard hardware

### NFR-2: Performance - Memory Usage

**Requirement**: \< 100 MB peak for typical tables  
**Rationale**: Reasonable for desktop R sessions  
**Measurement**: Profile with valgrind, R profiling tools

### NFR-3: Reliability - No Crashes

**Requirement**: All errors caught and reported gracefully; no R session
crashes  
**Rationale**: Users expect stable behaviour in long-running sessions  
**Measurement**: Error injection testing

### NFR-4: Reliability - Error Handling

**Requirement**: All errors caught and reported gracefully  
**Rationale**: No crashes, informative messages  
**Measurement**: Fuzz testing, error injection

### NFR-5: Usability - Documentation

**Requirement**: Complete documentation with examples  
**Rationale**: Users can learn and use the package  
**Measurement**: All functions documented, vignettes complete

### NFR-6: Usability - Error Messages

**Requirement**: Errors indicate problem and suggest fix  
**Rationale**: Users can correct issues independently  
**Measurement**: User testing, feedback

### NFR-7: Maintainability - Code Quality

**Requirement**: Modern idiomatic R, standard package practices  
**Rationale**: Long-term maintainability  
**Measurement**: Code reviews, style checks (`lintr`)

### NFR-8: Maintainability - Test Coverage

**Requirement**: \> 80% test coverage  
**Rationale**: Confidence in correctness  
**Measurement**: Code coverage tools

### NFR-9: Portability - Platform Support

**Requirement**: Works on Windows, macOS, Linux  
**Rationale**: Standard R package portability  
**Measurement**: CI/CD on all platforms

### NFR-10: Compatibility - R Version

**Requirement**: R ≥ 4.1  
**Rationale**: Native pipe `|>` (R 4.1), no compiled code  
**Measurement**: Test on R 4.1

------------------------------------------------------------------------

## Technical Requirements

### TR-1: R Standard

**Requirement**: R ≥ 4.1.0  
**Rationale**: Native pipe `|>`, modern tidyverse ecosystem  
**Dependencies**: No compiler requirements

### TR-2: R Package Dependencies

**Required**:

- dplyr (≥ 1.1.0)
- tidyr (≥ 1.3.0)
- rlang (≥ 1.1.0)
- ksformat (≥ 0.7.0)
- jsonlite (≥ 1.8.0)

**Suggests**:

- testthat (≥ 3.0.0)
- knitr
- rmarkdown
- glue (≥ 1.7.0, for `template` format type)

### TR-3: Build System

**Requirements**:

- Standard R package build tools (`devtools`, `roxygen2`)
- No `src/` directory, no `Makevars`, no compiled code
- `R CMD check` passes with no notes on Windows/macOS/Linux

### TR-5: File Formats

**Input**:

- JSON DSL (UTF-8)
- R data frames (tibble)
- ksformat definitions (via ksformat package)

**Output**:

- R code (character string, UTF-8)
- R data frames (tibble with character columns)

------------------------------------------------------------------------

## Interface Requirements

### IR-1: Main Compilation Interface

``` r

kst_compile(json_spec) -> character
```

**Input**:

- `json_spec`: JSON string or file path

**Output**: R code string (plain script, expects `data` in eval env)

**Behavior**: Validates the spec (same checks as `kst_validate_spec`)
then emits code. Metadata is not applied during compile.

**Errors**: Parsing errors, validation errors, compilation errors

### IR-2: Execution Workflow Interface

``` r

# optional metadata prep when include_missing_levels / ksformat headers needed
meta <- kst_extract_metadata(data, vars, format_map = ...)
data <- kst_apply_metadata(data, meta)

code <- kst_compile(json_spec)
env  <- new.env(parent = envir)
env$data <- data
result <- eval(parse(text = code), envir = env)
```

**Input**:

- `json_spec`: JSON string or file path
- `data`: Source data frame
- `envir`: Parent environment used to resolve calc/format functions

**Output**: Formatted tibble ready for ksTFL

**Notes**: Calc and format functions are resolved from `envir` as plain
function calls; no lists or registry needed. Execution is isolated in
`new.env(parent = envir)`.

**Errors**: Missing functions, data errors, calculation errors

### IR-3: Validation Interface

``` r

kst_validate_spec(json_spec) -> list(valid = TRUE/FALSE, errors = character)
```

**Input**: JSON string or file path

**Output**: Validation result with error messages

### IR-4: Metadata Extraction Interface

``` r

kst_extract_metadata(data, variables, use_ksformat = TRUE) -> list
```

**Input**:

- `data`: Source data frame
- `variables`: Variable names to extract metadata for
- `use_ksformat`: Query ksformat for metadata

**Output**: Metadata list (types, levels, formats)

------------------------------------------------------------------------

## Security Requirements

### SR-1: Code Injection Prevention

**Description**: All JSON-derived values used in generated R code must
be sanitized before emission

**Identifiers** (`variable`, `fun`, `format.fun`, `by` items): validated
against `^[A-Za-z.][A-Za-z0-9._]*$`; any value that does not match must
be rejected with an informative error.

**String literals** (`label`, `pattern`): `\` escaped to `\\` and `"`
escaped to `\"`before embedding in double-quoted R strings.

**Coverage**: applied to every JSON field before any code is emitted, in
`R/compiler.R`.

------------------------------------------------------------------------

## Data Requirements

### DR-1: Input Data Format

**Structure**: tibble or data.frame  
**Columns**: Any names, any types  
**Missing Values**: NA handled gracefully  
**Size**: No hard limit, memory permitting

### DR-2: Output Data Format

**Structure**: tibble  
**Columns**: As specified in DSL  
**Values**: All formatted as character strings  
**Metadata**: Column types preserved in attributes  
**Missing Values**: Formatted strings (not NA)

### DR-3: Metadata Format

**Structure**: Named list  
**Fields**:

- `type`: “numeric”, “character”, “factor”, “Date”, etc.
- `levels`: For factors (character vector)
- `format`: ksformat name (if applicable)
- `distinct_values`: For non-factors (up to N unique values)

### DR-4: JSON DSL Format

**Encoding**: UTF-8  
**Schema Version**: Included in JSON  
**Required Fields**: Depends on schema  
**Optional Fields**: Defaults provided  
**Comments**: Not supported (JSON limitation)

------------------------------------------------------------------------

## Calculation Function Contract

### CF-1: Function Signature

``` r

function(data) {
  # data: vector or tibble
  # return: scalar, vector, or tibble
}
```

### CF-2: Input

**Vector Case**: `data` is a numeric/character vector  
**Tibble Case**: `data` is a tibble (for complex calculations)

### CF-3: Output

**Scalar**: Single value (length 1)  
**Vector**: Same length as input  
**Tibble**: One row per input group

### CF-4: Error Handling

Functions should return NA or error message on failure  
Compiler wraps calls in try-catch

### CF-5: Example Functions

``` r

# Count non-missing values
count <- function(data) {
  sum(!is.na(data))
}

# Mean and SD combined
mean_sd <- function(data) {
  m <- mean(data, na.rm = TRUE)
  s <- sd(data, na.rm = TRUE)
  sprintf("%.1f (%.2f)", m, s)
}

# Median and range
median_range <- function(data) {
  med <- median(data, na.rm = TRUE)
  rng <- range(data, na.rm = TRUE)
  sprintf("%.1f [%.1f, %.1f]", med, rng[1], rng[2])
}
```

------------------------------------------------------------------------

## Quality Assurance

### QA-1: Unit Testing

**Coverage**: \> 80% for R code  
**Framework**: testthat  
**Scope**: All major functions, edge cases, error paths

### QA-2: Integration Testing

**Scope**: End-to-end workflows  
**Cases**: All example tables generate correctly  
**Validation**: Output matches expected structure

### QA-3: Performance Testing

**Metrics**: Compilation time, memory usage  
**Benchmarks**: Simple, medium, complex tables  
**Regression**: Compare across versions

### QA-4: Documentation Review

**Scope**: All exported functions, vignettes, README  
**Criteria**: Clear, accurate, comprehensive  
**Examples**: All examples run without errors

### QA-5: Code Review

**Scope**: All code changes  
**Criteria**: Style, correctness, performance  
**Tools**: Static analysis, linters

------------------------------------------------------------------------

## Success Criteria

### Milestone 1: Prototype (Phase 1-2)

✓ JSON parsing works  
✓ Basic code generation for simple table  
✓ Metadata extraction from data

### Milestone 2: Core Features (Phase 3-4)

✓ Full code generation pipeline  
✓ Function dispatch works  
✓ Optimization implemented  
✓ Formatting code generation

### Milestone 3: Complete Package (Phase 5)

✓ Package builds with `devtools::build()` on all platforms  
✓ All helper functions implemented  
✓ Package builds and installs

### Milestone 4: Validated (Phase 6)

✓ All tests pass  
✓ Example tables generate correctly  
✓ Integration with ksTFL works

### Milestone 5: Documented (Phase 7)

✓ Vignettes complete  
✓ Function documentation complete  
✓ README with quick start

### Release Criteria (v1.0)

✓ All milestones complete  
✓ CRAN checks pass  
✓ No critical bugs  
✓ Documentation complete  
✓ Performance targets met

------------------------------------------------------------------------

## Risk Assessment

### Risk 1: DSL Schema Complexity

**Probability**: Medium  
**Impact**: High  
**Mitigation**: Provide helpers, comprehensive examples, and good
validation error messages

### Risk 2: DSL Design Inadequate

**Probability**: Medium  
**Impact**: High  
**Mitigation**: User feedback early; iterative design

### Risk 3: Performance Targets Not Met

**Probability**: Low  
**Impact**: Medium  
**Mitigation**: Profile early; optimize hot paths

### Risk 4: ksformat Integration Issues

**Probability**: Low  
**Impact**: Medium  
**Mitigation**: Test integration early; coordinate with ksformat
maintainer

### Risk 5: Boost Dependencies

**Probability**: Medium  
**Impact**: Low  
**Mitigation**: Document setup; provide guidance for installation

------------------------------------------------------------------------

**Document Status**: Approved  
**Approver**: \[Project Lead\]  
**Date**: 2026-07-01
