### ksTable demo: Laboratory
###
### Laboratory summary table - mean, SD, median, range for key liver function
### tests across treatment groups, using parameter_stat layout.
###
### Shows:
###   - Multiple continuous parameters (ALT, AST, Bilirubin)
###   - All statistics use built-in R functions + "args": no user-defined
###     calc functions required
###   - sprintf format type for consistent decimal places

library(ksTable)

## -- 1. Synthetic laboratory data -------------------------------------------
##
## One row per subject per visit for three lab parameters.
## Realistic baseline values and treatment-related changes for liver enzymes.

set.seed(42L)
n_subj <- 120L
visits <- c("Baseline", "Week 4", "Week 8", "Week 12")

subjects <- data.frame(
  USUBJID = sprintf("SUBJ-%04d", seq_len(n_subj)),
  TRT01P  = rep(c("Placebo", "Drug A", "Drug B"),
                each = n_subj %/% 3L)
)

## Generate per-visit measurements
lb_list <- lapply(visits, function(vis) {
  base <- data.frame(
    USUBJID = subjects$USUBJID,
    TRT01P  = subjects$TRT01P,
    VISIT   = vis
  )
  # Simulate mild treatment-related ALT/AST elevations at later visits
  offset <- if (vis == "Baseline") 0 else match(vis, visits) - 1L
  base$ALT  <- pmax(1, round(rnorm(n_subj, mean = 28 + offset * 3, sd = 12)))
  base$AST  <- pmax(1, round(rnorm(n_subj, mean = 22 + offset * 2, sd = 9)))
  base$BILI <- pmax(0.1, round(rnorm(n_subj, mean = 0.7, sd = 0.3), 1))
  base
})
adlb <- do.call(rbind, lb_list)

## -- 2. No user-defined functions needed ------------------------------------
##
## Every statistic in this demo uses a built-in R function.
## Extra arguments (na.rm = TRUE) are passed via the "args" field in JSON.
## sprintf is used for consistent decimal places via the "format" field.

## -- 3. JSON spec - ALT summary ---------------------------------------------------

alt_spec <- '{
  "schema_version": "1.0",
  "table_spec": {
    "id":    "lab_alt",
    "title": "Alanine Aminotransferase (ALT) - Summary by Visit",
    "parameter": {
      "alt":  { "variable": "ALT",  "label": "ALT (U/L)"  },
      "ast":  { "variable": "AST",  "label": "AST (U/L)"  },
      "bili": { "variable": "BILI", "label": "Bilirubin (mg/dL)" }
    },
    "statistics": {
      "n": {
        "fun":   "length",
        "label": "N"
      },
      "mean": {
        "fun":    "mean",
        "args":   { "na.rm": true },
        "label":  "Mean",
        "format": { "type": "sprintf", "pattern": "%.1f" }
      },
      "sd": {
        "fun":    "sd",
        "args":   { "na.rm": true },
        "label":  "SD",
        "format": { "type": "sprintf", "pattern": "%.2f" }
      },
      "median": {
        "fun":    "median",
        "args":   { "na.rm": true },
        "label":  "Median",
        "format": { "type": "sprintf", "pattern": "%.1f" }
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

## -- 4. Validate -------------------------------------------------------------

v <- kst_validate_spec(alt_spec)
if (!v$valid) stop(paste(v$errors, collapse = "\n"))
message("Spec validation: PASS")

## -- 5. Inspect generated script -----------------------------------------------

cat("\n-- Generated R script (first stat only shown) ------------------------\n")
code <- kst_compile(alt_spec)
# Print just the first chunk to keep output readable
first_chunk <- paste(
  head(strsplit(code, "\n")[[1L]], 18L),
  collapse = "\n"
)
cat(first_chunk, "\n...\n\n")

## -- 6. Generate table - all visits combined -----------------------------------

lab_table <- kst_generate_table(alt_spec, adlb)

cat("-- Laboratory Summary (all visits) -------------------------------------\n")
print(lab_table, n = Inf, width = 120)

## -- 7. Generate table - baseline only ----------------------------------------

cat("\n-- Laboratory Summary (Baseline only) ----------------------------------\n")
baseline <- adlb[adlb$VISIT == "Baseline", ]
lab_baseline <- kst_generate_table(alt_spec, baseline)
print(lab_baseline, n = Inf, width = 120)

## -- 8. Generate table - Week 12 only -----------------------------------------

cat("\n-- Laboratory Summary (Week 12 only) -----------------------------------\n")
wk12 <- adlb[adlb$VISIT == "Week 12", ]
lab_wk12 <- kst_generate_table(alt_spec, wk12)
print(lab_wk12, n = Inf, width = 120)
