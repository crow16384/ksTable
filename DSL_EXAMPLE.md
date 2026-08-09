# ksTable JSON DSL Examples

**Version**: 1.1  
**Date**: 2026-08-09

Examples aligned with `inst/schema/table_spec_v1.json`. Aspirational fields
(`digits`, `layout.sort`, `group_headers`) are **not** in the schema and are
ignored by the compiler if present.

Output row ids use `.param` / `.stat` (parameter_stat) or `.parent` /
`.is_child` / `.row_label` / `.stat` (hierarchical). Value columns are character.

---

## Example 1: Demographics (`parameter_stat`)

```json
{
  "schema_version": "1.0",
  "table_spec": {
    "id": "demographics_age",
    "title": "Age by Treatment Group",
    "parameter": {
      "age": {
        "variable": "AGE",
        "label": "Age (years)"
      }
    },
    "statistics": {
      "n": { "fun": "count" },
      "mean_sd": {
        "fun": "mean_sd",
        "format": { "type": "custom", "fun": "format_mean_sd" }
      }
    },
    "groups": {
      "by": ["TRT01P"],
      "include_missing_levels": true,
      "format": { "TRT01P": "trt_fmt" }
    },
    "layout": {
      "row_structure": "parameter_stat",
      "column_structure": "groups"
    }
  }
}
```

`groups.format` documents the intended ksformat names. Apply before eval:

```r
meta <- kst_extract_metadata(adsl, "TRT01P",
                             format_map = list(TRT01P = "trt_fmt"))
adsl <- kst_apply_metadata(adsl, meta)
```

Expected shape:

```text
.param      .stat    Placebo       Drug A        Drug B
Age (years) n        160           160           160
Age (years) mean_sd  45.2 (12.3)   46.1 (11.8)   44.8 (12.9)
```

---

## Example 2: Two-way stratification

```json
{
  "schema_version": "1.0",
  "table_spec": {
    "id": "demographics_age_sex",
    "parameter": {
      "age": { "variable": "AGE", "label": "Age (years)" }
    },
    "statistics": {
      "n": { "fun": "count" },
      "mean_sd": {
        "fun": "mean_sd",
        "format": { "type": "custom", "fun": "format_mean_sd" }
      }
    },
    "groups": {
      "by": ["TRT01P", "SEX"],
      "include_missing_levels": true
    },
    "layout": {
      "row_structure": "parameter_stat",
      "column_structure": "groups"
    }
  }
}
```

Column names after `pivot_wider` are the combinations of `TRT01P` × `SEX`
(factor levels control order).

---

## Example 3: Adverse events (hierarchical)

```json
{
  "schema_version": "1.0",
  "table_spec": {
    "id": "ae_soc_pt",
    "parameter": {
      "soc": {
        "variable": "AESOC",
        "nested": {
          "pt": { "variable": "AEDECOD" }
        }
      }
    },
    "statistics": {
      "n": { "fun": "length" }
    },
    "groups": { "by": ["TRT01P"] },
    "layout": {
      "row_structure": "hierarchical",
      "column_structure": "groups"
    }
  }
}
```

v0.1 uses the **first** statistic only if several are listed.

---

## Example 4: `sprintf`, `args`, `apply_to`, multi-variable parameter

```json
{
  "schema_version": "1.0",
  "table_spec": {
    "parameter": {
      "labs": {
        "variables": ["ALT", "AST", "BILI"],
        "labels": ["ALT (U/L)", "AST (U/L)", "Bilirubin"]
      },
      "sex": { "variable": "SEX", "label": "Sex" }
    },
    "statistics": {
      "n": { "fun": "length" },
      "median": {
        "fun": "median",
        "args": { "na.rm": true },
        "apply_to": ["labs"],
        "format": { "type": "sprintf", "pattern": "%.1f" }
      }
    },
    "groups": { "by": ["TRT01P", "AVISIT"] },
    "layout": { "row_structure": "parameter_stat" }
  }
}
```

If `labels` is shorter than `variables`, missing labels default to the variable name.

---

## Example 5: Format types

```json
"statistics": {
  "plain":   { "fun": "mean", "args": { "na.rm": true } },
  "spr":     { "fun": "mean", "args": { "na.rm": true },
               "format": { "type": "sprintf", "pattern": "%.2f" } },
  "custom":  { "fun": "mean_sd",
               "format": { "type": "custom", "fun": "format_mean_sd" } },
  "templ":   { "fun": "mean_sd",
               "format": { "type": "template", "pattern": "{mean} ({sd})" } },
  "ksf":     { "fun": "identity",
               "format": { "type": "ksformat", "format_name": "some_fmt" } }
}
```

`template` requires the **glue** package at evaluation time.

---

## Calc / format functions (environment lookup)

Define functions in the parent of the eval environment. There is no
`calc_fns` / `format_fns` list API.

```r
count   <- function(x) sum(!is.na(x))
mean_sd <- function(x) list(mean = mean(x, na.rm = TRUE), sd = sd(x, na.rm = TRUE))
format_mean_sd <- function(x) sprintf("%.1f (%.2f)", x$mean, x$sd)

code <- kst_compile(spec)
env  <- new.env(parent = environment())
env$data <- adsl
result <- eval(parse(text = code), envir = env)
```

---

## Future (not in schema v1.0)

- Sort options, multi-stat hierarchical, nesting depth > 2, listing, shift matrices

**Document Version**: 1.1 · **Last Updated**: 2026-08-09
