# ksTable JSON DSL Examples

**Version**: 1.0  
**Date**: 2026-07-01

This document provides example JSON DSL specifications for various table types.

---

## Example 1: Simple Demographics Table

**Description**: Age statistics (n, mean, SD) by treatment group

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
      "n": {
        "fun": "count",
        "label": "n"
      },
      "mean_sd": {
        "fun": "mean_sd",
        "label": "Mean (SD)",
        "format": {
          "type": "template",
          "pattern": "{mean} ({sd})",
          "digits": {"mean": 1, "sd": 2}
        }
      }
    },
    "groups": {
      "by": ["TRT01P"],
      "include_missing_levels": true,
      "format": {
        "TRT01P": "trt_format"
      }
    },
    "layout": {
      "row_structure": "parameter_stat",
      "column_structure": "groups"
    }
  }
}
```

**Expected Output**:

```text
PARAM           STATISTIC    Placebo       Drug A        Drug B
Age (years)     n            160           160           160
Age (years)     Mean (SD)    45.2 (12.3)   46.1 (11.8)   44.8 (12.9)
```

---

## Example 2: Demographics with 2-Way Stratification

**Description**: Age statistics by treatment group and gender

```json
{
  "schema_version": "1.0",
  "table_spec": {
    "id": "demographics_age_sex",
    "title": "Age by Treatment Group and Sex",
    "parameter": {
      "age": {
        "variable": "AGE",
        "label": "Age (years)"
      }
    },
    "statistics": {
      "n": {
        "fun": "count",
        "label": "n"
      },
      "mean_sd": {
        "fun": "mean_sd",
        "label": "Mean (SD)"
      }
    },
    "groups": {
      "by": ["TRT01P", "SEX"],
      "include_missing_levels": true,
      "format": {
        "TRT01P": "trt_format",
        "SEX": "sex_format"
      }
    },
    "layout": {
      "row_structure": "parameter_stat",
      "column_structure": "groups",
      "group_headers": ["TRT01P", "SEX"]
    }
  }
}
```

**Expected Output**:

```text
                          Placebo                Drug A                Drug B
PARAM           STATISTIC Male    Female    Male    Female    Male    Female
Age (years)     n         80      80        82      78        79      81
Age (years)     Mean (SD) 45.1... 45.3...   46.0... 46.2...   44.7... 44.9...
```

---

## Example 3: Adverse Events (Hierarchical)

**Description**: AE counts by SOC and PT, with percentages

```json
{
  "schema_version": "1.0",
  "table_spec": {
    "id": "adverse_events",
    "title": "Adverse Events by System Organ Class and Preferred Term",
    "parameter": {
      "soc": {
        "variable": "AESOC",
        "label": "",
        "nested": {
          "pt": {
            "variable": "AEDECOD",
            "label": ""
          }
        }
      }
    },
    "statistics": {
      "n_pct": {
        "fun": "count_pct",
        "label": "n (%)",
        "format": {
          "type": "template",
          "pattern": "{n} ({pct})",
          "digits": {"pct": 1}
        }
      }
    },
    "groups": {
      "by": ["TRT01P"],
      "include_missing_levels": false
    },
    "layout": {
      "row_structure": "hierarchical",
      "column_structure": "groups",
      "sort": {
        "soc": "alphabetical",
        "pt": "frequency_desc"
      }
    }
  }
}
```

**Expected Output**:

```text
System Organ Class                Placebo       Drug A        Drug B
  Preferred Term
Cardiac disorders                 12 (7.5)      15 (9.4)      14 (8.8)
  Myocardial infarction          3 (1.9)       5 (3.1)       4 (2.5)
  Angina pectoris                2 (1.3)       3 (1.9)       3 (1.9)
  Atrial fibrillation            7 (4.4)       7 (4.4)       7 (4.4)
Gastrointestinal disorders        45 (28.1)     48 (30.0)     42 (26.3)
  Nausea                         20 (12.5)     25 (15.6)     18 (11.3)
  Diarrhea                       15 (9.4)      13 (8.1)      14 (8.8)
  Vomiting                       10 (6.3)      10 (6.3)      10 (6.3)
