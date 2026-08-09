### ksTable demo: ksformat Integration
###
### Demographics table: Age, BMI (continuous) and Sex (categorical) in ONE
### JSON spec using DSL features:
###
###  1. apply_to  -- bind each statistic to specific parameter IDs (no blanks)
###  2. variables -- array of columns sharing the same statistics (no repetition)
###  3. denominator -- declarative denom resolution (external big-N / data_n / n)
###     (legacy: calc functions may still close over env objects + cur_group())
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
# One calc function computes all continuous summary pieces at once.
cont_summary <- function(data) {
  if (!is.numeric(data)) return(NULL)
  finite_data <- data[is.finite(data)]
  safe_min <- if (length(finite_data) == 0L) NA_real_ else min(finite_data)
  safe_max <- if (length(finite_data) == 0L) NA_real_ else max(finite_data)

  list(
    variable = as.character(substitute(data)),
    n      = sum(!is.na(data)),
    mean   = mean(data, na.rm = TRUE),
    sd     = sd(data,   na.rm = TRUE),
    median = median(data, na.rm = TRUE),
    min    = safe_min,
    max    = safe_max
  )
}

# Variable-specific display precision.
precision_by_var <- list(
  AGE   = list(default = 1, mean = 1, sd = 2, median = 0, min = 0, max = 0),
  BMIBL = list(default = 1, mean = 1, sd = 2, median = 1, min = 1, max = 1)
)

cont_digits <- function(x, key) {
  d <- precision_by_var[[x$variable]]
  if (is.null(d)) d <- list(default = 1, sd = 2)
  out <- d[[key]]
  if (is.null(out)) out <- d$default
  if (is.null(out)) out <- 1L
  as.integer(out)
}

format_cont_value <- function(x, key) {
  if (is.null(x)) return("")
  value <- x[[key]]
  if (is.null(value) || length(value) == 0L || is.na(value) || is.infinite(value))
    return("")
  sprintf(paste0("%.", cont_digits(x, key), "f"), value)
}

# Formatting rules are a pure formatter-layer concern.
# The compiler/calc layer only carries raw summary numbers.
cont_format_rules <- list(
  mean_sd = function(x) {
    if (is.null(x) || any(!is.finite(c(x$mean, x$sd)))) return("")
    sprintf(
      paste0("%.", cont_digits(x, "mean"), "f (%.", cont_digits(x, "sd"), "f)"),
      x$mean,
      x$sd
    )
  },
  median = function(x) format_cont_value(x, "median"),
  min    = function(x) format_cont_value(x, "min"),
  max    = function(x) format_cont_value(x, "max")
)

format_cont_stat <- function(x, stat_key) {
  f <- cont_format_rules[[stat_key]]
  if (is.null(f)) return("")
  f(x)
}

# Small wrappers bound in JSON; each delegates to formatter rules above.
format_mean_sd <- function(x) format_cont_stat(x, "mean_sd")
format_median  <- function(x) format_cont_stat(x, "median")
format_min     <- function(x) format_cont_stat(x, "min")
format_max     <- function(x) format_cont_stat(x, "max")

## Categorical (SEX already formatted upstream; no ksformat call here)
cat_summary <- function(data) {
  if (is.numeric(data))
    return(data.frame(SEX = character(0), n = integer(0), percent = numeric(0)))

  out <- data.frame(SEX = as.character(data), stringsAsFactors = FALSE) |>
    dplyr::filter(!is.na(SEX)) |>
    dplyr::count(SEX, sort = FALSE, name = "n")

  if (nrow(out) == 0L)
    return(data.frame(SEX = character(0), n = integer(0), percent = numeric(0)))

  dplyr::mutate(out, percent = 100 * n / sum(n))
}

format_sex_counts <- function(x) {
  if (is.null(x)) return("")
  paste(sprintf("%s: %d (%.1f%%)", x$SEX, x$n, x$percent), collapse = "; ")
}

