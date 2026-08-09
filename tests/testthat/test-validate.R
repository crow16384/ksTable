# tests/testthat/test-validate.R
# Tests for kst_validate_spec()

# ── Helpers ───────────────────────────────────────────────────────────────────

minimal_spec <- function(overrides = list()) {
  base <- list(
    schema_version = "1.0",
    table_spec = list(
      parameter  = list(age = list(variable = "AGE")),
      statistics = list(n = list(fun = "length")),
      groups     = list(by = list("TRT")),
      layout     = list(row_structure = "parameter_stat")
    )
  )
  # Apply overrides (simple one-level)
  for (nm in names(overrides)) base$table_spec[[nm]] <- overrides[[nm]]
  jsonlite::toJSON(base, auto_unbox = TRUE)
}

# ── Valid specs ────────────────────────────────────────────────────────────────

test_that("minimal valid spec passes", {
  r <- kst_validate_spec(minimal_spec())
  expect_true(r$valid)
  expect_length(r$errors, 0L)
  expect_true(r$engine %in% c("jsonvalidate", "manual"))
})

test_that("spec with all format types passes", {
  spec <- '{
    "schema_version": "1.0",
    "table_spec": {
      "parameter":  { "age": { "variable": "AGE" } },
      "statistics": {
        "n":       { "fun": "length" },
        "mean":    { "fun": "mean",    "args": { "na.rm": true },
                     "format": { "type": "sprintf",  "pattern": "%.1f" } },
        "mean_sd": { "fun": "mean_sd",
                     "format": { "type": "custom",   "fun": "format_mean_sd" } },
        "grp":     { "fun": "median",
                     "format": { "type": "template", "pattern": "{v}" } },
        "trt":     { "fun": "identity",
                     "format": { "type": "ksformat", "format_name": "trt_fmt" } }
      },
      "groups":  { "by": ["TRT"], "include_missing_levels": false },
      "layout":  { "row_structure": "parameter_stat", "column_structure": "groups" }
    }
  }'
  r <- kst_validate_spec(spec)
  expect_true(r$valid)
  expect_length(r$errors, 0L)
})

test_that("statistics apply_to is accepted", {
  spec <- '{
    "schema_version": "1.0",
    "table_spec": {
      "parameter": {
        "cont": { "variables": ["AGE", "BMIBL"] },
        "sex":  { "variable": "SEX" }
      },
      "statistics": {
        "n":       { "fun": "length" },
        "mean_sd": { "fun": "mean_sd", "apply_to": ["cont"] },
        "sex_n":   { "fun": "length",  "apply_to": ["sex"] }
      },
      "groups":  { "by": ["TRT"] },
      "layout":  { "row_structure": "parameter_stat" }
    }
  }'
  r <- kst_validate_spec(spec)
  expect_true(r$valid)
  expect_length(r$errors, 0L)
})

test_that("hierarchical spec with nested parameter passes", {
  spec <- '{
    "schema_version": "1.0",
    "table_spec": {
      "parameter": {
        "soc": {
          "variable": "AESOC",
          "nested": { "pt": { "variable": "AEDECOD" } }
        }
      },
      "statistics": { "n": { "fun": "length" } },
      "groups":     { "by": ["TRT"] },
      "layout":     { "row_structure": "hierarchical" }
    }
  }'
  r <- kst_validate_spec(spec)
  expect_true(r$valid)
})

# ── Missing required fields ────────────────────────────────────────────────────

test_that("missing table_spec fails", {
  r <- kst_validate_spec('{"schema_version": "1.0"}')
  expect_false(r$valid)
  expect_true(any(grepl("table_spec", r$errors)))
})

test_that("missing parameter fails", {
  r <- kst_validate_spec(minimal_spec(list(parameter = NULL)))
  expect_false(r$valid)
  expect_true(any(grepl("parameter", r$errors)))
})

test_that("missing statistics fails", {
  r <- kst_validate_spec(minimal_spec(list(statistics = NULL)))
  expect_false(r$valid)
  expect_true(any(grepl("statistics", r$errors)))
})

test_that("missing groups fails", {
  r <- kst_validate_spec(minimal_spec(list(groups = NULL)))
  expect_false(r$valid)
  expect_true(any(grepl("groups", r$errors)))
})

