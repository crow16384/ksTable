### ksTable demo: ksformat Integration
###
### One JSON spec covering Age (years), BMI, and Sex in a demographics table.
### ksformat is used for:
###
###  1. Treatment arm column headers  -- "PBO" -> "Placebo" etc.
###  2. include_missing_levels        -- absent arm still gets a column
###  3. Sex cell formatting           -- modal sex code "M"/"F" -> "Male"/"Female"
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

## -- 3. Calc and format functions --------------------------------------------
##
## Because ONE spec covers both numeric (AGE, BMIBL) and categorical (SEX)
## parameters, every calc function must handle either type gracefully:
##   - Numeric stats return NA for character columns (shown as blank "")
##   - Sex counts return NA for numeric columns (shown as blank "")
## This mirrors how clinical demographics tables leave cells blank rather
## than showing "0" or "NA" for inapplicable combinations.

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

## Categorical stats -- return NA for numeric columns (blank in output)
n_male   <- function(data) if (is.numeric(data)) NA_integer_ else sum(data == "M", na.rm = TRUE)
n_female <- function(data) if (is.numeric(data)) NA_integer_ else sum(data == "F", na.rm = TRUE)
fmt_int_or_blank <- function(x) if (is.na(x)) "" else as.character(x)

## Modal sex code per group; NA for numeric variables.
## Custom format wrapper: blank for NA, ksformat label for actual codes.
mode_sex <- function(data) {
  if (is.numeric(data)) return(NA_character_)
  tbl <- sort(table(data[!is.na(data)]), decreasing = TRUE)
  if (length(tbl) == 0L) NA_character_ else names(tbl)[[1L]]
}
fmt_sex_or_blank <- function(x) {
  if (is.na(x)) return("")
  ksformat::fput(x, "sex_fmt")   # "M" -> "Male", "F" -> "Female"
}

## -- 4. One JSON spec: AGE + BMI + SEX ----------------------------------------
##
## parameters:
##   age  (AGE)   -- continuous: n, mean (SD), median, min, max
##   bmi  (BMIBL) -- continuous: n, mean (SD), median
##   sex  (SEX)   -- categorical: total n, n Male, n Female, modal sex (ksformat)
##
## groups.format references "trt_fmt" so kst_generate_table() auto-applies
## fput() labels and sets factor levels (including the absent D100 arm).

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
      "n_male": {
        "fun":    "n_male",
        "label":  "Male n",
        "format": { "type": "custom", "fun": "fmt_int_or_blank" }
      },
      "n_female": {
        "fun":    "n_female",
        "label":  "Female n",
        "format": { "type": "custom", "fun": "fmt_int_or_blank" }
      },
      "mode_sex": {
        "fun":    "mode_sex",
        "label":  "Most common",
        "format": { "type": "custom", "fun": "fmt_sex_or_blank" }
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

## -- 6. Generate the table ---------------------------------------------------
##
## kst_generate_table() detects groups.format, calls kst_extract_metadata()
## with format_map = list(TRT01P = "trt_fmt"), then kst_apply_metadata() to:
##   - replace "PBO"/"D50" with "Placebo"/"Drug A 50 mg" via fput()
##   - set TRT01P as an ordered factor with all three levels (incl. absent D100)
## Result columns are the formatted arm labels; "Drug A 100 mg" column is
## present but shows default as.character() output (0/NA) as it has no data.

cat("-- Generated script (first 20 lines) ------------------------------------\n")
code <- kst_compile(demographics_spec)
cat(paste(head(strsplit(code, "\n")[[1L]], 20L), collapse = "\n"), "\n...\n\n")

cat("-- Demographics Table ---------------------------------------------------\n")
result <- kst_generate_table(demographics_spec, adsl)
print(result, n = Inf, width = 140)

## -- 7. Inspect rows per parameter ------------------------------------------

cat("\n-- Age rows only --------------------------------------------------------\n")
print(result[result$.param == "Age (years)", ], width = 140)

cat("\n-- Sex rows only --------------------------------------------------------\n")
print(result[result$.param == "Sex", ], width = 140)

## -- 8. Save the script to a file -------------------------------------------

tmp <- tempfile(fileext = ".R")
kst_save(demographics_spec, tmp)
cat("\n-- Saved script header -------------------------------------------------\n")
cat(paste(head(readLines(tmp), 10L), collapse = "\n"), "\n")

## -- 9. Clean up the global format library ----------------------------------

fclear()
cat("\nFormats after fclear(): ")
fprint()


library(ksTable)

if (!requireNamespace("ksformat", quietly = TRUE))
  stop("This demo requires ksformat: ",
       'remotes::install_github("crow16384/ksformat")')

library(ksformat)

## -- 1. Register VALUE formats -----------------------------------------------
##
## fnew() maps raw data codes to display labels and stores the format by name.
## "D100" is registered but intentionally absent from the data below, to
## demonstrate include_missing_levels = true with ksformat-derived levels.

fnew("PBO"  = "Placebo",
     "D50"  = "Drug A 50 mg",
     "D100" = "Drug A 100 mg",
     name   = "trt_fmt")

fnew("M" = "Male", "F" = "Female", .missing = "Unknown", name = "sex_fmt")

cat("Registered formats:\n")
fprint()

## -- 2. Synthetic ADSL -------------------------------------------------------

set.seed(42L)
n    <- 200L
adsl <- data.frame(
  USUBJID = sprintf("SUBJ-%04d", seq_len(n)),
  AGE     = round(rnorm(n, mean = 52, sd = 14)),
  TRT01P  = sample(c("PBO", "D50"), n, replace = TRUE),   # "D100" absent
  SEX     = sample(c("M", "F"), n, replace = TRUE, prob = c(0.55, 0.45)),
  stringsAsFactors = FALSE
)
cat("\nRaw TRT01P codes in data: ", paste(sort(unique(adsl$TRT01P)), collapse = ", "), "\n")

## -- 3. Extract metadata and apply -------------------------------------------
##
## kst_extract_metadata() calls format_get("trt_fmt") to get the ks_format
## object, reads names(fmt$mappings) for the raw codes in registration order,
## then applies fput() to convert codes -> labels.  Those labels become the
## factor levels (including "Drug A 100 mg" which is absent from the data).
##
## kst_apply_metadata() calls fput() on TRT01P to replace "PBO"/"D50" with
## their labels, then sets the column as an ordered factor.

trt_meta <- kst_extract_metadata(
  adsl,
  variables  = "TRT01P",
  format_map = list(TRT01P = "trt_fmt")
)
cat("\nResolved factor levels from ksformat:\n")
cat("  ", paste(trt_meta$TRT01P$levels, collapse = " | "), "\n")

adsl_fmt <- kst_apply_metadata(adsl, trt_meta)
cat("\nAfter kst_apply_metadata:\n")
cat("  levels(TRT01P): ", paste(levels(adsl_fmt$TRT01P), collapse = " | "), "\n")
cat("  'Drug A 100 mg' in data: ", "Drug A 100 mg" %in% adsl_fmt$TRT01P, "\n\n")

## -- 4. Demographics: formatted headers + include_missing_levels -------------
##
## Because adsl_fmt$TRT01P is a factor with all three levels (including the
## absent arm), group_by(TRT01P, .drop = FALSE) produces a "Drug A 100 mg"
## column filled with the default as.character(0) = "0".

demog_spec <- '{
  "schema_version": "1.0",
  "table_spec": {
    "id":    "demog_ksformat",
    "title": "Demographics with ksformat headers",
    "parameter": {
      "age": { "variable": "AGE", "label": "Age (years)" }
    },
    "statistics": {
      "n":      { "fun": "length",  "label": "N" },
      "mean":   { "fun": "mean",    "args": { "na.rm": true }, "label": "Mean",
                  "format": { "type": "sprintf", "pattern": "%.1f" } },
      "median": { "fun": "median",  "args": { "na.rm": true }, "label": "Median",
                  "format": { "type": "sprintf", "pattern": "%.1f" } }
    },
    "groups": {
      "by": ["TRT01P"],
      "include_missing_levels": true,
      "format": { "TRT01P": "trt_fmt" }
    },
    "layout": {
      "row_structure": "parameter_stat",
      "column_structure": "groups"
    }
  }
}'

