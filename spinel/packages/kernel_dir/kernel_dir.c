/* kernel_dir.c -- the running executable's path, behind the kernel_dir package's Kernel#__dir__. */
#include "spinel/runtime.h"
#include <limits.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#ifdef __APPLE__
#include <mach-o/dyld.h>
#endif

/* The canonical path of the running executable as the OS reports it, "" where it can't tell. */
const char *spinel_kernel_dir_executable_path(void) {
  char resolved[PATH_MAX];
  const char *found = "";
#if defined(__APPLE__)
  char path[PATH_MAX];
  uint32_t size = sizeof path;
  if (_NSGetExecutablePath(path, &size) == 0 && realpath(path, resolved)) found = resolved;
#elif defined(__linux__)
  if (realpath("/proc/self/exe", resolved)) found = resolved;
#endif
  size_t length = strlen(found);
  char *r = sp_str_alloc(length);
  memcpy(r, found, length);
  sp_str_set_len(r, length);
  return r;
}