# Expand SEX summary into table rows (.stat = SEX level) for display.
sex_rows_from_summary <- function(data, group_values, summary_fun) {
  rows <- lapply(group_values, function(g) {
    sx <- summary_fun(data$SEX[as.character(data$TRT01P) == g], g)
    if (is.null(sx) || nrow(sx) == 0L) {
      empty <- data.frame(SEX = character(0), stringsAsFactors = FALSE)
      empty[[g]] <- character(0)
      return(empty)
    }
    sx[[g]] <- sprintf("%d (%.1f%%)", sx$n, sx$percent)
    sx[, c("SEX", g), drop = FALSE]
  })

  merged <- Reduce(function(x, y) merge(x, y, by = "SEX", all = TRUE, sort = FALSE), rows)
  if (is.null(merged) || nrow(merged) == 0L) {
    out <- data.frame(.param = character(0), .stat = character(0), stringsAsFactors = FALSE)
    for (g in group_values) out[[g]] <- character(0)
    return(out)
  }

  sex_levels <- unique(as.character(data$SEX))
  sex_levels <- sex_levels[!is.na(sex_levels)]
  merged$SEX <- factor(merged$SEX, levels = sex_levels)
  merged <- merged[order(merged$SEX), , drop = FALSE]
  merged$SEX <- as.character(merged$SEX)

  for (g in group_values) {
    miss <- is.na(merged[[g]])
    if (any(miss)) merged[[g]][miss] <- "0 (0.0%)"
  }

  merged$.param <- "Sex"
  merged$.stat  <- merged$SEX
  merged$SEX <- NULL
  merged[, c(".param", ".stat", group_values), drop = FALSE]
}

## -- 4. JSON spec: apply_to + variables --------------------------------------
##
## FEATURE 1 - apply_to:
##   Binds each statistic to specific parameter IDs, eliminating blank cells.
##   "n" has no apply_to -> runs for both "cont" and "sex" parameters.
##   "mean_sd", "median", "min", "max" use apply_to: ["cont"]
##   "sex_summary" uses apply_to: ["sex"] and is expanded to SEX rows after eval.
##
## FEATURE 2 - variables (array):
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
        "fun":   "length"
      },
      "mean_sd": {
        "fun":      "cont_summary",
        "apply_to": ["cont"],
        "format":   { "type": "custom", "fun": "format_mean_sd" }
      },
      "median": {
        "fun":      "cont_summary",
        "apply_to": ["cont"],
        "format":   { "type": "custom", "fun": "format_median" }
      },
      "min": {
        "fun":      "cont_summary",
        "apply_to": ["cont"],
        "format":   { "type": "custom", "fun": "format_min" }
      },
      "max": {
        "fun":      "cont_summary",
        "apply_to": ["cont"],
        "format":   { "type": "custom", "fun": "format_max" }
      },
      "sex_summary": {
        "fun":      "cat_summary",
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

## -- 6. FEATURE 3: denominators (declarative + legacy cur_group) -------------
##
## Preferred: JSON `statistics.*.denominator` with type "external" (or n /
## n_distinct / data_n). The compiler joins / inlines denom and calls
## fun(var, denom = ...). Bind population tables (e.g. adsl_n) in the eval env.
##
## Legacy: calc functions may still close over env objects and use
## dplyr::cur_group() when you need custom multi-row cell logic (sex breakdown
## below). Prefer `denominator` for simple n (pct%) cells.

n_by_arm <- adsl_fmt |>
  dplyr::count(TRT01P, name = "N") |>
  dplyr::filter(!is.na(TRT01P))

cat("External population N (bind as adsl_n for denominator.type=external):\n")
print(n_by_arm)
cat("\n")

count_pct <- function(x, denom, ...) {
  n <- sum(!is.na(x))
  list(
    n = n,
    pct = if (length(denom) == 1L && isTRUE(denom > 0)) 100 * n / denom else NA_real_
  )
}

spec_denom <- '{
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
    "groups": {
      "by": ["TRT01P"],
      "format": { "TRT01P": "trt_fmt" }
    },
    "layout": { "row_structure": "parameter_stat" }
  }
}'

sex_pct_ext <- function(data) {
  if (is.numeric(data)) return(NULL)
  arm <- as.list(dplyr::cur_group())$TRT01P
  N   <- denom$N[denom$TRT01P == arm]     # legacy: denom bound from parent env
  if (length(N) == 0L || is.na(N)) N <- 1L
  data.frame(SEX = as.character(data), stringsAsFactors = FALSE) |>
    dplyr::filter(!is.na(SEX)) |>
    dplyr::count(SEX, sort = FALSE, name = "n") |>
    dplyr::mutate(percent = 100 * n / N)
}

