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

static void record(const char *path, long value, int append) {
  int fd = open(path, O_WRONLY | O_CREAT | (append ? O_APPEND : O_TRUNC), 0600);
  if (fd < 0) _exit(91);
  char text[64];
  int size = snprintf(text, sizeof(text), "%ld\n", value);
  put(fd, text, (size_t)size);
  close(fd);
}

static void exit_zero(int signal_number) { (void)signal_number; _exit(0); }

int main(int argc, char **argv) {
  if (argc != 4) return 92;
  alarm(30); /* Every fixture remains bounded even if its test VM disappears. */
  record(argv[2], (long)getpid(), 1);
  const char *mode = argv[1];

  if (strcmp(mode, "binary") == 0) {
    const unsigned char out[] = {0, 255, 'o', 'u', 't'};
    const unsigned char err[] = {254, 0, 'e', 'r', 'r'};
    put(1, out, sizeof(out));
    put(2, err, sizeof(err));
    return 7;
  }
  if (strcmp(mode, "early_stdout") == 0) {
    put(1, "out", 3);
    close(1);
    usleep(150000);
    put(2, "late-err", 8);
    return 0;
  }
  if (strcmp(mode, "early_stderr") == 0) {
    put(2, "err", 3);
    close(2);
    usleep(150000);
    put(1, "late-out", 8);
    return 0;
  }
  if (strcmp(mode, "descendant") == 0) {
    pid_t child = fork();
    if (child < 0) return 93;
    if (child != 0) return 9;
    alarm(5); /* alarm is not inherited across fork. */
    record(argv[2], (long)getpid(), 1);
    while (access(argv[3], F_OK) != 0) usleep(1000);
    put(1, "late-child", 10);
    put(2, "child-err", 9);
    _exit(0);
  }
  if (strcmp(mode, "closed_alive") == 0) {
    close(1);
    close(2);
    for (;;) pause();
  }
  if (strcmp(mode, "flood") == 0) {
    char block[4096];
    memset(block, 'x', sizeof(block));
    for (long i = 1; i <= 65536; ++i) {
      put(i % 8 == 0 ? 2 : 1, block, sizeof(block));
      record(argv[3], i * (long)sizeof(block), 0);
    }
    return 0;
  }
  if (strcmp(mode, "quiet") == 0) {
    for (;;) pause();
  }
  if (strcmp(mode, "term_zero") == 0) {
    signal(SIGTERM, exit_zero);
    put(1, "ready", 5);
    for (;;) pause();
  }
  return 94;
}
