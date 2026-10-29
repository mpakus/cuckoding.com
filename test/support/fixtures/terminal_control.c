#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int final_packet(const void *buffer, size_t size) {
  const unsigned char *bytes = buffer;
  size_t offset = 0;
  while (size - offset >= 4) {
    uint32_t length;
    memcpy(&length, bytes + offset, 4);
    length = ntohl(length);
    if (length > size - offset - 4) return 0;
    if (length == 9 && bytes[offset + 4] == 'D') return 1;
    offset += 4 + length;
  }
  return 0;
}

/* A valid terminal receipt does not imply an open control pipe or helper exit. */
static ssize_t terminal_write(int fd, const void *bytes, size_t size) {
  if (fd != STDOUT_FILENO || !final_packet(bytes, size)) return write(fd, bytes, size);
  const char *marker = getenv("BOSS_TEST_TERMINAL_MARKER");
  if (!marker) _exit(80);
  int file = open(marker, O_WRONLY | O_CREAT | O_EXCL, 0600);
  if (file < 0 || write(file, "D", 1) != 1 || close(file) != 0) _exit(80);
  close(STDIN_FILENO);
  ssize_t result = write(fd, bytes, size);
  int saved = errno;
  usleep(100000);
  file = open(marker, O_WRONLY | O_APPEND);
  if (file < 0 || write(file, "E", 1) != 1 || close(file) != 0) _exit(80);
  const char *failure = getenv("BOSS_TEST_HELPER_FAILURE");
  if (failure) {
    if (!strcmp(failure, "signal")) raise(SIGKILL);
    _exit(81);
  }
  errno = saved;
  return result;
}

__attribute__((used, section("__DATA,__interpose")))
static const struct { const void *replacement; const void *original; } interpose[] = {
  {(const void *)terminal_write, (const void *)write}
};