format_sex_ext <- function(x) {
  if (is.null(x)) return("")
  paste(sprintf("%s: %d / N=%.1f%%", x$SEX, x$n, x$percent), collapse = "; ")
}

spec_ext <- gsub('"fun":      "cat_summary"',  '"fun": "sex_pct_ext"',
             gsub('"fun": "format_sex_counts"', '"fun": "format_sex_ext"',
                  demographics_spec))

## -- 7. Compiler-first workflow: generate dplyr/tidyr source ----------------

cat("-- Generated script for demographics spec -------------------------------\n")
code <- kst_compile(demographics_spec)
n_summarize <- lengths(regmatches(code, gregexpr("dplyr::summarize(", code, fixed = TRUE)))
cat("   summarize() calls:", n_summarize, "(single pass for parameter_stat)\n\n")
cat(code)

## -- 8. Optional: evaluate generated source manually -------------------------
##
## Run the compiled source in your own environment and inject any extra
## objects (e.g. denom) explicitly.

cat("\n\n-- Optional manual eval: demographics table ----------------------------\n")
env <- new.env(parent = environment())
env$data <- adsl_fmt
result <- eval(parse(text = code), envir = env)

group_values <- setdiff(names(result), c(".param", ".stat"))
sex_rows <- sex_rows_from_summary(
  adsl_fmt,
  group_values,
  function(x, group) cat_summary(x)
)
result <- dplyr::bind_rows(
  result[result$.stat != "sex_summary", , drop = FALSE],
  sex_rows
)
print(result, n = Inf, width = 140)

cat("\n-- Declarative denominator (external adsl_n → denom=) -----------------\n")
code_denom <- kst_compile(spec_denom)
cat(code_denom, "\n\n")
env_denom <- new.env(parent = environment())
env_denom$data <- adsl_fmt
env_denom$adsl_n <- n_by_arm
print(eval(parse(text = code_denom), envir = env_denom), width = 140)

cat("\n-- Optional manual eval: sex rows with legacy cur_group denominator ---\n")
code_ext <- kst_compile(spec_ext)
env_ext <- new.env(parent = environment())
env_ext$data <- adsl_fmt
env_ext$denom <- n_by_arm
# For compiler-only manual eval, expose a calc function whose closure sees denom.
env_ext$sex_pct_ext <- sex_pct_ext
environment(env_ext$sex_pct_ext) <- list2env(
  list(denom = n_by_arm),
  parent = environment(sex_pct_ext)
)
env_ext$format_sex_ext <- format_sex_ext
result_ext <- eval(parse(text = code_ext), envir = env_ext)

group_values_ext <- setdiff(names(result_ext), c(".param", ".stat"))
sex_rows_ext <- sex_rows_from_summary(
  adsl_fmt,
  group_values_ext,
  function(x, group) {
    N <- n_by_arm$N[n_by_arm$TRT01P == group]
    if (length(N) == 0L || is.na(N)) N <- 1L
    out <- cat_summary(x)
    out$percent <- 100 * out$n / N
    out
  }
)
result_ext <- dplyr::bind_rows(
  result_ext[result_ext$.stat != "sex_summary", , drop = FALSE],
  sex_rows_ext
)
print(result_ext[result_ext$.param == "Sex", ], width = 140)

## -- 9. Save generated source -------------------------------------------------

tmp <- tempfile(fileext = ".R")
kst_save(demographics_spec, tmp)
cat("\n-- Saved script header -------------------------------------------------\n")
cat(paste(head(readLines(tmp), 10L), collapse = "\n"), "\n")

tmp_ext <- tempfile(fileext = ".R")
kst_save(spec_ext, tmp_ext)
cat("\n-- Saved external-denominator script to: ", tmp_ext, "\n", sep = "")

tmp_denom <- tempfile(fileext = ".R")
kst_save(spec_denom, tmp_denom)
cat("-- Saved declarative-denominator script to: ", tmp_denom, "\n", sep = "")

fclear()
