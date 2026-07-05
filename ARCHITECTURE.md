---
marp: false
---

# ksTable Architecture Document

**Version**: 1.0  
**Date**: 2026-07-01

---

## System Overview

```text
┌────────────────────────────────────────────────────────────────┐
│                          User Space                            │
│                                                                │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐        │
│  │ JSON DSL     │   │ Input Data   │   │ Calculation  │        │
│  │ Specification│   │ (tibble)     │   │ Functions    │        │
│  └──────┬───────┘   └──────┬───────┘   └──────┬───────┘        │
│         │                  │                  │                │
└─────────┼──────────────────┼──────────────────┼────────────────┘
          │                  │                  │
          │                  │                  │
┌─────────▼──────────────────▼──────────────────▼─────────────────┐
│                       ksTable Package                           │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                   R Layer (Public API)                   │   │
│  │                                                          │   │
│  │  kst_compile()                                           │   │
│  │  kst_generate_table()                                    │   │
│  │  kst_validate_spec()                                     │   │
│  │  kst_extract_metadata()                                  │   │
│  │                                                          │   │
│  └───────────────────────┬──────────────────────────────────┘   │
│                          │                                      │
│                          ▼                                      │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │               Rcpp Interface Layer                       │   │
│  │                                                          │   │
│  │  compile_spec() [Rcpp wrapper]                           │   │
│  │  validate_json() [Rcpp wrapper]                          │   │
│  │                                                          │   │
│  └───────────────────────┬──────────────────────────────────┘   │
│                          │                                      │
│                          ▼                                      │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              C++23 Compiler Core                         │   │
│  │                                                          │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐    │   │
│  │  │   Parser     │→ │  Validator   │→ │   Metadata   │    │   │
│  │  │  (Boost.JSON)│  │              │  │   Consumer   │    │   │
│  │  └──────────────┘  └──────────────┘  └──────┬───────┘    │   │
│  │                                             │            │   │
│  │                          ┌──────────────────┘            │   │
│  │                          ▼                               │   │
│  │  ┌──────────────────────────────────────────────────┐    │   │
│  │  │            AST Builder & Optimizer               │    │   │
│  │  │                                                  │    │   │
│  │  │  • Query Plan Construction                       │    │   │
│  │  │  • Redundancy Elimination                        │    │   │
│  │  │  • Operation Reordering                          │    │   │
│  │  └──────────────────────┬───────────────────────────┘    │   │
│  │                         │                                │   │
│  │                         ▼                                │   │
│  │  ┌──────────────────────────────────────────────────┐    │   │
│  │  │         Code Generation Modules                  │    │   │
│  │  │                                                  │    │   │
│  │  │  ┌─────────────┐  ┌─────────────┐                │    │   │
│  │  │  │   Dplyr     │  │  Tidyr      │                │    │   │
│  │  │  │   CodeGen   │  │  CodeGen    │                │    │   │
│  │  │  └─────────────┘  └─────────────┘                │    │   │
│  │  │                                                  │    │   │
│  │  │  ┌─────────────┐  ┌─────────────┐                │    │   │
│  │  │  │  Format     │  │ Hierarchy   │                │    │   │
│  │  │  │  CodeGen    │  │  CodeGen    │                │    │   │
│  │  │  └─────────────┘  └─────────────┘                │    │   │
│  │  └──────────────────────┬───────────────────────────┘    │   │
│  │                         │                                │   │
│  │                         ▼                                │   │
│  │                  [ R Code String ]                       │   │
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
- Function registry management
- Generated code execution

**Key Functions**:

```r
kst_compile(json_spec, metadata = NULL, optimize = TRUE)

```

- Validate JSON spec
- Extract metadata if not provided
- Call C++ compiler
- Return R code string

```r
kst_generate_table(json_spec, data, calc_functions, ...)

```

- Extract metadata from data
- Compile spec to R code
- Register calculation functions
- Execute generated code
- Return formatted tibble

```r
kst_validate_spec(json_spec)

```

- Parse JSON
- Validate against schema
- Return validation result

```r
kst_extract_metadata(data, variables, use_ksformat = TRUE)