cat("-- Demographics: ksformat column headers, missing arm shown -------------\n")
## kst_generate_table auto-detects groups.format and applies metadata;
## adsl (not adsl_fmt) is passed here to show the automatic pipeline.
demog <- kst_generate_table(demog_spec, adsl)
print(demog, n = Inf, width = 120)

## -- 5. Cell formatting via ksformat -----------------------------------------
##
## statistics.format.type = "ksformat" emits in the generated script:
##   .value = ksformat::fput(.value_raw, "sex_fmt")
## The calc function returns a raw code ("M" or "F"); ksformat maps it to
## a display label in the format step.

mode_code <- function(data) {
  tbl <- sort(table(data[!is.na(data)]), decreasing = TRUE)
  if (length(tbl) == 0L) NA_character_ else names(tbl)[[1L]]
}

sex_spec <- '{
  "schema_version": "1.0",
  "table_spec": {
    "parameter": { "sex": { "variable": "SEX", "label": "Sex" } },
    "statistics": {
      "mode_sex": {
        "fun":    "mode_code",
        "label":  "Most common",
        "format": { "type": "ksformat", "format_name": "sex_fmt" }
      }
    },
    "groups":  { "by": ["TRT01P"] },
    "layout":  { "row_structure": "parameter_stat" }
  }
}'

cat("\n-- Generated script (ksformat cell formatting) --------------------------\n")
cat(kst_compile(sex_spec))

cat("\n\n-- Result (modal sex per arm, rendered by ksformat) ---------------------\n")
sex_result <- kst_generate_table(sex_spec, adsl_fmt)
print(sex_result)

## -- 6. Inspect the format object --------------------------------------------

cat("\n-- Format object: trt_fmt -----------------------------------------------\n")
fmt <- format_get("trt_fmt")
print(fmt)
cat("\nKey -> label:\n")
for (k in names(fmt$mappings))
  cat(sprintf("  %-6s -> %s\n", k, fput(k, fmt)))

## -- 7. Save the generated script to a file ----------------------------------

tmp <- tempfile(fileext = ".R")
kst_save(demog_spec, tmp)
cat("\n-- Saved script (first 12 lines) ----------------------------------------\n")
cat(paste(head(readLines(tmp), 12L), collapse = "\n"), "\n")

## -- 8. Clean up the global format library -----------------------------------

fclear()
cat("\nFormat library after fclear():\n")
fprint()
