/* Wrapper for the vendored libyaml 0.2.5 scanner.c (MIT, vendor/libyaml/License).
   spin compiles carried C with -O2 -I <package root> and no per-package flags,
   so the defines libyaml's own build would pass live here. One wrapper per
   source because libyaml's yaml_private.h has no include guard. */
#define YAML_VERSION_MAJOR 0
#define YAML_VERSION_MINOR 2
#define YAML_VERSION_PATCH 5
#define YAML_VERSION_STRING "0.2.5"
#include "vendor/libyaml/src/scanner.c"
