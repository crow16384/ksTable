# tests/testthat/test-compile.R
# Tests for kst_compile() — generated script structure and content

# ── Helpers ───────────────────────────────────────────────────────────────────

demog_spec <- '{
  "schema_version": "1.0",
  "table_spec": {
    "parameter":  { "age": { "variable": "AGE", "label": "Age (years)" } },
    "statistics": {
      "n":       { "fun": "length", "label": "N" },
      "mean_sd": { "fun": "mean_sd", "label": "Mean (SD)",
                   "format": { "type": "custom", "fun": "format_mean_sd" } },
      "median":  { "fun": "median",
                   "args": { "na.rm": true },
                   "label": "Median",
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

# ── Return type ────────────────────────────────────────────────────────────────

test_that("kst_compile returns a single character string", {
  code <- kst_compile(demog_spec)
  expect_type(code, "character")
  expect_length(code, 1L)
  expect_true(nchar(code) > 0L)
})

# ── parameter_stat layout ─────────────────────────────────────────────────────

test_that("parameter_stat: one .chunks[[i]] per parameter x statistic", {
  code <- kst_compile(demog_spec)
  # 1 parameter × 3 statistics = 3 chunks
  expect_equal(lengths(regmatches(code, gregexpr("\\.chunks\\[\\[", code))), 3L)
})

test_that("parameter_stat: references data variable as bare symbol", {
  code <- kst_compile(demog_spec)
  expect_true(grepl("\\bAGE\\b", code))
})

test_that("parameter_stat: uses data |> pipeline", {
  code <- kst_compile(demog_spec)
  expect_true(grepl("data \\|>", code))
})

test_that("parameter_stat: group_by uses correct column", {
  code <- kst_compile(demog_spec)
  expect_true(grepl("group_by.*TRT01P", code))
})

test_that("parameter_stat: calc functions called as bare names", {
  code <- kst_compile(demog_spec)
  expect_true(grepl("length\\(AGE\\)", code))
  expect_true(grepl("mean_sd\\(AGE\\)", code))
  expect_false(grepl("calc_fns", code))   # no list lookup
})

test_that("parameter_stat: args appended to function call", {
  code <- kst_compile(demog_spec)
  expect_true(grepl("median\\(AGE, na\\.rm = TRUE\\)", code))
})

test_that("parameter_stat: list() wraps calc for custom format", {
  code <- kst_compile(demog_spec)
  expect_true(grepl("list\\(mean_sd\\(AGE\\)\\)", code))
})

test_that("parameter_stat: default formatter is as.character", {
  code <- kst_compile(demog_spec)
  expect_true(grepl("as\\.character\\(\\.value_raw\\)", code))
})

test_that("parameter_stat: custom formatter uses vapply with function name", {
  code <- kst_compile(demog_spec)
  expect_true(grepl("vapply\\(\\.value_raw, format_mean_sd", code))
  expect_false(grepl("format_fns", code))  # no list lookup
})

test_that("parameter_stat: sprintf format emitted correctly", {
  code <- kst_compile(demog_spec)
  expect_true(grepl('sprintf\\("%.1f", \\.value_raw\\)', code))
})

test_that("parameter_stat: param label emitted as string literal", {
  code <- kst_compile(demog_spec)
  expect_true(grepl('"Age \\(years\\)"', code))
})

test_that("parameter_stat: .value_raw dropped in mutate", {
  code <- kst_compile(demog_spec)
  expect_true(grepl("\\.value_raw\\s*=\\s*NULL", code))
})

test_that("parameter_stat: assembles with bind_rows + pivot_wider", {
  code <- kst_compile(demog_spec)
  expect_true(grepl("dplyr::bind_rows\\(\\.chunks\\)", code))
  expect_true(grepl("tidyr::pivot_wider", code))
})

test_that("parameter_stat: pivot uses correct names_from column", {
  code <- kst_compile(demog_spec)
  expect_true(grepl("names_from\\s*=\\s*c\\(TRT01P\\)", code))
})

# ── include_missing_levels ────────────────────────────────────────────────────

test_that(".drop = FALSE emitted when include_missing_levels is true", {
  spec <- '{
    "schema_version":"1.0",
    "table_spec":{
      "parameter":{"age":{"variable":"AGE"}},
      "statistics":{"n":{"fun":"length"}},
      "groups":{"by":["TRT"],"include_missing_levels":true},
      "layout":{"row_structure":"parameter_stat"}
    }
  }'
  code <- kst_compile(spec)
  expect_true(grepl("\\.drop = FALSE", code))
})

test_that(".drop = FALSE absent when include_missing_levels is false", {
  spec <- '{
    "schema_version":"1.0",
    "table_spec":{
      "parameter":{"age":{"variable":"AGE"}},
      "statistics":{"n":{"fun":"length"}},
      "groups":{"by":["TRT"],"include_missing_levels":false},
      "layout":{"row_structure":"parameter_stat"}
    }
  }'
  code <- kst_compile(spec)
  expect_false(grepl("\\.drop = FALSE", code))
})

# ── hierarchical layout ────────────────────────────────────────────────────────

test_that("hierarchical: emits parent and child chunks", {
  code <- kst_compile(ae_spec)
  expect_true(grepl("Parent level", code))
  expect_true(grepl("Child level", code))
  expect_true(grepl("\\.chunks\\[\\[1L\\]\\]", code))
  expect_true(grepl("\\.chunks\\[\\[2L\\]\\]", code))
})

test_that("hierarchical: parent groups by SOC; child groups by SOC+PT", {
  code <- kst_compile(ae_spec)
  expect_true(grepl("group_by.*TRT01P, AESOC[^,]", code))
  expect_true(grepl("group_by.*TRT01P, AESOC, AEDECOD", code))
})

test_that("hierarchical: .is_child column set correctly", {
  code <- kst_compile(ae_spec)
  expect_true(grepl("\\.is_child\\s*=\\s*FALSE", code))
  expect_true(grepl("\\.is_child\\s*=\\s*TRUE",  code))
})

test_that("hierarchical: arrange by .parent, .is_child, .row_label", {
  code <- kst_compile(ae_spec)
  expect_true(grepl("arrange\\(\\.parent, \\.is_child, \\.row_label\\)", code))
})

# ── multi-group ────────────────────────────────────────────────────────────────

test_that("two-way stratification: both group vars in group_by", {
  spec <- '{
    "schema_version":"1.0",
    "table_spec":{
      "parameter":{"age":{"variable":"AGE"}},
      "statistics":{"n":{"fun":"length"}},
      "groups":{"by":["TRT","SEX"]},
      "layout":{"row_structure":"parameter_stat"}
    }
  }'
  code <- kst_compile(spec)
  expect_true(grepl("group_by.*TRT, SEX", code))
  expect_true(grepl("names_from\\s*=\\s*c\\(TRT, SEX\\)", code))
})

