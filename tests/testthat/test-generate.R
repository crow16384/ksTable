# tests/testthat/test-generate.R
# End-to-end tests for run_compiled_table()

# ── Shared fixtures ───────────────────────────────────────────────────────────

set.seed(42L)
n <- 120L

test_adsl <- data.frame(
  AGE    = round(rnorm(n, 45, 12)),
  TRT01P = rep(c("Placebo", "Drug A", "Drug B"), each = n %/% 3L),
  stringsAsFactors = FALSE
)

set.seed(7L)
n_ae      <- 90L
ae_ids    <- sample(seq_len(n), n_ae, replace = TRUE)
test_adae <- data.frame(
  TRT01P  = test_adsl$TRT01P[ae_ids],
  AESOC   = sample(c("Cardiac disorders", "GI disorders"), n_ae, replace = TRUE),
  AEDECOD = sample(c("Nausea", "Headache", "Rash"), n_ae, replace = TRUE),
  stringsAsFactors = FALSE
)

run_compiled_table <- function(spec, data, envir = parent.frame()) {
  code <- kst_compile(spec)
  env  <- new.env(parent = envir)
  env$data <- data
  eval(parse(text = code), envir = env)
}

demog_spec <- '{
  "schema_version": "1.0",
  "table_spec": {
    "parameter":  { "age": { "variable": "AGE", "label": "Age (years)" } },
    "statistics": {
      "n":      { "fun": "length" },
      "mean":   { "fun": "mean",   "args": { "na.rm": true },
                  "format": { "type": "sprintf", "pattern": "%.1f" } },
      "median": { "fun": "median", "args": { "na.rm": true },
                  "format": { "type": "sprintf", "pattern": "%.1f" } }
    },
    "groups":  { "by": ["TRT01P"] },
    "layout":  { "row_structure": "parameter_stat" }
  }
}'

ae_spec <- '{
  "schema_version": "1.0",
  "table_spec": {
    "parameter": {
      "soc": {
        "variable": "AESOC",
        "nested": { "pt": { "variable": "AEDECOD" } }
      }
    },
    "statistics": { "n": { "fun": "length" } },
    "groups":  { "by": ["TRT01P"] },
    "layout":  { "row_structure": "hierarchical" }
  }
}'

# ── Return type and shape ─────────────────────────────────────────────────────

test_that("returns a data frame / tibble", {
  result <- run_compiled_table(demog_spec, test_adsl)
  expect_true(is.data.frame(result))
})

test_that("parameter_stat: row count = n_params × n_stats", {
  result <- run_compiled_table(demog_spec, test_adsl)
  # 1 parameter × 3 statistics = 3 rows
  expect_equal(nrow(result), 3L)
})

test_that("parameter_stat: has .param and .stat columns", {
  result <- run_compiled_table(demog_spec, test_adsl)
  expect_true(".param"      %in% names(result))
  expect_true(".stat" %in% names(result))
})

test_that("parameter_stat: group columns present; formatted values are character", {
  result <- run_compiled_table(demog_spec, test_adsl)
  expect_true("Drug A"  %in% names(result))
  expect_true("Drug B"  %in% names(result))
  expect_true("Placebo" %in% names(result))
  # demog_spec mixes sprintf/custom formats → character value columns
  val_cols <- setdiff(names(result), c(".param", ".stat"))
  for (col in val_cols) expect_type(result[[col]], "character")
})

test_that("parameter_stat: param label matches spec", {
  result <- run_compiled_table(demog_spec, test_adsl)
  expect_true(all(result$.param == "Age (years)"))
})

test_that("parameter_stat: stat keys in correct order", {
  result <- run_compiled_table(demog_spec, test_adsl)
  expect_equal(result$.stat, c("n", "mean", "median"))
})

