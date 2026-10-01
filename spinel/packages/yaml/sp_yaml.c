/* sp_yaml.c -- YAML.load / YAML.dump over the vendored libyaml event API.

   Values cross into the program the way the bundled json package's do: scalars
   and arrays are built from the package ABI (sp_box_*, sp_PolyArray), hashes
   through the sp_json_mk_hash_fn / sp_json_hash_set_fn builders, and a dump
   walks the program's containers through sp_json_kind/len/aref/hpair. Every
   in-progress container is GC-rooted, as in sp_json.c.

   Scalar resolution mirrors Psych 5.4's ScalarScanner#tokenize, and dump
   mirrors Psych::Visitors::YAMLTree's style choices, so a document round-trips
   byte-for-byte with CRuby for the supported subset. Not here (yet): Symbol,
   Date and Time values (they load as Strings), non-String hash keys (refused),
   binary strings and object tags (!ruby/...). */
#include "spinel/runtime.h"
#include "vendor/libyaml/include/yaml.h"
#include <string.h>
#include <stdlib.h>
#include <errno.h>
#include <math.h>

sp_Bigint *sp_bigint_new_str(const char *s, int base);   /* the runtime archive */


/* ---------- scalar resolution (Psych::ScalarScanner#tokenize) ---------- */

enum { YS_STR, YS_NIL, YS_TRUE, YS_FALSE, YS_INT, YS_FLOAT, YS_TIME, YS_DATE, YS_SYM, YS_SEXA_INT, YS_SEXA_FLOAT, YS_INF, YS_NINF, YS_NAN };