```

- Query ksformat for format metadata
- Extract factor levels
- Compute distinct values
- Return metadata list

**Dependencies**:

- dplyr, tidyr, rlang (for generated code environment)
- ksformat (for format metadata)
- jsonlite (for R-side JSON parsing)
- Rcpp (for C++ integration)

---

### 2. Rcpp Interface Layer

**Location**: `src/rcpp_interface.cpp`, `src/RcppExports.cpp`

**Responsibilities**:

- Bridge between R and C++
- Type conversion (R ↔ C++)
- Error handling and exception translation
- Memory management

**Key Bindings**:

```cpp
// [[Rcpp::export]]
Rcpp::String compile_spec_impl(
    Rcpp::String json_spec,
    Rcpp::List metadata,
    bool optimize
)
```

```cpp
// [[Rcpp::export]]
Rcpp::List validate_json_impl(Rcpp::String json_spec)
```

**Type Conversions**:

- R character → std::string
- R list → JSON object (via jsonlite)
- C++ exceptions → R errors (via Rcpp::stop)

---

### 3. C++ Compiler Core

**Location**: `src/compiler/*.cpp`, `src/compiler/*.hpp`

#### 3.1 Parser Module

**File**: `src/compiler/parser.cpp`

**Responsibilities**:

- Parse JSON string using Boost.JSON
- Construct internal data structures
- Handle encoding (UTF-8)

**Data Structures**:

```cpp
struct TableSpec {
    std::string schema_version;
    std::string id;
    std::string title;
    std::string type;  // "summary" or "listing"
    
    std::map<std::string, Parameter> parameters;
    std::map<std::string, Statistic> statistics;
    GroupSpec groups;
    LayoutSpec layout;
};

struct Parameter {
    std::string name;
    std::string variable;
    std::string label;
    std::optional<Parameter> nested;  // For hierarchical
};

struct Statistic {
    std::string name;
    std::string fun;
    std::string label;
    FormatSpec format;
};

struct GroupSpec {
    std::vector<std::string> by;
    bool include_missing_levels;
    std::map<std::string, std::string> formats;  // var → ksformat name
};
```

#### 3.2 Validator Module

**File**: `src/compiler/validator.cpp`

**Responsibilities**:

- Schema validation
- Reference validation (function names, format names)
- Semantic validation (logical consistency)
- Error message generation

**Validation Rules**:

- Required fields present
- Types correct (string, bool, array, object)
- Function references valid (if function registry provided)
- Format references valid (if ksformat library provided)
- No circular dependencies in nested parameters
- Logical consistency (e.g., can't have both row_structure and column_structure)

**Error Format**:

```cpp
struct ValidationError {
    std::string path;      // JSON path (e.g., "/table_spec/statistics/n/fun")
    std::string message;   // Error description
    std::string suggestion; // How to fix (optional)
};
```

#### 3.3 Metadata Consumer

**File**: `src/compiler/metadata.cpp`

**Responsibilities**:

- Parse metadata JSON from R
- Build metadata index for code generation
- Resolve format specifications

**Metadata Structure**:

```cpp
struct VariableMetadata {
    std::string name;
    std::string type;  // "numeric", "factor", "character", etc.
    std::vector<std::string> levels;  // For factors
    std::optional<std::string> format;  // ksformat name
    std::vector<std::string> distinct_values;  // For non-factors
};

struct MetadataIndex {
    std::map<std::string, VariableMetadata> variables;
    
    VariableMetadata get(const std::string& var) const;
    bool has_format(const std::string& var) const;
    std::vector<std::string> get_levels(const std::string& var) const;
};
```

#### 3.4 AST Builder & Optimizer

**File**: `src/compiler/ast.hpp`, `src/compiler/optimizer.cpp`

**Responsibilities**:

- Build Abstract Syntax Tree for R code
- Optimize query plans
- Eliminate redundant operations
- Reorder operations for efficiency

**AST Structure**:

```cpp
enum class NodeType {
    Pipeline,      // %>% chain
    GroupBy,       // group_by()
    Summarize,     // summarize()
    Mutate,        // mutate()
    Filter,        // filter()
    Arrange,       // arrange()
    Pivot,         // pivot_wider/longer
    Nest,          // nest()
    Unnest,        // unnest()
    FunctionCall   // user function call
};

struct ASTNode {
    NodeType type;
    std::vector<std::shared_ptr<ASTNode>> children;
    std::map<std::string, std::string> params;
    
    std::string to_r_code() const;
};

struct Pipeline : ASTNode {
    std::vector<std::shared_ptr<ASTNode>> operations;
};
```

**Optimization Passes**:

1. **Redundancy Elimination**: Remove duplicate group_by() calls
2. **Operation Fusion**: Combine multiple mutate() into one
3. **Predicate Pushdown**: Move filter() earlier in pipeline
4. **Projection Pruning**: Only select() columns needed downstream

#### 3.5 Code Generation Modules

**Dplyr CodeGen** (`src/compiler/codegen_dplyr.cpp`):

- Generate group_by() calls
- Generate summarize() calls
- Generate mutate() calls for transformations
- Handle missing level inclusion

**Tidyr CodeGen** (`src/compiler/codegen_tidyr.cpp`):

- Generate pivot_wider() / pivot_longer() calls
- Generate nest() / unnest() for hierarchical tables

**Format CodeGen** (`src/compiler/format_gen.cpp`):

- Generate ksformat::fput() calls
- Generate sprintf() calls
- Generate template string interpolation
- Generate custom format function calls

**Hierarchy CodeGen** (`src/compiler/hierarchy.cpp`):

- Generate nested grouping code
- Generate parent row deduplication
- Generate indentation markers
- Handle arbitrary nesting depth

**Output**: R code string (UTF-8)

---

## Data Flow

### Compilation Flow

```text
JSON DSL
  ↓
[Parser] → TableSpec object
  ↓
[Validator] → Validation result
  ↓
[Metadata Consumer] → MetadataIndex
  ↓
[AST Builder] → AST
  ↓
[Optimizer] → Optimized AST
  ↓
[Code Generators] → R code string
  ↓
Return to R
```

### Execution Flow

```text
R code string
  ↓
[Create environment] → Include calc functions, data
  ↓
[eval(parse(text = code), envir = env)]
  ↓
[Execute dplyr pipeline]
  ↓
Formatted tibble
  ↓
Return to user
```

---

## Memory Management

### R Side

- Standard R garbage collection
- No manual memory management required
- Rcpp handles SEXP ↔ C++ conversion

### C++ Side

- Modern C++23: use std::unique_ptr, std::shared_ptr
- RAII for resource management
- No raw pointers for owned memory
- Boost.JSON manages JSON parse tree

### Rcpp Bridge

- Rcpp handles reference counting
- Automatic conversion of C++ exceptions to R errors
- Safe transfer of strings (uses UTF-8)

---

## Error Handling

### Error Categories

1. **JSON Parse Errors**
   - Syntax errors (malformed JSON)
   - Encoding errors (non-UTF-8)
   - **Handled by**: Parser module
   - **Reported as**: R error with line/column number

2. **Validation Errors**
   - Schema violations (missing fields, wrong types)
   - Reference errors (undefined functions/formats)
   - Semantic errors (inconsistent specifications)
   - **Handled by**: Validator module
   - **Reported as**: R error with JSON path and suggestion

3. **Compilation Errors**
   - Code generation failures
   - Unsupported DSL features
   - **Handled by**: Code generation modules
   - **Reported as**: R error with context

4. **Runtime Errors**
   - Calculation function errors
   - Data errors (missing variables, type mismatches)
   - **Handled by**: Generated code (try-catch)
   - **Reported as**: R error with stack trace

### Error Reporting Strategy

**Principle**: Fail fast, provide context, suggest fixes

**Example Error Message**:

```text
Error in kst_compile():
  Validation failed at /table_spec/statistics/n/fun:
    Function 'count' is not registered.
    
  Suggestion: Register the function using:
    kst_register_calc("count", function(data) length(data))
    
  Or ensure the function name matches exactly (case-sensitive).
```

---

## Performance Considerations

### Compilation Performance

**Target**: < 1 second for simple tables, < 10 seconds for complex

**Optimization Strategies**:

1. **Parser**: Use Boost.JSON (fast C++ parser)
2. **AST Building**: Use move semantics, avoid copies
3. **Optimization**: Limit passes, use efficient data structures
4. **Code Generation**: String building with fmt library (fast)

### Runtime Performance

**Target**: Generated code should be as efficient as hand-written dplyr

**Optimization Strategies**:

1. **Query Plan**: Optimize operation order (filter early, etc.)
2. **Operation Fusion**: Combine operations to reduce passes
3. **Memory**: Avoid unnecessary copies in generated code
4. **Vectorization**: Use vectorized R operations

### Memory Usage

**Target**: < 100 MB peak for typical tables

**Strategies**:

1. **Metadata**: Don't load full data, only distinct values
2. **AST**: Share subtrees with std::shared_ptr
3. **Generated Code**: Stream output, don't build entire string in memory
4. **R Execution**: Let R manage data frame memory

---

## Testing Strategy

### Unit Tests

**C++ Tests** (Catch2):

- Parser: JSON parsing, edge cases
- Validator: Schema validation, error messages
- Code Generation: AST → R code correctness
- Optimizer: Optimization passes preserve semantics

**R Tests** (testthat):

- Public API: All exported functions
- Metadata extraction: ksformat integration, factor levels
- Function registry: Registration, lookup
- Integration: End-to-end compilation

### Integration Tests

**Test Cases**:

- Simple demographics table
- 2-way stratification
- Hierarchical table (AE)
- Efficacy table (change from baseline)
- Lab shift table
- Listing

**Verification**:

- Generated code is valid R
- Generated code produces expected output
- Output structure matches specification
- All values are formatted strings
- ksTFL integration works

### Performance Tests

**Benchmarks**:

- Compilation time for various table sizes
- Memory usage during compilation
- Execution time of generated code
- Comparison with hand-written dplyr code

---

## Build System

### R Package Build

**Tools**: standard R package tools, devtools, Rcpp

**Process**:

1. Rcpp compiles C++ code
2. Generates RcppExports.R and RcppExports.cpp
3. Links against Boost libraries
4. Creates package binary

**Configuration**:

`src/Makevars`:

```makefile
CXX_STD = CXX23
PKG_CXXFLAGS = -I../inst/include
PKG_LIBS = -lboost_json -lfmt
```

`DESCRIPTION`:

```text
SystemRequirements: C++23, Boost (>= 1.80), fmt (>= 10.0)
```

### C++ Dependencies

**Boost.JSON**: Header-only (mostly), link if needed  
**fmt**: Header-only or link library  
**range-v3**: Header-only  

**Installation**:

- Linux: apt/yum package managers
- macOS: Homebrew (`brew install boost fmt`)
- Windows: vcpkg or pre-built binaries

---

## Extension Points

### Custom Code Generators

**Interface**:

```cpp
class CodeGenerator {
public:
    virtual ~CodeGenerator() = default;
    virtual std::string generate(const ASTNode& node) const = 0;
};
```

Users can implement custom generators and register them.

### Custom Format Handlers

**Interface**:

```cpp
class FormatHandler {
public:
    virtual ~FormatHandler() = default;
    virtual std::string generate_format_code(
        const FormatSpec& spec,
        const std::string& value_expr
    ) const = 0;
};
```

Allows custom formatting logic beyond ksformat/sprintf/templates.

### Custom Optimization Passes

**Interface**:

```cpp
class OptimizationPass {
public:
    virtual ~OptimizationPass() = default;
    virtual void optimize(ASTNode& root) const = 0;
};
```

Users can add domain-specific optimizations.

---

## Security Considerations

### Code Injection

**Risk**: JSON DSL contains malicious R code strings

**Mitigation**:

- DSL is declarative, not imperative
- No direct R code execution from JSON
- Function references only (not inline code)
- Function registry is explicit (user provides functions)

### Function Registry

**Risk**: Malicious functions in registry

**Mitigation**:

- User explicitly registers functions
- No automatic discovery of functions
- Functions run in user's R session (same security context)

### File System Access

**Risk**: JSON file path traversal

**Mitigation**:

- JSON content is string, not file paths
- R handles file I/O, not C++ code
- Standard R security applies

---

## Future Enhancements

### Phase 2 Features

- Multi-parameter tables (multiple variables in same table)
- Cross-tabulation support
- Conditional formatting (highlighting, colors)
- Page breaks and continuation headers
- Cell-level annotations (footnote markers)

### Phase 3 Features

- Interactive DSL builder (Shiny app)
- Template library (common table patterns)
- DSL macro system (reusable components)
- Code generation to other backends (data.table, SQL)

### Performance Enhancements

- Compiled code caching (hash-based)
- Lazy evaluation of calculations
- Parallel execution of independent groups
- Streaming for large datasets

---

**Document Version**: 1.0  
**Last Updated**: 2026-07-01