test_that("parameter_stat: n row contains integer count as string", {
  result <- run_compiled_table(demog_spec, test_adsl)
  n_row  <- result[result$.stat == "n", ]
  counts <- as.integer(c(n_row[["Drug A"]], n_row[["Drug B"]], n_row[["Placebo"]]))
  expect_true(all(!is.na(counts)))
  expect_equal(sum(counts), n)
})

test_that("parameter_stat: mean row values are numeric-looking strings", {
  result  <- run_compiled_table(demog_spec, test_adsl)
  mean_row <- result[result$.stat == "mean", ]
  # Each value should be parseable as a number with one decimal
  vals <- c(mean_row[["Drug A"]], mean_row[["Drug B"]], mean_row[["Placebo"]])
  expect_true(all(grepl("^[0-9]+\\.[0-9]$", vals)))
})

# ── custom format function resolved from calling env ─────────────────────────

test_that("custom format function resolved from caller env", {
  spec <- '{
    "schema_version": "1.0",
    "table_spec": {
      "parameter":  { "age": { "variable": "AGE" } },
      "statistics": {
        "ms": { "fun": "my_mean_sd",
                "format": { "type": "custom", "fun": "my_fmt" } }
      },
      "groups":  { "by": ["TRT01P"] },
      "layout":  { "row_structure": "parameter_stat" }
    }
  }'

  my_mean_sd <- function(data) list(m = mean(data, na.rm = TRUE),
                                    s = sd(data,   na.rm = TRUE))
  my_fmt     <- function(x) sprintf("%.1f\u00b1%.1f", x$m, x$s)

  result <- run_compiled_table(spec, test_adsl)
  val <- result[["Drug A"]]
  expect_true(grepl("±", val))
})

# ── args in generated code ────────────────────────────────────────────────────

test_that("args passed to built-in function: median with na.rm", {
  result <- run_compiled_table(demog_spec, test_adsl)
  med_row <- result[result$.stat == "median", ]
  vals    <- c(med_row[["Drug A"]], med_row[["Drug B"]], med_row[["Placebo"]])
  nums    <- suppressWarnings(as.numeric(vals))
  expect_true(all(!is.na(nums)))
  expect_true(all(nums > 0))
})

# ── hierarchical layout ────────────────────────────────────────────────────────

test_that("hierarchical: result has .parent, .is_child, .row_label columns", {
  result <- run_compiled_table(ae_spec, test_adae)
  expect_true(".parent"    %in% names(result))
  expect_true(".is_child"  %in% names(result))
  expect_true(".row_label" %in% names(result))
})

test_that("hierarchical: .is_child is logical", {
  result <- run_compiled_table(ae_spec, test_adae)
  expect_type(result$.is_child, "logical")
})

test_that("hierarchical: parent rows have .is_child = FALSE", {
  result   <- run_compiled_table(ae_spec, test_adae)
  parents  <- result[!result$.is_child, ]
  expected <- sort(unique(test_adae$AESOC))
  expect_equal(sort(parents$.row_label), expected)
})

test_that("hierarchical: child rows have .is_child = TRUE", {
  result   <- run_compiled_table(ae_spec, test_adae)
  children <- result[result$.is_child, ]
  expect_true(nrow(children) > 0L)
  expect_true(all(children$.row_label %in% unique(test_adae$AEDECOD)))
})

test_that("hierarchical: rows ordered parent-before-children within each SOC", {
  result <- run_compiled_table(ae_spec, test_adae)
  # For each SOC parent, parent row should come before its children
  for (soc in unique(test_adae$AESOC)) {
    soc_rows <- result[result$.parent == soc, ]
    parent_idx <- which(!soc_rows$.is_child)
    child_idx  <- which( soc_rows$.is_child)
    if (length(parent_idx) > 0L && length(child_idx) > 0L)
      expect_true(all(parent_idx < child_idx))
  }
})

test_that("hierarchical: value columns keep raw type when no format", {
  result   <- run_compiled_table(ae_spec, test_adae)
  val_cols <- setdiff(names(result), c(".parent", ".is_child", ".row_label", ".stat"))
  for (col in val_cols) expect_type(result[[col]], "integer")
})