static int ys_digit(char c) { return c >= '0' && c <= '9'; }
static int ys_ieq(const char *s, size_t n, const char *lit) {
  if (strlen(lit) != n) return 0;
  for (size_t i = 0; i < n; i++) {
    char a = s[i];
    if (a >= 'A' && a <= 'Z') a = (char)(a + 32);
    if (a != lit[i]) return 0;
  }
  return 1;
}
/* [[:alpha:]_\s!@#$%\^&*(){}<>|/\\~;=] -- a non-ASCII byte reads as alpha */
static int ys_strclass(unsigned char c) {
  if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c >= 0x80) return 1;
  if (c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f' || c == '\v') return 1;
  return c && strchr("_!@#$%^&*(){}<>|/\\~;=", c) != NULL;
}
/* %r{^[^\d.:-]?[[:alpha:]...]+} || /\n/ */
static int ys_stringish(const char *s, size_t n) {
  if (memchr(s, '\n', n)) return 1;
  if (n >= 1 && ys_strclass((unsigned char)s[0])) return 1;
  if (n >= 2 && !ys_digit(s[0]) && s[0] != '.' && s[0] != ':' && s[0] != '-' &&
      ys_strclass((unsigned char)s[1])) return 1;
  return 0;
}
static size_t ys_digits(const char *s, size_t i, size_t n) { while (i < n && ys_digit(s[i])) i++; return i; }
/* TIME: ^-?\d{4}-\d{1,2}-\d{1,2}(?:[Tt]|\s+)\d{1,2}:\d\d:\d\d(?:\.\d*)?(?:\s*(?:Z|[-+]\d{1,2}:?(?:\d\d)?))?$ */
static int ys_time(const char *s, size_t n) {
  size_t i = 0, j;
  if (i < n && s[i] == '-') i++;
  j = ys_digits(s, i, n); if (j - i != 4 || j >= n || s[j] != '-') return 0; i = j + 1;
  j = ys_digits(s, i, n); if (j - i < 1 || j - i > 2 || j >= n || s[j] != '-') return 0; i = j + 1;
  j = ys_digits(s, i, n); if (j - i < 1 || j - i > 2 || j >= n) return 0; i = j;
  if (s[i] == 'T' || s[i] == 't') i++;
  else { if (s[i] != ' ' && s[i] != '\t') return 0; while (i < n && (s[i] == ' ' || s[i] == '\t')) i++; }
  j = ys_digits(s, i, n); if (j - i < 1 || j - i > 2 || j >= n || s[j] != ':') return 0; i = j + 1;
  j = ys_digits(s, i, n); if (j - i != 2 || j >= n || s[j] != ':') return 0; i = j + 1;
  j = ys_digits(s, i, n); if (j - i != 2) return 0; i = j;
  if (i < n && s[i] == '.') i = ys_digits(s, i + 1, n);
  if (i == n) return 1;
  while (i < n && (s[i] == ' ' || s[i] == '\t')) i++;
  if (i < n && s[i] == 'Z') return i + 1 == n;
  if (i < n && (s[i] == '-' || s[i] == '+')) {
    i++;
    j = ys_digits(s, i, n); if (j - i < 1 || j - i > 2) return 0; i = j;
    if (i < n && s[i] == ':') i++;
    if (i == n) return 1;
    j = ys_digits(s, i, n); return j - i == 2 && j == n;
  }
  return 0;
}
/* ^\d{4}-(?:1[012]|0\d|\d)-(?:[12]\d|3[01]|0\d|\d)$ */
static int ys_date(const char *s, size_t n) {
  size_t j = ys_digits(s, 0, n);
  if (j != 4 || j >= n || s[j] != '-') return 0;
  size_t m = j + 1, me = ys_digits(s, m, n);
  if (me >= n || s[me] != '-') return 0;
  if (!(me - m == 1 || (me - m == 2 && ((s[m] == '1' && s[m + 1] <= '2') || s[m] == '0')))) return 0;
  size_t d = me + 1, de = ys_digits(s, d, n);
  if (de != n) return 0;
  return de - d == 1 || (de - d == 2 && ((s[d] == '1' || s[d] == '2') || (s[d] == '3' && s[d + 1] <= '1') || s[d] == '0'));
}
/* ^[-+]?[0-9][0-9_]*(:[0-5]?[0-9]){1,2}   followed by $ (int) or \.[0-9_]*$ (float) */
static int ys_sexagesimal(const char *s, size_t n, int *is_float) {
  size_t i = 0;
  if (i < n && (s[i] == '-' || s[i] == '+')) i++;
  if (i >= n || !ys_digit(s[i])) return 0;
  while (i < n && (ys_digit(s[i]) || s[i] == '_')) i++;
  int groups = 0;
  while (i < n && s[i] == ':') {
    i++;
    size_t j = ys_digits(s, i, n);
    if (j - i == 1) {}
    else if (j - i == 2 && s[i] <= '5') {}
    else return 0;
    i = j; groups++;
  }
  if (groups < 1 || groups > 2) return 0;
  if (i == n) { *is_float = 0; return 1; }
  if (s[i] != '.') return 0;
  for (i++; i < n; i++) if (!ys_digit(s[i]) && s[i] != '_') return 0;
  *is_float = 1;
  return 1;
}
/* FLOAT: ^[-+]?([0-9][0-9_,]*)?\.[0-9]*([eE][-+][0-9]+)?$ */
static int ys_float(const char *s, size_t n) {
  size_t i = 0;
  if (i < n && (s[i] == '-' || s[i] == '+')) i++;
  if (i < n && ys_digit(s[i])) { i++; while (i < n && (ys_digit(s[i]) || s[i] == '_' || s[i] == ',')) i++; }
  if (i >= n || s[i] != '.') return 0;
  i = ys_digits(s, i + 1, n);
  if (i < n && (s[i] == 'e' || s[i] == 'E')) {
    i++;
    if (i >= n || (s[i] != '-' && s[i] != '+')) return 0;
    size_t j = ys_digits(s, i + 1, n);
    if (j == i + 1) return 0;
    i = j;
  }
  return i == n;
}
static int ys_in(char c, const char *set) { return c && strchr(set, c) != NULL; }
/* INTEGER_LEGACY (Psych's default, strict_integer: false) */
static int ys_int(const char *s, size_t n) {
  size_t i = 0;
  if (i < n && (s[i] == '-' || s[i] == '+')) i++;
  if (i >= n) return 0;
  if (n - i >= 2 && s[i] == '0' && s[i + 1] == 'b') {
    i += 2; while (i < n && ys_in(s[i], "_,")) i++;
    if (i >= n || !ys_in(s[i], "01")) return 0;
    for (; i < n; i++) if (!ys_in(s[i], "01_,")) return 0;
    return 1;
  }
  if (n - i >= 2 && s[i] == '0' && s[i + 1] == 'x') {
    i += 2; while (i < n && ys_in(s[i], "_,")) i++;
    if (i >= n || !ys_in(s[i], "0123456789abcdefABCDEF")) return 0;
    for (; i < n; i++) if (!ys_in(s[i], "0123456789abcdefABCDEF_,")) return 0;
    return 1;
  }
  if (s[i] == '0') {
    if (i + 1 == n) return 1;                         /* 0 */
    i++; while (i < n && ys_in(s[i], "_,")) i++;      /* 0[_,]*[0-7][0-7_,]* */
    if (i >= n || !ys_in(s[i], "01234567")) return 0;
    for (; i < n; i++) if (!ys_in(s[i], "01234567_,")) return 0;
    return 1;
  }
  if (s[i] < '1' || s[i] > '9') return 0;             /* [1-9](?:[0-9]|,[0-9]|_[0-9])* */
  for (i++; i < n; i++) {
    if (ys_digit(s[i])) continue;
    if ((s[i] == ',' || s[i] == '_') && i + 1 < n && ys_digit(s[i + 1])) { i++; continue; }
    return 0;
  }
  return 1;
}
static int ys_resolve(const char *s, size_t n) {
  if (n == 0) return YS_NIL;
  if (ys_stringish(s, n)) {
    if (n > 5) return YS_STR;
    if (!ys_in(s[0], "ytonfYTONF~")) return YS_STR;
    if ((n == 1 && s[0] == '~') || ys_ieq(s, n, "null")) return YS_NIL;
    if (ys_ieq(s, n, "yes") || ys_ieq(s, n, "true") || ys_ieq(s, n, "on")) return YS_TRUE;
    if (ys_ieq(s, n, "no") || ys_ieq(s, n, "false") || ys_ieq(s, n, "off")) return YS_FALSE;
    return YS_STR;
  }
  if (ys_time(s, n)) return YS_TIME;
  if (ys_date(s, n)) return YS_DATE;
  if (ys_ieq(s, n, ".inf") || ys_ieq(s, n, "+.inf")) return YS_INF;
  if (ys_ieq(s, n, "-.inf")) return YS_NINF;
  if (ys_ieq(s, n, ".nan")) return YS_NAN;
  if (n >= 2 && s[0] == ':') return YS_SYM;
  int sf;
  if (ys_sexagesimal(s, n, &sf)) return sf ? YS_SEXA_FLOAT : YS_SEXA_INT;
  if (ys_float(s, n)) {
    if (n == 1 || (n == 2 && (s[0] == '-' || s[0] == '+'))) return YS_STR;   /* \A[-+]?\.\Z */
    return YS_FLOAT;
  }
  if (ys_int(s, n)) return YS_INT;
  return YS_STR;
}

