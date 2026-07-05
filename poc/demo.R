# poc/demo.R ──────────────────────────────────────────────────────────────────
# ksTable PoC demonstration and benchmark
#
# Run:  Rscript poc/demo.R   (from project root)
#   or: source("poc/demo.R") (from an R session in project root)

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(jsonlite)
})
source("poc/generator.R")

sep <- strrep("\u2500", 60)
cat("ksTable PoC \u2500 pure-R DSL code generator\n", sep, "\n\n", sep = "")

# ── Synthetic data ────────────────────────────────────────────────────────────
set.seed(42)
n <- 480L

adsl <- tibble(
  USUBJID = sprintf("%03d-%04d", rep(1:3, each = n %/% 3L), seq_len(n)),
  AGE     = round(rnorm(n, 45, 12)),
  SEX     = sample(c("M", "F"), n, replace = TRUE),
  TRT01P  = rep(c("Placebo", "Drug A", "Drug B"), each = n %/% 3L)
)

set.seed(7)
n_ae   <- 300L
ae_ids <- sample(adsl$USUBJID, n_ae, replace = TRUE)
ae_soc <- sample(c("Cardiac disorders", "Gastrointestinal disorders"),
                 n_ae, replace = TRUE, prob = c(0.4, 0.6))
ae_pt  <- ifelse(
  ae_soc == "Cardiac disorders",
  sample(c("Myocardial infarction", "Angina pectoris"), n_ae, replace = TRUE),
  sample(c("Nausea", "Diarrhea"),                       n_ae, replace = TRUE)
)
ae <- tibble(
  USUBJID = ae_ids,
  TRT01P  = adsl$TRT01P[match(ae_ids, adsl$USUBJID)],
  AESOC   = ae_soc,
  AEDECOD = ae_pt
)

# ── Calculation and format functions ────────────────────────────────────────
# Referenced by name in the JSON spec; resolved from the environment at runtime.
# calc functions   → return raw numeric or named list (no string coercion)
# format functions → convert a raw value or named list to a display string

count   <- function(data) sum(!is.na(data))             # → integer
mean_sd <- function(data) list(                         # → named list
  mean = mean(data, na.rm = TRUE),
  sd   = sd(data,   na.rm = TRUE)
)
count_n <- function(data) length(data)                  # → integer

format_mean_sd <- function(x) sprintf("%.1f (%.2f)", x$mean, x$sd)

# ── Example 1: parameter_stat (Demographics) ─────────────────────────────────
demog_json <- '{
  "schema_version": "1.0",
  "table_spec": {
    "id": "demographics_age",
    "title": "Age by Treatment Group",
    "parameter": {
      "age": { "variable": "AGE", "label": "Age (years)" }
    },
    "statistics": {
      "n": {
        "fun": "count",
        "label": "n"
      },
      "mean_sd": {
        "fun": "mean_sd",
        "label": "Mean (SD)",
        "format": { "type": "custom", "fun": "format_mean_sd" }
      }
    },
    "groups": {
      "by": ["TRT01P"],
      "include_missing_levels": false
    },
    "layout": {
      "row_structure": "parameter_stat",
      "column_structure": "groups"
    }
  }
}'

cat("Example 1 \u2500 Demographics (parameter_stat)\n\n")
code1 <- poc_compile(demog_json)
cat("Generated code:\n\n", code1, "\n\n")
# Isolated execution: global env is parent so calc/format functions are visible;
# intermediate objects (.chunks, .long) live in env1, not in globalenv.
env1 <- new.env(parent = globalenv())
env1$data <- adsl
result1 <- eval(parse(text = code1), envir = env1)
cat("Result:\n")
print(result1, n = Inf)
cat("Intermediate objects available for inspection: ",
    paste(ls(env1, all.names = TRUE), collapse = ", "), "\n")

# ── Example 2: hierarchical (Adverse Events) ─────────────────────────────────
ae_json <- '{
  "schema_version": "1.0",
  "table_spec": {
    "id": "adverse_events",
    "title": "Adverse Events by SOC and PT",
    "parameter": {
      "soc": {
        "variable": "AESOC",
        "label": "",
        "nested": {
          "pt": { "variable": "AEDECOD" }
        }
      }
    },
    "statistics": {
      "n": { "fun": "count_n", "label": "n" }
    },
    "groups": {
      "by": ["TRT01P"],
      "include_missing_levels": false
    },
    "layout": {
      "row_structure": "hierarchical",
      "column_structure": "groups"
    }
  }
}'

cat("\nExample 2 \u2500 Adverse Events (hierarchical)\n\n")
code2 <- poc_compile(ae_json)
cat("Generated code:\n\n", code2, "\n\n")
env2 <- new.env(parent = globalenv())
env2$data <- ae
result2 <- eval(parse(text = code2), envir = env2)
cat("Result:\n")
print(result2, n = Inf)

# ── Injection guard test ──────────────────────────────────────────────────────
cat("\nExample 3 \u2500 Injection guard\n\n")
bad_json <- '{
  "schema_version": "1.0",
  "table_spec": {
    "id": "x",
    "parameter": { "p": { "variable": "AGE); system(\\"echo INJECTED\\"", "label": "x" } },
    "statistics": { "n": { "fun": "count", "label": "n" } },
    "groups": { "by": ["TRT01P"] },
    "layout": { "row_structure": "parameter_stat" }
  }
}'
tryCatch(
  poc_compile(bad_json),
  error = function(e) cat("Injection correctly rejected:\n ", conditionMessage(e), "\n")
)

# ── Benchmark ─────────────────────────────────────────────────────────────────
cat("\nBenchmark \u2500 compilation time\n\n")
REPS <- 10000L
t    <- system.time(for (i in seq_len(REPS)) poc_compile(demog_json))
cat(sprintf(
  "%d iterations: %.3f s total  \u2192  %.1f \u00b5s per call\n\n",
  REPS, t["elapsed"], t["elapsed"] / REPS * 1e6
))
cat("Rcpp toolchain build (C++): 30\u2013120 s per R CMD INSTALL.\n")
cat("At <200 \u00b5s per call, pure-R generation overhead is negligible.\n")