test_that("missing layout fails", {
  r <- kst_validate_spec(minimal_spec(list(layout = NULL)))
  expect_false(r$valid)
  expect_true(any(grepl("layout", r$errors)))
})

test_that("missing statistics.fun fails", {
  spec <- minimal_spec(list(statistics = list(n = list(args = list(na.rm = TRUE)))))
  r <- kst_validate_spec(spec)
  expect_false(r$valid)
  expect_true(any(grepl("fun", r$errors)))
})

test_that("statistics.label is rejected", {
  spec <- minimal_spec(list(statistics = list(n = list(fun = "length", label = "N"))))
  r <- kst_validate_spec(spec)
  expect_false(r$valid)
  expect_true(any(grepl("additional properties|additionalProperty|label", r$errors)))
})

test_that("missing parameter.variable fails", {
  spec <- minimal_spec(list(parameter = list(age = list(label = "Age"))))
  r <- kst_validate_spec(spec)
  expect_false(r$valid)
  expect_true(any(grepl("variable", r$errors)))
})

test_that("invalid row_structure fails", {
  spec <- minimal_spec(list(layout = list(row_structure = "not_a_layout")))
  r <- kst_validate_spec(spec)
  expect_false(r$valid)
  expect_true(any(grepl("row_structure", r$errors)))
})

# ── Format spec conditional requirements ──────────────────────────────────────

test_that("sprintf without pattern fails", {
  spec <- minimal_spec(list(
    statistics = list(n = list(fun = "mean", format = list(type = "sprintf")))
  ))
  r <- kst_validate_spec(spec)
  expect_false(r$valid)
  expect_true(any(grepl("pattern", r$errors)))
})

test_that("custom without fun fails", {
  spec <- minimal_spec(list(
    statistics = list(n = list(fun = "mean_sd", format = list(type = "custom")))
  ))
  r <- kst_validate_spec(spec)
  expect_false(r$valid)
  expect_true(any(grepl("fun", r$errors)))
})

test_that("template without pattern fails", {
  spec <- minimal_spec(list(
    statistics = list(n = list(fun = "f", format = list(type = "template")))
  ))
  r <- kst_validate_spec(spec)
  expect_false(r$valid)
  expect_true(any(grepl("pattern", r$errors)))
})

test_that("ksformat without format_name fails", {
  spec <- minimal_spec(list(
    statistics = list(n = list(fun = "f", format = list(type = "ksformat")))
  ))
  r <- kst_validate_spec(spec)
  expect_false(r$valid)
  expect_true(any(grepl("format_name", r$errors)))
})

# ── SR-1 injection prevention ─────────────────────────────────────────────────

test_that("injected variable is rejected", {
  spec <- minimal_spec(list(
    parameter = list(age = list(variable = 'AGE); system("echo INJECTED")'))
  ))
  r <- kst_validate_spec(spec)
  expect_false(r$valid)
  expect_true(any(grepl("not a valid R identifier", r$errors)))
})

test_that("injected fun is rejected", {
  spec <- minimal_spec(list(
    statistics = list(n = list(fun = "rm -rf /"))
  ))
  r <- kst_validate_spec(spec)
  expect_false(r$valid)
})

test_that("injected groups$by is rejected", {
  spec <- minimal_spec(list(groups = list(by = list("TRT); stop()"))))
  r <- kst_validate_spec(spec)
  expect_false(r$valid)
})

test_that("injected args key is rejected", {
  spec <- minimal_spec(list(
    statistics = list(n = list(fun = "median",
                               args = list("na.rm); stop()" = TRUE)))
  ))
  r <- kst_validate_spec(spec)
  expect_false(r$valid)
})

test_that("valid dot-containing identifier is accepted", {
  spec <- minimal_spec(list(
    statistics = list(n = list(fun = "na.rm.check"))  # na.rm is valid R identifier
  ))
  r <- kst_validate_spec(spec)
  expect_true(r$valid)
})

# ── File path input ────────────────────────────────────────────────────────────

test_that("nonexistent file path fails gracefully", {
  r <- kst_validate_spec("/no/such/file.json")
  expect_false(r$valid)
  expect_true(any(grepl("[Ff]ile|exist|path|JSON", r$errors)))
})