/* ---------- load ---------- */

static const char *ys_gcstr(const char *s, size_t n) {
  char *r = sp_str_alloc(n);
  if (n) memcpy(r, s, n);
  sp_str_set_len(r, n);
  return r;
}
/* Integer(string.delete(',_')): 0b / 0x / leading-0 octal / decimal, Bignum past int64 */
static sp_RbVal ys_mk_int(const char *s, size_t n) {
  char tmp[256]; size_t k = 0;
  for (size_t i = 0; i < n && k < sizeof tmp - 1; i++) if (s[i] != ',' && s[i] != '_') tmp[k++] = s[i];
  tmp[k] = 0;
  const char *p = tmp; int neg = 0;
  if (*p == '-' || *p == '+') { neg = *p == '-'; p++; }
  int base = 10;
  if (p[0] == '0' && p[1] == 'b') { base = 2; p += 2; }
  else if (p[0] == '0' && p[1] == 'x') { base = 16; p += 2; }
  else if (p[0] == '0' && p[1]) { base = 8; p += 1; }
  errno = 0;
  unsigned long long u = strtoull(p, NULL, base);
  if (errno == ERANGE || u > (unsigned long long)INT64_MAX + (neg ? 1ULL : 0ULL)) {
    char big[260]; snprintf(big, sizeof big, "%s%s", neg ? "-" : "", p);
    return sp_box_bigint(sp_bigint_new_str(big, base));
  }
  return sp_box_i64(neg ? (int64_t)(0 - u) : (int64_t)u);
}
/* Float(string.delete(',_').gsub(/\.([Ee]|$)/, '\1')) -- strtod reads "1." and "1.e+3" the same */
static sp_RbVal ys_mk_float(const char *s, size_t n) {
  char tmp[256]; size_t k = 0;
  for (size_t i = 0; i < n && k < sizeof tmp - 1; i++) if (s[i] != ',' && s[i] != '_') tmp[k++] = s[i];
  tmp[k] = 0;
  return sp_box_float(strtod(tmp, NULL));
}
/* Base 60: each ':'-separated part weighted 60**(e - 2).abs, as Psych computes it. */
static sp_RbVal ys_mk_sexagesimal(const char *s, size_t n, int is_float) {
  char tmp[256]; size_t k = n < sizeof tmp - 1 ? n : sizeof tmp - 1;
  memcpy(tmp, s, k); tmp[k] = 0;
  double parts[3]; int np = 0;
  for (char *tok = strtok(tmp, ":"); tok && np < 3; tok = strtok(NULL, ":")) {
    char clean[128]; size_t c = 0;
    for (char *q = tok; *q && c < sizeof clean - 1; q++) if (*q != '_') clean[c++] = *q;
    clean[c] = 0;
    parts[np++] = is_float ? strtod(clean, NULL) : (double)strtoll(clean, NULL, 10);
  }
  double acc = 0;
  for (int e = 0; e < np; e++) { int w = abs(e - 2); acc += parts[e] * (w == 0 ? 1 : w == 1 ? 60 : 3600); }
  return is_float ? sp_box_float(acc) : sp_box_i64((int64_t)acc);
}

/* Load modes (the flags argument), matching Psych's entry points:
     unsafe_load              YL_ALIASES
     load / load_file         YL_NIL_FALLBACK | YL_PERMIT_SYMBOL   (+ YL_ALIASES with aliases: true)
     safe_load / _file        YL_NIL_FALLBACK                      (+ YL_ALIASES with aliases: true)
   Without YL_PERMIT_SYMBOL-or-unsafe, a Date / Time / Symbol scalar is Psych's
   DisallowedClass; with it (or unsafe) it loads as its String for now. */
#define YL_ALIASES       1
#define YL_SAFE          2
#define YL_PERMIT_SYMBOL 4
#define YL_NIL_FALLBACK  8

