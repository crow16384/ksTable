# ksTable

**JSON DSL to Dplyr Code Generator for Clinical Tables**

[![License: GPL-3](https://img.shields.io/badge/License-GPL%203-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![R: ≥ 4.1](https://img.shields.io/badge/R-%E2%89%A5%204.1-blue.svg)](https://www.r-project.org/)
[![C++: 23](https://img.shields.io/badge/C%2B%2B-23-blue.svg)](https://en.cppreference.com/w/cpp/23)

> **Status**: Planning Phase (v0.1.0-dev)

---

## Overview

**ksTable** is an R package that reads declarative JSON table specifications and uses a C++23 compiler to generate optimized dplyr/tidyr R code. The generated code produces pre-formatted tibbles ready for rendering with the [ksTFL](https://github.com/crow16384/ksTFL) package.

**Key Innovation**: Separate data preparation from rendering. ksTable formats data → ksTFL renders it.

---

## Architecture

```text
User JSON DSL → C++23 Compiler → Generated R Code → Execution → Formatted Tibble → ksTFL
```

**What ksTable Does**:

- Parses declarative JSON table specifications
- Introspects metadata (ksformat, factor levels, distinct values)
- Generates optimized dplyr/tidyr code
- Formats values using ksformat, templates, or custom functions
- Produces tibbles with all values as formatted strings

**What ksTable Does NOT Do** (out of scope):

- DOCX rendering (handled by ksTFL)
- Statistical calculations (user provides these)
- Data validation or cleaning
- GUI or interactive builder

---

## Example

### JSON DSL Specification

```json
{
  "schema_version": "1.0",
  "table_spec": {
    "id": "demographics_age",
    "title": "Age by Treatment Group",
    "parameter": {
      "age": {
        "variable": "AGE",
        "label": "Age (years)"
      }
    },
    "statistics": {
      "n": {"fun": "count", "label": "n"},
      "mean_sd": {"fun": "mean_sd", "label": "Mean (SD)"}
    },
    "groups": {
      "by": ["TRT01P"],
      "include_missing_levels": true
    }
  }
}
```

### R Workflow

```r
library(ksTable)

# Define calculation functions
count <- function(data) length(data)
mean_sd <- function(data) {
  sprintf("%.1f (%.2f)", mean(data, na.rm = TRUE), sd(data, na.rm = TRUE))
}

# Register functions
kst_register_calc("count", count)
kst_register_calc("mean_sd", mean_sd)

# Load data
adsl <- read.csv("adsl.csv")

# Generate table
result <- kst_generate_table(
  json_spec = "demographics_age.json",
  data = adsl,
  calc_functions = list(count = count, mean_sd = mean_sd)
)

# Result: tibble with formatted strings
# PARAM           STATISTIC    Placebo       Drug A        Drug B
# Age (years)     n            160           160           160
# Age (years)     Mean (SD)    45.2 (12.3)   46.1 (11.8)   44.8 (12.9)

# Render with ksTFL
library(ksTFL)
spec <- create_table(result)
report <- create_report(spec)
write_doc(report, "demographics.docx")
```

---

## Features

### Core Capabilities

- ✓ **Declarative DSL**: JSON specifications describe desired output
- ✓ **Metadata-driven**: Introspects ksformat, factor levels, distinct values
- ✓ **User calculations**: Reference R functions for statistical calculations
- ✓ **Multi-way stratification**: Group by multiple variables
- ✓ **Hierarchical tables**: Nested structures (SOC → PT)
- ✓ **Multiple format methods**: ksformat, sprintf templates, custom functions
- ✓ **Query optimization**: C++ compiler optimizes dplyr query plans
- ✓ **ksTFL integration**: Seamless rendering workflow

### Table Types Supported

- Demographics tables (baseline characteristics)
- Adverse events (hierarchical SOC → PT)
- Efficacy tables (change from baseline)
- Laboratory summaries (shift tables)
- Exposure tables
- Listings (subject-level data)

---

## Project Status

**Current Phase**: Planning & Design (v0.1.0-dev)

### Documentation

- [x] Project plan (PLAN.md)
- [x] Requirements specification (REQUIREMENTS.md)
- [x] Architecture design (ARCHITECTURE.md)
- [x] DSL examples (DSL_EXAMPLE.md)
- [ ] Implementation started

### Roadmap

- **Phase 1**: Core DSL schema & parser (2-3 weeks)
- **Phase 2**: Metadata introspection (1-2 weeks)
- **Phase 3**: Code generation engine (3-4 weeks)
- **Phase 4**: Calculation function integration (2-3 weeks)
- **Phase 5**: R package structure (2-3 weeks)
- **Phase 6**: Testing & validation (2-3 weeks)
- **Phase 7**: Documentation & examples (1-2 weeks)

**Target**: v1.0 release in ~8-12 weeks

---

## Dependencies

### R Packages

- **dplyr** (≥ 1.1.0) — Data manipulation in generated code
- **tidyr** (≥ 1.3.0) — Data reshaping (pivoting, nesting)
- **rlang** (≥ 1.1.0) — Tidy evaluation
- **ksformat** (≥ 0.7.0) — Value formatting ([github.com/crow16384/ksformat](https://github.com/crow16384/ksformat))
- **jsonlite** (≥ 1.8.0) — JSON parsing in R
- **Rcpp** (≥ 1.0.12) — C++ integration

### C++ Libraries

- **Boost.JSON** (≥ 1.80) — JSON parsing in C++
- **fmt** (≥ 10.0) — String formatting
- **range-v3** (≥ 0.12) — Modern ranges

### System Requirements

- **R** ≥ 4.6 (for native pipe and modern Rcpp)
- **C++ compiler** with C++23 support (gcc ≥ 13, clang ≥ 17, MSVC ≥ 19.34)

---

## Installation

> **Note**: Package not yet available. This section describes the planned installation process.

### From GitHub (Development Version)

```r
# Install dependencies first
install.packages(c("dplyr", "tidyr", "rlang", "jsonlite", "Rcpp"))
install.packages("ksformat")  # Or install from github.com/crow16384/ksformat

# Install ksTable
remotes::install_github("crow16384/ksTable")
```

### System Dependencies

**Linux (Ubuntu/Debian)**:

```bash
sudo apt-get install libboost-dev libfmt-dev
```

**macOS (Homebrew)**:

```bash
brew install boost fmt
```

**Windows**:

- Use [vcpkg](https://vcpkg.io/) or install pre-built binaries
- Ensure Rtools is installed with C++23 support

---

## Quick Start

> **Note**: This is the planned workflow. Implementation pending.

### 1. Create JSON DSL Specification

```json
{
  "schema_version": "1.0",
  "table_spec": {
    "parameter": {
      "age": {"variable": "AGE"}
    },
    "statistics": {
      "n": {"fun": "count"},
      "mean_sd": {"fun": "mean_sd"}
    },
    "groups": {
      "by": ["TRT"],
      "include_missing_levels": true
    }
  }
}
```

### 2. Define Calculation Functions

```r
count <- function(data) sum(!is.na(data))
mean_sd <- function(data) {
  m <- mean(data, na.rm = TRUE)
  s <- sd(data, na.rm = TRUE)
  sprintf("%.1f (%.2f)", m, s)
}
```

### 3. Generate Table

```r
library(ksTable)

result <- kst_generate_table(
  json_spec = "table_spec.json",
  data = my_data,
  calc_functions = list(
    count = count,
    mean_sd = mean_sd
  )
)
```

### 4. Render with ksTFL

```r
library(ksTFL)
spec <- create_table(result)
write_doc(create_report(spec), "output.docx")
```

---

## Project Structure

```text
ksTable/
├── PLAN.md                  # Development plan (this document links to it)
├── REQUIREMENTS.md          # Requirements specification
├── ARCHITECTURE.md          # System architecture design
├── DSL_EXAMPLE.md           # JSON DSL examples and reference
├── README.md                # This file
├── DESCRIPTION              # R package metadata
├── NAMESPACE                # R exports
├── LICENSE                  # GPL-3 license
├── R/                       # R source files
│   ├── compile.R           # Main compilation API
│   ├── generate.R          # Table generation
│   ├── metadata.R          # Metadata extraction
│   ├── format.R            # Formatting utilities
│   ├── validate.R          # Validation helpers
│   └── registry.R          # Function registration
├── src/                     # C++ source files
│   ├── compiler/           # Compiler components
│   │   ├── parser.cpp
│   │   ├── validator.cpp
│   │   ├── codegen.cpp
│   │   ├── optimizer.cpp
│   │   └── ...
│   ├── rcpp_interface.cpp  # Rcpp bindings
│   └── Makevars            # Build configuration
├── inst/                    # Installed files
│   ├── schema/             # JSON schemas
│   └── examples/           # Example DSL files
├── tests/                   # Tests
│   ├── testthat/           # R tests
│   └── cpp/                # C++ tests
└── vignettes/              # Documentation
    ├── getting_started.Rmd
    ├── dsl_reference.Rmd
    └── kstfl_integration.Rmd
```

---

## Design Principles

### 1. Declarative over Imperative

Users describe **what** they want, not **how** to compute it. The compiler figures out the optimal transformation strategy.

### 2. Metadata-Driven

Generated code adapts to runtime data using ksformat metadata, factor levels, and distinct values.

### 3. Separation of Concerns

- **ksTable**: Data preparation and formatting
- **ksTFL**: Layout and rendering
- Clear interface: formatted tibbles

### 4. User-Provided Calculations

Users know their domain. The package provides the infrastructure, users provide the statistical logic.

### 5. Performance

C++ compiler generates optimized dplyr code. Query plan optimization eliminates redundant operations.

### 6. Extensibility

Support for ksformat, sprintf templates, and custom format functions. Users can extend with custom calculation functions.

---

## References

### Related Projects

- **ksTFL**: Clinical table rendering ([github.com/crow16384/ksTFL](https://github.com/crow16384/ksTFL))
- **ksformat**: SAS-style value formatting ([github.com/crow16384/ksformat](https://github.com/crow16384/ksformat))

### Standards & Specifications

- **CDISC ARS**: Analysis Results Standard ([cdisc-org.github.io/analysis-results-standard](https://cdisc-org.github.io/analysis-results-standard/))
- **LinkML**: Data modeling framework ([linkml.io](https://linkml.io/))

### Research

- **PharmaSUG Japan 2024**: Clinical tables automation ([pharmasug.org/proceedings/japan2024/PharmaSUG-Japan-2024-02.pdf](https://pharmasug.org/proceedings/japan2024/PharmaSUG-Japan-2024-02.pdf))

---

## Contributing

> **Note**: Contribution guidelines will be finalized after initial implementation.

### Development Setup

1. Clone repository
2. Install R package dependencies
3. Install C++ dependencies (Boost, fmt)
4. Build package: `devtools::build()`
5. Run tests: `devtools::test()`

### Code Style

- **R**: Follow tidyverse style guide
- **C++**: Follow C++ Core Guidelines, use modern C++23 features
- **Documentation**: Roxygen2 for R, Doxygen for C++

---

## License

GPL-3.0

Copyright (c) 2026 [Your Name/Organization]

---

## Contact

- **Issues**: [GitHub Issues](https://github.com/crow16384/ksTable/issues)
- **Discussions**: [GitHub Discussions](https://github.com/crow16384/ksTable/discussions)
- **Email**: [your-email@example.com]

---

## Acknowledgments

- Inspired by CDISC Analysis Results Standard (ARS)
- Built on the shoulders of tidyverse (Hadley Wickham et al.)
- Integrates with ksTFL and ksformat packages
- C++ compiler design influenced by LLVM and modern compiler architecture

---

**Last Updated**: 2026-07-01  
**Version**: 0.1.0-dev (Planning Phase)
