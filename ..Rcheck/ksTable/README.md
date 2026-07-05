# ksTable

**JSON DSL to Dplyr Code Generator for Clinical Tables**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![R: ≥ 4.1](https://img.shields.io/badge/R-%E2%89%A5%204.1-blue.svg)](https://www.r-project.org/)
[![GitHub issues](https://img.shields.io/github/issues/crow16384/ksTable)](https://github.com/crow16384/ksTable/issues)

> **Status**: Implementation Phase (v0.1.0-dev)

---

## Overview

**ksTable** is an R package that reads declarative JSON table specifications and uses a pure-R generator to produce dplyr/tidyr R code. The generated code produces pre-formatted tibbles ready for rendering with the [ksTFL](https://github.com/crow16384/ksTFL) package.

**Key Innovation**: Separate data preparation from rendering. ksTable formats data → ksTFL renders it.

---

## Architecture

```text
User JSON DSL → R Generator (compiler.R) → Generated R Code → Execution → Formatted Tibble → ksTFL
```

**What ksTable Does**:

- Parses declarative JSON table specifications
- Introspects metadata (ksformat, factor levels, distinct values)
- Generates pipe-based dplyr/tidyr code (~62 µs per compile call)
- Executes generated code in a clean environment
- Produces tibbles with all values as formatted strings

**What ksTable Does NOT Do** (out of scope):

- DOCX rendering (handled by ksTFL)
- Statistical calculations (user provides these)
- Data validation or cleaning
- Visual formatting / indentation (handled by ksTFL)
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

# Define calculation functions (return raw numeric / named list)
calc_fns <- list(
  count   = function(data) sum(!is.na(data)),
  mean_sd = function(data) list(mean = mean(data, na.rm = TRUE), sd = sd(data, na.rm = TRUE))
)

# Define format functions (convert raw value to display string)
format_fns <- list(
  format_mean_sd = function(x) sprintf("%.1f (%.2f)", x$mean, x$sd)
)

# Load data
adsl <- read.csv("adsl.csv")

# Generate table
result <- kst_generate_table(
  json_spec       = "demographics_age.json",
  data            = adsl,
  calc_functions  = calc_fns,
  format_functions = format_fns
)

# Result: tibble with formatted strings
# .param      .stat_label  Placebo       Drug A        Drug B
# Age (years) n            160           160           160
# Age (years) Mean (SD)    45.2 (12.3)   46.1 (11.8)   44.8 (12.9)

# Render with ksTFL
library(ksTFL)
spec   <- create_table(result)
report <- create_report(spec)
write_doc(report, "demographics.docx")
```

---

## Features

### Core Capabilities

- ✓ **Declarative DSL**: JSON specifications describe desired output
- ✓ **Metadata-driven**: Introspects ksformat, factor levels, distinct values
- ✓ **User calculations**: define `calc` and `format` functions in your environment — no lists, no registry
- ✓ **Multi-way stratification**: Group by multiple variables
- ✓ **Hierarchical tables**: Nested structures (SOC → PT)
- ✓ **Multiple format methods**: `sprintf`, `template`, `custom`, `ksformat`
- ✓ **Injection-safe**: All JSON identifiers validated before code emission (SR-1)
- ✓ **Fast compilation**: ~62 µs per call; pure R, no compiled code
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

- **Phase 1**: JSON schema + R validator (1 week)
- **Phase 2**: R code generator (2 weeks)
- **Phase 3**: Metadata extraction (1 week)
- **Phase 4**: Format step codegen (1 week)
- **Phase 5**: R package structure (1 week)
- **Phase 6**: Testing & validation (1–2 weeks)
- **Phase 7**: Documentation & examples (1 week)

**Target**: v1.0 release in ~8 weeks

---

## Dependencies

### R Packages

- **dplyr** (≥ 1.1.0) — Data manipulation in generated code
- **tidyr** (≥ 1.3.0) — Data reshaping (pivoting)
- **rlang** (≥ 1.1.0) — Tidy evaluation
- **ksformat** (≥ 0.7.0) — Value formatting ([github.com/crow16384/ksformat](https://github.com/crow16384/ksformat))
- **jsonlite** (≥ 1.8.0) — JSON parsing

### System Requirements

- **R** ≥ 4.1.0 (for native pipe `|>`)
- No C++ compiler required
- No system libraries required

---

## Installation

> **Note**: Package not yet available. This section describes the planned installation process.

### From GitHub (Development Version)

```r
# Install dependencies first
install.packages(c("dplyr", "tidyr", "rlang", "jsonlite"))
install.packages("ksformat")  # Or install from github.com/crow16384/ksformat

# Install ksTable
remotes::install_github("crow16384/ksTable")
```

> No C++ compiler or system libraries required.

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

### 2. Define Calc and Format Functions

```r
# calc functions: return raw numeric values or named lists
count   <- function(data) sum(!is.na(data))
mean_sd <- function(data) list(mean = mean(data, na.rm = TRUE),
                                sd   = sd(data,   na.rm = TRUE))

# format functions: convert raw value to display string
format_mean_sd <- function(x) sprintf("%.1f (%.2f)", x$mean, x$sd)
```

### 3. Generate Table

```r
library(ksTable)

result <- kst_generate_table(
  json_spec = "table_spec.json",
  data      = my_data
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
├── PLAN.md                  # Development plan
├── REQUIREMENTS.md          # Requirements specification
├── ARCHITECTURE.md          # System architecture
├── DSL_EXAMPLE.md           # JSON DSL examples and reference
├── README.md                # This file
├── DESCRIPTION              # R package metadata
├── NAMESPACE                # R exports
├── LICENSE                  # GPL-3 license
├── R/
│   ├── compile.R            # kst_compile() + kst_generate_table()
│   ├── compiler.R           # R code generator internals
│   ├── validate.R           # kst_validate_spec()
│   ├── metadata.R           # kst_extract_metadata()
│   └── format_helpers.R     # Optional format helpers
├── inst/
│   ├── schema/              # JSON schemas
│   └── examples/            # Example DSL files
├── tests/
│   └── testthat/            # R tests
└── vignettes/
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

Pure-R generator produces pipe-based dplyr code. Measured compile time: ~62 µs per call.

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
2. Install R package dependencies: `install.packages(c("dplyr", "tidyr", "rlang", "jsonlite", "ksformat"))`
3. Build package: `devtools::build()`
4. Run tests: `devtools::test()`

### Code Style

- **R**: Follow tidyverse style guide
- **Documentation**: Roxygen2

---

## License

MIT License — Copyright (c) 2026 [Vladimir Larchenko](mailto:crow16384@gmail.com)

---

## Contact

- **Issues**: [GitHub Issues](https://github.com/crow16384/ksTable/issues)
- **Discussions**: [GitHub Discussions](https://github.com/crow16384/ksTable/discussions)
- **Author**: [Vladimir Larchenko](mailto:crow16384@gmail.com)

---

## Acknowledgments

- Inspired by CDISC Analysis Results Standard (ARS)
- Built on the shoulders of tidyverse (Hadley Wickham et al.)
- Integrates with ksTFL and ksformat packages

---

**Last Updated**: 2026-07-05  
**Version**: 0.1.0-dev (Implementation Phase)  
**Author**: [Vladimir Larchenko](mailto:crow16384@gmail.com)