typedef struct {
  yaml_parser_t parser;
  yaml_event_t ev;
  int has_ev;
  int flags;
  const char *filename;
  char **anchor_names;
  sp_RbVal *anchor_vals;
  int n_anchors, cap_anchors;
} yrd;

static void yr_cleanup(yrd *r) {
  if (r->has_ev) yaml_event_delete(&r->ev);
  r->has_ev = 0;
  yaml_parser_delete(&r->parser);
  for (int i = 0; i < r->n_anchors; i++) free(r->anchor_names[i]);
  free(r->anchor_names);
  free(r->anchor_vals);
  r->anchor_names = NULL; r->anchor_vals = NULL; r->n_anchors = 0;
}
static SP_NORETURN void yr_fail(yrd *r, const char *cls, const char *msg) {
  const char *m = sp_sprintf("%s", msg);   /* onto the GC heap before the cleanup below */
  yr_cleanup(r);
  sp_raise_cls(cls, m);
}
static SP_NORETURN void yr_syntax_error(yrd *r) {
  /* Psych::SyntaxError's message: "(<file>): <problem> <context> at line L column C" */
  char buf[512];
  const char *problem = r->parser.problem ? r->parser.problem : "unknown error";
  if (r->parser.context)
    snprintf(buf, sizeof buf, "(%s): %s %s at line %d column %d", r->filename, problem, r->parser.context,
             (int)r->parser.context_mark.line + 1, (int)r->parser.context_mark.column + 1);
  else
    snprintf(buf, sizeof buf, "(%s): %s at line %d column %d", r->filename, problem,
             (int)r->parser.problem_mark.line + 1, (int)r->parser.problem_mark.column + 1);
  yr_fail(r, "Psych::SyntaxError", buf);
}
static void yr_next(yrd *r) {
  if (r->has_ev) { yaml_event_delete(&r->ev); r->has_ev = 0; }
  if (!yaml_parser_parse(&r->parser, &r->ev)) yr_syntax_error(r);
  r->has_ev = 1;
}
/* A value this package cannot represent. Psych builds the whole first
   document's node tree before converting any of it, so a syntax error anywhere
   in that document wins over a conversion error: read on to its end first. */
static SP_NORETURN void yr_refuse(yrd *r, const char *cls, const char *msg) {
  const char *m = sp_sprintf("%s", msg);
  SP_GC_ROOT_STR(m);
  while (r->has_ev && r->ev.type != YAML_DOCUMENT_END_EVENT && r->ev.type != YAML_STREAM_END_EVENT)
    yr_next(r);    /* raises Psych::SyntaxError on a malformed rest */
  yr_cleanup(r);
  sp_raise_cls(cls, m);
}
static void yr_anchor(yrd *r, const yaml_char_t *name, sp_RbVal v) {
  if (!name) return;
  if (r->n_anchors == r->cap_anchors) {
    r->cap_anchors = r->cap_anchors ? r->cap_anchors * 2 : 8;
    r->anchor_names = realloc(r->anchor_names, sizeof(char *) * (size_t)r->cap_anchors);
    r->anchor_vals = realloc(r->anchor_vals, sizeof(sp_RbVal) * (size_t)r->cap_anchors);
    if (!r->anchor_names || !r->anchor_vals) sp_oom_die();
  }
  r->anchor_names[r->n_anchors] = strdup((const char *)name);
  r->anchor_vals[r->n_anchors++] = v;   /* reachable through the tree it was placed in */
}
static sp_RbVal yr_alias(yrd *r, const yaml_char_t *name) {
  if (!(r->flags & YL_ALIASES))
    yr_refuse(r, "Psych::AliasesNotEnabled",
              "Alias parsing was not enabled. To enable it, pass `aliases: true` to `Psych::load` or `Psych::safe_load`.");
  for (int i = r->n_anchors - 1; i >= 0; i--)
    if (!strcmp(r->anchor_names[i], (const char *)name)) return r->anchor_vals[i];
  char buf[300]; snprintf(buf, sizeof buf, "An alias referenced an unknown anchor: %s", (const char *)name);
  yr_refuse(r, "Psych::AnchorNotDefined", buf);
}

