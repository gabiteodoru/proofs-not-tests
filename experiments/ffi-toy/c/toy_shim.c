/* Plain C API over the Lean export `toy_categorize`, so Python's ctypes can
 * call it without knowing about Lean objects.
 *
 * Strings cross the boundary as (UTF-8 bytes, length), not NUL-terminated,
 * because a Python str may contain U+0000.
 *
 * This file is part of the trusted base: nothing here is proven.
 */
#include <lean/lean.h>
#include <stdlib.h>
#include <string.h>

void lean_initialize_runtime_module(void); /* not declared in lean.h */
lean_object *initialize_Toy_Toy_Categorize(uint8_t builtin);
lean_object *toy_categorize(lean_object *merchant, lean_object *declared,
                            lean_object *allowed);

static int g_initialized = 0;

/* Returns 0 on success. Call once, from the thread that will call
 * toy_categorize_c (see README: threading is not handled yet). */
int toy_init(void) {
  if (g_initialized) return 0;
  lean_initialize_runtime_module();
  lean_object *res = initialize_Toy_Toy_Categorize(1 /* builtin */);
  if (lean_io_result_is_error(res)) {
    lean_io_result_show_error(res);
    lean_dec_ref(res);
    return 1;
  }
  lean_dec_ref(res);
  lean_io_mark_end_initialization();
  g_initialized = 1;
  return 0;
}

/* Inputs are UTF-8 byte strings with explicit lengths. `declared` may be
 * NULL, meaning Python's None.
 *
 * Returns 0 if accepted (*out = the category), 1 if rejected (*out = the error
 * message). *out is malloc'd, holds *out_len bytes plus a trailing NUL, and
 * must be released with toy_free. */
int toy_categorize_c(const char *merchant, size_t merchant_len,
                     const char *declared, size_t declared_len,
                     const char *const *allowed, const size_t *allowed_lens,
                     size_t n_allowed, char **out, size_t *out_len) {
  lean_object *m = lean_mk_string_from_bytes(merchant, merchant_len);

  lean_object *d;
  if (declared == NULL) {
    d = lean_box(0); /* Option.none */
  } else {
    d = lean_alloc_ctor(1, 1, 0); /* Option.some */
    lean_ctor_set(d, 0, lean_mk_string_from_bytes(declared, declared_len));
  }

  lean_object *a = lean_mk_empty_array_with_capacity(lean_box(n_allowed));
  for (size_t i = 0; i < n_allowed; i++)
    a = lean_array_push(a, lean_mk_string_from_bytes(allowed[i], allowed_lens[i]));

  /* m, d, a are consumed by the call (@[export] parameters are owned). */
  lean_object *r = toy_categorize(m, d, a);

  /* Except String String: tag 0 = error, tag 1 = ok; both have one field. */
  int accepted = lean_obj_tag(r) == 1;
  lean_object *s = lean_ctor_get(r, 0);
  size_t len = lean_string_size(s) - 1; /* m_size counts the trailing NUL */
  char *buf = malloc(len + 1);
  memcpy(buf, lean_string_cstr(s), len + 1);
  lean_dec(r);

  *out = buf;
  *out_len = len;
  return accepted ? 0 : 1;
}

void toy_free(char *p) { free(p); }
