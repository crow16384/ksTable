### ksTable demo: ksformat Integration
###
### Demographics table: Age, BMI (continuous) and Sex (categorical) in ONE
### JSON spec using three new DSL features:
###
###  1. apply_to  -- bind each statistic to specific parameter IDs (no blanks)
###  2. variables -- array of columns sharing the same statistics (no repetition)
###  3. denominator -- external N tibble accessed via dplyr::cur_group()
###
### Requires: remotes::install_github("crow16384/ksformat")

library(ksTable)

if (!requireNamespace("ksformat", quietly = TRUE))
  stop("This demo requires ksformat: ",
       'remotes::install_github("crow16384/ksformat")')

library(ksformat)

## -- 1. Register VALUE formats -----------------------------------------------

fnew("PBO"  = "Placebo",
     "D50"  = "Drug A 50 mg",
     "D100" = "Drug A 100 mg",   # registered but absent from data
     name   = "trt_fmt")

fnew("M" = "Male", "F" = "Female", .missing = "Unknown", name = "sex_fmt")

## -- 2. Synthetic ADSL -------------------------------------------------------

set.seed(42L)
n    <- 240L
adsl <- data.frame(
  USUBJID = sprintf("SUBJ-%04d", seq_len(n)),
  AGE     = round(rnorm(n, mean = 52, sd = 14)),
  BMIBL   = round(rnorm(n, mean = 26.5, sd = 4.8), 1),
  TRT01P  = sample(c("PBO", "D50"), n, replace = TRUE),
  SEX     = sample(c("M", "F"), n, replace = TRUE, prob = c(0.55, 0.45)),
  stringsAsFactors = FALSE
)
adsl$SEX[sample(n, 10L)] <- NA    # 10 subjects with missing sex

## Apply ksformat to TRT01P and SEX; sets factor levels (incl. D100 arm)
meta     <- kst_extract_metadata(adsl, c("TRT01P", "SEX"),
                                  format_map = list(TRT01P = "trt_fmt",
                                                    SEX    = "sex_fmt"))
adsl_fmt <- kst_apply_metadata(adsl, meta)

cat("TRT01P levels:", paste(levels(adsl_fmt$TRT01P), collapse = " | "), "\n")
cat("SEX values:   ", paste(sort(unique(adsl_fmt$SEX), na.last = TRUE), collapse = ", "), "\n\n")

## -- 3. Calc and format functions --------------------------------------------

## Continuous
mean_sd <- function(data) list(mean = mean(data, na.rm = TRUE),
                               sd   = sd(data,   na.rm = TRUE))
format_mean_sd      <- function(x) sprintf("%.1f (%.2f)", x$mean, x$sd)
format_num_or_blank <- function(x) if (is.na(x) || is.infinite(x)) "" else sprintf("%.1f", x)
median_safe <- function(data) if (!is.numeric(data)) NA_real_ else median(data, na.rm = TRUE)
min_safe    <- function(data) if (!is.numeric(data)) NA_real_ else min(data, na.rm = TRUE)
max_safe    <- function(data) if (!is.numeric(data)) NA_real_ else max(data, na.rm = TRUE)

## Categorical (SEX already formatted upstream; no ksformat call here)
cat_summary <- function(data) {
  if (is.numeric(data)) return(NULL)
  data.frame(x = data) |>
    dplyr::count(x, sort = FALSE, name = "n") |>
    dplyr::mutate(pct = 100 * n / sum(n))
}
format_sex_counts <- function(x) {
  if (is.null(x)) return("")
  paste(sprintf("%s: %d (%.1f%%)", x$x, x$n, x$pct), collapse = "; ")
}

## -- 4. JSON spec: apply_to + variables --------------------------------------
##
## FEATURE 1 — apply_to:
##   Binds each statistic to specific parameter IDs, eliminating blank cells.
##   "n" has no apply_to -> runs for both "cont" and "sex" parameters.
##   "mean_sd", "median", "min", "max" use apply_to: ["cont"]
##   "sex_summary" uses apply_to: ["sex"]
##
## FEATURE 2 — variables (array):
##   The "cont" parameter lists two variables: AGE and BMIBL.
##   Both share the same statistics; each expands into its own row block.
##   No need to write separate "age" and "bmi" parameter definitions.

