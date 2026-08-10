# tests/testthat/test-spec-builder-helpers.R
# Unit tests for Spec Builder JSON helpers (no Shiny session required)

test_that("spec_to_json / json_to_spec roundtrip", {
  sp <- spec_empty()
  json <- spec_to_json(sp)
  expect_type(json, "character")
  expect_true(grepl("table_spec", json))
  parsed <- json_to_spec(json)
  expect_true(parsed$ok)
  expect_equal(parsed$spec$schema_version, "1.0")
  expect_equal(parsed$spec$table_spec$layout$row_structure, "parameter_stat")
  expect_equal(parsed$spec$table_spec$parameter$age$variable, "AGE")
})

test_that("json_to_spec rejects bad input", {
  expect_false(json_to_spec("")$ok)
  expect_false(json_to_spec("{")$ok)
  expect_false(json_to_spec('{"foo": 1}')$ok)
  expect_match(json_to_spec('{"foo": 1}')$error, "table_spec")
})

test_that("spec_from_example loads demographics_age", {
  sp <- spec_from_example("demographics_age")
  expect_equal(sp$table_spec$id, "demographics_age")
  expect_true("age" %in% names(sp$table_spec$parameter))
  v <- spec_validate_live(sp)
  expect_true(v$valid)
})

test_that("spec_list_examples finds packaged JSON", {
  ex <- spec_list_examples()
  expect_true("demographics_age" %in% ex)
  expect_true("ae_soc_pt" %in% ex)
})

test_that("spec_validate_live accepts JSON string", {
  sp <- spec_from_example("demographics_age")
  v <- spec_validate_live(spec_to_json(sp))
  expect_true(v$valid)
})

test_that("example specs compile", {
  for (nm in spec_list_examples()) {
    sp <- spec_from_example(nm)
    json <- spec_to_json(sp)
    expect_true(kst_validate_spec(json)$valid, info = nm)
    code <- kst_compile(json)
    expect_type(code, "character")
    expect_true(nchar(code) > 0L, info = nm)
  }
})