# ── isolation: intermediates not in caller env ────────────────────────────────

test_that("compiled eval does not pollute calling environment", {
  run_compiled_table(demog_spec, test_adsl)
  # Intermediates from the generated script must not appear in the caller's env
  expect_false(".raw"    %in% ls())
  expect_false(".chunks" %in% ls())
  expect_false(".long"   %in% ls())
  expect_false("data"    %in% ls(envir = parent.env(environment())))
})

# ── multiple parameters ────────────────────────────────────────────────────────

test_that("multiple parameters produce combined rows", {
  adsl2 <- test_adsl
  adsl2$BMIBL <- round(rnorm(n, 26, 5), 1)

  spec2 <- '{
    "schema_version": "1.0",
    "table_spec": {
      "parameter": {
        "age": { "variable": "AGE",   "label": "Age (years)"   },
        "bmi": { "variable": "BMIBL", "label": "BMI (kg/m2)" }
      },
      "statistics": { "n": { "fun": "length" } },
      "groups":  { "by": ["TRT01P"] },
      "layout":  { "row_structure": "parameter_stat" }
    }
  }'

  result <- run_compiled_table(spec2, adsl2)
  # 2 parameters × 1 statistic = 2 rows
  expect_equal(nrow(result), 2L)
  expect_true("Age (years)" %in% result$.param)
  expect_true("BMI (kg/m2)" %in% result$.param)
})

# ── variables array ───────────────────────────────────────────────────────────

test_that("variables array: each column produces its own row block", {
  adsl2 <- test_adsl
  adsl2$BMIBL <- round(rnorm(n, 26, 5), 1)

  spec <- '{
    "schema_version": "1.0",
    "table_spec": {
      "parameter": {
        "cont": { "variables": ["AGE", "BMIBL"], "labels": ["Age", "BMI"] }
      },
      "statistics": { "n": { "fun": "length" } },
      "groups":  { "by": ["TRT01P"] },
      "layout":  { "row_structure": "parameter_stat" }
    }
  }'
  result <- run_compiled_table(spec, adsl2)
  expect_equal(nrow(result), 2L)          # 2 variables × 1 stat
  expect_setequal(result$.param, c("Age", "BMI"))
})

test_that("variables array: label defaults to variable name", {
  adsl2 <- test_adsl
  adsl2$BMIBL <- round(rnorm(n, 26, 5), 1)

  spec <- '{
    "schema_version": "1.0",
    "table_spec": {
      "parameter": { "cont": { "variables": ["AGE", "BMIBL"] } },
      "statistics": { "n": { "fun": "length" } },
      "groups":  { "by": ["TRT01P"] },
      "layout":  { "row_structure": "parameter_stat" }
    }
  }'
  result <- run_compiled_table(spec, adsl2)
  expect_setequal(result$.param, c("AGE", "BMIBL"))
})

# ── apply_to ──────────────────────────────────────────────────────────────────

test_that("apply_to restricts a statistic to listed parameter IDs", {
  spec <- '{
    "schema_version": "1.0",
    "table_spec": {
      "parameter": {
        "age": { "variable": "AGE", "label": "Age" },
        "sex": { "variable": "TRT01P", "label": "Arm" }
      },
      "statistics": {
        "n":    { "fun": "length" },
        "mean": { "fun": "mean", "args": { "na.rm": true },
                  "apply_to": ["age"],
                  "format": { "type": "sprintf", "pattern": "%.1f" } }
      },
      "groups":  { "by": ["TRT01P"] },
      "layout":  { "row_structure": "parameter_stat" }
    }
  }'
  result <- run_compiled_table(spec, test_adsl)
  # age: n + mean (2 rows); arm: n only (1 row) => 3 rows total
  expect_equal(nrow(result), 3L)
  mean_rows <- result[result$.stat == "mean", ]
  expect_equal(nrow(mean_rows), 1L)
  expect_equal(mean_rows$.param, "Age")
})