static sp_RbVal yr_scalar(yrd *r) {
  const char *s = (const char *)r->ev.data.scalar.value;
  size_t n = r->ev.data.scalar.length;
  const char *tag = (const char *)r->ev.data.scalar.tag;
  if (tag) {
    if (!strcmp(tag, "tag:yaml.org,2002:str") || !strcmp(tag, "!")) return sp_box_str(ys_gcstr(s, n));
    if (!strcmp(tag, "tag:yaml.org,2002:null")) return sp_box_nil();
    if (!strcmp(tag, "tag:yaml.org,2002:merge")) return sp_box_str(ys_gcstr(s, n));   /* the `!!merge <<` key */
    if (!strcmp(tag, "tag:yaml.org,2002:int") && ys_int(s, n)) return ys_mk_int(s, n);
    if (!strcmp(tag, "tag:yaml.org,2002:float") && ys_float(s, n)) return ys_mk_float(s, n);
    if (!strcmp(tag, "tag:yaml.org,2002:bool")) {
      int t = ys_resolve(s, n);
      if (t == YS_TRUE || t == YS_FALSE) return sp_box_bool(t == YS_TRUE);
    }
    char buf[300]; snprintf(buf, sizeof buf, "unsupported tag %s (sp_yaml loads core-schema tags only)", tag);
    yr_refuse(r, "Psych::DisallowedClass", buf);
  }
  if (r->ev.data.scalar.style != YAML_PLAIN_SCALAR_STYLE) return sp_box_str(ys_gcstr(s, n));
  switch (ys_resolve(s, n)) {
    case YS_NIL:        return sp_box_nil();
    case YS_TRUE:       return sp_box_bool(1);
    case YS_FALSE:      return sp_box_bool(0);
    case YS_INT:        return ys_mk_int(s, n);
    case YS_FLOAT:      return ys_mk_float(s, n);
    case YS_SEXA_INT:   return ys_mk_sexagesimal(s, n, 0);
    case YS_SEXA_FLOAT: return ys_mk_sexagesimal(s, n, 1);
    case YS_INF:        return sp_box_float(INFINITY);
    case YS_NINF:       return sp_box_float(-INFINITY);
    case YS_NAN:        return sp_box_float(NAN);
    case YS_TIME: case YS_DATE: case YS_SYM: {
      int t = ys_resolve(s, n);
      int permitted = !(r->flags & YL_SAFE) && (t == YS_SYM ? 1 : !(r->flags & YL_PERMIT_SYMBOL));
      if (!permitted) {
        const char *cls = t == YS_SYM ? "Symbol" : t == YS_DATE ? "Date" : "Time";
        char buf[64]; snprintf(buf, sizeof buf, "Tried to load unspecified class: %s", cls);
        yr_refuse(r, "Psych::DisallowedClass", buf);
      }
      return sp_box_str(ys_gcstr(s, n));   /* permitted: the String, until the package can build the object */
    }
    default:            return sp_box_str(ys_gcstr(s, n));
  }
}

#define YR_MAX_DEPTH 512
static sp_RbVal yr_node(yrd *r, int depth);

/* Psych's revive_hash merge: `<<: *m` and `<<: [*a, *b]` (later sources lose). */
static void yr_merge_into(yrd *r, sp_RbVal hash, sp_RbVal src) {
  if (src.tag != SP_TAG_OBJ || !sp_json_kind_fn || sp_json_kind_fn(src) != 2) {
    yr_refuse(r, "TypeError", "sp_yaml: a merge key's value must be a mapping");
  }
  sp_int n = sp_json_len_fn(src);
  for (sp_int i = 0; i < n; i++) {
    sp_RbVal k, v;
    sp_json_hpair_fn(src, i, &k, &v);
    if (k.tag == SP_TAG_STR) sp_json_hash_set_fn(hash, k.v.s, v);
  }
}

static sp_RbVal yr_mapping(yrd *r, int depth) {
  const yaml_char_t *anchor = r->ev.data.mapping_start.anchor;
  char *anchor_copy = anchor ? strdup((const char *)anchor) : NULL;
  sp_RbVal box = sp_json_mk_hash_fn();
  SP_GC_ROOT_RBVAL(box);
  for (;;) {
    yr_next(r);
    if (r->ev.type == YAML_MAPPING_END_EVENT) break;
    int merge = r->ev.type == YAML_SCALAR_EVENT && r->ev.data.scalar.length == 2 &&
                !memcmp(r->ev.data.scalar.value, "<<", 2) &&
                ((!r->ev.data.scalar.tag && r->ev.data.scalar.style == YAML_PLAIN_SCALAR_STYLE) ||
                 (r->ev.data.scalar.tag && !strcmp((const char *)r->ev.data.scalar.tag, "tag:yaml.org,2002:merge")));
    sp_RbVal key = yr_node(r, depth + 1);
    SP_GC_ROOT_RBVAL(key);   /* survive the value parse; the hash stores the ptr */
    yr_next(r);
    if (merge && (r->ev.type == YAML_ALIAS_EVENT || r->ev.type == YAML_MAPPING_START_EVENT)) {
      sp_RbVal src = yr_node(r, depth + 1);
      SP_GC_ROOT_RBVAL(src);
      yr_merge_into(r, box, src);
      continue;
    }
    if (merge && r->ev.type == YAML_SEQUENCE_START_EVENT) {
      sp_RbVal seq = yr_node(r, depth + 1);
      SP_GC_ROOT_RBVAL(seq);
      sp_int n = sp_json_len_fn(seq);
      for (sp_int i = n - 1; i >= 0; i--) yr_merge_into(r, box, sp_json_aref_fn(seq, i));
      continue;
    }
    if (key.tag != SP_TAG_STR) {
      free(anchor_copy);
      yr_refuse(r, "Psych::DisallowedClass", "sp_yaml: only String mapping keys are supported");
    }
    sp_RbVal val = yr_node(r, depth + 1);
    sp_json_hash_set_fn(box, key.v.s, val);
  }
  if (anchor_copy) { yr_anchor(r, (const yaml_char_t *)anchor_copy, box); free(anchor_copy); }
  return box;
}

