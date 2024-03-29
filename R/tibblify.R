#' Rectangle a nested list
#'
#' @param x A nested list.
#' @param spec A specification how to convert `x`. Generated with `tspec_row()`
#'   or `tspec_df()`.
#' @param unspecified A string that describes what happens if the specification
#'   contains unspecified fields. Can be one of
#'   * `"error"`: Throw an error.
#'   * `"inform"`: Inform.
#'   * `"drop"`: Do not parse these fields.
#'   * `"list"`: Parse an unspecified field into a list.
#'
#' @return Either a tibble or a list, depending on the specification
#' @seealso Use [`untibblify()`] to undo the result of `tibblify()`.
#' @export
#'
#' @examples
#' # List of Objects -----------------------------------------------------------
#' x <- list(
#'   list(id = 1, name = "Tyrion Lannister"),
#'   list(id = 2, name = "Victarion Greyjoy")
#' )
#' tibblify(x)
#'
#' # Provide a specification
#' spec <- tspec_df(
#'   id = tib_int("id"),
#'   name = tib_chr("name")
#' )
#' tibblify(x, spec)
#'
#' # Object --------------------------------------------------------------------
#' # Provide a specification for a single object
#' tibblify(x[[1]], tspec_object(spec))
#'
#' # Recursive Trees -----------------------------------------------------------
#' x <- list(
#'   list(
#'     id = 1,
#'     name = "a",
#'     children = list(
#'       list(id = 11, name = "aa"),
#'       list(id = 12, name = "ab", children = list(
#'         list(id = 121, name = "aba")
#'       ))
#'     ))
#' )
#' spec <- tspec_recursive(
#'   tib_int("id"),
#'   tib_chr("name"),
#'   .children = "children"
#' )
#' out <- tibblify(x, spec)
#' out
#' out$children
#' out$children[[1]]$children[[2]]
tibblify <- function(x,
                     spec = NULL,
                     unspecified = NULL) {
  withr::local_locale(c(LC_COLLATE = "C"))

  if (is_null(spec)) {
    spec <- guess_tspec(x, inform_unspecified = TRUE, call = current_call())
    unspecified <- unspecified %||% "list"
  }

  if (!is_tspec(spec)) {
    friendly_type <- obj_type_friendly(spec)
    msg <- "{.arg spec} must be a tibblify spec, not {friendly_type}."
    cli::cli_abort(msg)
  }

  spec <- tibblify_prepare_unspecified(spec, unspecified, call = current_call())
  spec_org <- spec
  spec <- spec_prep(spec)
  spec$rowmajor <- spec$input_form == "rowmajor"

  path <- list(depth = 0, path_elts = list())
  call <- current_call()
  try_fetch(
    out <- .Call(ffi_tibblify, x, spec, path),
    error = function(cnd) {
      if (inherits(cnd, "tibblify_error")) {
        cnd$call <- call
        cnd_signal(cnd)
      }

      path_str <- path_to_string(path)
      tibblify_abort(
        "Problem while tibblifying {.arg {path_str}}",
        parent = cnd,
        call = call
      )
    }
  )

  if (inherits(spec_org, "tspec_object")) {
    out <- purrr::map2(spec_org$fields, out, finalize_tspec_object)
    class(out) <- "tibblify_object"
  }

  out <- set_spec(out, spec_org)
  attr(out, "waldo_opts") <- list(ignore_attr = c("tib_spec", "waldo_opts"))
  out
}

finalize_tspec_object <- function(field_spec, field) {
  UseMethod("finalize_tspec_object")
}

#' @export
finalize_tspec_object.tib_scalar <- function(field_spec, field) {
  field
}

#' @export
finalize_tspec_object.tib_df <- function(field_spec, field) {
  field[[1]]
}

#' @export
finalize_tspec_object.tib_row <- function(field_spec, field) {
  purrr::map2(field_spec$fields, field, finalize_tspec_object)
}

#' @export
finalize_tspec_object.tib_variant <- function(field_spec, field) {
  field[[1]]
}

#' @export
finalize_tspec_object.tib_vector <- function(field_spec, field) {
  field[[1]]
}

#' @export
finalize_tspec_object.tib_recursive <- function(field_spec, field) {
  field[[1]]
}

spec_prep <- function(spec) {
  type <- spec$type
  if (type == "recursive") {
    # TODO how to rename?
    recursive_helper_field <- tib_df(
      spec$child,
      .required = FALSE
    )
    recursive_helper_field$type <- "recursive_helper"
    spec$fields[[spec$children_to]] <- recursive_helper_field
  }

  n_cols <- length(spec$fields)
  if (is_null(spec$names_col)) {
    coll_locations <- seq2(1, n_cols) - 1L
    spec$col_names <- names2(spec$fields)
  } else {
    coll_locations <- seq2(1, n_cols)
    n_cols <- n_cols + 1L
    spec$col_names <- c(spec$names_col, names(spec$fields))
  }

  spec$coll_locations <- as.list(coll_locations)
  spec$n_cols <- n_cols

  spec$ptype_dummy <- vctrs::vec_init(list(), n_cols)
  result <- prep_nested_keys2(spec$fields, coll_locations)
  spec$fields <- result$fields
  spec$keys <- result$keys
  spec$coll_locations <- result$coll_locations
  # TODO maybe add `key_match_ind`?

  if (type == "recursive") {
    spec$type <- "df"
    spec["names_col"] <- list(NULL)
    spec$child_coll_pos <- which(compat_map_chr(spec$fields, "type") == "recursive_helper") - 1L
  }

  spec
}

