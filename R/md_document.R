#' Convert to a markdown document
#'
#' Format for converting from R Markdown to another variant of markdown (e.g.
#' strict markdown or github flavored markdown)
#'
#' See the [online
#' documentation](https://bookdown.org/yihui/rmarkdown/markdown-document.html)
#' for additional details on using the `md_document()` format.
#'
#' R Markdown documents can have optional metadata that is used to generate a
#' document header that includes the title, author, and date. For more details
#' see the documentation on R Markdown [metadata][rmd_metadata].
#' @inheritParams html_document
#' @param variant Markdown variant to produce (defaults to "markdown_strict").
#'   Other valid values are "commonmark", "gfm", "commonmark_x", "markdown_mmd",
#'   markdown_phpextra", "markdown_github", or even "markdown" (which produces
#'   pandoc markdown). You can also compose custom markdown variants, see the
#'   \href{https://pandoc.org/MANUAL.html}{pandoc online documentation} for
#'   details.
#' @param preserve_yaml Preserve YAML front matter in final document.
#' @param standalone Set to `TRUE` to include title, date and other metadata
#'   field in addition to Rmd content as a body.
#' @param fig_retina Scaling to perform for retina displays. Defaults to
#'   `NULL` which performs no scaling. A setting of 2 will work for all
#'   widely used retina displays, but will also result in the output of
#'   `<img>` tags rather than markdown images due to the need to set the
#'   width of the image explicitly.
#' @param ext Extension of the output file (defaults to ".md").
#' @return R Markdown output format to pass to [render()]
#' @examples
#' \dontrun{
#' library(rmarkdown)
#'
#' render("input.Rmd", md_document())
#'
#' render("input.Rmd", md_document(variant = "markdown_github"))
#' }
#' @export
#' @md
md_document <- function(variant = "markdown_strict",
                        preserve_yaml = FALSE,
                        toc = FALSE,
                        toc_depth = 3,
                        number_sections = FALSE,
                        standalone = FALSE,
                        fig_width = 7,
                        fig_height = 5,
                        fig_retina = NULL,
                        dev = 'png',
                        df_print = "default",
                        includes = NULL,
                        md_extensions = NULL,
                        pandoc_args = NULL,
                        ext = ".md") {


  # base pandoc options for all markdown output

  if (toc) standalone <- TRUE

  args <- c(if (standalone) "--standalone")

  # table of contents
  args <- c(args, pandoc_toc_args(toc, toc_depth))

  # content includes
  args <- c(args, includes_to_pandoc_args(includes))

  # pandoc args
  args <- c(args, pandoc_args)

  # Preprocess number_sections if variant is a markdown flavor +gfm_auto_identifiers
  if (number_sections && !pandoc_available("2.1")) {
    warning("`number_sections = TRUE` requires at least Pandoc 2.1. The feature will be deactivated",
            call. = FALSE)
    number_sections <- FALSE
  }
  pre_processor <- if (
    number_sections
    && grepl("^(commonmark|gfm|markdown)", variant)
    && any(grepl("+gfm_auto_identifiers", md_extensions, fixed = TRUE))
  ) {
    function(metadata, input_file, ...) {
      input_lines <- read_utf8(input_file)
      pandoc_convert(
        input_file, to = "markdown", output = input_file,
        options = c(
          "--lua-filter", pkg_file_lua("number-sections.lua"),
          "--metadata", "preprocess_number_sections=true"
        )
      )
      input_lines2 <- read_utf8(input_file)
      write_utf8(.preserve_yaml(input_lines, input_lines2), input_file)
      return(character(0L))
    }
  }

  # variants
  variant <- adapt_md_variant(variant)

  # add post_processor for yaml preservation as Pandoc +yaml_metadata_block has
  # undesired sorting (https://github.com/rstudio/rmarkdown/pull/2190/files)
  post_processor <- if (preserve_yaml) {
    function(metadata, input_file, output_file, clean, verbose) {
      input_lines <- read_utf8(input_file)
      output_lines <- read_utf8(output_file)
      write_utf8(
        .preserve_yaml(input_lines, output_lines),
        output_file
      )
      output_file
    }
  }

  # return format
  output_format(
    knitr = knitr_options_html(fig_width, fig_height, fig_retina, FALSE, dev),
    pandoc = pandoc_options(
      to = variant,
      from = from_rmarkdown(extensions = md_extensions),
      args = args,
      lua_filters = if (number_sections) pkg_file_lua("number-sections.lua"),
      ext = ext
    ),
    clean_supporting = FALSE,
    df_print = df_print,
    pre_processor = pre_processor,
    post_processor = post_processor
  )
}

.preserve_yaml <- function(input_lines, output_lines) {
  partitioned <- partition_yaml_front_matter(input_lines)
  if (!is.null(partitioned$front_matter)) {
    output_lines <- c(partitioned$front_matter, "", output_lines)
  }
  output_lines
}

adapt_md_variant <- function(variant) {
  variant_base <- gsub("^([^+-]*).*", "\\1", variant)
  variant_extensions <- gsub(sprintf("^%s", variant_base), "", variant)

  set_extension <- function(format, ext, add = TRUE) {
    ext <- paste0(ifelse(add, "+", "-"), ext)
    for (e in ext) {
      if (grepl(e, format, fixed = TRUE)) next
      format <- paste0(format, e, collapse = "")
    }
    format
  }

  # Remove yaml_metadata_block extension unless user asked otherwise in variant
  if (!grepl("yaml_metadata_block", variant_extensions, fixed = TRUE)) {
    variant_extensions <- switch(
      variant_base,
      gfm = ,
      commonmark = ,
      commonmark_x = {
        if (pandoc_available("2.13")) {
          set_extension(variant_extensions, "yaml_metadata_block", FALSE)
        } else {
          # Unsupported extension before YAML 2.13
          variant_extensions
        }
      },
      markdown = set_extension(variant_extensions, c("yaml_metadata_block", "pandoc_title_block"), FALSE),
      markdown_mmd = set_extension(variant_extensions, c("yaml_metadata_block", "mmd_title_block"), FALSE),
      markdown_github = ,
      markdown_phpextra = ,
      markdown_strict = set_extension(variant_extensions, "yaml_metadata_block", FALSE),
      # do not modified for unknown (yet) md variant
      variant_extensions
    )
  }

  paste0(variant_base, variant_extensions, collapse = "")
}