test_that("apply_to accepts variable names as well as parameter IDs", {
  spec <- '{
    "schema_version": "1.0",
    "table_spec": {
      "parameter": { "age": { "variable": "AGE", "label": "Age" } },
      "statistics": {
        "mean": { "fun": "mean", "args": { "na.rm": true },
                  "apply_to": ["AGE"],
                  "format": { "type": "sprintf", "pattern": "%.1f" } }
      },
      "groups":  { "by": ["TRT01P"] },
      "layout":  { "row_structure": "parameter_stat" }
    }
  }'
  result <- run_compiled_table(spec, test_adsl)
  expect_equal(nrow(result), 1L)
  expect_equal(result$.stat, "mean")
})

# ── parent-environment objects in compiled execution ─────────────────────────

test_that("parent-environment objects are visible to calc functions", {
  spec <- '{
    "schema_version": "1.0",
    "table_spec": {
      "parameter":  { "age": { "variable": "AGE", "label": "Age" } },
      "statistics": { "pct_over": { "fun": "pct_over_thresh" } },
      "groups":  { "by": ["TRT01P"] },
      "layout":  { "row_structure": "parameter_stat" }
    }
  }'
  cutoff <- 50
  pct_over_thresh <- function(data)
    sprintf("%.1f%%", 100 * mean(data > cutoff, na.rm = TRUE))

  result <- run_compiled_table(spec, test_adsl)
  expect_true(is.data.frame(result))
  vals <- unlist(result[, setdiff(names(result), c(".param", ".stat"))])
  expect_true(all(grepl("%$", vals)))
})

test_that("denominator lookup via cur_group works from parent env", {
  denom <- data.frame(TRT01P = c("Placebo", "Drug A", "Drug B"),
                      N = c(100L, 200L, 300L),
                      stringsAsFactors = FALSE)
  spec <- '{
    "schema_version": "1.0",
    "table_spec": {
      "parameter":  { "age": { "variable": "AGE", "label": "Age" } },
      "statistics": { "pct": { "fun": "n_over_denom" } },
      "groups":  { "by": ["TRT01P"] },
      "layout":  { "row_structure": "parameter_stat" }
    }
  }'
  n_over_denom <- function(data) {
    arm <- as.list(dplyr::cur_group())$TRT01P
    N   <- denom$N[denom$TRT01P == arm]
    sprintf("%d/%d", length(data), N)
  }
  result <- run_compiled_table(spec, test_adsl)
  expect_true(grepl("/200$", result[["Drug A"]]))
})

# ── Declarative denominator (statistics.*.denominator) ────────────────────────

count_pct <- function(x, denom, ...) {
  n <- sum(!is.na(x))
  list(
    n = n,
    pct = if (length(denom) == 1L && isTRUE(denom > 0)) 100 * n / denom else NA_real_
  )
}

test_that("denominator external resolves population N via join", {
  skip_if_not_installed("glue")
  adsl_n <- data.frame(
    TRT01P = c("Placebo", "Drug A", "Drug B"),
    N = c(100L, 200L, 300L),
    stringsAsFactors = FALSE
  )
  spec <- '{
    "schema_version": "1.0",
    "table_spec": {
      "parameter":  { "age": { "variable": "AGE", "label": "Age" } },
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
      "groups":  { "by": ["TRT01P"] },
      "layout":  { "row_structure": "parameter_stat" }
    }
  }'
  result <- run_compiled_table(spec, test_adsl)
  # 40 subjects per arm in test_adsl; Drug A denom 200 → 20%
  expect_equal(result[["Drug A"]], "40 (20%)")
})

