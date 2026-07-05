### ksTable demo: Demography
###
### Demographics table - continuous variable summaries (AGE, BMI) across
### three treatment groups using parameter_stat layout.
###
### Shows:
###   - Multiple parameters in one spec
###   - Built-in R functions with extra arguments ("args")
###   - User-defined calc + format functions for multi-part statistics
###   - kst_validate_spec(), kst_compile(), kst_generate_table()

library(tidyr)
library(dplyr, warn.conflicts = FALSE)
library(ksformat)
#library(ksTable)
devtools::load_all()

rm(list=ls())
options(stringsAsFactors = FALSE)

## -- 1. Synthetic ADSL -------------------------------------------------------------------

set.seed(2024L)
n <- 360L

adsl <- tibble(
  USUBJID = sprintf("SUBJ-%04d", seq_len(n)),
  AGE     = round(rnorm(n, mean = 52, sd = 14)),
  BMIBL   = round(rnorm(n, mean = 26.5, sd = 4.8), 1),
  TRT01P  = sample(c("PBO", "D50"), n, replace = TRUE),   # "D100" absent
  SEX     = sample(c("M", "F"), n, replace = TRUE, prob = c(0.55, 0.45))
)

## -- 2. Calc and format functions --------------------------------------------------------

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

## -- 3. Formats for variables

fnew("PBO"  = "Placebo",
     "D50"  = "Drug A 50 mg",
     "D100" = "Drug A 100 mg",
     name   = "trt_fmt")

fnew("M" = "Male", "F" = "Female", .missing = "Unknown", name = "sex_fmt")

## -- 4. JSON spec --------------------------------------------------------------

spec <- '{
  "schema_version": "1.0",
  "table_spec": {
    "id":    "demography",
    "title": "Demographic Characteristics",
    "parameter": {
      "age": { "variable": "AGE",   "label": "Age (years)" },
      "bmi": { "variable": "BMIBL", "label": "BMI at Baseline (kg/m\\u00b2)" },
      "sex": { "variable": "SEX", "label": "Sex" }
    },
    "statistics": {
      "n": {
        "fun":   "count",
        "label": "N"
      },
      "mean_sd": {
        "fun":    "mean_sd",
        "label":  "Mean (SD)",
        "format": { "type": "custom", "fun": "format_mean_sd" }
      },
      "median_iqr": {
        "fun":    "median_iqr",
        "label":  "Median [Q1, Q3]",
        "format": { "type": "custom", "fun": "format_median_iqr" }
      },
      "min": {
        "fun":    "min",
        "args":   { "na.rm": true },
        "label":  "Min",
        "format": { "type": "sprintf", "pattern": "%.1f" }
      },
      "max": {
        "fun":    "max",
        "args":   { "na.rm": true },
        "label":  "Max",
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