prep_nested_keys2 <- function(spec, coll_locations) {
  remove_first_key <- function(x) {
    x$key <- x$key[-1]
    x
  }

  keys <- lapply(spec, `[[`, "key")
  first_keys <- vapply(keys, `[[`, 1L, FUN.VALUE = character(1))
  key_order <- order(first_keys, method = "radix")

  spec <- spec[key_order]
  coll_locations <- coll_locations[key_order]
  keys <- keys[key_order]
  first_keys <- first_keys[key_order]

  is_sub <- lengths(keys) > 1
  spec_simple_prepped <- purrr::map(
    spec[!is_sub],
    function(x) {
      x$key <- x$key[[1]]

      x <- switch (x$type,
        scalar = prep_tib_scalar(x),
        vector = prep_tib_vector(x),
        row = spec_prep(x),
        df = spec_prep(x),
        recursive = spec_prep(x),
        x
      )

      x
    }
  )

  if (!any(is_sub)) {
    out <- list(
      fields = spec_simple_prepped,
      coll_locations = vctrs::vec_chop(coll_locations),
      keys = first_keys
    )

    return(out)
  }

  spec_complex <- purrr::map(spec[is_sub], remove_first_key)
  spec_split <- vec_split(spec_complex, first_keys[is_sub])
  spec_complex_prepped <- purrr::map2(
    spec_split$key, spec_split$val,
    function(key, sub_spec) {
      out <- list(
        key = key,
        type = "sub",
        fields = sub_spec
      )

      spec_prep(out)
    }
  )

  spec_out <- c(
    spec_simple_prepped,
    spec_complex_prepped
  )
  coll_locations <- c(
    vec_chop(coll_locations[!is_sub]),
    vec_split(coll_locations[is_sub], first_keys[is_sub])$val
  )

  first_keys <- compat_map_chr(spec_out, list("key", 1))
  key_order <- order(first_keys)

  list(
    fields = spec_out[key_order],
    coll_locations = coll_locations[key_order],
    keys = first_keys[key_order]
  )
}

prep_tib_scalar <- function(x) {
  x$na <- vctrs::vec_init(x$ptype_inner, 1L)
  x
}

prep_tib_vector <- function(x) {
  if (!is.null(x$names_to) || !is.null(x$values_to)) {
    if (!is.null(x$names_to)) {
      col_names <- c(x$names_to, x$values_to)
      list_of_ptype <- list(character(), x$ptype)
      fill_list <- list(names(x$fill), unname(x$fill))
    } else {
      col_names <- x$values_to
      list_of_ptype <- list(x$ptype)
      fill_list <- list(unname(x$fill))
    }
    if (!is.null(x$fill)) {
      x$fill <- tibble::as_tibble(set_names(fill_list, col_names))
    }
    list_of_ptype <- set_names(list_of_ptype, col_names)
    list_of_ptype <- tibble::as_tibble(list_of_ptype)
  } else {
    col_names <- NULL
    list_of_ptype <- x$ptype
  }

  x["col_names"] <- list(col_names)
  x$list_of_ptype <- list_of_ptype
  x$na <- vec_init(x$ptype)

  x
}

tibblify_prepare_unspecified <- function(spec, unspecified, call) {
  unspecified <- unspecified %||% "error"
  unspecified <- arg_match0(
    unspecified,
    c("error", "inform", "drop", "list"),
    arg_nm = "unspecified",
    error_call = call
  )

  if (unspecified %in% c("inform", "error")) {
    spec_inform_unspecified(spec, action = unspecified, call = call)
  } else {
    spec_replace_unspecified(spec, unspecified)
  }
}

spec_replace_unspecified <- function(spec, unspecified) {
  fields <- spec$fields

  # need to go backwards over fields because some are removed
  for (i in rev(seq_along(spec$fields))) {
    field <- spec$fields[[i]]
    if (field$type == "unspecified") {
      if (unspecified == "drop") {
        fields[[i]] <- NULL
      } else {
        fields[[i]] <- tib_variant(field$key, required = field$required)
      }
    } else if (field$type %in% c("df", "row")) {
      fields[[i]] <- spec_replace_unspecified(field, unspecified)
    }
  }

  spec$fields <- fields
  spec
}

set_spec <- function(x, spec) {
  attr(x, "tib_spec") <- spec
  x
}

#' Examine the column specification
#'
#' @param x The data frame object to extract from.
#'
#' @export
#' @return A tibblify specification object.
#' @examples
#' df <- tibblify(list(list(x = 1, y = "a"), list(x = 2)))
#' get_spec(df)
get_spec <- function(x) {
  attr(x, "tib_spec")
}
