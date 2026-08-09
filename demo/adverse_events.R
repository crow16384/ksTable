### ksTable demo: Adverse Events
###
### Adverse events table - event counts by System Organ Class (SOC) and
### Preferred Term (PT) across treatment groups, using hierarchical layout.
###
### Shows:
###   - hierarchical row structure (SOC parent rows -> PT child rows)
###   - Sorting: parent rows first, children alphabetically within each parent
###   - Intermediate object inspection for debugging

library(ksTable)

## -- 1. Synthetic AE data ------------------------------------------------------

set.seed(7L)
n_subj <- 180L

subjects <- data.frame(
  USUBJID = sprintf("SUBJ-%04d", seq_len(n_subj)),
  TRT01P  = rep(c("Placebo", "Drug A", "Drug B"), each = n_subj %/% 3L)
)

## AE categories - realistic SOC/PT combinations
soc_pt <- list(
  "Cardiac disorders" = c(
    "Palpitations", "Tachycardia", "Atrial fibrillation", "Bradycardia"
  ),
  "Gastrointestinal disorders" = c(
    "Nausea", "Diarrhoea", "Vomiting", "Abdominal pain", "Constipation"
  ),
  "Nervous system disorders" = c(
    "Headache", "Dizziness", "Somnolence", "Tremor"
  ),
  "Skin and subcutaneous tissue disorders" = c(
    "Rash", "Pruritus", "Urticaria"
  )
)

## Generate events: each subject may have 0-4 events
set.seed(7L)
ae_rows <- lapply(seq_len(n_subj), function(i) {
  n_events <- sample(0:4, 1, prob = c(0.35, 0.30, 0.20, 0.10, 0.05))
  if (n_events == 0L) return(NULL)
  soc_names <- sample(names(soc_pt), n_events, replace = TRUE)
  pt_names  <- mapply(function(soc) sample(soc_pt[[soc]], 1L),
                      soc_names, SIMPLIFY = TRUE)
  data.frame(
    USUBJID = subjects$USUBJID[[i]],
    TRT01P  = subjects$TRT01P[[i]],
    AESOC   = soc_names,
    AEDECOD = pt_names,
    stringsAsFactors = FALSE
  )
})
adae <- do.call(rbind, ae_rows)
rownames(adae) <- NULL

cat(sprintf("AE dataset: %d events from %d subjects across %d SOCs\n",
            nrow(adae),
            length(unique(adae$USUBJID)),
            length(unique(adae$AESOC))))

## -- 2. Calc function ----------------------------------------------------------
##
## count: number of events per group.
## For distinct-subject counts, users would call length(unique(USUBJID)) -
## the variable to pass is determined by the "variable" field in the spec.
##
## Here we count total AE events (rows) per SOC/PT per treatment using length().

## -- 3. JSON spec --------------------------------------------------------------

ae_spec <- '{
  "schema_version": "1.0",
  "table_spec": {
    "id":    "adverse_events",
    "title": "Adverse Events by System Organ Class and Preferred Term",
    "parameter": {
      "soc": {
        "variable": "AESOC",
        "label":    "",
        "nested": {
          "pt": { "variable": "AEDECOD", "label": "" }
        }
      }
    },
    "statistics": {
      "n": {
        "fun":   "length"
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

## -- 4. Validate ---------------------------------------------------------------

v <- kst_validate_spec(ae_spec)
if (!v$valid) stop(paste(v$errors, collapse = "\n"))
message("Spec validation: PASS")

## -- 5. Inspect generated script -----------------------------------------------

cat("\n-- Generated R script --------------------------------------------------\n")
cat(kst_compile(ae_spec))
cat("\n\n")

## -- 6. Generate table ---------------------------------------------------------

code <- kst_compile(ae_spec)
env  <- new.env(parent = environment())
env$data <- adae
ae_table <- eval(parse(text = code), envir = env)

cat("-- Adverse Events Table ------------------------------------------------\n")
print(ae_table, n = Inf, width = 120)

## -- 7. Reading the output -----------------------------------------------------
##
## .is_child = FALSE  ->  SOC-level row (parent)
## .is_child = TRUE   ->  PT-level row  (child, alphabetically sorted within SOC)
##
## ksTFL uses .parent and .is_child to apply indentation and group headers.

cat("\n-- Parent rows (SOC totals) ---------------------------------------------\n")
print(ae_table[!ae_table$.is_child, ], n = Inf, width = 120)

cat("\n-- Child rows for 'Gastrointestinal disorders' ---------------------------\n")
gi <- ae_table[ae_table$.is_child &
               ae_table$.parent == "Gastrointestinal disorders", ]
print(gi, n = Inf, width = 120)

## -- 8. Step-through: inspect intermediates ------------------------------------

# Reuse the same environment from section 6.

cat("\n-- Intermediate objects in execution env -------------------------------\n")
cat("Objects: ", paste(ls(env, all.names = TRUE), collapse = ", "), "\n")
cat("\nParent chunk (.chunks[[1L]], head):\n")
print(head(env$.chunks[[1L]]))
cat("\nLong-format before pivot (.long, head):\n")
print(head(env$.long))
