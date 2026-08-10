#!/usr/bin/env Rscript
# scripts/bump_version.R
#
# Bump the package version in DESCRIPTION, then sync hardcoded package-version
# strings across docs. Does NOT touch JSON DSL schema_version ("1.0").
#
# Usage:
#   Rscript scripts/bump_version.R patch          # 0.2.0 -> 0.2.1
#   Rscript scripts/bump_version.R minor          # 0.2.0 -> 0.3.0
#   Rscript scripts/bump_version.R major          # 0.2.0 -> 1.0.0
#   Rscript scripts/bump_version.R 0.2.1          # set explicit version
#   Rscript scripts/bump_version.R --sync-only    # sync from DESCRIPTION only
#
# After bumping:
#   Rscript -e 'devtools::document(); pkgdown::build_site(preview = FALSE)'

find_root <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  file_arg <- sub("^--file=", "", grep("^--file=", ca, value = TRUE))
  if (length(file_arg) == 1L && nzchar(file_arg)) {
    return(normalizePath(file.path(dirname(file_arg), ".."), mustWork = TRUE))
  }
  if (file.exists(file.path(getwd(), "DESCRIPTION")))
    return(normalizePath(getwd(), mustWork = TRUE))
  stop("Run from the package root, or invoke as Rscript scripts/bump_version.R ...",
       call. = FALSE)
}

root <- find_root()
desc_path <- file.path(root, "DESCRIPTION")

read_desc_version <- function() {
  d <- read.dcf(desc_path)
  list(
    Version = unname(d[1L, "Version"]),
    Date    = if ("Date" %in% colnames(d)) unname(d[1L, "Date"]) else NA_character_
  )
}

set_desc_fields <- function(version = NULL, date = NULL) {
  lines <- readLines(desc_path, warn = FALSE)
  if (!is.null(version)) {
    i <- grep("^Version:", lines)
    if (!length(i)) stop("No Version: field in DESCRIPTION", call. = FALSE)
    lines[[i[[1L]]]] <- paste0("Version: ", version)
  }
  if (!is.null(date)) {
    i <- grep("^Date:", lines)
    if (length(i)) {
      lines[[i[[1L]]]] <- paste0("Date: ", date)
    } else {
      v <- grep("^Version:", lines)[[1L]]
      lines <- append(lines, paste0("Date: ", date), after = v)
    }
  }
  writeLines(lines, desc_path)
}

parse_version <- function(v) {
  parts <- as.integer(strsplit(v, ".", fixed = TRUE)[[1L]])
  if (length(parts) < 2L || length(parts) > 4L || anyNA(parts))
    stop("Invalid version: '", v, "'", call. = FALSE)
  parts
}

format_version <- function(parts) paste(parts, collapse = ".")

bump_parts <- function(parts, which) {
  which <- match.arg(which, c("major", "minor", "patch"))
  while (length(parts) < 3L) parts <- c(parts, 0L)
  parts <- parts[seq_len(3L)]
  if (which == "major") {
    parts[1L] <- parts[1L] + 1L
    parts[2:3] <- 0L
  } else if (which == "minor") {
    parts[2L] <- parts[2L] + 1L
    parts[3L] <- 0L
  } else {
    parts[3L] <- parts[3L] + 1L
  }
  parts
}

replace_file <- function(rel, patterns) {
  path <- file.path(root, rel)
  if (!file.exists(path)) {
    message("skip (missing): ", rel)
    return(invisible(FALSE))
  }
  lines <- readLines(path, warn = FALSE)
  txt <- paste(lines, collapse = "\n")
  orig <- txt
  for (nm in names(patterns))
    txt <- gsub(nm, patterns[[nm]], txt, perl = TRUE)
  if (identical(txt, orig)) {
    message("unchanged: ", rel)
    return(invisible(FALSE))
  }
  writeLines(strsplit(txt, "\n", fixed = TRUE)[[1L]], path)
  message("updated: ", rel)
  invisible(TRUE)
}

ensure_news_heading <- function(version, date) {
  path <- file.path(root, "NEWS.md")
  if (!file.exists(path)) return(invisible(FALSE))
  lines <- readLines(path, warn = FALSE)
  ver_re <- gsub(".", "\\.", version, fixed = TRUE)
  if (any(grepl(paste0("^## ksTable ", ver_re, "\\b"), lines))) {
    message("unchanged: NEWS.md (heading exists)")
    return(invisible(FALSE))
  }
  insert_at <- 1L
  if (length(lines) >= 1L && grepl("^#\\s+News", lines[[1L]])) {
    insert_at <- 2L
    if (length(lines) >= 2L && !nzchar(lines[[2L]])) insert_at <- 3L
  }
  block <- c(
    sprintf("## ksTable %s (%s)", version, date),
    "",
    "* Version bump.",
    ""
  )
  if (insert_at <= length(lines)) {
    out <- c(lines[seq_len(insert_at - 1L)], block, lines[insert_at:length(lines)])
  } else {
    out <- c(lines, "", block)
  }
  writeLines(out, path)
  message("updated: NEWS.md (added heading)")
  invisible(TRUE)
}

