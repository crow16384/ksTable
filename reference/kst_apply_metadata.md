# Apply extracted metadata to a data frame

For each variable in `metadata`:

1.  If a `format_name` is recorded (from `format_map` in
    [`kst_extract_metadata`](https://crow16384.github.io/ksTable/reference/kst_extract_metadata.md)),
    applies
    [`ksformat::fput()`](https://rdrr.io/pkg/ksformat/man/fput.html) to
    replace raw codes with display labels.

2.  Converts the column to an ordered factor with the levels from the
    metadata, including any levels absent from the data (required for
    `include_missing_levels = true` via `group_by(..., .drop = FALSE)`).

## Usage

``` r
kst_apply_metadata(data, metadata)
```

## Arguments

- data:

  Input data frame.

- metadata:

  List from
  [`kst_extract_metadata`](https://crow16384.github.io/ksTable/reference/kst_extract_metadata.md).

## Value

The data frame with columns re-coded and re-levelled.

## Details

Call this on `data` **before** evaluating code from
[`kst_compile`](https://crow16384.github.io/ksTable/reference/kst_compile.md).
Compile does not apply metadata.