test_that("denominator data_n uses subset of groups.by", {
  skip_if_not_installed("glue")
  df <- data.frame(
    USUBJID = c("S1", "S2", "S3", "S4", "S5", "S6"),
    TRT01P  = c("A", "A", "A", "B", "B", "B"),
    SEX     = c("F", "F", "M", "F", "M", "M"),
    FLAG    = c(1L, 1L, 1L, 1L, 1L, 1L),
    stringsAsFactors = FALSE
  )
  # Within TRT A: 3 distinct subjects; F among A: 2 rows → pct = 200/3
  spec <- '{
    "schema_version": "1.0",
    "table_spec": {
      "parameter":  { "flag": { "variable": "FLAG", "label": "Flag" } },
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
      "groups":  { "by": ["TRT01P", "SEX"] },
      "layout":  { "row_structure": "parameter_stat" }
    }
  }'
  result <- run_compiled_table(spec, df)
  expect_true("A_F" %in% names(result))
  expect_match(result[["A_F"]], "^2 \\(66\\.6")
})

test_that("denominator type n uses dplyr::n() as denom", {
  skip_if_not_installed("glue")
  df <- data.frame(
    TRT01P = c("A", "A", "A", "B", "B"),
    SEX    = c("F", "F", "M", "F", "M"),
    stringsAsFactors = FALSE
  )
  spec <- '{
    "schema_version": "1.0",
    "table_spec": {
      "parameter":  { "sex": { "variable": "SEX", "label": "Sex" } },
      "statistics": {
        "n_pct": {
          "fun": "count_pct",
          "denominator": { "type": "n" },
          "format": { "type": "template", "pattern": "{n} ({pct}%)" }
        }
      },
      "groups":  { "by": ["TRT01P"] },
      "layout":  { "row_structure": "parameter_stat" }
    }
  }'
  result <- run_compiled_table(spec, df)
  # Within arm A, n()=3 and all SEX non-missing → 3 (100%)
  expect_equal(result[["A"]], "3 (100%)")
})

test_that("stats without denominator still compile and eval", {
  result <- run_compiled_table(demog_spec, test_adsl)
  expect_true(is.data.frame(result))
  expect_true(nrow(result) >= 1L)
})

# ── include_missing_levels + metadata ─────────────────────────────────────────

test_that("include_missing_levels keeps empty factor levels after metadata", {
  adsl <- test_adsl
  adsl$TRT01P <- factor(adsl$TRT01P, levels = c("Placebo", "Drug A", "Drug B", "Drug C"))
  # Drop Drug C from the observed data but keep the level
  adsl <- adsl[adsl$TRT01P != "Drug C", , drop = FALSE]
  adsl$TRT01P <- factor(adsl$TRT01P, levels = c("Placebo", "Drug A", "Drug B", "Drug C"))

  meta <- kst_extract_metadata(adsl, "TRT01P")
  adsl <- kst_apply_metadata(adsl, meta)

  spec <- '{
    "schema_version": "1.0",
    "table_spec": {
      "parameter":  { "age": { "variable": "AGE", "label": "Age" } },
      "statistics": { "n": { "fun": "length" } },
      "groups":  { "by": ["TRT01P"], "include_missing_levels": true },
      "layout":  { "row_structure": "parameter_stat" }
    }
  }'
  result <- run_compiled_table(spec, adsl)
  expect_true("Drug C" %in% names(result))
  expect_equal(result[["Drug C"]], 0L)
})

test_that("template format requires glue at eval time", {
  skip_if_not_installed("glue")
  mean_sd <- function(x) list(mean = mean(x, na.rm = TRUE), sd = sd(x, na.rm = TRUE))
  spec <- '{
    "schema_version": "1.0",
    "table_spec": {
      "parameter":  { "age": { "variable": "AGE", "label": "Age" } },
      "statistics": {
        "mean_sd": {
          "fun": "mean_sd",
          "format": { "type": "template", "pattern": "{mean} ({sd})" }
        }
      },
      "groups":  { "by": ["TRT01P"] },
      "layout":  { "row_structure": "parameter_stat" }
    }
  }'
  result <- run_compiled_table(spec, test_adsl)
  expect_equal(nrow(result), 1L)
  expect_true(all(grepl("\\(", result[["Placebo"]])))
})
