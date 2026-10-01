/* kernel_exec.c -- the execvp(3) call behind the kernel_exec package's Kernel#exec. */
#include "spinel/runtime.h"
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static const char *kernel_exec_gc_string(const char *s) {
  size_t length = strlen(s);
  char *r = sp_str_alloc(length);
  memcpy(r, s, length);
  sp_str_set_len(r, length);
  return r;
}

/* Replace the process with `path`, given `argv` (an Array of Strings, argv[0] first).
   Only returns when the exec failed, answering errno. */
sp_int spinel_kernel_execvp(const char *path, sp_RbVal argv) {
  sp_int count = sp_json_len_fn(argv);
  char **args = calloc((size_t)count + 1, sizeof(char *));
  if (!args) return ENOMEM;
  for (sp_int i = 0; i < count; i++) {
    sp_RbVal arg = sp_json_aref_fn(argv, i);
    if (arg.tag != SP_TAG_STR) {
      free(args);
      return EINVAL;
    }
    args[i] = (char *)arg.v.s;
  }
  execvp(path, args);
  int error = errno;
  free(args);
  return error;
}

/* The name of an errno's Errno class, resolved here since the numbers differ between platforms. */
const char *spinel_kernel_exec_errno_name(sp_int error) {
  switch (error) {
    case E2BIG: return kernel_exec_gc_string("E2BIG");
    case EACCES: return kernel_exec_gc_string("EACCES");
    case EFAULT: return kernel_exec_gc_string("EFAULT");
    case EINVAL: return kernel_exec_gc_string("EINVAL");
    case EIO: return kernel_exec_gc_string("EIO");
    case EISDIR: return kernel_exec_gc_string("EISDIR");
    case ELOOP: return kernel_exec_gc_string("ELOOP");
    case EMFILE: return kernel_exec_gc_string("EMFILE");
    case ENAMETOOLONG: return kernel_exec_gc_string("ENAMETOOLONG");
    case ENFILE: return kernel_exec_gc_string("ENFILE");
    case ENOENT: return kernel_exec_gc_string("ENOENT");
    case ENOEXEC: return kernel_exec_gc_string("ENOEXEC");
    case ENOMEM: return kernel_exec_gc_string("ENOMEM");
    case ENOTDIR: return kernel_exec_gc_string("ENOTDIR");
    case EPERM: return kernel_exec_gc_string("EPERM");
    case ETXTBSY: return kernel_exec_gc_string("ETXTBSY");
    default: return kernel_exec_gc_string("");
  }
}

const char *spinel_kernel_exec_strerror(sp_int error) {
  return kernel_exec_gc_string(strerror((int)error));
}