# ── args edge cases ────────────────────────────────────────────────────────────

test_that("boolean args: true -> TRUE, false -> FALSE", {
  spec <- '{
    "schema_version":"1.0",
    "table_spec":{
      "parameter":{"x":{"variable":"X"}},
      "statistics":{"n":{"fun":"f","args":{"a":true,"b":false}}},
      "groups":{"by":["G"]},
      "layout":{"row_structure":"parameter_stat"}
    }
  }'
  code <- kst_compile(spec)
  expect_true(grepl("f\\(X, a = TRUE, b = FALSE\\)", code))
})

test_that("numeric args emitted correctly", {
  spec <- '{
    "schema_version":"1.0",
    "table_spec":{
      "parameter":{"x":{"variable":"X"}},
      "statistics":{"n":{"fun":"quantile","args":{"probs":0.25,"na.rm":true}}},
      "groups":{"by":["G"]},
      "layout":{"row_structure":"parameter_stat"}
    }
  }'
  code <- kst_compile(spec)
  expect_true(grepl("quantile\\(X, probs = 0\\.25, na\\.rm = TRUE\\)", code))
})

# ── label escaping ────────────────────────────────────────────────────────────

test_that("label with double quotes is escaped in generated code", {
  spec <- '{
    "schema_version":"1.0",
    "table_spec":{
      "parameter":{"x":{"variable":"X","label":"He said \\"hello\\""}},
      "statistics":{"n":{"fun":"length"}},
      "groups":{"by":["G"]},
      "layout":{"row_structure":"parameter_stat"}
    }
  }'
  code <- kst_compile(spec)
  # Should not produce unescaped double-quotes breaking R syntax
  expect_no_error(parse(text = code))
})

