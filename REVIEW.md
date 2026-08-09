# ksTable Design Review

**Date**: 2026-07-05  
**Status**: Historical (Post-PoC). Current shipped API uses bare
function calls (not `calc_fns` registries) and caller-driven
`kst_extract_metadata` / `kst_apply_metadata`. See
[ARCHITECTURE.md](https://crow16384.github.io/ksTable/ARCHITECTURE.md)
and [PLAN.md](https://crow16384.github.io/ksTable/PLAN.md) for the live
design.

------------------------------------------------------------------------

## 1. Author Clarifications

Responses to questions raised in the initial review:

| \# | Question | Author answer | Impact |
|----|----|----|----|
| 1 | C++ optimizer rationale | “Not measured, just a guess” | **Major** – see PoC below |
| 2 | Denominator / big-N source | User’s responsibility in calc functions | Removes FR-10 footnote |
| 3 | Distinct-subject counting | User’s responsibility; JSON specifies which variable to pass | Removes a hidden contract requirement |
| 4 | Compile-time vs runtime levels | **Runtime** confirmed | `.drop = FALSE` approach |
| 5 | Registry vs `calc_functions` arg | `calc_functions` is a named list; key = `fun` ID in JSON | Simplifies API (see §4) |
| 6 | CRAN portability | Not a concern | Boost.JSON + C++23 remain on the table |

------------------------------------------------------------------------

## 2. Pure-R Proof of Concept

### What was built

[poc/generator.R](https://crow16384.github.io/ksTable/poc/generator.R) —
~130 lines of pure R implementing: - `poc_compile(json_spec)` → R code
string - `poc_execute(code, data, calc_fns)` → tibble - `parameter_stat`
and `hierarchical` layouts - Identifier injection guard

[poc/demo.R](https://crow16384.github.io/ksTable/poc/demo.R) — exercises
both layouts plus security and benchmark.

### Generated code (demographics example)

``` r

.chunks <- list()

.chunks[[1L]] <- .data |>
  dplyr::group_by(TRT01P) |>
  dplyr::summarize(
    .value      = as.character(calc_fns[["count"]](AGE)),
    .groups     = "drop"
  ) |>
  dplyr::mutate(
    .param      = "Age (years)",
    .stat = "n"
  )

.chunks[[2L]] <- .data |>
  dplyr::group_by(TRT01P) |>
  dplyr::summarize(
    .value      = as.character(calc_fns[["mean_sd"]](AGE)),
    .groups     = "drop"
  ) |>
  dplyr::mutate(
    .param      = "Age (years)",
    .stat = "Mean (SD)"
  )

.long <- dplyr::bind_rows(.chunks)

tidyr::pivot_wider(
  .long,
  id_cols     = c(.param, .stat),
  names_from  = c(TRT01P),
  values_from = .value
)
```

### Results

**Demographics** (n = 480, 3 arms):

    # A tibble: 2 × 5
      .param      .stat Drug A       Drug B       Placebo
    1 Age (years) n           160          160          160
    2 Age (years) Mean (SD)   44.9 (11.37) 44.9 (11.84) 44.5 (11.96)

**Adverse events** (hierarchical SOC → PT):

    # A tibble: 6 × 7
      .parent                    .is_child  .row_label               n: Drug A  Drug B  Placebo
    1 Cardiac disorders          FALSE      Cardiac disorders            36       39      34
    2 Cardiac disorders          TRUE         Angina pectoris            14       21      21
    3 Cardiac disorders          TRUE         Myocardial infarction      22       18      13
    4 Gastrointestinal disorders FALSE      Gastrointestinal disorders   73       64      54
    5 Gastrointestinal disorders TRUE         Diarrhea                   39       31      35
    6 Gastrointestinal disorders TRUE         Nausea                     34       33      19

Parent rows precede their children. Ordering is correct.

**Injection guard**:

    'AGE); system("echo INJECTED"' is not a valid R identifier
    (field: parameter.p.variable)

**Benchmark** (10,000 iterations, MacBook):

    10,000 iterations: 0.507 s total  →  50.7 µs per call

------------------------------------------------------------------------

## 3. Key Decision: Drop C++23, Use Pure R

**Verdict: the C++23 compiler is not justified for the current scope.**

Concrete numbers:

| Operation | Time |
|----|----|
| Pure-R DSL compile (demographics) | **~51 µs** |
| Pure-R DSL compile (AE hierarchical) | ~80 µs (estimated) |
| [`Rcpp::compileAttributes()`](https://rdrr.io/pkg/Rcpp/man/compileAttributes.html) + rebuild | 30–120 **seconds** |
| C++23 compiler install (Boost, fmt, range-v3) | minutes per platform |

The optimizations that were cited as justification (redundancy
elimination, predicate pushdown, operation fusion) are classical
database-planner concepts applied to single in-memory
`group_by |> summarize` chains. In practice:

- R already evaluates only needed columns (lazy evaluation within
  dplyr).
- Multiple `summarize` calls over the same data frame are the correct
  pattern — not a redundancy to eliminate.
- A pipeline with two `group_by |> summarize` blocks runs in \< 1 ms on
  clinical-scale data.

**What the pure-R generator already does:** - Parses JSON
([`jsonlite::fromJSON`](https://jeroen.r-universe.dev/jsonlite/reference/fromJSON.html))
— same library referenced in dependencies. - Assembles an R code string
— pure string manipulation, ~50 µs. - Validates identifiers against
injection — a single `grepl` per field. - Escapes label strings — two
`gsub` calls. - Supports `parameter_stat` and `hierarchical` layouts.

**Remaining role for C++ (optional, if needed later):** none identified
yet. If a genuine bottleneck emerges after profiling real workloads, a
targeted Rcpp function can be added then. Don’t build the toolchain
speculatively.

**Recommended architecture change:**

    Before:  JSON → C++23 Compiler → R code string → eval() → tibble
    After:   JSON → R generator     → R code string → eval() → tibble

This eliminates Phases 1–4 as currently scoped (C++ parser, validator,
metadata consumer, AST, optimizer, codegen), replacing them with a
single `R/compiler.R` (~300–400 lines). Phases 5–7 (package structure,
testing, docs) are unchanged.

------------------------------------------------------------------------

## 4. Function Resolution Contract — Clarified

The runtime contract is simpler than the plan implies. There is no
global registry and no calc-function list argument. Functions referenced
by `statistics[].fun` and `statistics[].format.fun` are resolved from
the parent chain of the evaluation environment used to run compiled
code:

``` r

code <- kst_compile(spec)
env  <- new.env(parent = environment())
env$data <- adsl
result <- eval(parse(text = code), envir = env)
```

**Consequences:**

1.  **Drop `kst_register_calc` / `kst_list_calc` / `kst_get_calc`** from
    the plan (IR-5). A global mutable registry adds complexity and makes
    functions hard to test in isolation.

2.  **Two function shapes** exist in the DSL and need to be documented
    as distinct concepts:

    | Shape | Where used | Signature | Example |
    |----|----|----|----|
    | Calc function | `statistics[].fun` | `function(data_vector) → scalar/string` | `count`, `mean_sd` |
    | Format function | `statistics[].format.fun` | `function(...named_values) → string` | `format_median_range` |

    The `format` step is separate from the `calc` step — this is correct
    in the DSL design. It should be stated explicitly in the contract
    doc to avoid confusion.

3.  **Sort before format.** Because calc functions can return raw
    numeric values (e.g., `list(mean=45.2, sd=12.3)`), and the `format`
    spec (template / custom / sprintf) converts them to strings, sorting
    by value must happen **before** the format step. The code generator
    must ensure: `compute raw → arrange → format → pivot`. This ordering
    should be pinned as FR-4 behavior.

------------------------------------------------------------------------

## 5. Security: Code Injection (First-Class Requirement)

The PoC demonstrates the pattern, but injection prevention must be a
documented requirement, not an implementation detail.

**Risk surface:** every JSON string field that ends up in generated R
code: - `parameter[].variable` → used as a bare column name inside
`summarize()` - `statistics[].fun` → used as a `calc_fns[["..."]]` key -
`statistics[].format.fun` → same - `groups[].by[]` → used inside
`group_by()` - Label fields (`label`) → interpolated as R string
literals

**Mitigations (both required):**

1.  **Identifiers** (`variable`, `fun`, `by` values): validate with
    `^[A-Za-z.][A-Za-z0-9._]*$` — rejects anything containing `)`, `;`,
    spaces, etc.
2.  **String literals** (`label`, `pattern`): escape `\` → `\\` and `"`
    → `\"` before embedding in double-quoted R strings.

Add as: **SR-1 (Security Requirement): All JSON-derived identifiers and
string literals must be sanitized before code emission.**

------------------------------------------------------------------------

## 6. Documentation Inconsistencies to Fix

These are quick edits, not architectural issues:

| File | Issue | Fix |
|----|----|----|
| PLAN.md verification section | Uses `ks_compile`, `ks_generate_table`, `ks_validate_spec` | Change to `kst_*` |
| README.md | Badge says R ≥ 4.1, body says R ≥ 4.6 | Decide and standardize; PoC uses `\|>` (R ≥ 4.1) |
| PLAN.md + DSL_EXAMPLE.md | `count` defined as `length(data)` in one place, `sum(!is.na(data))` in another | Pick one (`sum(!is.na(data))` is more correct) |
| PLAN.md IR-5 | `kst_register_calc` / `kst_list_calc` / `kst_get_calc` | Remove (see §4) |

------------------------------------------------------------------------

## 7. Scope Reduction Recommendation for v1.0

The following table types require substantially different codegen paths
and should move to v1.1:

| Feature | Reason to defer |
|----|----|
| `shift_matrix` layout | Cross-tabulation of two categorical vars — structurally unlike summary tables |
| `listing` type | No aggregation; pure select/sort/format pipeline |
| Multi-level nesting (\> 2) | PoC handles 2 levels; generalization adds complexity for rare use |
| Conditional formatting | Depends on output format (ksTFL feature, not ksTable) |

Focus v1.0 on `parameter_stat` + `hierarchical` layouts with the five
table types already in
[DSL_EXAMPLE.md](https://crow16384.github.io/ksTable/DSL_EXAMPLE.md)
(examples 1–4). Ship something that works.

------------------------------------------------------------------------

## 8. Revised Phase Plan

Based on all the above, the phases simplify to:

| Phase | Content | Weeks |
|----|----|----|
| 1 | JSON schema definition + R-side validator (`kst_validate_spec`) | 1 |
| 2 | R code generator (`R/compiler.R`) — `parameter_stat` + `hierarchical` | 2 |
| 3 | Metadata extraction (`R/metadata.R`) — ksformat, factors, `.drop = FALSE` | 1 |
| 4 | Format step in codegen — template / custom / sprintf / ksformat | 1 |
| 5 | R package structure (DESCRIPTION, NAMESPACE, Rcpp-free build) | 1 |
| 6 | Testing (testthat) + examples | 1–2 |
| 7 | Documentation + vignettes | 1 |

**Total: ~8 weeks** (same as before, but no C++ toolchain, no Rcpp, no
Boost).

------------------------------------------------------------------------

## 9. Resolved Questions

1.  **`include_missing_levels` source of truth**: `kst_extract_metadata`
    is responsible for ensuring the grouping variable is a factor with
    the correct levels before the generated code runs. Generated code
    can then safely use `group_by(..., .drop = FALSE)`. **Closed.**

2.  **Multi-parameter tables**: Iterating all parameters and producing
    rows for each is the intended behavior. A table with `age` + `sex`
    parameters simply produces more rows with distinct `.param` values.
    No separate layout needed. **Closed.**

3.  **Column ordering in output**: Out of scope for ksTable. Column
    ordering is the responsibility of the ksTFL renderer. ksTable makes
    no guarantees about column order beyond what `pivot_wider` produces
    by default. **Closed.**
