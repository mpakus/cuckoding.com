#include <errno.h>
#include <sys/types.h>
#include <unistd.h>

/* Force the parent to validate its group after an unguarded child has exited. */
static pid_t delayed_fork(void) {
  pid_t child = fork();
  if (child > 0) usleep(100000);
  return child;
}

/* macOS can reject redundant concurrent assignments even for the same PGID. */
static int exclusive_setpgid(pid_t pid, pid_t group) {
  if (pid > 0 && getpgid(pid) == group) {
    errno = EPERM;
    return -1;
  }
  return setpgid(pid, group);
}

__attribute__((used, section("__DATA,__interpose")))
static const struct {
  const void *replacement;
  const void *original;
} interpose[] = {
  {(const void *)delayed_fork, (const void *)fork},
  {(const void *)exclusive_setpgid, (const void *)setpgid}
};
