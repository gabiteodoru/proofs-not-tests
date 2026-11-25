/* Exercise toy_categorize_c under valgrind: accepted and rejected paths,
 * None and Some, embedded NUL, non-ASCII. Exits non-zero on a wrong answer. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int toy_init(void);
int toy_categorize_c(const char *, size_t, const char *, size_t,
                     const char *const *, const size_t *, size_t, char **, size_t *);
void toy_free(char *);

static const char *allowed[] = {"food", "travel", "office", "other"};
static const size_t lens[] = {4, 6, 6, 5};

static int check(const char *m, size_t ml, const char *d, size_t dl,
                 int want_rc, const char *want, size_t want_len) {
  char *out; size_t out_len;
  int rc = toy_categorize_c(m, ml, d, dl, allowed, lens, 4, &out, &out_len);
  int ok = rc == want_rc && out_len == want_len && memcmp(out, want, want_len) == 0;
  if (!ok) printf("FAIL: rc=%d out=%.*s\n", rc, (int)out_len, out);
  toy_free(out);
  return ok;
}

/* S("...") expands to the literal and its length in bytes, NULs included. */
#define S(lit) lit, (sizeof(lit) - 1)

int main(void) {
  if (toy_init() != 0) return 2;
  int ok = 1;
  for (int i = 0; i < 10000; i++) {
    ok &= check(S("Blue Cafe"), NULL, 0, 0, S("food"));
    ok &= check(S("Bookshop"), NULL, 0, 0, S("other"));
    ok &= check(S("x"), S(" FOOD\t"), 0, S("food"));
    ok &= check(S("x"), S("Entertainment"), 1, S("category 'entertainment' is not allowed"));
    ok &= check(S("x"), S("fo\0od"), 1, S("category 'fo\0od' is not allowed"));
    ok &= check(S("x"), S("\xc3\x89"), 1, S("category '\xc3\x89' is not allowed"));
  }
  printf(ok ? "all checks passed\n" : "SOME CHECKS FAILED\n");
  return ok ? 0 : 1;
}