static sp_RbVal yr_sequence(yrd *r, int depth) {
  const yaml_char_t *anchor = r->ev.data.sequence_start.anchor;
  char *anchor_copy = anchor ? strdup((const char *)anchor) : NULL;
  sp_RbVal box = sp_box_poly_array(sp_PolyArray_new());
  SP_GC_ROOT_RBVAL(box);
  for (;;) {
    yr_next(r);
    if (r->ev.type == YAML_SEQUENCE_END_EVENT) break;
    sp_RbVal v = yr_node(r, depth + 1);
    sp_PolyArray_push((sp_PolyArray *)box.v.p, v);
  }
  if (anchor_copy) { yr_anchor(r, (const yaml_char_t *)anchor_copy, box); free(anchor_copy); }
  return box;
}

/* The current event starts a node; consume it (and its children) and answer the value. */
static sp_RbVal yr_node(yrd *r, int depth) {
  if (depth > YR_MAX_DEPTH) yr_fail(r, "Psych::SyntaxError", "(<unknown>): nesting too deep");
  switch (r->ev.type) {
    case YAML_SCALAR_EVENT: {
      sp_RbVal v = yr_scalar(r);
      if (r->ev.data.scalar.anchor) yr_anchor(r, r->ev.data.scalar.anchor, v);
      return v;
    }
    case YAML_ALIAS_EVENT:          return yr_alias(r, r->ev.data.alias.anchor);
    case YAML_MAPPING_START_EVENT:  return yr_mapping(r, depth);
    case YAML_SEQUENCE_START_EVENT: return yr_sequence(r, depth);
    default: yr_fail(r, "Psych::SyntaxError", "(<unknown>): unexpected event");
  }
}

/* The first document of `s`, as the Psych entry point `flags` names answers it
   (minus the Symbol/Date/Time/object revivals noted at the top). */
sp_RbVal spinel_yaml_load(const char *s, sp_int flags, const char *filename) {
  SP_GC_ROOT_STR(s);   /* see sp_json_parse: the parse allocates while reading s */
  SP_GC_ROOT_STR(filename);
  yrd r; memset(&r, 0, sizeof r);
  r.flags = (int)flags;
  r.filename = filename && *filename ? filename : "<unknown>";
  if (!yaml_parser_initialize(&r.parser)) sp_oom_die();
  yaml_parser_set_input_string(&r.parser, (const unsigned char *)(s ? s : ""), s ? sp_str_byte_len(s) : 0);
  yr_next(&r);                                   /* STREAM-START */
  yr_next(&r);
  if (r.ev.type == YAML_STREAM_END_EVENT) { yr_cleanup(&r); return (flags & YL_NIL_FALLBACK) ? sp_box_nil() : sp_box_bool(0); }
  yr_next(&r);                                   /* past DOCUMENT-START */
  sp_RbVal v = yr_node(&r, 0);
  SP_GC_ROOT_RBVAL(v);
  yr_next(&r);                                   /* DOCUMENT-END */
  yr_cleanup(&r);
  return v;
}

/* ---------- dump ---------- */

typedef struct { char *p; size_t len, cap; } ybuf;
static int yw_write(void *data, unsigned char *buf, size_t size) {
  ybuf *b = (ybuf *)data;
  if (b->len + size + 1 > b->cap) {
    b->cap = (b->len + size + 1) * 2;
    b->p = realloc(b->p, b->cap);
    if (!b->p) sp_oom_die();
  }
  memcpy(b->p + b->len, buf, size);
  b->len += size;
  return 1;
}

/* Object identity for anchors. Psych's YAMLTree registers every Array and Hash
   it visits and, meeting one again, gives it the next anchor id (&1, &2, ...
   in order of first repeat) and emits an alias. A pre-pass over the same walk
   order assigns those ids; the emit pass puts the anchor on the first
   occurrence and an alias on every later one. */
typedef struct { void *p; int id; int emitted; } yref;
typedef struct { yref *slots; size_t cap, len; int next_id; } yrefs;

