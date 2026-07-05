### ksTable demo: ksformat Integration
###
### One JSON spec covering Age (years), BMI, and Sex in a demographics table.
### ksformat is used for:
###
###  1. Treatment arm column headers  -- "PBO" -> "Placebo" etc.
###  2. include_missing_levels        -- absent arm still gets a column
###  3. SEX pre-formatted upstream    -- fput() applied before generating code
###     so cat_summary() receives "Male"/"Female"/"Unknown" directly
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
     "D100" = "Drug A 100 mg",   # registered but absent from data (missing level demo)
     name   = "trt_fmt")

fnew("M" = "Male", "F" = "Female", .missing = "Unknown", name = "sex_fmt")

## -- 2. Synthetic ADSL -------------------------------------------------------
##
## Two arms only (PBO, D50); D100 is absent to exercise include_missing_levels.
## Ten SEX values are set to NA to demonstrate the .missing = "Unknown" label.

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
cat("Raw SEX values:  ", paste(sort(unique(adsl$SEX), na.last = TRUE), collapse = ", "), "\n")

## -- 3. Calc and format functions --------------------------------------------
##
## Because ONE spec covers both numeric (AGE, BMIBL) and categorical (SEX)
## parameters, every calc function must handle either type gracefully:
##   - Numeric stats return NA / NULL for character columns (shown as "")
##   - The categorical summary returns NULL for numeric columns (shown as "")

## Continuous stats -- safe versions that return NA for character input
mean_sd <- function(data) {
  if (!is.numeric(data)) return(list(mean = NA_real_, sd = NA_real_))
  list(mean = mean(data, na.rm = TRUE), sd = sd(data, na.rm = TRUE))
}
format_mean_sd <- function(x) {
  if (is.na(x$mean)) return("")
  sprintf("%.1f (%.2f)", x$mean, x$sd)
}

median_safe <- function(data) {
  if (!is.numeric(data)) return(NA_real_)
  median(data, na.rm = TRUE)
}
format_num_or_blank <- function(x) if (is.na(x) || is.infinite(x)) "" else sprintf("%.1f", x)

min_safe <- function(data) { if (!is.numeric(data)) NA_real_ else min(data, na.rm = TRUE) }
max_safe <- function(data) { if (!is.numeric(data)) NA_real_ else max(data, na.rm = TRUE) }

## Categorical summary -- uses dplyr::count() internally.
##
## SEX is pre-formatted upstream by kst_apply_metadata() (see step 3 below),
## so this function receives display labels ("Male", "Female", "Unknown")
## directly -- no ksformat translation needed here.
## NA values should not reach this function if .missing is set in the format;
## any remaining NA is counted separately as a safeguard.

cat_summary <- function(data) {
  if (is.numeric(data)) return(NULL)
  data.frame(x = data) |>                    # include all values; NA from .missing
    dplyr::count(x, sort = FALSE, name = "n") |>
    dplyr::mutate(pct = 100 * n / sum(n))
}

format_sex_counts <- function(x) {
  if (is.null(x)) return("")
  # Labels already translated upstream; just render counts and percentages.
  paste(sprintf("%s: %d (%.1f%%)", x$x, x$n, x$pct), collapse = "; ")
}

## -- 4. One JSON spec: AGE + BMI + SEX ----------------------------------------
##
## The spec does NOT need a format reference for SEX; the column is already
## pre-formatted.  cat_summary() + format_sex_counts() are pure data functions.
## groups.format for TRT01P drives the auto-pipeline in kst_generate_table().

demographics_spec <- '{
  "schema_version": "1.0",
  "table_spec": {
    "id":    "demographics",
    "title": "Baseline Demographic Characteristics",
    "parameter": {
      "age": {
        "variable": "AGE",
        "label":    "Age (years)"
      },
      "bmi": {
        "variable": "BMIBL",
        "label":    "BMI at Baseline (kg/m2)"
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
        "fun":    "mean_sd",
        "label":  "Mean (SD)",
        "format": { "type": "custom", "fun": "format_mean_sd" }
      },
      "median": {
        "fun":    "median_safe",
        "label":  "Median",
        "format": { "type": "custom", "fun": "format_num_or_blank" }
      },
      "min": {
        "fun":    "min_safe",
        "label":  "Min",
        "format": { "type": "custom", "fun": "format_num_or_blank" }
      },
      "max": {
        "fun":    "max_safe",
        "label":  "Max",
        "format": { "type": "custom", "fun": "format_num_or_blank" }
      },
      "sex_summary": {
        "fun":    "cat_summary",
        "label":  "n (%)",
        "format": { "type": "custom", "fun": "format_sex_counts" }
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

## -- 5. Validate the spec ----------------------------------------------------

v <- kst_validate_spec(demographics_spec)
if (!v$valid) stop(paste(v$errors, collapse = "\n"))
cat("Spec validation:", v$engine, "-> PASS\n\n")

## -- 6. Pre-process: apply formats to TRT01P AND SEX -------------------------
##
## kst_extract_metadata() with format_map for both variables:
##   TRT01P: codes "PBO"/"D50"/"D100" -> labels; factor levels include absent D100
##   SEX:    codes "M"/"F" -> "Male"/"Female"; NA -> "Unknown" (.missing label)
##
## After kst_apply_metadata(), generated code receives already-labelled values:
##   cat_summary(SEX) sees "Male", "Female", "Unknown" -- no ksformat call needed.

meta <- kst_extract_metadata(
  adsl,
  variables  = c("TRT01P", "SEX"),
  format_map = list(TRT01P = "trt_fmt", SEX = "sex_fmt")
)
adsl_fmt <- kst_apply_metadata(adsl, meta)

cat("SEX after fput():  ", paste(sort(unique(adsl_fmt$SEX), na.last = TRUE), collapse = ", "), "\n")
cat("TRT01P levels:     ", paste(levels(adsl_fmt$TRT01P), collapse = " | "), "\n\n")

## -- 7. Generate the table ---------------------------------------------------
##
## kst_generate_table() still auto-runs the TRT01P metadata pipeline because
## groups.format is present in the spec.  The pipeline is idempotent: fput() on
## already-formatted labels ("Placebo") returns them unchanged.
## The SEX column is NOT in groups.format, so its pre-processing is ours alone.

cat("-- Generated script (first 20 lines) ------------------------------------\n")
code <- kst_compile(demographics_spec)
cat(paste(head(strsplit(code, "\n")[[1L]], 20L), collapse = "\n"), "\n...\n\n")

cat("-- Demographics Table ---------------------------------------------------\n")
result <- kst_generate_table(demographics_spec, adsl_fmt)
print(result, n = Inf, width = 140)

## -- 8. Inspect sex rows only -----------------------------------------------

cat("\n-- Sex rows (Unknown appears because .missing = 'Unknown') --------------\n")
print(result[result$.param == "Sex", ], width = 140)

## -- 9. Save the script to a file -------------------------------------------

tmp <- tempfile(fileext = ".R")
kst_save(demographics_spec, tmp)
cat("\n-- Saved script header -------------------------------------------------\n")
cat(paste(head(readLines(tmp), 10L), collapse = "\n"), "\n")

## -- 10. Clean up the global format library ----------------------------------

fclear()
cat("\nFormats after fclear(): ")
fprint()
