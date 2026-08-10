# ksTable

**JSON DSL to Dplyr Code Generator for Clinical Tables**

[![License:
MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://crow16384.github.io/ksTable/LICENSE)
[![R: ≥
4.1](https://img.shields.io/badge/R-%E2%89%A5%204.1-blue.svg)](https://www.r-project.org/)
[![R-CMD-check](https://github.com/crow16384/ksTable/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/crow16384/ksTable/actions/workflows/R-CMD-check.yaml)
[![pkgdown](https://github.com/crow16384/ksTable/actions/workflows/pkgdown.yaml/badge.svg)](https://crow16384.github.io/ksTable/)
[![GitHub
issues](https://img.shields.io/github/issues/crow16384/ksTable)](https://github.com/crow16384/ksTable/issues)

> **Status**: Usable v0.2.0 compiler — `parameter_stat` and 2-level
> `hierarchical` layouts

------------------------------------------------------------------------

## Overview

**ksTable** compiles declarative JSON table specifications into plain
dplyr/tidyr R scripts. Evaluating those scripts against a data frame
named `data` produces pre-formatted character tibbles ready for
[ksTFL](https://github.com/crow16384/ksTFL).

**Boundary**: ksTable prepares and formats data; ksTFL renders DOCX;
users supply calc/format functions;
[ksformat](https://github.com/crow16384/ksformat) handles VALUE formats
when needed.

``` text
JSON DSL → kst_validate_spec() / kst_compile() → R script
         → (optional) kst_extract_metadata + kst_apply_metadata on data
         → eval in new.env(parent = ...) with env$data
         → formatted tibble → ksTFL
```

------------------------------------------------------------------------

## What works in v0.1

- `parameter_stat` layout (rows = parameter × statistic; columns =
  groups)
- `hierarchical` layout (parent + one nested child, e.g. SOC → PT; first
  statistic only)
- Format types: default `as.character`, `sprintf`, `custom`, `template`
  (needs **glue**), `ksformat`
- Extra `args` on statistics; `apply_to`; multi-variable parameters;
  multi-way `groups.by`
- `include_missing_levels` via factors + `kst_extract_metadata` /
  `kst_apply_metadata` **before** eval
- SR-1 identifier validation; compile rejects invalid specs
- Demos: demography, laboratory, adverse_events, ksformat_integration

**Not in v0.1** (deferred): listing, shift matrices, nesting depth \> 2,
multi-stat hierarchical, DSL sort options, query-plan optimization.

------------------------------------------------------------------------

## Example

``` json
{
  "schema_version": "1.0",
  "table_spec": {
    "id": "demographics_age",
    "title": "Age by Treatment Group",
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
    "groups": {
      "by": ["TRT01P"],
      "include_missing_levels": true
    },
    "layout": {
      "row_structure": "parameter_stat",
      "column_structure": "groups"
    }
  }
}
```

``` r

library(ksTable)

count   <- function(x) sum(!is.na(x))
mean_sd <- function(x) list(mean = mean(x, na.rm = TRUE), sd = sd(x, na.rm = TRUE))
format_mean_sd <- function(x) sprintf("%.1f (%.2f)", x$mean, x$sd)

adsl <- read.csv("adsl.csv")
# Optional: factor levels / ksformat labels before eval when using
# include_missing_levels or groups.format documentation in the JSON
# meta <- kst_extract_metadata(adsl, "TRT01P", format_map = list(TRT01P = "trt_fmt"))
# adsl <- kst_apply_metadata(adsl, meta)

code <- kst_compile("demographics_age.json")  # validates then compiles
env  <- new.env(parent = environment())
env$data <- adsl
result <- eval(parse(text = code), envir = env)
# Columns: .param, .stat, then one column per group level (character values)
```

------------------------------------------------------------------------

## Public API

| Function | Role |
|----|----|
| `kst_validate_spec(json_spec)` | Schema + SR-1 checks; returns `list(valid, errors, engine)` |
| `kst_compile(json_spec)` | Validate + emit R script (`character(1)`) |
| `kst_save(json_spec, file, overwrite = FALSE)` | Compile and write a reviewable `.R` file |
| `kst_extract_metadata(data, variables, ...)` | Levels / ksformat labels for grouping columns |
| `kst_apply_metadata(data, metadata)` | Apply factors / `fput` **before** eval |

Optional JSON `groups.format` is documentation only: pass the same map
as `format_map` to
[`kst_extract_metadata()`](https://crow16384.github.io/ksTable/reference/kst_extract_metadata.md).
Compile does not apply metadata.

------------------------------------------------------------------------

## Installation

``` r

install.packages(c("dplyr", "tidyr", "jsonlite"))
# ksformat is an Import — install from CRAN or GitHub as available
remotes::install_github("crow16384/ksformat")  # if needed
remotes::install_github("crow16384/ksTable")
```

Optional Suggests: `jsonvalidate` (preferred schema engine), `glue`
(`template` formats).

------------------------------------------------------------------------

## Project structure

``` text
ksTable/
├── R/                 compile.R, compiler.R, validate.R, metadata.R
├── inst/schema/       table_spec_v1.json
├── inst/examples/     sample JSON specs
├── demo/              demography, laboratory, adverse_events, ksformat_integration
├── tests/testthat/
├── vignettes/         getting_started, dsl_reference
├── ARCHITECTURE.md    design (matches current code)
├── DSL_EXAMPLE.md     schema-aligned examples
├── PLAN.md            roadmap / phase status
└── REQUIREMENTS.md    requirements
```

------------------------------------------------------------------------

## Design principles

1.  **Declarative DSL** — describe the table; the generator emits the
    dplyr shape.
2.  **Bare function calls** — `"fun": "count"` → `count(AGE)` resolved
    from the eval env.
3.  **Compile ≠ execute** — review/save scripts; run them in an isolated
    `new.env`.
4.  **Separation of concerns** — ksTable formats; ksTFL lays out; users
    own stats.
5.  **Injection-safe** — every JSON-derived identifier must match
    `^[A-Za-z.][A-Za-z0-9._]*$`.

------------------------------------------------------------------------

## Documentation

Package website: <https://crow16384.github.io/ksTable/>

Locally:
[`pkgdown::build_site()`](https://pkgdown.r-lib.org/reference/build_site.html)
(writes to `docs/`).

Bump / sync the package version (DESCRIPTION → README, NEWS, vignettes,
…):

``` r
Rscript scripts/bump_version.R patch       # or minor / major / 0.2.1
Rscript scripts/bump_version.R --sync-only # re-sync without bumping
```

pkgdown reads `DESCRIPTION` `Version` automatically for the site navbar.

------------------------------------------------------------------------

## License

MIT License — Copyright (c) 2026 [Vladimir
Larchenko](mailto:crow16384@gmail.com)

**Issues**: [GitHub Issues](https://github.com/crow16384/ksTable/issues)

**Last Updated**: 2026-08-10 · **Version**: 0.2.0
