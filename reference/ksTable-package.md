# ksTable: JSON DSL to Dplyr Code Generator for Clinical Tables

Reads declarative JSON table specifications and uses a pure-R generator
to produce pipe-based dplyr/tidyr R code. The generated code produces
pre-formatted tibbles ready for rendering with the ksTFL package.
Supports parameter-statistic and hierarchical (SOC -\> PT) table
layouts, multi-way stratification, ksformat integration, and multiple
format methods (sprintf, template, custom function, ksformat). Template
formats require the suggested 'glue' package at evaluation time. All
JSON-derived identifiers are validated before code emission to prevent
injection attacks (SR-1).

## See also

Useful links:

- <https://github.com/crow16384/ksTable>

- Report bugs at <https://github.com/crow16384/ksTable/issues>

## Author

**Maintainer**: Vladimir Larchenko <crow16384@gmail.com>

Authors:

- Vladimir Larchenko <crow16384@gmail.com>
