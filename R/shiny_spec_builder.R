# R/shiny_spec_builder.R ---------------------------------------------------
# miniUI Shiny gadget: forms + JSON two-way sync for ksTable DSL specs.
# Requires Suggested packages shiny + miniUI (checked by kst_spec_builder()).

# Compact schema help under a field.
kst_field_help <- function(...) {
  shiny::helpText(
    style = "color:#555; font-size:11px; margin:2px 0 10px 0; line-height:1.35;",
    ...
  )
}

# Right-hand help card for denominator.type
kst_denom_help_panel <- function(type) {
  type <- type %||% ""
  all_types <- shiny::tags$ul(
    style = "padding-left: 18px; margin: 4px 0;",
    shiny::tags$li(shiny::tags$b("n"), ": rows in the current groups.by cell (",
                   shiny::tags$code("dplyr::n()"), ")."),
    shiny::tags$li(shiny::tags$b("n_distinct"), ": distinct values of a column in that cell."),
    shiny::tags$li(shiny::tags$b("data_n"), ": pre-aggregate analysis data over a ",
                   shiny::tags$em("subset"), " of groups.by, then join."),
    shiny::tags$li(shiny::tags$b("external"), ": population / big-N object from the eval env ",
                   "(keyed tibble or scalar).")
  )
  detail <- switch(
    type,
    "n" = "No extra fields. Emitted as denom = dplyr::n().",
    "n_distinct" = "Requires variable (e.g. USUBJID). Emitted as denom = dplyr::n_distinct(VAR).",
    "data_n" = paste(
      "Requires by (subset of groups.by). Optional distinct -> n_distinct during pre-agg;",
      "omit distinct for row count. Compiler builds .kst_dK and uses dplyr::first(.kst_dK)."
    ),
    "external" = paste(
      "Requires name (env object). With by, also require value (N column) and join keys;",
      "without by, name is a scalar symbol (e.g. N_total)."
    ),
    "Choose a type to see field requirements. The calc function still owns percent math;",
    "the DSL only wires denom=."
  )
  shiny::div(
    style = "background:#f7f7f7; border:1px solid #e0e0e0; border-radius:4px; padding:8px 10px; font-size:11px; line-height:1.4;",
    shiny::strong("Denominator types"),
    all_types,
    shiny::tags$p(style = "margin:8px 0 0 0;", shiny::tags$b("Selected: "), detail)
  )
}

