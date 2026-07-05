pkgname <- "ksTable"
source(file.path(R.home("share"), "R", "examples-header.R"))
options(warn = 1)
library('ksTable')

base::assign(".oldSearch", base::search(), pos = 'CheckExEnv')
base::assign(".old_wd", base::getwd(), pos = 'CheckExEnv')
cleanEx()
nameEx("kst_compile")
### * kst_compile

flush(stderr()); flush(stdout())

### Name: kst_compile
### Title: Compile a JSON DSL table spec to a plain R script
### Aliases: kst_compile

### ** Examples

spec <- '{
  "schema_version": "1.0",
  "table_spec": {
    "parameter": { "age": { "variable": "AGE", "label": "Age (years)" } },
    "statistics": { "n": { "fun": "count", "label": "n" } },
    "groups": { "by": ["TRT"] },
    "layout": { "row_structure": "parameter_stat", "column_structure": "groups" }
  }
}'
cat(kst_compile(spec))




cleanEx()
nameEx("kst_extract_metadata")
### * kst_extract_metadata

flush(stderr()); flush(stdout())

### Name: kst_extract_metadata
### Title: Extract variable metadata from a data frame
### Aliases: kst_extract_metadata

### ** Examples

## Not run: 
##D adsl <- tibble::tibble(
##D   TRT = factor(c("A", "B"), levels = c("Placebo", "Drug A", "Drug B"))
##D )
##D meta <- kst_extract_metadata(adsl, "TRT")
##D meta$TRT$levels  # "Placebo" "Drug A" "Drug B"
## End(Not run)




cleanEx()
nameEx("kst_generate_table")
### * kst_generate_table

flush(stderr()); flush(stdout())

### Name: kst_generate_table
### Title: Generate a formatted table from a JSON DSL spec and a data frame
### Aliases: kst_generate_table

### ** Examples

## Not run: 
##D # Define calc / format functions in the current environment
##D count   <- function(data) sum(!is.na(data))
##D mean_sd <- function(data) list(mean = mean(data, na.rm = TRUE),
##D                                sd   = sd(data,   na.rm = TRUE))
##D format_mean_sd <- function(x) sprintf("%.1f (%.2f)", x$mean, x$sd)
##D 
##D result <- kst_generate_table(spec, adsl)
## End(Not run)




cleanEx()
nameEx("kst_validate_spec")
### * kst_validate_spec

flush(stderr()); flush(stdout())

### Name: kst_validate_spec
### Title: Validate a JSON DSL table specification
### Aliases: kst_validate_spec

### ** Examples

spec <- '{
  "schema_version": "1.0",
  "table_spec": {
    "parameter":  { "age": { "variable": "AGE" } },
    "statistics": { "n": { "fun": "length" } },
    "groups":     { "by": ["TRT"] },
    "layout":     { "row_structure": "parameter_stat" }
  }
}'
kst_validate_spec(spec)




### * <FOOTER>
###
cleanEx()
options(digits = 7L)
base::cat("Time elapsed: ", proc.time() - base::get("ptime", pos = 'CheckExEnv'),"\n")
grDevices::dev.off()
###
### Local variables: ***
### mode: outline-minor ***
### outline-regexp: "\\(> \\)?### [*]+" ***
### End: ***
quit('no')
