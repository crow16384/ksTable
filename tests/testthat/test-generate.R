# tests/testthat/test-generate.R
# End-to-end tests for kst_generate_table()

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

demog_spec <- '{
  "schema_version": "1.0",
  "table_spec": {
    "parameter":  { "age": { "variable": "AGE", "label": "Age (years)" } },
    "statistics": {
      "n":      { "fun": "length", "label": "N" },
      "mean":   { "fun": "mean",   "args": { "na.rm": true }, "label": "Mean",
                  "format": { "type": "sprintf", "pattern": "%.1f" } },
      "median": { "fun": "median", "args": { "na.rm": true }, "label": "Median",
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
    "statistics": { "n": { "fun": "length", "label": "n" } },
    "groups":  { "by": ["TRT01P"] },
    "layout":  { "row_structure": "hierarchical" }
  }
}'

# ── Return type and shape ─────────────────────────────────────────────────────

test_that("returns a data frame / tibble", {
  result <- kst_generate_table(demog_spec, test_adsl)
  expect_true(is.data.frame(result))
})

test_that("parameter_stat: row count = n_params × n_stats", {
  result <- kst_generate_table(demog_spec, test_adsl)
  # 1 parameter × 3 statistics = 3 rows
  expect_equal(nrow(result), 3L)
})

test_that("parameter_stat: has .param and .stat_label columns", {
  result <- kst_generate_table(demog_spec, test_adsl)
  expect_true(".param"      %in% names(result))
  expect_true(".stat_label" %in% names(result))
})

test_that("parameter_stat: group columns present as character", {
  result <- kst_generate_table(demog_spec, test_adsl)
  expect_true("Drug A"  %in% names(result))
  expect_true("Drug B"  %in% names(result))
  expect_true("Placebo" %in% names(result))
  # All value columns are character
  val_cols <- setdiff(names(result), c(".param", ".stat_label"))
  for (col in val_cols) expect_type(result[[col]], "character")
})

test_that("parameter_stat: param label matches spec", {
  result <- kst_generate_table(demog_spec, test_adsl)
  expect_true(all(result$.param == "Age (years)"))
})

test_that("parameter_stat: stat labels in correct order", {
  result <- kst_generate_table(demog_spec, test_adsl)
  expect_equal(result$.stat_label, c("N", "Mean", "Median"))
})

test_that("parameter_stat: N row contains integer count as string", {
  result <- kst_generate_table(demog_spec, test_adsl)
  n_row  <- result[result$.stat_label == "N", ]
  counts <- as.integer(c(n_row[["Drug A"]], n_row[["Drug B"]], n_row[["Placebo"]]))
  expect_true(all(!is.na(counts)))
  expect_equal(sum(counts), n)
})

test_that("parameter_stat: mean row values are numeric-looking strings", {
  result  <- kst_generate_table(demog_spec, test_adsl)
  mean_row <- result[result$.stat_label == "Mean", ]
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

  result <- kst_generate_table(spec, test_adsl)
  val <- result[["Drug A"]]
  expect_true(grepl("±", val))
})

# ── args in generated code ────────────────────────────────────────────────────

test_that("args passed to built-in function: median with na.rm", {
  result <- kst_generate_table(demog_spec, test_adsl)
  med_row <- result[result$.stat_label == "Median", ]
  vals    <- c(med_row[["Drug A"]], med_row[["Drug B"]], med_row[["Placebo"]])
  nums    <- suppressWarnings(as.numeric(vals))
  expect_true(all(!is.na(nums)))
  expect_true(all(nums > 0))
})

# ── hierarchical layout ────────────────────────────────────────────────────────

test_that("hierarchical: result has .parent, .is_child, .row_label columns", {
  result <- kst_generate_table(ae_spec, test_adae)
  expect_true(".parent"    %in% names(result))
  expect_true(".is_child"  %in% names(result))
  expect_true(".row_label" %in% names(result))
})

test_that("hierarchical: .is_child is logical", {
  result <- kst_generate_table(ae_spec, test_adae)
  expect_type(result$.is_child, "logical")
})

test_that("hierarchical: parent rows have .is_child = FALSE", {
  result   <- kst_generate_table(ae_spec, test_adae)
  parents  <- result[!result$.is_child, ]
  expected <- sort(unique(test_adae$AESOC))
  expect_equal(sort(parents$.row_label), expected)
})

test_that("hierarchical: child rows have .is_child = TRUE", {
  result   <- kst_generate_table(ae_spec, test_adae)
  children <- result[result$.is_child, ]
  expect_true(nrow(children) > 0L)
  expect_true(all(children$.row_label %in% unique(test_adae$AEDECOD)))
})

test_that("hierarchical: rows ordered parent-before-children within each SOC", {
  result <- kst_generate_table(ae_spec, test_adae)
  # For each SOC parent, parent row should come before its children
  for (soc in unique(test_adae$AESOC)) {
    soc_rows <- result[result$.parent == soc, ]
    parent_idx <- which(!soc_rows$.is_child)
    child_idx  <- which( soc_rows$.is_child)
    if (length(parent_idx) > 0L && length(child_idx) > 0L)
      expect_true(all(parent_idx < child_idx))
  }
})

test_that("hierarchical: value columns are character", {
  result   <- kst_generate_table(ae_spec, test_adae)
  val_cols <- setdiff(names(result), c(".parent", ".is_child", ".row_label", ".stat_label"))
  for (col in val_cols) expect_type(result[[col]], "character")
})

# ── isolation: intermediates not in caller env ────────────────────────────────

test_that("kst_generate_table does not pollute calling environment", {
  kst_generate_table(demog_spec, test_adsl)
  # Intermediates from the generated script must not appear in the caller's env
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
      "statistics": { "n": { "fun": "length", "label": "N" } },
      "groups":  { "by": ["TRT01P"] },
      "layout":  { "row_structure": "parameter_stat" }
    }
  }'

  result <- kst_generate_table(spec2, adsl2)
  # 2 parameters × 1 statistic = 2 rows
  expect_equal(nrow(result), 2L)
  expect_true("Age (years)" %in% result$.param)
  expect_true("BMI (kg/m2)" %in% result$.param)
})