```

---

## Example 4: Efficacy Table (Change from Baseline)

**Description**: Mean change from baseline by visit

```json
{
  "schema_version": "1.0",
  "table_spec": {
    "id": "efficacy_change",
    "title": "Change from Baseline in Systolic BP",
    "parameter": {
      "chg": {
        "variable": "CHG",
        "label": "Change from Baseline (mmHg)"
      }
    },
    "statistics": {
      "n": {
        "fun": "count",
        "label": "n"
      },
      "mean_sd": {
        "fun": "mean_sd",
        "label": "Mean (SD)"
      },
      "median_range": {
        "fun": "median_range",
        "label": "Median [Min, Max]",
        "format": {
          "type": "custom",
          "fun": "format_median_range"
        }
      }
    },
    "groups": {
      "by": ["TRT01P", "AVISIT"],
      "include_missing_levels": false,
      "format": {
        "TRT01P": "trt_format",
        "AVISIT": "visit_format"
      }
    },
    "layout": {
      "row_structure": "groups_stat",
      "column_structure": "parameter",
      "group_headers": ["AVISIT", "TRT01P"]
    }
  }
}
```

**Expected Output**:

```text
                                Change from Baseline (mmHg)
Visit           Treatment       n        Mean (SD)        Median [Min, Max]
Week 4          Placebo         158      -2.1 (8.3)      -2.0 [-25.0, 18.0]
Week 4          Drug A          159      -5.3 (7.9)      -5.0 [-28.0, 15.0]
Week 4          Drug B          157      -8.2 (8.1)      -8.0 [-30.0, 12.0]
Week 8          Placebo         156      -3.2 (9.1)      -3.0 [-30.0, 20.0]
Week 8          Drug A          158      -7.8 (8.5)      -8.0 [-32.0, 18.0]
Week 8          Drug B          155      -12.1 (9.2)     -12.0 [-35.0, 15.0]
```

---

## Example 5: Laboratory Shift Table

**Description**: Baseline to post-baseline transitions

```json
{
  "schema_version": "1.0",
  "table_spec": {
    "id": "lab_shift",
    "title": "Laboratory Shift Table - ALT (Alanine Aminotransferase)",
    "parameter": {
      "shift": {
        "source_variable": "BASE_CAT",
        "target_variable": "POST_CAT",
        "label": ""
      }
    },
    "statistics": {
      "n_pct": {
        "fun": "count_pct",
        "label": "n (%)"
      }
    },
    "groups": {
      "by": ["TRT01P"],
      "include_missing_levels": false
    },
    "layout": {
      "row_structure": "shift_matrix",
      "column_structure": "groups",
      "shift_categories": ["Low", "Normal", "High"],
      "show_totals": true
    }
  }
}
```

**Expected Output**:

```text
Baseline      Post-Baseline    Placebo       Drug A        Drug B
Low           Low              5 (3.1)       4 (2.5)       6 (3.8)
Low           Normal           8 (5.0)       9 (5.6)       7 (4.4)
Low           High             2 (1.3)       3 (1.9)       2 (1.3)
Normal        Low              6 (3.8)       7 (4.4)       5 (3.1)
Normal        Normal           120 (75.0)    115 (71.9)    118 (73.8)
Normal        High             10 (6.3)      12 (7.5)      14 (8.8)
High          Low              1 (0.6)       2 (1.3)       1 (0.6)
High          Normal           5 (3.1)       6 (3.8)       5 (3.1)
High          High             3 (1.9)       2 (1.3)       2 (1.3)
Total                          160 (100.0)   160 (100.0)   160 (100.0)
```

---

## Example 6: Listing

**Description**: Subject-level data listing (not aggregated)

```json
{
  "schema_version": "1.0",
  "table_spec": {
    "id": "listing_demographics",
    "title": "Subject Demographics Listing",
    "type": "listing",
    "columns": [
      {
        "variable": "USUBJID",
        "label": "Subject ID",
        "width": "15%"
      },
      {
        "variable": "AGE",
        "label": "Age",
        "width": "10%",
        "format": {
          "type": "sprintf",
          "pattern": "%d"
        }
      },
      {
        "variable": "SEX",
        "label": "Sex",
        "width": "10%",
        "format": {
          "type": "ksformat",
          "format_name": "sex_format"
        }
      },
      {
        "variable": "RACE",
        "label": "Race",
        "width": "20%"
      },
      {
        "variable": "ETHNIC",
        "label": "Ethnicity",
        "width": "20%"
      },
      {
        "variable": "TRT01P",
        "label": "Treatment",
        "width": "25%",
        "format": {
          "type": "ksformat",
          "format_name": "trt_format"
        }
      }
    ],
    "sort": ["TRT01P", "USUBJID"]
  }
}
```

**Expected Output**:

```text
Subject ID    Age    Sex       Race               Ethnicity              Treatment
01-001        45     Male      White              Not Hispanic/Latino    Placebo
01-002        52     Female    White              Not Hispanic/Latino    Placebo
01-003        38     Male      Black/AA           Hispanic/Latino        Drug A
...
```

---

## DSL Schema Components

### Top-Level Structure

```json
{
  "schema_version": "1.0",
  "table_spec": {
    "id": "unique_identifier",
    "title": "Table Title",
    "type": "summary" | "listing",
    "parameter": {...},
    "statistics": {...},
    "groups": {...},
    "layout": {...}
  }
}
```

### Parameter Definition

```json
"parameter": {
  "param_name": {
    "variable": "VARIABLE_NAME",
    "label": "Display Label",
    "nested": {
      "child_param": {...}
    }
  }
}
```

### Statistics Definition

```json
"statistics": {
  "stat_name": {
    "fun": "function_name",
    "label": "Display Label",
    "format": {
      "type": "template" | "custom" | "sprintf" | "ksformat",
      "pattern": "...",
      "digits": {...}
    }
  }
}
```

### Groups Definition

```json
"groups": {
  "by": ["VAR1", "VAR2"],
  "include_missing_levels": true | false,
  "format": {
    "VAR1": "ksformat_name"
  }
}
```

### Layout Definition

```json
"layout": {
  "row_structure": "parameter_stat" | "groups_stat" | "hierarchical" | "shift_matrix",
  "column_structure": "groups" | "parameter",
  "group_headers": ["VAR1", "VAR2"],
  "sort": {
    "var1": "alphabetical" | "frequency_desc" | "frequency_asc"
  }
}
```

### Format Specifications

**Template Format**:

```json
"format": {
  "type": "template",
  "pattern": "{mean} ({sd})",
  "digits": {"mean": 1, "sd": 2}
}
```

**Custom Function Format**:

```json
"format": {
  "type": "custom",
  "fun": "format_median_range"
}
```

**sprintf Format**:

```json
"format": {
  "type": "sprintf",
  "pattern": "%.1f"
}
```

**ksformat Integration**:

```json
"format": {
  "type": "ksformat",
  "format_name": "trt_format"
}
```

---

## Calculation Function Examples

These functions would be provided by the user:

```r
# Count non-missing values
count <- function(data) {
  sum(!is.na(data))
}

