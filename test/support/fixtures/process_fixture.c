#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>

static void put(int fd, const void *data, size_t length) {
  const char *bytes = data;
  while (length) {
    ssize_t n = write(fd, bytes, length);
    if (n < 0 && errno == EINTR) continue;
    if (n <= 0) _exit(90);
    bytes += n;
    length -= (size_t)n;
  }
}

static void record(const char *path, const char *role, pid_t pid) {
  int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0600);
  if (fd < 0) _exit(91);
  char text[80];
  int length = snprintf(text, sizeof(text), "%s:%d\n", role, pid);
  put(fd, text, (size_t)length);
  close(fd);
}

static void term_zero(int value) { (void)value; _exit(0); }

int main(int argc, char **argv) {
  if (argc != 3) return 92;
  alarm(15);
  record(argv[2], "leader", getpid());
  record(argv[2], "guardian", getppid());
  const char *mode = argv[1];
  if (!strcmp(mode, "binary")) {
    const char out[] = {0, (char)255, 'o', 'u', 't'};
    const char err[] = {(char)254, 0, 'e', 'r', 'r'};
    put(1, out, sizeof(out));
    put(2, err, sizeof(err));
    return 7;
  }
  if (!strcmp(mode, "exit137")) return 137;
  if (!strcmp(mode, "signal")) { raise(SIGKILL); return 93; }
  if (!strcmp(mode, "echo")) {
    char bytes[4096];
    ssize_t n;
    while ((n = read(0, bytes, sizeof(bytes))) > 0) put(1, bytes, (size_t)n);
    return 0;
  }
  if (!strcmp(mode, "early_stdout") || !strcmp(mode, "early_stderr")) {
    int closed = !strcmp(mode, "early_stdout") ? 1 : 2;
    close(closed);
    usleep(100000);
    put(closed == 1 ? 2 : 1, "late", 4);
    return 0;
  }
  if (!strcmp(mode, "descendant")) {
    pid_t pid = fork();
    if (pid < 0) return 94;
    if (pid) return 9;
    alarm(5);
    record(argv[2], "child", getpid());
    usleep(150000);
    put(1, "late-child", 10);
    put(2, "child-err", 9);
    _exit(0);
  }
  if (!strcmp(mode, "tree") || !strcmp(mode, "orphan")) {
    int ready[2];
    if (pipe(ready)) return 95;
    signal(SIGTERM, SIG_IGN);
    pid_t pid = fork();
    if (pid < 0) return 96;
    if (!pid) {
      close(ready[0]);
      alarm(10);
      record(argv[2], "child", getpid());
      if (!strcmp(mode, "orphan")) {
        int fd = open("/dev/null", O_WRONLY);
        dup2(fd, 1); dup2(fd, 2); close(fd);
      }
      put(ready[1], "r", 1);
      close(ready[1]);
      for (;;) pause();
    }
    close(ready[1]);
    char value;
    if (read(ready[0], &value, 1) != 1) return 97;
    close(ready[0]);
    record(argv[2], "ready", getpid());
    if (!strcmp(mode, "orphan")) return 0;
    for (;;) pause();
  }
  if (!strcmp(mode, "term_zero")) {
    signal(SIGTERM, term_zero);
    record(argv[2], "ready", getpid());
    for (;;) pause();
  }
  if (!strcmp(mode, "closed_alive")) { close(1); close(2); for (;;) pause(); }
  if (!strcmp(mode, "flood")) {
    char bytes[4096];
    memset(bytes, 'x', sizeof(bytes));
    for (int i = 0; i < 65536; ++i) put(i % 2 ? 2 : 1, bytes, sizeof(bytes));
    return 0;
  }
  if (!strcmp(mode, "quiet")) { for (;;) pause(); }
  return 98;
}
