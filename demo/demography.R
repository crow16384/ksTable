### ksTable demo: Demography
###
### Demographics table - continuous variable summaries (AGE, BMI) across
### three treatment groups using parameter_stat layout.
###
### Shows:
###   - Multiple parameters in one spec
###   - Built-in R functions with extra arguments ("args")
###   - User-defined calc + format functions for multi-part statistics
###   - kst_validate_spec(), kst_compile(), explicit eval(parse(...))

library(ksTable)

## -- 1. Synthetic ADSL -------------------------------------------------------------------

set.seed(2024L)
n <- 360L

adsl <- data.frame(
  USUBJID = sprintf("SUBJ-%04d", seq_len(n)),
  AGE     = round(rnorm(n, mean = 52, sd = 14)),
  BMIBL   = round(rnorm(n, mean = 26.5, sd = 4.8), 1),
  TRT01P  = rep(c("Placebo", "Drug A 50 mg", "Drug A 100 mg"),
                each = n %/% 3L)
)

## -- 2. Calc and format functions --------------------------------------------------------
##
## count, min, max, median - use built-in R functions via "fun" + "args" in JSON.
## mean_sd, median_iqr    - return a named list; a format function renders it.

count <- function(data) sum(!is.na(data))   # non-missing count

mean_sd <- function(data) list(
  mean = mean(data, na.rm = TRUE),
  sd   = sd(data,   na.rm = TRUE)
)

median_iqr <- function(data) list(
  median = median(data,              na.rm = TRUE),
  q1     = quantile(data, probs = 0.25, na.rm = TRUE),
  q3     = quantile(data, probs = 0.75, na.rm = TRUE)
)

format_mean_sd    <- function(x) sprintf("%.1f (%.2f)",        x$mean, x$sd)
format_median_iqr <- function(x) sprintf("%.1f [%.1f, %.1f]", x$median, x$q1, x$q3)

## -- 3. JSON spec --------------------------------------------------------------

spec <- '{
  "schema_version": "1.0",
  "table_spec": {
    "id":    "demography",
    "title": "Demographic Characteristics",
    "parameter": {
      "age": { "variable": "AGE",   "label": "Age (years)"          },
      "bmi": { "variable": "BMIBL", "label": "BMI at Baseline (kg/m\\u00b2)" }
    },
    "statistics": {
      "n": {
        "fun":   "count"
      },
      "mean_sd": {
        "fun":    "mean_sd",
        "format": { "type": "custom", "fun": "format_mean_sd" }
      },
      "median_iqr": {
        "fun":    "median_iqr",
        "format": { "type": "custom", "fun": "format_median_iqr" }
      },
      "min": {
        "fun":    "min",
        "args":   { "na.rm": true },
        "format": { "type": "sprintf", "pattern": "%.1f" }
      },
      "max": {
        "fun":    "max",
        "args":   { "na.rm": true },
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

## -- 4. Validate -------------------------------------------------------------

v <- kst_validate_spec(spec)
if (!v$valid) stop(paste(v$errors, collapse = "\n"))
message("Spec validation: PASS")

## -- 5. Inspect generated script -----------------------------------------------

cat("\n-- Generated R script --------------------------------------------------\n")
cat(kst_compile(spec))
cat("\n\n")

## -- 6. Generate table -------------------------------------------------------

code <- kst_compile(spec)
env  <- new.env(parent = environment())
env$data <- adsl
demog <- eval(parse(text = code), envir = env)

cat("-- Demography Table ----------------------------------------------------\n")
print(demog, n = Inf, width = 120)

## -- 7. Step-through (optional) ------------------------------------------------
##
## Compile once, inspect intermediates in an isolated env:
##
##   code <- kst_compile(spec)
##   env  <- new.env(parent = environment())
##   env$data <- adsl
##   eval(parse(text = code), envir = env)
##   env$.chunks   # list of per-stat tibbles before bind_rows
##   env$.long     # long-format assembled table
