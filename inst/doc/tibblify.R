## ---- include = FALSE---------------------------------------------------------
knitr::opts_chunk$set(
  collapse = TRUE,
  comment = "#>"
)

## ----setup--------------------------------------------------------------------

## ----usage_example------------------------------------------------------------
library(tibblify)

str(politicians[1])

## ----usage_leaders------------------------------------------------------------
politicians_tibble <- tibblify(politicians)
politicians_tibble

## ----usage_tibble_column------------------------------------------------------
politicians_tibble$parents

## ----usage_list_of_column-----------------------------------------------------
politicians_tibble$spouses

## ----specification------------------------------------------------------------
get_spec(politicians_tibble)

## ----path_examples------------------------------------------------------------
leader <- politicians[[1]]

# get the element `id`
path <- c("id")
leader[["id"]]

# get the element `father` in the element `parents`
path <- c("parents", "father")
leader[["parents"]][["mother"]]

# get the first element in the element `spouses`
path <- list("spouses", 1)
leader[["spouses"]][[1]]

## ----vector_cols--------------------------------------------------------------
tibblify(
  politicians,
  lcols(
    lcol_int("id"),
    lcol_chr("name"),
    `family name` = lcol_chr("surname")
  )
)

## ----missing_elements, error=TRUE---------------------------------------------
list_default <- list(
  list(a = 1),
  list(a = NULL),
  list(a = integer()),
  list()
)

tibblify(
  list_default,
  lcols(lcol_int("a"))
)

tibblify(
  list_default,
  lcols(lcol_int("a", .default = 0))
)

## ----custom_parser------------------------------------------------------------
tibblify(
  politicians,
  lcols(
    lcol_chr("surname"),
    lcol_dat("dob", .parser = ~ as.Date(.x, format = "%Y-%m-%d"))
  )
)

## -----------------------------------------------------------------------------
spouses_tbl <- tibblify(
  politicians,
  lcols(
    lcol_chr("surname"),
    lcol_lst_of("spouses", .ptype = character())
  )
)

spouses_tbl$spouses

## -----------------------------------------------------------------------------
leaders_tibble <- tibblify(
  politicians,
  lcols(
    lcol_chr("surname"),
    lcol_guess("parents")
  )
)

leaders_tibble

## -----------------------------------------------------------------------------
now <- Sys.time()
past <- now - c(100, 200)

x <- list(
  list(timediff = now - past[1]),
  list(timediff = now - past[2])
)

x

## -----------------------------------------------------------------------------
ptype <- as.difftime(0, units = "secs")
ptype

## -----------------------------------------------------------------------------
tibblify(
  x,
  lcols(
    lcol_vec("timediff", ptype = ptype)
  )
)

## -----------------------------------------------------------------------------
tibblify(
  politicians,
  lcols(
    lcol_chr("name"),
    lcol_chr("surname"),
    .default = lcol_lst(path = zap(), .default = NULL)
  )
)