static yref *yrefs_find(yrefs *t, void *p, int insert) {
  if (insert && (t->len + 1) * 2 > t->cap) {
    size_t ncap = t->cap ? t->cap * 2 : 64;
    yref *ns = calloc(ncap, sizeof(yref));
    if (!ns) sp_oom_die();
    for (size_t i = 0; i < t->cap; i++) if (t->slots[i].p) {
      size_t h = ((uintptr_t)t->slots[i].p >> 4) & (ncap - 1);
      while (ns[h].p) h = (h + 1) & (ncap - 1);
      ns[h] = t->slots[i];
    }
    free(t->slots); t->slots = ns; t->cap = ncap;
  }
  if (!t->cap) return NULL;
  size_t h = ((uintptr_t)p >> 4) & (t->cap - 1);
  while (t->slots[h].p) {
    if (t->slots[h].p == p) return &t->slots[h];
    h = (h + 1) & (t->cap - 1);
  }
  if (!insert) return NULL;
  t->slots[h].p = p; t->len++;
  return &t->slots[h];
}
static int yw_kind(sp_RbVal v) { return (v.tag == SP_TAG_OBJ && sp_json_kind_fn) ? sp_json_kind_fn(v) : 0; }
static void yrefs_scan(yrefs *t, sp_RbVal v, int depth) {
  int kind = yw_kind(v);
  if ((kind != 1 && kind != 2) || depth > 512) return;
  yref *e = yrefs_find(t, v.v.p, 0);
  if (e) { if (!e->id) e->id = ++t->next_id; return; }
  yrefs_find(t, v.v.p, 1);
  sp_int n = sp_json_len_fn(v);
  for (sp_int i = 0; i < n; i++) {
    if (kind == 1) yrefs_scan(t, sp_json_aref_fn(v, i), depth + 1);
    else { sp_RbVal k, x; sp_json_hpair_fn(v, i, &k, &x); yrefs_scan(t, k, depth + 1); yrefs_scan(t, x, depth + 1); }
  }
}

typedef struct { yaml_emitter_t em; yaml_event_t ev; ybuf out; yrefs refs; } ywr;

static void yw_cleanup(ywr *w) { yaml_emitter_delete(&w->em); free(w->out.p); w->out.p = NULL; free(w->refs.slots); w->refs.slots = NULL; }
static SP_NORETURN void yw_fail(ywr *w, const char *cls, const char *msg) {
  const char *m = sp_sprintf("%s", msg);
  yw_cleanup(w);
  sp_raise_cls(cls, m);
}
static void yw_emit(ywr *w) {
  if (!yaml_emitter_emit(&w->em, &w->ev))
    yw_fail(w, "Psych::Exception", w->em.problem ? w->em.problem : "emitter error");
}
static void yw_scalar(ywr *w, const char *s, size_t n, const char *tag, int plain, int quoted, yaml_scalar_style_t style) {
  yaml_scalar_event_initialize(&w->ev, NULL, (yaml_char_t *)tag, (yaml_char_t *)s, (int)n, plain, quoted, style);
  yw_emit(w);
}
/* /\n(?!\Z)/ -- a newline that is not the last character, nor the second to
   last before a final newline (\Z matches there too). */
static int ys_inner_newline(const char *s, size_t n) {
  for (size_t i = 0; i < n; i++)
    if (s[i] == '\n' && !(i == n - 1 || (i == n - 2 && s[n - 1] == '\n'))) return 1;
  return 0;
}
/* [[:word:]]; a non-ASCII byte reads as a word character */
static int ys_word(unsigned char c) {
  return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || ys_digit((char)c) || c == '_' || c >= 0x80;
}
/* /^[^[:word:]][^"]*$/ with Ruby's per-line ^ and $: some line starts with a
   non-word character and the rest of that line holds no double quote. */