# Mean and SD
mean_sd <- function(data) {
  m <- mean(data, na.rm = TRUE)
  s <- sd(data, na.rm = TRUE)
  list(mean = m, sd = s)
}

# Count and percentage
count_pct <- function(data) {
  n <- length(data)
  total <- attr(data, "total")  # Set by compiler
  pct <- 100 * n / total
  list(n = n, pct = pct)
}

# Median and range
median_range <- function(data) {
  med <- median(data, na.rm = TRUE)
  rng <- range(data, na.rm = TRUE)
  list(median = med, min = rng[1], max = rng[2])
}

# Custom format function
format_median_range <- function(median, min, max) {
  sprintf("%.1f [%.1f, %.1f]", median, min, max)
}
```

---

## Notes on DSL Design

### Design Principles

1. **Declarative**: Describe what you want, not how to compute it
2. **Composable**: Complex tables built from simple components
3. **Metadata-aware**: Leverages ksformat and factor metadata
4. **Extensible**: Custom functions and formats supported
5. **Readable**: JSON structure mirrors table structure

### Evolution Strategy

- Version in schema (`schema_version`)
- Backwards compatibility within major versions
- Clear migration guides for breaking changes
- Deprecation warnings before removal

### Future Extensions

- Cross-tabulation support
- Conditional formatting (highlighting, colors)
- Multi-parameter tables (multiple variables in same table)
- Page breaks and continuation headers
- Cell-level annotations (footnote markers)

---

**Document Version**: 1.0  
**Last Updated**: 2026-07-01