ensure_vignette_version <- function(rel) {
  path <- file.path(root, rel)
  if (!file.exists(path)) return(invisible(FALSE))
  lines <- readLines(path, warn = FALSE)
  if (any(grepl("kst_pkg_version", lines, fixed = TRUE))) {
    message("unchanged: ", rel, " (version chunk present)")
    return(invisible(FALSE))
  }
  chunk_lines <- c(
    "```{r kst_pkg_version, echo = FALSE, eval = TRUE}",
    "kst_pkg_version <- tryCatch(",
    "  as.character(utils::packageVersion(\"ksTable\")),",
    "  error = function(e) {",
    "    desc <- if (file.exists(\"DESCRIPTION\")) \"DESCRIPTION\" else \"../DESCRIPTION\"",
    "    unname(read.dcf(desc)[1L, \"Version\"])",
    "  }",
    ")",
    "```",
    "",
    "*Package version `r kst_pkg_version`.*",
    ""
  )
  # Insert after YAML front matter (first --- ... --- block)
  if (length(lines) >= 1L && identical(trimws(lines[[1L]]), "---")) {
    end <- which(trimws(lines) == "---")
    end <- end[end > 1L][1L]
    if (is.na(end)) stop("Unclosed YAML in ", rel, call. = FALSE)
    out <- c(lines[seq_len(end)], "", chunk_lines, lines[seq(end + 1L, length.out = max(0L, length(lines) - end))])
  } else {
    out <- c(chunk_lines, lines)
  }
  writeLines(out, path)
  message("updated: ", rel, " (added dynamic version)")
  invisible(TRUE)
}

sync_version <- function(version, date) {
  replace_file("README.md", list(
    "Usable v[0-9]+\\.[0-9]+\\.[0-9]+" = paste0("Usable v", version),
    "\\*\\*Version\\*\\*:\\s*[0-9]+\\.[0-9]+\\.[0-9]+" = paste0("**Version**: ", version),
    "\\*\\*Last Updated\\*\\*:\\s*[0-9]{4}-[0-9]{2}-[0-9]{2}" = paste0("**Last Updated**: ", date)
  ))
  replace_file("PLAN.md", list(
    "\\*\\*Status\\*\\*:\\s*v[0-9]+\\.[0-9]+\\.[0-9]+ usable" =
      paste0("**Status**: v", version, " usable")
  ))
  replace_file("ARCHITECTURE.md", list(
    "not implemented in [0-9]+\\.[0-9]+\\.[0-9]+:" =
      paste0("not implemented in ", version, ":")
  ))
  ensure_news_heading(version, date)
  ensure_vignette_version("vignettes/getting_started.Rmd")
  ensure_vignette_version("vignettes/dsl_reference.Rmd")
  # pkgdown reads DESCRIPTION Version automatically; keep a comment in yml
  yml <- file.path(root, "_pkgdown.yml")
  if (file.exists(yml))
    message("note: _pkgdown.yml uses DESCRIPTION Version via pkgdown (no edit needed)")
  message("Synced package version ", version, " (Date ", date, ")")
  invisible(version)
}

# ── main ──────────────────────────────────────────────────────────────────────

args <- commandArgs(trailingOnly = TRUE)
sync_only <- "--sync-only" %in% args
args <- setdiff(args, "--sync-only")

cur <- read_desc_version()
old <- cur$Version
date <- format(Sys.Date(), "%Y-%m-%d")

if (sync_only) {
  set_desc_fields(date = date)
  sync_version(old, date)
  quit(save = "no", status = 0L)
}

if (length(args) != 1L) {
  message("Usage: Rscript scripts/bump_version.R [patch|minor|major|X.Y.Z|--sync-only]")
  message("Current version: ", old)
  quit(save = "no", status = 1L)
}

spec <- args[[1L]]
if (spec %in% c("major", "minor", "patch")) {
  new <- format_version(bump_parts(parse_version(old), spec))
} else {
  invisible(format_version(parse_version(spec)))
}

set_desc_fields(version = new, date = date)
message("DESCRIPTION: ", old, " -> ", new)
sync_version(new, date)
message("Done. Consider: devtools::document(); pkgdown::build_site()")
