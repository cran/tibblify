#include "rlang.h"
#include <R.h>
#include <Rinternals.h>
#include <stdlib.h> // for NULL
#include <R_ext/Rdynload.h>

#include <R_ext/Visibility.h>
#define export attribute_visible extern

/* .Call calls */
extern SEXP ffi_tibblify(SEXP, SEXP, SEXP);
extern SEXP ffi_is_object(SEXP);
extern SEXP ffi_is_object_list(SEXP);
extern SEXP ffi_is_null_list(SEXP);
extern SEXP ffi_list_is_list_null(SEXP);

// Defined below
extern SEXP tibblify_initialize(SEXP);

static const R_CallMethodDef CallEntries[] = {
    {"ffi_tibblify",           (DL_FUNC) &ffi_tibblify,           3},
    {"ffi_is_object",          (DL_FUNC) &ffi_is_object,          1},
    {"ffi_is_object_list",     (DL_FUNC) &ffi_is_object_list,     1},
    {"ffi_is_null_list",       (DL_FUNC) &ffi_is_null_list,       1},
    {"ffi_list_is_list_null",  (DL_FUNC) &ffi_list_is_list_null,  1},
    {"tibblify_initialize",    (DL_FUNC) &tibblify_initialize,    1},
    {NULL, NULL, 0}
};

export void R_init_tibblify(DllInfo* dll){
  R_registerRoutines(dll, NULL, CallEntries, NULL, NULL);
  R_useDynamicSymbols(dll, FALSE);
  // R_forceSymbols(dll, TRUE);
}

// tibblify-vctrs-private.c
void tibblify_initialize_vctrs_private(void);

// tibblify-vctrs-public.c
void tibblify_initialize_vctrs_public(void);

// utils.c
void tibblify_init_utils(SEXP);

// utils.c
SEXP r_init_library(SEXP);


SEXP tibblify_initialize(SEXP ns) {
  r_init_library(ns);

  tibblify_initialize_vctrs_private();
  tibblify_initialize_vctrs_public();
  tibblify_init_utils(ns);
  return R_NilValue;
}