# ── valid R syntax ────────────────────────────────────────────────────────────

test_that("generated parameter_stat script parses as valid R", {
  code <- kst_compile(demog_spec)
  expect_no_error(parse(text = code))
})

test_that("generated hierarchical script parses as valid R", {
  code <- kst_compile(ae_spec)
  expect_no_error(parse(text = code))
})

# ── kst_save ──────────────────────────────────────────────────────────────────

test_that("kst_save creates a file", {
  tmp <- tempfile(fileext = ".R")
  on.exit(unlink(tmp))
  kst_save(demog_spec, tmp)
  expect_true(file.exists(tmp))
})

test_that("kst_save returns the normalised file path invisibly", {
  tmp <- tempfile(fileext = ".R")
  on.exit(unlink(tmp))
  result <- kst_save(demog_spec, tmp)
  expect_type(result, "character")
  expect_equal(result, normalizePath(tmp))
})

test_that("kst_save file contains the header comment block", {
  tmp <- tempfile(fileext = ".R")
  on.exit(unlink(tmp))
  kst_save(demog_spec, tmp)
  lines <- readLines(tmp)
  expect_true(any(grepl("Generated by ksTable", lines)))
  expect_true(any(grepl("Usage:", lines)))
  expect_true(any(grepl("source\\(", lines)))
})

test_that("kst_save embeds spec id and title when present", {
  spec_with_meta <- '{
    "schema_version": "1.0",
    "table_spec": {
      "id":    "my_table",
      "title": "My Test Table",
      "parameter":  { "x": { "variable": "X" } },
      "statistics": { "n": { "fun": "length" } },
      "groups":     { "by": ["G"] },
      "layout":     { "row_structure": "parameter_stat" }
    }
  }'
  tmp <- tempfile(fileext = ".R")
  on.exit(unlink(tmp))
  kst_save(spec_with_meta, tmp)
  content <- paste(readLines(tmp), collapse = "\n")
  expect_true(grepl("my_table", content))
  expect_true(grepl("My Test Table", content))
})

test_that("kst_save writes valid R code after the header", {
  tmp <- tempfile(fileext = ".R")
  on.exit(unlink(tmp))
  kst_save(demog_spec, tmp)
  expect_no_error(parse(file = tmp))
})

test_that("kst_save stops on existing file when overwrite = FALSE", {
  tmp <- tempfile(fileext = ".R")
  writeLines("existing content", tmp)
  on.exit(unlink(tmp))
  expect_error(kst_save(demog_spec, tmp, overwrite = FALSE),
               "already exists")
})

test_that("kst_save overwrites when overwrite = TRUE", {
  tmp <- tempfile(fileext = ".R")
  writeLines("existing content", tmp)
  on.exit(unlink(tmp))
  expect_no_error(kst_save(demog_spec, tmp, overwrite = TRUE))
  lines <- readLines(tmp)
  expect_false(any(lines == "existing content"))
})

test_that("sourcing a saved script produces a valid tibble", {
  tmp <- tempfile(fileext = ".R")
  on.exit(unlink(tmp))

  # Use a spec with only built-in functions so no user functions needed
  simple_spec <- '{
    "schema_version": "1.0",
    "table_spec": {
      "parameter":  { "age": { "variable": "AGE", "label": "Age" } },
      "statistics": {
        "n":    { "fun": "length", "label": "N" },
        "mean": { "fun": "mean", "args": { "na.rm": true }, "label": "Mean",
                  "format": { "type": "sprintf", "pattern": "%.1f" } }
      },
      "groups": { "by": ["TRT01P"] },
      "layout": { "row_structure": "parameter_stat" }
    }
  }'

  set.seed(1L)
  n   <- 60L
  dat <- data.frame(AGE    = round(rnorm(n, 45, 12)),
                    TRT01P = rep(c("A", "B", "C"), each = n %/% 3L))
  kst_save(simple_spec, tmp)

  env       <- new.env(parent = environment())
  env$data  <- dat
  result    <- source(tmp, local = env)$value

  expect_true(is.data.frame(result))
  expect_true(".param" %in% names(result))
  expect_equal(nrow(result), 2L)   # 1 param x 2 stats
})