demographics_spec <- '{
  "schema_version": "1.0",
  "table_spec": {
    "id":    "demographics",
    "title": "Baseline Demographic Characteristics",
    "parameter": {
      "cont": {
        "variables": ["AGE",          "BMIBL"],
        "labels":    ["Age (years)",  "BMI at Baseline (kg/m2)"]
      },
      "sex": {
        "variable": "SEX",
        "label":    "Sex"
      }
    },
    "statistics": {
      "n": {
        "fun":   "length",
        "label": "N"
      },
      "mean_sd": {
        "fun":      "mean_sd",
        "label":    "Mean (SD)",
        "apply_to": ["cont"],
        "format":   { "type": "custom", "fun": "format_mean_sd" }
      },
      "median": {
        "fun":      "median_safe",
        "label":    "Median",
        "apply_to": ["cont"],
        "format":   { "type": "custom", "fun": "format_num_or_blank" }
      },
      "min": {
        "fun":      "min_safe",
        "label":    "Min",
        "apply_to": ["cont"],
        "format":   { "type": "custom", "fun": "format_num_or_blank" }
      },
      "max": {
        "fun":      "max_safe",
        "label":    "Max",
        "apply_to": ["cont"],
        "format":   { "type": "custom", "fun": "format_num_or_blank" }
      },
      "sex_summary": {
        "fun":      "cat_summary",
        "label":    "n (%)",
        "apply_to": ["sex"],
        "format":   { "type": "custom", "fun": "format_sex_counts" }
      }
    },
    "groups": {
      "by": ["TRT01P"],
      "include_missing_levels": true,
      "format": { "TRT01P": "trt_fmt" }
    },
    "layout": {
      "row_structure":    "parameter_stat",
      "column_structure": "groups"
    }
  }
}'

## -- 5. Validate -------------------------------------------------------------

v <- kst_validate_spec(demographics_spec)
if (!v$valid) stop(paste(v$errors, collapse = "\n"))
cat("Spec validation: PASS\n\n")

## -- 6. FEATURE 3: denominator from an external tibble ----------------------
##
## When computing AE percentages, the denominator is the number of subjects
## per arm (from ADSL), NOT the number of events in the AE group.
##
## kst_generate_table(denominator = ...) binds the tibble into the eval env
## as `denominator`.  Calc functions read it using dplyr::cur_group() to
## get the current arm key:
##
##   n_pct_ae <- function(data) {
##     arm <- as.list(dplyr::cur_group())$TRT01P
##     N   <- denominator$N[denominator$TRT01P == arm]
##     list(n = length(unique(data)), pct = 100 * length(unique(data)) / N)
##   }
##
## For this demo we compute sex % relative to arm N from ADSL (not the SEX
## column itself), to illustrate the pattern.

n_by_arm <- adsl_fmt |>
  dplyr::count(TRT01P, name = "N") |>
  dplyr::filter(!is.na(TRT01P))

cat("External denominator (arm N from ADSL):\n")
print(n_by_arm)
cat("\n")

sex_pct_ext <- function(data) {
  if (is.numeric(data)) return(NULL)
  arm <- as.list(dplyr::cur_group())$TRT01P
  N   <- denominator$N[denominator$TRT01P == arm]   # reads from eval env
  if (length(N) == 0L || is.na(N)) N <- 1L
  data.frame(x = data) |>
    dplyr::count(x, sort = FALSE, name = "n") |>
    dplyr::mutate(pct = 100 * n / N)
}
format_sex_ext <- function(x) {
  if (is.null(x)) return("")
  paste(sprintf("%s: %d / N=%.1f%%", x$x, x$n, x$pct), collapse = "; ")
}

spec_ext <- gsub('"fun":      "cat_summary"',  '"fun": "sex_pct_ext"',
             gsub('"fun": "format_sex_counts"', '"fun": "format_sex_ext"',
                  demographics_spec))

## -- 7. Generate tables ------------------------------------------------------

cat("-- Demographics Table (apply_to + variables) ---------------------------\n")
result <- kst_generate_table(demographics_spec, adsl_fmt)
print(result, n = Inf, width = 140)

cat("\n-- Sex rows with external denominator from n_by_arm --------------------\n")
result_ext <- kst_generate_table(spec_ext, adsl_fmt, denominator = n_by_arm)
print(result_ext[result_ext$.param == "Sex", ], width = 140)

## -- 8. Inspect generated script (apply_to effect visible in chunk count) ---

cat("\n-- Generated script: only 7 chunks (n×2 + mean_sd×2+median×2+min×2+max×2 + sex_summary×1)\n")
code <- kst_compile(demographics_spec)
n_chunks <- lengths(regmatches(code, gregexpr(".chunks[[", code, fixed = TRUE)))
cat("   Chunk count:", n_chunks, "\n\n")
cat(code)

## -- 9. Save and clean up ----------------------------------------------------

tmp <- tempfile(fileext = ".R")
kst_save(demographics_spec, tmp)
cat("\n-- Saved script header -------------------------------------------------\n")
cat(paste(head(readLines(tmp), 10L), collapse = "\n"), "\n")

fclear()