static int ys_nonword_line(const char *s, size_t n) {
  for (size_t p = 0; p < n; p++) {
    if (p > 0 && s[p - 1] != '\n') continue;
    if (ys_word((unsigned char)s[p])) continue;
    size_t e = p + 1;
    while (e < n && s[e] != '\n' && s[e] != '"') e++;
    if (e == n || s[e] == '\n') return 1;
  }
  return 0;
}
/* Psych::Visitors::YAMLTree#visit_String */
static void yw_string(ywr *w, const char *s, size_t n) {
  yaml_scalar_style_t style = YAML_PLAIN_SCALAR_STYLE;
  const char *tag = NULL;
  int plain = 1, quoted = 1;
  if (ys_inner_newline(s, n)) style = YAML_LITERAL_SCALAR_STYLE;
  else if (n == 2 && s[0] == '<' && s[1] == '<') {
    style = YAML_SINGLE_QUOTED_SCALAR_STYLE; tag = "tag:yaml.org,2002:str"; plain = 0; quoted = 0;
  }
  else if (n == 1 && ys_in(s[0], "yYnN")) style = YAML_DOUBLE_QUOTED_SCALAR_STYLE;
  else if (ys_nonword_line(s, n)) style = YAML_DOUBLE_QUOTED_SCALAR_STYLE;
  else if (ys_resolve(s, n) != YS_STR || (n >= 2 && s[0] == '0' && ({
             size_t i = 1; while (i < n && s[i] >= '0' && s[i] <= '7') i++; i < n && (s[i] == '8' || s[i] == '9'); })))
    style = YAML_SINGLE_QUOTED_SCALAR_STYLE;       /* not String === tokenize(o), or /\A0[0-7]*[89]/ */
  yw_scalar(w, s, n, tag, plain, quoted, style);
}
#define YW_MAX_DEPTH 512
static void yw_value(ywr *w, sp_RbVal v, int depth) {
  if (depth > YW_MAX_DEPTH) yw_fail(w, "ArgumentError", "sp_yaml: nesting too deep");
  switch (v.tag) {
    case SP_TAG_NIL:  yw_scalar(w, "", 0, "tag:yaml.org,2002:null", 1, 0, YAML_ANY_SCALAR_STYLE); return;
    case SP_TAG_BOOL: yw_scalar(w, v.v.i ? "true" : "false", v.v.i ? 4 : 5, NULL, 1, 0, YAML_ANY_SCALAR_STYLE); return;
    case SP_TAG_INT: { const char *t = sp_int_to_s(v.v.i); yw_scalar(w, t, strlen(t), NULL, 1, 0, YAML_ANY_SCALAR_STYLE); return; }
    case SP_TAG_FLT: {
      const char *t = isnan(v.v.f) ? ".nan" : isinf(v.v.f) ? (v.v.f > 0 ? ".inf" : "-.inf") : sp_float_to_s(v.v.f);
      yw_scalar(w, t, strlen(t), NULL, 1, 0, YAML_ANY_SCALAR_STYLE);
      return;
    }
    case SP_TAG_BIGINT: { const char *t = sp_bigint_to_s((sp_Bigint *)v.v.p); yw_scalar(w, t, strlen(t), NULL, 1, 0, YAML_ANY_SCALAR_STYLE); return; }
    case SP_TAG_STR: yw_string(w, v.v.s ? v.v.s : "", v.v.s ? sp_str_byte_len(v.v.s) : 0); return;
    case SP_TAG_SYM: {
      const char *name = sp_sym_name_fn ? sp_sym_name_fn((sp_sym)v.v.i) : "";
      char *t = malloc(strlen(name) + 2); if (!t) sp_oom_die();
      t[0] = ':'; strcpy(t + 1, name);
      yaml_scalar_event_initialize(&w->ev, NULL, NULL, (yaml_char_t *)t, (int)strlen(t), 1, 0, YAML_ANY_SCALAR_STYLE);
      free(t);
      yw_emit(w);
      return;
    }
    default: break;
  }
  int kind = yw_kind(v);
  char anchor[24]; const yaml_char_t *anc = NULL;
  if (kind == 1 || kind == 2) {
    yref *e = yrefs_find(&w->refs, v.v.p, 0);
    if (e && e->id) {
      snprintf(anchor, sizeof anchor, "%d", e->id);
      if (e->emitted) {
        yaml_alias_event_initialize(&w->ev, (yaml_char_t *)anchor);
        yw_emit(w);
        return;
      }
      e->emitted = 1;
      anc = (const yaml_char_t *)anchor;
    }
  }
  if (kind == 1) {
    yaml_sequence_start_event_initialize(&w->ev, (yaml_char_t *)anc, NULL, 1, YAML_BLOCK_SEQUENCE_STYLE);
    yw_emit(w);
    sp_int n = sp_json_len_fn(v);
    for (sp_int i = 0; i < n; i++) yw_value(w, sp_json_aref_fn(v, i), depth + 1);
    yaml_sequence_end_event_initialize(&w->ev);
    yw_emit(w);
    return;
  }
  if (kind == 2) {
    yaml_mapping_start_event_initialize(&w->ev, (yaml_char_t *)anc, NULL, 1, YAML_BLOCK_MAPPING_STYLE);
    yw_emit(w);
    sp_int n = sp_json_len_fn(v);
    for (sp_int i = 0; i < n; i++) {
      sp_RbVal k, val;
      sp_json_hpair_fn(v, i, &k, &val);
      yw_value(w, k, depth + 1);
      yw_value(w, val, depth + 1);
    }
    yaml_mapping_end_event_initialize(&w->ev);
    yw_emit(w);
    return;
  }
  yw_fail(w, "TypeError", "sp_yaml: can't dump this object (only nil, true/false, Integer, Float, String, Symbol, Array and Hash)");
}

/* Psych.dump(v): "--- " header, block style, 2-space indent, 80-column folding. */
const char *spinel_yaml_dump(sp_RbVal v) {
  SP_GC_ROOT_RBVAL(v);   /* sp_int_to_s / sp_float_to_s allocate while the walk reads v */
  ywr w; memset(&w, 0, sizeof w);
  if (!yaml_emitter_initialize(&w.em)) sp_oom_die();
  yaml_emitter_set_unicode(&w.em, 1);
  yaml_emitter_set_indent(&w.em, 2);
  yaml_emitter_set_output(&w.em, yw_write, &w.out);
  yaml_stream_start_event_initialize(&w.ev, YAML_UTF8_ENCODING); yw_emit(&w);
  yaml_document_start_event_initialize(&w.ev, NULL, NULL, NULL, 0); yw_emit(&w);
  yrefs_scan(&w.refs, v, 0);
  yw_value(&w, v, 0);
  yaml_document_end_event_initialize(&w.ev, 1); yw_emit(&w);
  yaml_stream_end_event_initialize(&w.ev); yw_emit(&w);
  char *r = sp_str_alloc(w.out.len);
  if (w.out.len) memcpy(r, w.out.p, w.out.len);
  sp_str_set_len(r, w.out.len);
  yw_cleanup(&w);
  return r;
}