spec_builder_app <- function(start_spec) {
  stopifnot(is.list(start_spec))
  has_ace <- requireNamespace("shinyAce", quietly = TRUE)

  ui <- miniUI::miniPage(
    shiny::tags$style(shiny::HTML("
      .kst-section-nav .shiny-options-group { margin-top: 0; }
      .kst-section-nav label.radio-inline { margin-right: 12px; font-weight: 600; }
      .kst-pane { height: 100%; overflow-y: auto; padding: 4px 8px; }
      .kst-json-pane { display: flex; flex-direction: column; height: 100%;
                       padding: 4px 8px; border-left: 1px solid #ddd; }
    ")),
    miniUI::gadgetTitleBar("ksTable Spec Builder"),
    miniUI::miniContentPanel(
      padding = 6,
      shiny::fillRow(
        flex = c(1, 1),
        shiny::div(
          class = "kst-pane",
          shiny::selectInput(
            "load_example",
            "Load packaged example",
            choices = c("(choose...)" = "", stats::setNames(spec_list_examples(),
                                                          spec_list_examples())),
            width = "100%"
          ),
          shiny::div(
            class = "kst-section-nav",
            shiny::radioButtons(
              "form_section",
              label = NULL,
              choices = c(
                "Meta", "Parameters", "Statistics",
                "Groups", "Layout", "Preview"
              ),
              selected = "Meta",
              inline = TRUE
            )
          ),
          shiny::uiOutput("json_freeze_banner"),
          shiny::hr(style = "margin: 6px 0;"),
          # One visible section at a time (avoids broken nested shiny/bootstrap tabs in miniUI)
          shiny::conditionalPanel(
            "input.form_section == 'Meta'",
            shiny::uiOutput("form_meta")
          ),
          shiny::conditionalPanel(
            "input.form_section == 'Parameters'",
            shiny::uiOutput("form_params")
          ),
          shiny::conditionalPanel(
            "input.form_section == 'Statistics'",
            shiny::uiOutput("form_stats")
          ),
          shiny::conditionalPanel(
            "input.form_section == 'Groups'",
            shiny::uiOutput("form_groups")
          ),
          shiny::conditionalPanel(
            "input.form_section == 'Layout'",
            shiny::uiOutput("form_layout")
          ),
          shiny::conditionalPanel(
            "input.form_section == 'Preview'",
            shiny::uiOutput("form_preview")
          )
        ),
        shiny::div(
          class = "kst-json-pane",
          shiny::strong("JSON"),
          shiny::div(
            style = "flex: 1; min-height: 360px;",
            if (has_ace) {
              shinyAce::aceEditor(
                "json_text",
                value = spec_to_json(start_spec),
                mode = "json",
                theme = "textmate",
                height = "420px",
                fontSize = 12,
                wordWrap = TRUE,
                showLineNumbers = TRUE,
                tabSize = 2
              )
            } else {
              shiny::textAreaInput(
                "json_text",
                label = NULL,
                value = spec_to_json(start_spec),
                width = "100%",
                height = "420px"
              )
            }
          ),
          shiny::verbatimTextOutput("json_status", placeholder = TRUE),
          shiny::verbatimTextOutput("validate_out", placeholder = TRUE)
        )
      )
    ),
    miniUI::miniButtonBlock(
      shiny::actionButton("btn_load_file", "Load file..."),
      shiny::actionButton("btn_validate", "Validate", class = "btn-info"),
      shiny::actionButton("btn_insert", "Insert JSON", class = "btn-primary"),
      shiny::actionButton("btn_save_json", "Save JSON"),
      shiny::actionButton("btn_compile", "Compile->.R", class = "btn-success")
    )
  )

  server <- function(input, output, session) {
    rv <- shiny::reactiveValues(
      spec = start_spec,
      json_ok = TRUE,
      json_error = NULL,
      freeze = FALSE,
      form_tick = 0L,
      skip_json_observer = FALSE,
      last_source = "init",
      validate_msg = "",
      prefer_param = NULL,
      prefer_stat = NULL
    )

    # Push JSON text without re-entering the JSON observer.
    set_json_text <- function(text) {
      rv$skip_json_observer <- TRUE
      if (has_ace) {
        shinyAce::updateAceEditor(session, "json_text", value = text)
      } else {
        shiny::updateTextAreaInput(session, "json_text", value = text)
      }
    }

    push_spec_from_forms <- function(new_spec) {
      if (isTRUE(rv$freeze)) return(invisible())
      rv$spec <- new_spec
      rv$last_source <- "forms"
      rv$json_ok <- TRUE
      rv$json_error <- NULL
      set_json_text(spec_to_json(new_spec))
    }

    # Debounced JSON -> spec
    json_debounced <- shiny::debounce(
      shiny::reactive(input$json_text %||% ""),
      300
    )

    shiny::observeEvent(json_debounced(), {
      if (isTRUE(rv$skip_json_observer)) {
        rv$skip_json_observer <- FALSE
        return()
      }
      text <- json_debounced()
      parsed <- json_to_spec(text)
      if (!isTRUE(parsed$ok)) {
        rv$json_ok <- FALSE
        rv$json_error <- parsed$error
        rv$freeze <- TRUE
        return()
      }
      rv$json_ok <- TRUE
      rv$json_error <- NULL
      rv$freeze <- FALSE
      rv$spec <- parsed$spec
      rv$last_source <- "json"
      rv$form_tick <- rv$form_tick + 1L
    }, ignoreInit = TRUE)

    output$json_freeze_banner <- shiny::renderUI({
      if (!isTRUE(rv$freeze)) return(NULL)
      shiny::div(
        class = "alert alert-warning",
        style = "padding: 6px 10px; margin-bottom: 8px;",
        shiny::strong("JSON parse error - forms paused. "),
        rv$json_error %||% ""
      )
    })

    output$json_status <- shiny::renderText({
      if (isTRUE(rv$json_ok)) "JSON: OK"
      else paste0("JSON: ERROR - ", rv$json_error %||% "")
    })

    # -- Meta --------------------------------------------------------------
    output$form_meta <- shiny::renderUI({
      rv$form_tick
      ts <- rv$spec$table_spec %||% list()
      shiny::tagList(
        shiny::textInput("meta_id", "id", value = ts$id %||% ""),
        kst_field_help("Optional table identifier string (not an R symbol). Used in docs / kst_save headers."),
        shiny::textInput("meta_title", "title", value = ts$title %||% ""),
        kst_field_help("Optional human-readable table title."),
        shiny::textInput("meta_schema", "schema_version",
                         value = rv$spec$schema_version %||% "1.0"),
        kst_field_help("DSL schema version. Currently must be \"1.0\"."),
        shiny::actionButton("meta_apply", "Apply meta", class = "btn-sm btn-default")
      )
    })

    shiny::observeEvent(input$meta_apply, {
      sp <- rv$spec
      sp$schema_version <- input$meta_schema %||% "1.0"
      sp$table_spec$id <- input$meta_id
      sp$table_spec$title <- input$meta_title
      push_spec_from_forms(sp)
    })

    # -- Groups ------------------------------------------------------------
    output$form_groups <- shiny::renderUI({
      rv$form_tick
      g <- rv$spec$table_spec$groups %||% list()
      by_txt <- paste(unlist(g$by %||% list()), collapse = ", ")
      fmt <- g$format %||% list()
      fmt_txt <- if (length(fmt)) {
        paste(sprintf("%s=%s", names(fmt), unlist(fmt)), collapse = ", ")
      } else ""
      shiny::tagList(
        shiny::textInput("groups_by", "by (comma-separated)", value = by_txt),
        kst_field_help(
          "Required. Stratification columns; after pivot_wider these become column headers. ",
          "Each name must be an R identifier (SR-1)."
        ),
        shiny::checkboxInput("groups_miss", "include_missing_levels",
                             value = isTRUE(g$include_missing_levels)),
        kst_field_help(
          "If TRUE, emits group_by(..., .drop = FALSE) so empty factor levels appear. ",
          "Apply factor levels with kst_extract_metadata / kst_apply_metadata before eval."
        ),
        shiny::textInput("groups_format", "format map (docs only)", value = fmt_txt),
        kst_field_help(
          "Optional documentation: COL=ksformat_name pairs. The compiler does ",
          shiny::tags$em("not"),
          " apply these - pass the same mapping as format_map to metadata helpers. ",
          "Example: TRT01P=trt_fmt, SEX=sex_fmt"
        ),
        shiny::actionButton("groups_apply", "Apply groups", class = "btn-sm")
      )
    })

    shiny::observeEvent(input$groups_apply, {
      sp <- rv$spec
      by <- trimws(strsplit(input$groups_by %||% "", ",", fixed = TRUE)[[1L]])
      by <- by[nzchar(by)]
      sp$table_spec$groups$by <- as.list(by)
      sp$table_spec$groups$include_missing_levels <- isTRUE(input$groups_miss)
      fmt_raw <- trimws(input$groups_format %||% "")
      if (nzchar(fmt_raw)) {
        parts <- trimws(strsplit(fmt_raw, ",", fixed = TRUE)[[1L]])
        kv <- strsplit(parts, "=", fixed = TRUE)
        nm <- vapply(kv, function(x) trimws(x[[1L]]), character(1L))
        vl <- vapply(kv, function(x) trimws(x[[length(x)]]), character(1L))
        sp$table_spec$groups$format <- stats::setNames(as.list(vl), nm)
      } else {
        sp$table_spec$groups$format <- NULL
      }
      push_spec_from_forms(sp)
    })

    # -- Layout ------------------------------------------------------------
    output$form_layout <- shiny::renderUI({
      rv$form_tick
      ly <- rv$spec$table_spec$layout %||% list()
      shiny::tagList(
        shiny::selectInput(
          "layout_row", "row_structure",
          choices = c("parameter_stat", "hierarchical"),
          selected = ly$row_structure %||% "parameter_stat"
        ),
        kst_field_help(
          shiny::tags$b("parameter_stat"), ": one row per parameter x statistic; columns = group levels. ",
          shiny::tags$b("hierarchical"), ": parent + one nested child (e.g. SOC -> PT); uses first parameter, ",
          "first nested child, and first statistic only."
        ),
        shiny::selectInput(
          "layout_col", "column_structure",
          choices = c("groups"),
          selected = ly$column_structure %||% "groups"
        ),
        kst_field_help("Only \"groups\" is supported: pivot_wider on groups.by combinations."),
        shiny::actionButton("layout_apply", "Apply layout", class = "btn-sm")
      )
    })

    shiny::observeEvent(input$layout_apply, {
      sp <- rv$spec
      sp$table_spec$layout$row_structure <- input$layout_row
      sp$table_spec$layout$column_structure <- input$layout_col
      push_spec_from_forms(sp)
    })

    # -- Parameters --------------------------------------------------------
    output$form_params <- shiny::renderUI({
      rv$form_tick
      params <- rv$spec$table_spec$parameter %||% list()
      ids <- names(params)
      if (!length(ids)) ids <- character(0)
      prefer <- rv$prefer_param
      rv$prefer_param <- NULL
      sel <- prefer %||% input$param_sel
      if (is.null(sel) || !sel %in% ids) sel <- if (length(ids)) ids[[1L]] else ""
      p <- if (nzchar(sel) && !is.null(params[[sel]])) params[[sel]] else list()

      vars <- p[["variables"]]
      var_txt <- if (!is.null(vars)) {
        paste(unlist(vars), collapse = ", ")
      } else {
        p[["variable"]] %||% ""
      }
      labels <- p[["labels"]]
      lab_txt <- if (!is.null(labels)) {
        paste(unlist(labels), collapse = ", ")
      } else {
        p[["label"]] %||% ""
      }
      nested <- p$nested
      nest_id <- if (!is.null(nested) && length(nested)) names(nested)[[1L]] else ""
      nest_var <- if (nzchar(nest_id)) nested[[nest_id]]$variable %||% "" else ""
      nest_lab <- if (nzchar(nest_id)) nested[[nest_id]]$label %||% "" else ""

      shiny::tagList(
        shiny::selectInput(
          "param_sel", "Select parameter",
          choices = if (length(ids)) ids else c("(none)" = ""),
          selected = sel
        ),
        kst_field_help("Pick which parameter block to edit. Keys are the JSON names under table_spec.parameter."),
        shiny::fluidRow(
          shiny::column(6, shiny::actionButton("param_add", "Add", class = "btn-sm")),
          shiny::column(6, shiny::actionButton("param_del", "Remove", class = "btn-sm btn-danger"))
        ),
        shiny::hr(),
        shiny::textInput("param_id", "Rename parameter key", value = sel),
        kst_field_help(
          "Change the JSON key for this parameter (e.g. age -> cont). Must be an R identifier ",
          "(SR-1: letters/dots/underscores). Click ", shiny::tags$b("Apply parameter"),
          " to rename."
        ),
        shiny::radioButtons(
          "param_mode", "Shape",
          choices = c("single variable" = "single", "variables array" = "multi"),
          selected = if (!is.null(p[["variables"]])) "multi" else "single",
          inline = TRUE
        ),
        kst_field_help(
          "Single: one column via \"variable\" + optional \"label\". ",
          "Array: \"variables\" (+ optional \"labels\") - each column gets its own row block."
        ),
        shiny::textInput("param_vars", "variable / variables (comma-sep)", value = var_txt),
        kst_field_help("Data column name(s). Mutually exclusive shapes: variable vs variables."),
        shiny::textInput("param_labs", "label / labels (comma-sep)", value = lab_txt),
        kst_field_help(
          "Display label(s) for .param. If labels is shorter than variables, missing entries ",
          "default to the variable name."
        ),
        shiny::hr(),
        shiny::strong("Nested child (hierarchical layout)"),
        kst_field_help(
          "Exactly one nested child when row_structure is hierarchical (e.g. parent AESOC, ",
          "child AEDECOD). Leave blank for parameter_stat."
        ),
        shiny::textInput("param_nest_id", "nested id (JSON key)", value = nest_id),
        shiny::textInput("param_nest_var", "nested variable", value = nest_var),
        shiny::textInput("param_nest_lab", "nested label (optional)", value = nest_lab),
        shiny::actionButton("param_apply", "Apply parameter", class = "btn-sm btn-primary")
      )
    })

    shiny::observeEvent(input$param_add, {
      sp <- rv$spec
      if (is.null(sp$table_spec$parameter)) sp$table_spec$parameter <- list()
      base <- "param"
      i <- 1L
      while (paste0(base, i) %in% names(sp$table_spec$parameter)) i <- i + 1L
      id <- paste0(base, i)
      sp$table_spec$parameter[[id]] <- list(variable = "VAR", label = "VAR")
      rv$prefer_param <- id
      push_spec_from_forms(sp)
      rv$form_tick <- rv$form_tick + 1L
    })

    shiny::observeEvent(input$param_del, {
      sp <- rv$spec
      id <- input$param_sel
      if (!nzchar(id %||% "")) return()
      sp$table_spec$parameter[[id]] <- NULL
      push_spec_from_forms(sp)
    })

    shiny::observeEvent(input$param_apply, {
      sp <- rv$spec
      old_id <- input$param_sel %||% ""
      new_id <- trimws(input$param_id %||% "")
      if (!nzchar(new_id)) return()
      if (!grepl("^[A-Za-z.][A-Za-z0-9._]*$", new_id)) {
        rv$validate_msg <- paste0(
          "Invalid parameter key '", new_id,
          "' - must be an R identifier (SR-1)."
        )
        return()
      }
      vars <- trimws(strsplit(input$param_vars %||% "", ",", fixed = TRUE)[[1L]])
      vars <- vars[nzchar(vars)]
      labs <- trimws(strsplit(input$param_labs %||% "", ",", fixed = TRUE)[[1L]])
      labs <- labs[nzchar(labs)]
      p <- list()
      if (identical(input$param_mode, "multi")) {
        p$variables <- as.list(vars)
        if (length(labs)) p$labels <- as.list(labs)
      } else {
        p$variable <- if (length(vars)) vars[[1L]] else "VAR"
        if (length(labs)) p$label <- labs[[1L]]
        else if (length(vars)) p$label <- vars[[1L]]
      }
      nid <- trimws(input$param_nest_id %||% "")
      nvar <- trimws(input$param_nest_var %||% "")
      if (nzchar(nid) && nzchar(nvar)) {
        child <- list(variable = nvar)
        nlab <- trimws(input$param_nest_lab %||% "")
        if (nzchar(nlab)) child$label <- nlab
        p$nested <- stats::setNames(list(child), nid)
      }
      if (is.null(sp$table_spec$parameter)) sp$table_spec$parameter <- list()
      if (nzchar(old_id) && !identical(old_id, new_id) && !is.null(sp$table_spec$parameter[[old_id]]))
        sp$table_spec$parameter[[old_id]] <- NULL
      sp$table_spec$parameter[[new_id]] <- p
      rv$prefer_param <- new_id
      push_spec_from_forms(sp)
      rv$form_tick <- rv$form_tick + 1L
      rv$validate_msg <- if (!identical(old_id, new_id) && nzchar(old_id))
        paste0("Renamed parameter '", old_id, "' -> '", new_id, "'.")
      else
        paste0("Applied parameter '", new_id, "'.")
    })

    # -- Statistics --------------------------------------------------------
    output$form_stats <- shiny::renderUI({
      rv$form_tick
      stats <- rv$spec$table_spec$statistics %||% list()
      ids <- names(stats)
      if (!length(ids)) ids <- character(0)
      prefer <- rv$prefer_stat
      rv$prefer_stat <- NULL
      sel <- prefer %||% input$stat_sel
      if (is.null(sel) || !sel %in% ids) sel <- if (length(ids)) ids[[1L]] else ""
      s <- if (nzchar(sel) && !is.null(stats[[sel]])) stats[[sel]] else list()

      args <- s$args %||% list()
      args_txt <- if (length(args)) {
        paste(vapply(names(args), function(k) {
          v <- args[[k]]
          if (is.null(v)) paste0(k, "=null")
          else if (is.logical(v)) paste0(k, "=", if (isTRUE(v)) "true" else "false")
          else if (is.numeric(v)) paste0(k, "=", v)
          else paste0(k, "=", as.character(v))
        }, character(1L)), collapse = ", ")
      } else ""

      apply_to <- paste(unlist(s$apply_to %||% list()), collapse = ", ")
      fmt <- s$format %||% list()
      denom <- s$denominator %||% list()
      den_type <- denom$type %||% ""

      shiny::tagList(
        shiny::selectInput(
          "stat_sel", "Select statistic",
          choices = if (length(ids)) ids else c("(none)" = ""),
          selected = sel
        ),
        kst_field_help("JSON keys under table_spec.statistics; key order is row order in the table."),
        shiny::fluidRow(
          shiny::column(6, shiny::actionButton("stat_add", "Add", class = "btn-sm")),
          shiny::column(6, shiny::actionButton("stat_del", "Remove", class = "btn-sm btn-danger"))
        ),
        shiny::hr(),
        shiny::textInput("stat_id", "Rename statistic key", value = sel),
        kst_field_help(
          "Change the JSON key (e.g. n -> n_pct). Must be an R identifier (SR-1). ",
          "Click ", shiny::tags$b("Apply statistic"), " to rename."
        ),
        shiny::textInput("stat_fun", "fun", value = s$fun %||% ""),
        kst_field_help(
          "Calc function name from the eval environment. Receives the analysis column vector; ",
          "with denominator, also gets denom = <scalar>. May return a scalar or named list."
        ),
        shiny::textInput("stat_args", "args (k=v, ...)", value = args_txt),
        kst_field_help(
          "Extra literal args appended to fun(...), e.g. na.rm=true, probs=0.25. ",
          "Booleans true/false, null, numbers, or strings. Do not use args.denom - use denominator."
        ),
        shiny::textInput("stat_apply_to", "apply_to (comma-sep)", value = apply_to),
        kst_field_help(
          "Optional allow-list of parameter ids or variable names. If omitted, the statistic ",
          "applies to all parameters."
        ),
        shiny::hr(),
        shiny::strong("format"),
        kst_field_help(
          "Omit format to keep the raw type. sprintf -> pattern; custom -> fun; template -> glue ",
          "pattern (needs glue at eval); ksformat -> format_name."
        ),
        shiny::selectInput(
          "stat_fmt_type", "format type",
          choices = c("(none)" = "", "sprintf", "custom", "template", "ksformat"),
          selected = fmt$type %||% ""
        ),
        shiny::textInput("stat_fmt_pattern", "pattern (sprintf / template)",
                         value = fmt$pattern %||% ""),
        kst_field_help("sprintf: e.g. %.1f. template: e.g. {n} ({pct}%) matching list names from fun."),
        shiny::textInput("stat_fmt_fun", "fun (custom)", value = fmt$fun %||% ""),
        kst_field_help("Format function name in the eval env; receives each named-list element."),
        shiny::textInput("stat_fmt_name", "format_name (ksformat)",
                         value = fmt$format_name %||% ""),
        kst_field_help("Registered ksformat VALUE format name, e.g. trt_fmt."),
        shiny::hr(),
        shiny::strong("denominator"),
        shiny::fluidRow(
          shiny::column(
            6,
            shiny::selectInput(
              "stat_den_type", "type",
              choices = c("(none)" = "", "n", "n_distinct", "data_n", "external"),
              selected = den_type
            ),
            shiny::textInput("stat_den_variable", "variable (n_distinct)",
                             value = denom$variable %||% ""),
            kst_field_help("Column for n_distinct (required when type is n_distinct)."),
            shiny::textInput("stat_den_by", "by (comma-sep)",
                             value = paste(unlist(denom$by %||% list()), collapse = ", ")),
            kst_field_help("For data_n / external: keys; must be a subset of groups.by."),
            shiny::textInput("stat_den_distinct", "distinct (data_n)",
                             value = denom$distinct %||% ""),
            kst_field_help("Optional; if set, pre-agg uses n_distinct(col), else dplyr::n()."),
            shiny::textInput("stat_den_name", "name (external)",
                             value = denom$name %||% ""),
            kst_field_help("Eval-env object name (tibble or scalar). Required for external."),
            shiny::textInput("stat_den_value", "value (external)",
                             value = denom$value %||% ""),
            kst_field_help("N column on the external tibble; required when external.by is set.")
          ),
          shiny::column(
            6,
            shiny::uiOutput("stat_den_help")
          )
        ),
        shiny::actionButton("stat_apply", "Apply statistic", class = "btn-sm btn-primary")
      )
    })

    output$stat_den_help <- shiny::renderUI({
      kst_denom_help_panel(input$stat_den_type)
    })

    shiny::observeEvent(input$stat_add, {
      sp <- rv$spec
      if (is.null(sp$table_spec$statistics)) sp$table_spec$statistics <- list()
      base <- "stat"
      i <- 1L
      while (paste0(base, i) %in% names(sp$table_spec$statistics)) i <- i + 1L
      id <- paste0(base, i)
      sp$table_spec$statistics[[id]] <- list(fun = "length")
      rv$prefer_stat <- id
      push_spec_from_forms(sp)
      rv$form_tick <- rv$form_tick + 1L
    })

    shiny::observeEvent(input$stat_del, {
      sp <- rv$spec
      id <- input$stat_sel
      if (!nzchar(id %||% "")) return()
      sp$table_spec$statistics[[id]] <- NULL
      push_spec_from_forms(sp)
      rv$form_tick <- rv$form_tick + 1L
    })

    parse_args_field <- function(txt) {
      txt <- trimws(txt %||% "")
      if (!nzchar(txt)) return(NULL)
      parts <- trimws(strsplit(txt, ",", fixed = TRUE)[[1L]])
      out <- list()
      for (p in parts) {
        kv <- strsplit(p, "=", fixed = TRUE)[[1L]]
        if (length(kv) < 2L) next
        k <- trimws(kv[[1L]])
        vraw <- trimws(paste(kv[-1L], collapse = "="))
        if (identical(vraw, "true")) out[[k]] <- TRUE
        else if (identical(vraw, "false")) out[[k]] <- FALSE
        else if (identical(vraw, "null")) out[[k]] <- NULL
        else if (grepl("^[-+]?[0-9]*\\.?[0-9]+$", vraw)) out[[k]] <- as.numeric(vraw)
        else out[[k]] <- vraw
      }
      if (!length(out)) NULL else out
    }

    shiny::observeEvent(input$stat_apply, {
      sp <- rv$spec
      old_id <- input$stat_sel %||% ""
      new_id <- trimws(input$stat_id %||% "")
      if (!nzchar(new_id)) return()
      if (!grepl("^[A-Za-z.][A-Za-z0-9._]*$", new_id)) {
        rv$validate_msg <- paste0(
          "Invalid statistic key '", new_id,
          "' - must be an R identifier (SR-1)."
        )
        return()
      }
      s <- list(fun = trimws(input$stat_fun %||% "length"))
      args <- parse_args_field(input$stat_args)
      if (!is.null(args)) s$args <- args
      at <- trimws(strsplit(input$stat_apply_to %||% "", ",", fixed = TRUE)[[1L]])
      at <- at[nzchar(at)]
      if (length(at)) s$apply_to <- as.list(at)

      ft <- input$stat_fmt_type %||% ""
      if (nzchar(ft)) {
        fmt <- list(type = ft)
        if (ft %in% c("sprintf", "template"))
          fmt$pattern <- input$stat_fmt_pattern %||% ""
        if (identical(ft, "custom"))
          fmt$fun <- input$stat_fmt_fun %||% ""
        if (identical(ft, "ksformat"))
          fmt$format_name <- input$stat_fmt_name %||% ""
        s$format <- fmt
      }

      dt <- input$stat_den_type %||% ""
      if (nzchar(dt)) {
        d <- list(type = dt)
        if (identical(dt, "n_distinct"))
          d$variable <- trimws(input$stat_den_variable %||% "")
        if (dt %in% c("data_n", "external")) {
          by <- trimws(strsplit(input$stat_den_by %||% "", ",", fixed = TRUE)[[1L]])
          by <- by[nzchar(by)]
          if (length(by)) d$by <- as.list(by)
        }
        if (identical(dt, "data_n")) {
          dist <- trimws(input$stat_den_distinct %||% "")
          if (nzchar(dist)) d$distinct <- dist
        }
        if (identical(dt, "external")) {
          d$name <- trimws(input$stat_den_name %||% "")
          val <- trimws(input$stat_den_value %||% "")
          if (nzchar(val)) d$value <- val
        }
        s$denominator <- d
      }

      if (is.null(sp$table_spec$statistics)) sp$table_spec$statistics <- list()
      if (nzchar(old_id) && !identical(old_id, new_id) && !is.null(sp$table_spec$statistics[[old_id]]))
        sp$table_spec$statistics[[old_id]] <- NULL
      sp$table_spec$statistics[[new_id]] <- s
      rv$prefer_stat <- new_id
      push_spec_from_forms(sp)
      rv$form_tick <- rv$form_tick + 1L
      rv$validate_msg <- if (!identical(old_id, new_id) && nzchar(old_id))
        paste0("Renamed statistic '", old_id, "' -> '", new_id, "'.")
      else
        paste0("Applied statistic '", new_id, "'.")
    })

    # -- Preview -----------------------------------------------------------
    output$form_preview <- shiny::renderUI({
      rv$form_tick
      v <- spec_validate_live(rv$spec)
      code <- tryCatch(kst_compile(spec_to_json(rv$spec)), error = function(e) NULL)
      shiny::tagList(
        shiny::h4(if (isTRUE(v$valid)) "Valid" else "Invalid"),
        if (!isTRUE(v$valid))
          shiny::tags$ul(lapply(v$errors, shiny::tags$li)),
        shiny::hr(),
        shiny::strong("Compiled script preview"),
        shiny::tags$pre(
          style = "max-height: 360px; overflow: auto; font-size: 11px;",
          if (is.null(code)) "(fix on compile - fix validation errors first)" else code
        )
      )
    })

    # -- Actions -----------------------------------------------------------
    current_json <- function() {
      if (isTRUE(rv$json_ok)) spec_to_json(rv$spec)
      else input$json_text %||% spec_to_json(rv$spec)
    }

    shiny::observeEvent(input$load_example, {
      nm <- input$load_example
      if (!nzchar(nm %||% "")) return()
      sp <- tryCatch(spec_from_example(nm), error = function(e) {
        rv$validate_msg <- conditionMessage(e)
        NULL
      })
      if (is.null(sp)) return()
      rv$freeze <- FALSE
      rv$json_ok <- TRUE
      rv$json_error <- NULL
      rv$spec <- sp
      rv$form_tick <- rv$form_tick + 1L
      set_json_text(spec_to_json(sp))
      shiny::updateSelectInput(session, "load_example", selected = "")
    }, ignoreInit = TRUE)

    shiny::observeEvent(input$btn_load_file, {
      path <- tryCatch(file.choose(new = FALSE), error = function(e) "")
      if (!nzchar(path)) return()
      raw <- paste(readLines(path, warn = FALSE), collapse = "\n")
      parsed <- json_to_spec(raw)
      if (!isTRUE(parsed$ok)) {
        rv$validate_msg <- paste("Load failed:", parsed$error)
        return()
      }
      rv$freeze <- FALSE
      rv$json_ok <- TRUE
      rv$json_error <- NULL
      rv$spec <- parsed$spec
      rv$form_tick <- rv$form_tick + 1L
      set_json_text(spec_to_json(parsed$spec))
      rv$validate_msg <- paste("Loaded", basename(path))
    })

    shiny::observeEvent(input$btn_validate, {
      v <- spec_validate_live(current_json())
      rv$validate_msg <- if (isTRUE(v$valid)) {
        paste0("Valid (engine: ", v$engine, ")")
      } else {
        paste(c("Invalid:", v$errors), collapse = "\n")
      }
    })

    output$validate_out <- shiny::renderText(rv$validate_msg)

    shiny::observeEvent(input$btn_insert, {
      json <- current_json()
      v <- spec_validate_live(json)
      if (!isTRUE(v$valid)) {
        rv$validate_msg <- paste(c("Insert blocked - invalid:", v$errors), collapse = "\n")
        return()
      }
      if (!requireNamespace("rstudioapi", quietly = TRUE) ||
          !isTRUE(rstudioapi::isAvailable())) {
        rv$validate_msg <- "rstudioapi not available; cannot insert."
        return()
      }
      rstudioapi::insertText(json)
      rv$validate_msg <- "Inserted JSON at cursor."
    })

    shiny::observeEvent(input$btn_save_json, {
      json <- current_json()
      v <- spec_validate_live(json)
      if (!isTRUE(v$valid)) {
        rv$validate_msg <- paste(c("Save blocked - invalid:", v$errors), collapse = "\n")
        return()
      }
      path <- tryCatch(file.choose(new = TRUE), error = function(e) "")
      if (!nzchar(path)) return()
      if (!grepl("\\.json$", path, ignore.case = TRUE))
        path <- paste0(path, ".json")
      writeLines(json, path)
      rv$validate_msg <- paste("Saved", path)
    })

    shiny::observeEvent(input$btn_compile, {
      json <- current_json()
      v <- spec_validate_live(json)
      if (!isTRUE(v$valid)) {
        rv$validate_msg <- paste(c("Compile blocked - invalid:", v$errors), collapse = "\n")
        return()
      }
      path <- tryCatch(file.choose(new = TRUE), error = function(e) "")
      if (!nzchar(path)) return()
      if (!grepl("\\.R$", path, ignore.case = TRUE))
        path <- paste0(path, ".R")
      tryCatch({
        kst_save(json, path, overwrite = TRUE)
        rv$validate_msg <- paste("Compiled script saved to", path)
      }, error = function(e) {
        rv$validate_msg <- paste("Compile failed:", conditionMessage(e))
      })
    })

    shiny::observeEvent(input$done, {
      shiny::stopApp(rv$spec)
    })

    shiny::observeEvent(input$cancel, {
      shiny::stopApp(NULL)
    })
  }

  shiny::shinyApp(ui, server)
}
