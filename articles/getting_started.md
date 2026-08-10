# Getting Started with ksTable

*Package version 0.2.0.*

![ksTable logo](figures/logo.png)

## Overview

**ksTable** reads a declarative JSON table specification and generates a
plain, human-readable dplyr/tidyr R script. Running that script against
your data produces a formatted tibble ready for rendering with
[ksTFL](https://github.com/crow16384/ksTFL).

    JSON spec  →  kst_compile()  →  R script  →  eval()  →  tibble  →  ksTFL

Key design principles:

- **Declarative**: describe *what* you want, not how to compute it.
- **Plain-R output**: the generated script is ordinary dplyr — paste it
  into the console, step through it, save it to a file.
- **No infrastructure**: calc and format functions are resolved from
  your environment just like any other R function call.
- **Isolated execution**: intermediate objects (`.raw`, `.long`) stay in
  a private environment and never pollute your workspace.

------------------------------------------------------------------------

## Installation

``` r

remotes::install_github("crow16384/ksTable")
```

``` r

library(ksTable)
```

------------------------------------------------------------------------

## Function contracts

ksTable uses two distinct function types, both defined by the user in
their own environment.

### Calc functions

Referenced by the `"fun"` field in a statistic. Receive a **column
vector** (one group’s data) as the first argument; return a raw
**numeric** or **named list**. *No string formatting here.*

When the statistic declares `"denominator"`, the compiler also passes a
scalar `denom = ...` for the current group (see [Percentages with
denominators](#percentages-with-denominators)).

``` r

count   <- function(data) sum(!is.na(data))          # → integer

mean_sd <- function(data) list(                       # → named list
  mean = mean(data, na.rm = TRUE),
  sd   = sd(data,   na.rm = TRUE)
)

count_n <- function(data) length(data)               # → integer

# Used with statistics.*.denominator (compiler supplies denom=)
count_pct <- function(x, denom, ...) {
  n <- sum(!is.na(x))
  list(
    n   = n,
    pct = if (length(denom) == 1L && isTRUE(denom > 0)) 100 * n / denom
          else NA_real_
  )
}
```

### Format functions

Referenced by `"format": { "type": "custom", "fun": "..." }`. Receive
the raw value from the corresponding calc function, return a single
**character** string. Format is applied **only** when `"format"` is
present in the JSON; otherwise the raw type is kept.

``` r

format_mean_sd <- function(x) sprintf("%.1f (%.2f)", x$mean, x$sd)
```

Built-in R functions (`median`, `sum`, `mean`, …) can be used directly
as calc functions. Extra **literal** arguments — such as `na.rm = TRUE`
— go in the optional `"args"` field. Use `"denominator"` (not `"args"`)
to wire a group-resolved `denom`.

------------------------------------------------------------------------

## Example 1: Demographics table

### Synthetic data

``` r

set.seed(42)
n <- 480L

adsl <- data.frame(
  USUBJID = sprintf("%03d-%04d", rep(1:3, each = n %/% 3L), seq_len(n)),
  AGE     = round(rnorm(n, 45, 12)),
  SEX     = sample(c("M", "F"), n, replace = TRUE),
  TRT01P  = rep(c("Placebo", "Drug A", "Drug B"), each = n %/% 3L),
  stringsAsFactors = FALSE
)
```

### JSON spec

Three statistics are requested:

- **n** — a user-defined `count()` function.
- **mean_sd** — a user-defined `mean_sd()` returning a named list,
  formatted by a user-defined `format_mean_sd()`.
- **median** — the built-in
  [`median()`](https://rdrr.io/r/stats/median.html) with `na.rm = TRUE`
  supplied via `"args"`.

``` r

demog_spec <- '{
  "schema_version": "1.0",
  "table_spec": {
    "id": "demographics_age",
    "title": "Age by Treatment Group",
    "parameter": {
      "age": { "variable": "AGE", "label": "Age (years)" }
    },
    "statistics": {
      "n": {
        "fun":   "count",
        "format": { "type": "sprintf", "pattern": "%d" }
      },
      "mean_sd": {
        "fun":    "mean_sd",
        "format": { "type": "custom", "fun": "format_mean_sd" }
      },
      "median": {
        "fun":   "median",
        "args":  { "na.rm": true },
        "format": { "type": "sprintf", "pattern": "%.1f" }
      }
    },
    "groups": {
      "by": ["TRT01P"],
      "include_missing_levels": false
    },
    "layout": {
      "row_structure":    "parameter_stat",
      "column_structure": "groups"
    }
  }
}'
```

### Inspect the generated script

[`kst_compile()`](https://crow16384.github.io/ksTable/reference/kst_compile.md)
returns a character string you can read before running it:

``` r

code <- kst_compile(demog_spec)
cat(code)
#> .raw <- data |>
#>   dplyr::group_by(TRT01P) |>
#>   dplyr::summarize(
#>     .c1 = count(AGE),
#>     .c2 = list(mean_sd(AGE)),
#>     .c3 = median(AGE, na.rm = TRUE),
#>     .groups = "drop"
#>   )
#> 
#> .long <- .raw |>
#>   dplyr::mutate(
#>     TRT01P = TRT01P,
#>     .c1 = sprintf("%d", .c1),
#>     .c2 = vapply(.c2, format_mean_sd, character(1L)),
#>     .c3 = sprintf("%.1f", .c3),
#>     .keep = "none"
#>   ) |>
#>   tidyr::pivot_longer(
#>     cols = c(.c1, .c2, .c3),
#>     names_to = ".cid",
#>     values_to = ".value"
#>   ) |>
#>   dplyr::mutate(
#>     .param = unname(c(".c1" = "Age (years)", ".c2" = "Age (years)", ".c3" = "Age (years)")[.cid]),
#>     .stat  = unname(c(".c1" = "n", ".c2" = "mean_sd", ".c3" = "median")[.cid]),
#>     .cid = NULL
#>   )
#> 
#> tidyr::pivot_wider(
#>   .long,
#>   id_cols     = c(.param, .stat),
#>   names_from  = c(TRT01P),
#>   values_from = .value
#> )
```

### Generate the table

``` r

code <- kst_compile(demog_spec)
env <- new.env(parent = environment())
env$data <- adsl
result <- eval(parse(text = code), envir = env)
print(result)
#> # A tibble: 3 × 5
#>   .param      .stat   `Drug A`     `Drug B`     Placebo     
#>   <chr>       <chr>   <chr>        <chr>        <chr>       
#> 1 Age (years) n       160          160          160         
#> 2 Age (years) mean_sd 44.9 (11.37) 44.9 (11.84) 44.5 (11.96)
#> 3 Age (years) median  45.0         44.5         44.0
```

------------------------------------------------------------------------

## Example 2: Adverse events table (hierarchical)

The `hierarchical` row structure produces parent rows (SOC) with child
rows (PT) nested beneath them.

### Additional data

``` r

set.seed(7)
n_ae   <- 300L
ae_ids <- sample(adsl$USUBJID, n_ae, replace = TRUE)
ae_soc <- sample(c("Cardiac disorders", "Gastrointestinal disorders"),
                 n_ae, replace = TRUE, prob = c(0.4, 0.6))
ae_pt  <- ifelse(
  ae_soc == "Cardiac disorders",
  sample(c("Myocardial infarction", "Angina pectoris"), n_ae, replace = TRUE),
  sample(c("Nausea", "Diarrhea"), n_ae, replace = TRUE)
)
ae <- data.frame(
  USUBJID = ae_ids,
  TRT01P  = adsl$TRT01P[match(ae_ids, adsl$USUBJID)],
  AESOC   = ae_soc,
  AEDECOD = ae_pt,
  stringsAsFactors = FALSE
)
```

### JSON spec

``` r

ae_spec <- '{
  "schema_version": "1.0",
  "table_spec": {
    "id": "adverse_events",
    "title": "Adverse Events by SOC and PT",
    "parameter": {
      "soc": {
        "variable": "AESOC",
        "label":    "",
        "nested": {
          "pt": { "variable": "AEDECOD" }
        }
      }
    },
    "statistics": {
      "n": {
        "fun":   "length",
        "args":  {}
      }
    },
    "groups": {
      "by": ["TRT01P"],
      "include_missing_levels": false
    },
    "layout": {
      "row_structure":    "hierarchical",
      "column_structure": "groups"
    }
  }
}'
```

### Generate the table

``` r

ae_code <- kst_compile(ae_spec)
ae_env <- new.env(parent = environment())
ae_env$data <- ae
ae_result <- eval(parse(text = ae_code), envir = ae_env)
print(ae_result)
#> # A tibble: 6 × 7
#>   .parent                   .is_child .row_label .stat `Drug A` `Drug B` Placebo
#>   <chr>                     <lgl>     <chr>      <chr>    <int>    <int>   <int>
#> 1 Cardiac disorders         FALSE     Cardiac d… n           36       39      34
#> 2 Cardiac disorders         TRUE      Angina pe… n           14       21      21
#> 3 Cardiac disorders         TRUE      Myocardia… n           22       18      13
#> 4 Gastrointestinal disorde… FALSE     Gastroint… n           73       64      54
#> 5 Gastrointestinal disorde… TRUE      Diarrhea   n           39       31      35
#> 6 Gastrointestinal disorde… TRUE      Nausea     n           34       33      19
```

The `.parent` and `.is_child` columns identify the hierarchy; `ksTFL`
will use them to apply indentation and header formatting during
rendering.

------------------------------------------------------------------------

## Percentages with denominators

Percentages are a **hybrid** contract: the JSON declares *how* to
resolve `denom`, and your calc function still computes `n` / `pct` (and
formatting via `"format"`).

| `denominator.type` | Meaning | Emitted `denom =` |
|----|----|----|
| `n` | Rows in the current `groups.by` cell | [`dplyr::n()`](https://dplyr.tidyverse.org/reference/context.html) |
| `n_distinct` | Distinct values of a column in the cell | `dplyr::n_distinct(<variable>)` |
| `data_n` | Aggregate analysis `data` over a **subset** of `groups.by` | `dplyr::first(.kst_dK)` after pre-agg + join |
| `external` | Population / big-N from the eval environment | join + `first(.kst_dK)`, or bare scalar `name` |

``` r

# Round pct for readable template output
count_pct <- function(x, denom, ...) {
  n <- sum(!is.na(x))
  pct <- if (length(denom) == 1L && isTRUE(denom > 0)) 100 * n / denom else NA_real_
  list(n = n, pct = round(pct, 1))
}

run_denom <- function(spec, data, extras = list()) {
  code <- kst_compile(spec)
  env  <- new.env(parent = environment())
  env$data <- data
  for (nm in names(extras)) env[[nm]] <- extras[[nm]]
  eval(parse(text = code), envir = env)
}
```

### 1. `external` — population N (keyed tibble)

Build a population table and bind it under `"name"`:

``` r

adsl_n <- dplyr::count(adsl, TRT01P, name = "N")
adsl_n
#>    TRT01P   N
#> 1  Drug A 160
#> 2  Drug B 160
#> 3 Placebo 160

ext_keyed_spec <- '{
  "schema_version": "1.0",
  "table_spec": {
    "parameter": {
      "age": { "variable": "AGE", "label": "Age (years)" }
    },
    "statistics": {
      "n_pct": {
        "fun": "count_pct",
        "denominator": {
          "type": "external",
          "name": "adsl_n",
          "value": "N",
          "by": ["TRT01P"]
        },
        "format": { "type": "template", "pattern": "{n} ({pct}%)" }
      }
    },
    "groups": { "by": ["TRT01P"] },
    "layout": { "row_structure": "parameter_stat" }
  }
}'

cat(kst_compile(ext_keyed_spec))
#> .kst_d1 <- adsl_n |>
#>   dplyr::select(TRT01P, N) |>
#>   dplyr::rename(.kst_d1 = N)
#> 
#> .raw <- data |>
#>   dplyr::left_join(.kst_d1, by = c("TRT01P")) |>
#>   dplyr::group_by(TRT01P) |>
#>   dplyr::summarize(
#>     .c1 = list(count_pct(AGE, denom = dplyr::first(.kst_d1))),
#>     .groups = "drop"
#>   )
#> 
#> .long <- .raw |>
#>   dplyr::mutate(
#>     TRT01P = TRT01P,
#>     .c1 = vapply(.c1, function(.x) glue::glue_data(.x, "{n} ({pct}%)"), character(1L)),
#>     .keep = "none"
#>   ) |>
#>   tidyr::pivot_longer(
#>     cols = c(.c1),
#>     names_to = ".cid",
#>     values_to = ".value"
#>   ) |>
#>   dplyr::mutate(
#>     .param = unname(c(".c1" = "Age (years)")[.cid]),
#>     .stat  = unname(c(".c1" = "n_pct")[.cid]),
#>     .cid = NULL
#>   )
#> 
#> tidyr::pivot_wider(
#>   .long,
#>   id_cols     = c(.param, .stat),
#>   names_from  = c(TRT01P),
#>   values_from = .value
#> )
run_denom(ext_keyed_spec, adsl, list(adsl_n = adsl_n))
#> # A tibble: 1 × 5
#>   .param      .stat `Drug A`   `Drug B`   Placebo   
#>   <chr>       <chr> <chr>      <chr>      <chr>     
#> 1 Age (years) n_pct 160 (100%) 160 (100%) 160 (100%)
```

### 2. `external` — scalar big-N

Omit `"by"` / `"value"` when the denominator is a single number in the
eval env:

``` r

N_total <- nrow(adsl)

ext_scalar_spec <- '{
  "schema_version": "1.0",
  "table_spec": {
    "parameter": {
      "age": { "variable": "AGE", "label": "Age (years)" }
    },
    "statistics": {
      "n_pct": {
        "fun": "count_pct",
        "denominator": { "type": "external", "name": "N_total" },
        "format": { "type": "template", "pattern": "{n} ({pct}%)" }
      }
    },
    "groups": { "by": ["TRT01P"] },
    "layout": { "row_structure": "parameter_stat" }
  }
}'

cat(kst_compile(ext_scalar_spec))
#> .raw <- data |>
#>   dplyr::group_by(TRT01P) |>
#>   dplyr::summarize(
#>     .c1 = list(count_pct(AGE, denom = N_total)),
#>     .groups = "drop"
#>   )
#> 
#> .long <- .raw |>
#>   dplyr::mutate(
#>     TRT01P = TRT01P,
#>     .c1 = vapply(.c1, function(.x) glue::glue_data(.x, "{n} ({pct}%)"), character(1L)),
#>     .keep = "none"
#>   ) |>
#>   tidyr::pivot_longer(
#>     cols = c(.c1),
#>     names_to = ".cid",
#>     values_to = ".value"
#>   ) |>
#>   dplyr::mutate(
#>     .param = unname(c(".c1" = "Age (years)")[.cid]),
#>     .stat  = unname(c(".c1" = "n_pct")[.cid]),
#>     .cid = NULL
#>   )
#> 
#> tidyr::pivot_wider(
#>   .long,
#>   id_cols     = c(.param, .stat),
#>   names_from  = c(TRT01P),
#>   values_from = .value
#> )
run_denom(ext_scalar_spec, adsl, list(N_total = N_total))
#> # A tibble: 1 × 5
#>   .param      .stat `Drug A`    `Drug B`    Placebo    
#>   <chr>       <chr> <chr>       <chr>       <chr>      
#> 1 Age (years) n_pct 160 (33.3%) 160 (33.3%) 160 (33.3%)
```

### 3. `n` — within-cell row count

`denom = dplyr::n()` for the current `groups.by` cell (no prep / join):

``` r

n_spec <- '{
  "schema_version": "1.0",
  "table_spec": {
    "parameter": {
      "age": { "variable": "AGE", "label": "Age (years)" }
    },
    "statistics": {
      "n_pct": {
        "fun": "count_pct",
        "denominator": { "type": "n" },
        "format": { "type": "template", "pattern": "{n} ({pct}%)" }
      }
    },
    "groups": { "by": ["TRT01P"] },
    "layout": { "row_structure": "parameter_stat" }
  }
}'

cat(kst_compile(n_spec))
#> .raw <- data |>
#>   dplyr::group_by(TRT01P) |>
#>   dplyr::summarize(
#>     .c1 = list(count_pct(AGE, denom = dplyr::n())),
#>     .groups = "drop"
#>   )
#> 
#> .long <- .raw |>
#>   dplyr::mutate(
#>     TRT01P = TRT01P,
#>     .c1 = vapply(.c1, function(.x) glue::glue_data(.x, "{n} ({pct}%)"), character(1L)),
#>     .keep = "none"
#>   ) |>
#>   tidyr::pivot_longer(
#>     cols = c(.c1),
#>     names_to = ".cid",
#>     values_to = ".value"
#>   ) |>
#>   dplyr::mutate(
#>     .param = unname(c(".c1" = "Age (years)")[.cid]),
#>     .stat  = unname(c(".c1" = "n_pct")[.cid]),
#>     .cid = NULL
#>   )
#> 
#> tidyr::pivot_wider(
#>   .long,
#>   id_cols     = c(.param, .stat),
#>   names_from  = c(TRT01P),
#>   values_from = .value
#> )
run_denom(n_spec, adsl)
#> # A tibble: 1 × 5
#>   .param      .stat `Drug A`   `Drug B`   Placebo   
#>   <chr>       <chr> <chr>      <chr>      <chr>     
#> 1 Age (years) n_pct 160 (100%) 160 (100%) 160 (100%)
```

### 4. `n_distinct` — distinct values in the cell

Useful when analysis data can have multiple rows per subject (e.g. AE
records). Here each ADSL row is one subject, so `n` and
`n_distinct(USUBJID)` match:

``` r

nd_spec <- '{
  "schema_version": "1.0",
  "table_spec": {
    "parameter": {
      "age": { "variable": "AGE", "label": "Age (years)" }
    },
    "statistics": {
      "n_pct": {
        "fun": "count_pct",
        "denominator": {
          "type": "n_distinct",
          "variable": "USUBJID"
        },
        "format": { "type": "template", "pattern": "{n} ({pct}%)" }
      }
    },
    "groups": { "by": ["TRT01P"] },
    "layout": { "row_structure": "parameter_stat" }
  }
}'

cat(kst_compile(nd_spec))
#> .raw <- data |>
#>   dplyr::group_by(TRT01P) |>
#>   dplyr::summarize(
#>     .c1 = list(count_pct(AGE, denom = dplyr::n_distinct(USUBJID))),
#>     .groups = "drop"
#>   )
#> 
#> .long <- .raw |>
#>   dplyr::mutate(
#>     TRT01P = TRT01P,
#>     .c1 = vapply(.c1, function(.x) glue::glue_data(.x, "{n} ({pct}%)"), character(1L)),
#>     .keep = "none"
#>   ) |>
#>   tidyr::pivot_longer(
#>     cols = c(.c1),
#>     names_to = ".cid",
#>     values_to = ".value"
#>   ) |>
#>   dplyr::mutate(
#>     .param = unname(c(".c1" = "Age (years)")[.cid]),
#>     .stat  = unname(c(".c1" = "n_pct")[.cid]),
#>     .cid = NULL
#>   )
#> 
#> tidyr::pivot_wider(
#>   .long,
#>   id_cols     = c(.param, .stat),
#>   names_from  = c(TRT01P),
#>   values_from = .value
#> )
run_denom(nd_spec, adsl)
#> # A tibble: 1 × 5
#>   .param      .stat `Drug A`   `Drug B`   Placebo   
#>   <chr>       <chr> <chr>      <chr>      <chr>     
#> 1 Age (years) n_pct 160 (100%) 160 (100%) 160 (100%)
```

On AE data, the same kind denominates event counts by distinct subjects
in the cell:

``` r

nd_ae_spec <- '{
  "schema_version": "1.0",
  "table_spec": {
    "parameter": {
      "pt": { "variable": "AEDECOD", "label": "Preferred Term" }
    },
    "statistics": {
      "n_pct": {
        "fun": "count_pct",
        "denominator": {
          "type": "n_distinct",
          "variable": "USUBJID"
        },
        "format": { "type": "template", "pattern": "{n} ({pct}%)" }
      }
    },
    "groups": { "by": ["TRT01P"] },
    "layout": { "row_structure": "parameter_stat" }
  }
}'

run_denom(nd_ae_spec, ae)
#> # A tibble: 1 × 5
#>   .param         .stat `Drug A`     `Drug B`     Placebo    
#>   <chr>          <chr> <chr>        <chr>        <chr>      
#> 1 Preferred Term n_pct 109 (136.2%) 103 (135.5%) 88 (125.7%)
```

### 5. `data_n` — subset of `groups.by`

When columns are `TRT01P × SEX`, take the denominator over **TRT only**
(ignore SEX). Optional `"distinct"` uses `n_distinct`; omit it for row
count.

``` r

data_n_spec <- '{
  "schema_version": "1.0",
  "table_spec": {
    "parameter": {
      "age": { "variable": "AGE", "label": "Age (years)" }
    },
    "statistics": {
      "n_pct": {
        "fun": "count_pct",
        "denominator": {
          "type": "data_n",
          "by": ["TRT01P"],
          "distinct": "USUBJID"
        },
        "format": { "type": "template", "pattern": "{n} ({pct}%)" }
      }
    },
    "groups": { "by": ["TRT01P", "SEX"] },
    "layout": { "row_structure": "parameter_stat" }
  }
}'

cat(kst_compile(data_n_spec))
#> .kst_d1 <- data |>
#>   dplyr::group_by(TRT01P) |>
#>   dplyr::summarize(.kst_d1 = dplyr::n_distinct(USUBJID), .groups = "drop")
#> 
#> .raw <- data |>
#>   dplyr::left_join(.kst_d1, by = c("TRT01P")) |>
#>   dplyr::group_by(TRT01P, SEX) |>
#>   dplyr::summarize(
#>     .c1 = list(count_pct(AGE, denom = dplyr::first(.kst_d1))),
#>     .groups = "drop"
#>   )
#> 
#> .long <- .raw |>
#>   dplyr::mutate(
#>     TRT01P = TRT01P,
#>     SEX = SEX,
#>     .c1 = vapply(.c1, function(.x) glue::glue_data(.x, "{n} ({pct}%)"), character(1L)),
#>     .keep = "none"
#>   ) |>
#>   tidyr::pivot_longer(
#>     cols = c(.c1),
#>     names_to = ".cid",
#>     values_to = ".value"
#>   ) |>
#>   dplyr::mutate(
#>     .param = unname(c(".c1" = "Age (years)")[.cid]),
#>     .stat  = unname(c(".c1" = "n_pct")[.cid]),
#>     .cid = NULL
#>   )
#> 
#> tidyr::pivot_wider(
#>   .long,
#>   id_cols     = c(.param, .stat),
#>   names_from  = c(TRT01P, SEX),
#>   values_from = .value
#> )
run_denom(data_n_spec, adsl)
#> # A tibble: 1 × 8
#>   .param   .stat `Drug A_F` `Drug A_M` `Drug B_F` `Drug B_M` Placebo_F Placebo_M
#>   <chr>    <chr> <chr>      <chr>      <chr>      <chr>      <chr>     <chr>    
#> 1 Age (ye… n_pct 85 (53.1%) 75 (46.9%) 70 (43.8%) 90 (56.2%) 80 (50%)  80 (50%)
```

Rules that apply to every kind:

- `data_n.by` / `external.by` must be a subset of `groups.by`.
- `external` with `by` requires `value` (N column name).
- Do not set both `denominator` and `args.denom`.
- Identical denom specs are deduplicated to one prep table / join.
- The same `denominator` field works on hierarchical statistics.

See
[`vignette("dsl_reference")`](https://crow16384.github.io/ksTable/articles/dsl_reference.md)
for the field schema.

------------------------------------------------------------------------

## Step-through debugging

Run the compiled script in `new.env(parent = environment())`. For
interactive debugging, set up the environment manually and inspect
intermediate objects:

``` r

code <- kst_compile(demog_spec)

env       <- new.env(parent = environment())   # calc/format functions visible via parent
env$data  <- adsl

# Run the whole script at once
result <- eval(parse(text = code), envir = env)

# Or paste individual lines into the console to step through the pipeline:
#   eval(parse(text = ".raw <- data |> ..."), envir = env)
#   env$.raw

# Intermediates for parameter_stat: .raw, .long, data
# (hierarchical uses .chunks instead of a single .raw)
ls(env, all.names = TRUE)
#> [1] ".long" ".raw"  "data"

env$.long   # long-format table before pivoting
#> # A tibble: 9 × 4
#>   TRT01P  .value       .param      .stat  
#>   <chr>   <chr>        <chr>       <chr>  
#> 1 Drug A  160          Age (years) n      
#> 2 Drug A  44.9 (11.37) Age (years) mean_sd
#> 3 Drug A  45.0         Age (years) median 
#> 4 Drug B  160          Age (years) n      
#> 5 Drug B  44.9 (11.84) Age (years) mean_sd
#> 6 Drug B  44.5         Age (years) median 
#> 7 Placebo 160          Age (years) n      
#> 8 Placebo 44.5 (11.96) Age (years) mean_sd
#> 9 Placebo 44.0         Age (years) median
```

------------------------------------------------------------------------

## Using built-in R functions

Any function available in the calling environment can be used as a calc
function. Pass extra arguments via `"args"` in the JSON spec:

``` json
"statistics": {
  "n":      { "fun": "sum",      "args": { "na.rm": true  } },
  "median": { "fun": "median",   "args": { "na.rm": true  } },
  "q25":    { "fun": "quantile", "args": { "probs": 0.25, "na.rm": true } },
  "sd":     { "fun": "sd",       "args": { "na.rm": true  } }
}
```

Generated code (for `median`):

``` r

.value_raw = median(AGE, na.rm = TRUE)
```

`"args"` values are converted to R literals:

| JSON type        | R literal               |
|------------------|-------------------------|
| `true` / `false` | `TRUE` / `FALSE`        |
| `null`           | `NULL`                  |
| number           | numeric literal         |
| string           | double-quoted character |

------------------------------------------------------------------------

## Validation

[`kst_validate_spec()`](https://crow16384.github.io/ksTable/reference/kst_validate_spec.md)
checks the spec without generating any code. It is useful for early
feedback and for testing JSON produced by tooling or users.

``` r

result <- kst_validate_spec(demog_spec)
result$valid    # TRUE
#> [1] TRUE
result$errors   # character(0)
#> character(0)
```

``` r

bad_spec <- '{"schema_version":"1.0","table_spec":{"parameter":{},
               "statistics":{},"groups":{"by":["TRT"]},"layout":{}}}'
result <- kst_validate_spec(bad_spec)
result$valid
#> [1] FALSE
# [1] FALSE
result$errors
#> [1] "/table_spec/parameter: must NOT have fewer than 1 items"        
#> [2] "/table_spec/statistics: must NOT have fewer than 1 items"       
#> [3] "/table_spec/layout: must have required property 'row_structure'"
# [1] "Missing required field: /table_spec/layout/row_structure"
```

Injection attempts are rejected at the identifier level (SR-1):

``` r

inject <- '{"schema_version":"1.0","table_spec":{"parameter":{
              "p":{"variable":"AGE); system(\\"rm -rf /\\""}},
              "statistics":{"n":{"fun":"count"}},"groups":{"by":["TRT"]},
              "layout":{"row_structure":"parameter_stat"}}}'
result <- kst_validate_spec(inject)
result$valid
#> [1] FALSE
# [1] FALSE
result$errors
#> [1] "/table_spec/parameter/p/variable: must match pattern \"^[A-Za-z.][A-Za-z0-9._]*$\""   
#> [2] "'AGE); system(\"rm -rf /\"' is not a valid R identifier (field: parameter.p.variable)"
# [1] "'AGE); system(\"rm -rf /\"' is not a valid R identifier ..."
```

------------------------------------------------------------------------

## Performance

Compilation is ~130–150 µs per call (pure R string assembly). At that
rate, compiling is negligible overhead even in loops or Shiny apps.

``` r

system.time(for (i in 1:1000L) kst_compile(demog_spec))
#>    user  system elapsed 
#> 109.656   1.846  80.204
```

------------------------------------------------------------------------

## Next steps

- See
  [`vignette("dsl_reference")`](https://crow16384.github.io/ksTable/articles/dsl_reference.md)
  for the complete JSON schema reference, including the **Denominators**
  section.
- The generated script can be saved to a `.R` file and used
  independently of the package — useful for audit trails in regulated
  environments.
- Set the parent of your eval environment (for example,
  `new.env(parent = environment())`) when you need precise control over
  function lookup scope. Bind external population tables (e.g. `adsl_n`)
  in that environment when using `denominator.type = "external"`.
