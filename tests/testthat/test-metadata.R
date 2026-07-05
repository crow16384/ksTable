# tests/testthat/test-metadata.R
# Tests for kst_extract_metadata() and kst_apply_metadata()

# ── Shared fixture ────────────────────────────────────────────────────────────

test_df <- data.frame(
  TRT  = c("A", "B", "A", "B", "A"),
  AGE  = c(30, 40, 50, 60, 70),
  SEX  = factor(c("M", "F", "M", "M", "F"), levels = c("M", "F")),
  stringsAsFactors = FALSE
)

# ── kst_extract_metadata: no ksformat ─────────────────────────────────────────

test_that("returns one entry per variable", {
  meta <- kst_extract_metadata(test_df, c("TRT", "AGE"))
  expect_named(meta, c("TRT", "AGE"))
})

test_that("type field reflects R class", {
  meta <- kst_extract_metadata(test_df, "TRT")
  expect_equal(meta$TRT$type, "character")

  meta2 <- kst_extract_metadata(test_df, "SEX")
  expect_equal(meta2$SEX$type, "factor")
})

test_that("levels: character column -> sorted distinct values", {
  meta <- kst_extract_metadata(test_df, "TRT")
  expect_equal(meta$TRT$levels, c("A", "B"))
})

test_that("levels: factor column -> existing factor levels", {
  meta <- kst_extract_metadata(test_df, "SEX")
  expect_equal(meta$SEX$levels, c("M", "F"))
})

test_that("format_name is NULL when format_map is empty", {
  meta <- kst_extract_metadata(test_df, "TRT")
  expect_null(meta$TRT$format_name)
})

test_that("warns on unknown variable", {
  expect_warning(kst_extract_metadata(test_df, "NOPE"),
                 "not found in data")
})

test_that("format_map stores format_name in result", {
  meta <- kst_extract_metadata(test_df, "TRT",
                                format_map = list(TRT = "some_fmt"))
  expect_equal(meta$TRT$format_name, "some_fmt")
})

# ── kst_extract_metadata: ksformat integration ────────────────────────────────

test_that("with ksformat: levels from fput(codes, fmt) in registration order", {
  skip_if_not_installed("ksformat")
  library(ksformat)
  on.exit(ksformat::fclear(), add = TRUE)

  ksformat::fnew("A" = "Drug A", "B" = "Placebo", "C" = "Drug B (absent)",
                 name = "trt_test")

  meta <- kst_extract_metadata(test_df, "TRT",
                                format_map = list(TRT = "trt_test"))
  expect_equal(meta$TRT$levels,
               c("Drug A", "Placebo", "Drug B (absent)"))   # registration order
  expect_equal(meta$TRT$format_name, "trt_test")
})

# ── kst_apply_metadata: no ksformat ──────────────────────────────────────────

test_that("converts column to factor with given levels", {
  meta <- list(TRT = list(type = "character",
                           levels = c("B", "A"),    # custom order
                           format_name = NULL))
  result <- kst_apply_metadata(test_df, meta)
  expect_s3_class(result$TRT, "factor")
  expect_equal(levels(result$TRT), c("B", "A"))
})

test_that("absent level is present in factor levels", {
  meta <- list(TRT = list(type = "character",
                           levels = c("A", "B", "C"),   # "C" absent from data
                           format_name = NULL))
  result <- kst_apply_metadata(test_df, meta)
  expect_equal(levels(result$TRT), c("A", "B", "C"))
  expect_false("C" %in% result$TRT)
  expect_true( is.na(factor("C", levels = c("A", "B")) ))  # sanity check
})

test_that("ignores variables not present in data", {
  meta   <- list(NOPE = list(type = "character", levels = c("x"), format_name = NULL))
  result <- kst_apply_metadata(test_df, meta)
  expect_false("NOPE" %in% names(result))
})

# ── kst_apply_metadata: ksformat integration ──────────────────────────────────

test_that("with ksformat: fput converts codes to labels before factoring", {
  skip_if_not_installed("ksformat")
  library(ksformat)
  on.exit(ksformat::fclear(), add = TRUE)

  ksformat::fnew("A" = "Drug A", "B" = "Placebo", name = "trt_apply_test")

  meta <- list(TRT = list(type = "character",
                           levels = c("Drug A", "Placebo"),
                           format_name = "trt_apply_test"))
  result <- kst_apply_metadata(test_df, meta)

  expect_s3_class(result$TRT, "factor")
  expect_equal(levels(result$TRT), c("Drug A", "Placebo"))
  expect_true("Drug A"  %in% result$TRT)
  expect_true("Placebo" %in% result$TRT)
  expect_false("A" %in% as.character(result$TRT))   # raw codes gone
})

# ── round-trip: extract + apply ───────────────────────────────────────────────

test_that("round-trip: character var -> factor with correct levels and values", {
  skip_if_not_installed("ksformat")
  library(ksformat)
  on.exit(ksformat::fclear(), add = TRUE)

  ksformat::fnew("A" = "Drug A", "B" = "Placebo", "C" = "Drug B",
                 name = "trt_rt")

  meta   <- kst_extract_metadata(test_df, "TRT",
                                  format_map = list(TRT = "trt_rt"))
  result <- kst_apply_metadata(test_df, meta)

  expect_equal(levels(result$TRT), c("Drug A", "Placebo", "Drug B"))
  # "C" was never in test_df, so "Drug B" must not appear as a value
  expect_false("Drug B" %in% as.character(result$TRT))
  # Codes "A"/"B" replaced with labels
  expect_false("A" %in% as.character(result$TRT))
  expect_false("B" %in% as.character(result$TRT))
})
