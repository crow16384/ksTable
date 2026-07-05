### ksTable demo: ksformat Integration
###
### Shows how ksformat VALUE formats interact with ksTable:
###
###  1. Column headers  -- ksformat labels as pivot column names
###  2. Factor levels   -- ksformat keys drive include_missing_levels
###  3. Cell formatting -- statistics.format.type = "ksformat"
###
### Requires: remotes::install_github("crow16384/ksformat")

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
