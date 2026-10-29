#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

static void mark(char value) {
  const char *path = getenv("BOSS_TEST_REAP_MARKER");
  if (!path) _exit(80);
  int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0600);
  if (fd < 0 || write(fd, &value, 1) != 1 || close(fd) != 0) _exit(80);
}

/* Interrupt the reserved leader's final reap, after waitid observed its exit. */
static pid_t interrupted_reap(pid_t child, int *status, int options) {
  static int calls;
  const char *mode = getenv("BOSS_TEST_REAP_MODE");
  if (!mode) return waitpid(child, status, options);
  ++calls;
  if (calls == 1 || strcmp(mode, "once") != 0) {
    if (calls <= 2) mark('I');
    errno = strcmp(mode, "error") == 0 ? ECHILD : EINTR;
    return -1;
  }
  mark('R');
  return waitpid(child, status, options);
}

__attribute__((used, section("__DATA,__interpose")))
static const struct {
  const void *replacement;
  const void *original;
} interpose[] = {{(const void *)interrupted_reap, (const void *)waitpid}};
