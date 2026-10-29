/* Private packet-4 protocol; no text diagnostics or user data on stderr. */
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <libproc.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define CHUNK 4096
#define INPUT_MAX 1048576
#define QUEUE_MAX 32768
#define GROUP_MAX 4096

static volatile sig_atomic_t interrupted;
static unsigned char queue[QUEUE_MAX];
static size_t queued;
static int connected = 1;

static int64_t now_ms(void) {
  struct timespec ts;
  if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) _exit(80);
  return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static void handle_signal(int signal_number) {
  (void)signal_number;
  interrupted = 1;
}

static int nonblocking(int fd) {
  int flags = fcntl(fd, F_GETFL);
  return flags < 0 ? -1 : fcntl(fd, F_SETFL, flags | O_NONBLOCK);
}

static void close_fd(int *fd) {
  if (*fd >= 0) close(*fd);
  *fd = -1;
}

static int packet(const void *bytes, size_t length) {
  if (!connected) return 0;
  if (length + 4 > QUEUE_MAX - queued) {
    connected = 0;
    queued = 0;
    return -1;
  }
  uint32_t size = htonl((uint32_t)length);
  memcpy(queue + queued, &size, 4);
  memcpy(queue + queued + 4, bytes, length);
  queued += 4 + length;
  return 0;
}

static void flush_output(void) {
  if (!connected || queued == 0) return;
  ssize_t written = write(STDOUT_FILENO, queue, queued);
  if (written > 0) {
    queued -= (size_t)written;
    memmove(queue, queue + written, queued);
  } else if (written < 0 && errno != EAGAIN && errno != EINTR) {
    connected = 0;
    queued = 0;
  }
}

static int read_exact(void *target, size_t length, int64_t deadline) {
  unsigned char *bytes = target;
  while (length > 0 && !interrupted && now_ms() < deadline) {
    struct pollfd fd = {.fd = STDIN_FILENO, .events = POLLIN};
    int ready = poll(&fd, 1, 20);
    if (ready < 0 && errno == EINTR) continue;
    if (ready <= 0) continue;
    ssize_t size = read(STDIN_FILENO, bytes, length);
    if (size <= 0) return -1;
    bytes += size;
    length -= (size_t)size;
  }
  return length == 0 ? 0 : -1;
}

static unsigned long number(const char *text, unsigned long maximum) {
  char *end;
  errno = 0;
  unsigned long value = strtoul(text, &end, 10);
  return errno || !*text || *end || value == 0 || value > maximum ? 0 : value;
}

/* The unreaped leader reserves its PID/PGID until every signal is finished. */
static int group_members(pid_t leader, int leader_exited) {
  pid_t pids[GROUP_MAX];
  errno = 0;
  int size = proc_listpids(PROC_PGRP_ONLY, (uint32_t)leader, pids, sizeof(pids));
  if (size < 0 || (size == 0 && errno != 0) || size >= (int)sizeof(pids) ||
      size % (int)sizeof(pid_t) != 0) return -1;
  int members = 0;
  for (int i = 0; i < size / (int)sizeof(pid_t); ++i) {
    if (pids[i] > 0 && !(leader_exited && pids[i] == leader)) ++members;
  }
  return members;
}

static void start_stop(pid_t child, int reason, int *cause, int64_t *kill_at,
                       int64_t *finish_at) {
  if (*cause != 0) return;
  *cause = reason;
  (void)kill(-child, SIGTERM);
  *kill_at = now_ms() + 200;
  *finish_at = now_ms() + 1800;
}

int main(int argc, char **argv) {
  int devnull = open("/dev/null", O_WRONLY);
  if (devnull < 0 || dup2(devnull, STDERR_FILENO) < 0) return 80;
  if (devnull != STDERR_FILENO) close(devnull);
  struct rlimit no_core = {.rlim_cur = 0, .rlim_max = 0};
  (void)setrlimit(RLIMIT_CORE, &no_core);
  signal(SIGPIPE, SIG_IGN);
  signal(SIGCHLD, SIG_DFL);
  struct sigaction action;
  memset(&action, 0, sizeof(action));
  action.sa_handler = handle_signal;
  sigemptyset(&action.sa_mask);
  sigaction(SIGTERM, &action, NULL);
  sigaction(SIGHUP, &action, NULL);
  sigaction(SIGINT, &action, NULL);

  if (argc < 4) return 80;
  unsigned long timeout = number(argv[1], 86400000);
  unsigned long output_limit = number(argv[2], 67108864);
  if (!timeout || !output_limit) return 80;

  uint32_t input_length;
  int64_t startup_deadline = now_ms() + 5000;
  if (read_exact(&input_length, 4, startup_deadline) != 0) return 80;
  input_length = ntohl(input_length);
  if (input_length < 1 || input_length > INPUT_MAX + 1) return 80;
  unsigned char *input = malloc(input_length);
  if (!input) return 80;
  if (read_exact(input, input_length, startup_deadline) != 0 || input[0] != 'I') {
    free(input);
    return 80;
  }

  int command_in[2], command_out[2], command_err[2], start_gate[2];
  if (pipe(command_in) || pipe(command_out) || pipe(command_err) || pipe(start_gate))
    return 80;
  int fd_limit = getdtablesize();
  pid_t child = fork();
  if (child < 0) return 80;
  if (child == 0) {
    close(start_gate[1]);
    signal(SIGPIPE, SIG_DFL);
    signal(SIGTERM, SIG_DFL);
    signal(SIGHUP, SIG_DFL);
    signal(SIGINT, SIG_DFL);
    if (dup2(command_in[0], 0) < 0 ||
        dup2(command_out[1], 1) < 0 || dup2(command_err[1], 2) < 0) _exit(127);
    /* macOS rejects getpgid on zombies; do not exec before parent validation. */
    unsigned char release;
    ssize_t released;
    do { released = read(start_gate[0], &release, 1); } while (released < 0 && errno == EINTR);
    if (released != 1 || release != 'G' || getpgrp() != getpid()) _exit(127);
    /* In particular, descendants must not retain the BEAM control channel. */
    for (int fd = 3; fd < fd_limit; ++fd) close(fd);
    execv(argv[3], &argv[3]);
    _exit(127);
  }

  close(start_gate[0]);
  close(command_in[0]);
  close(command_out[1]);
  close(command_err[1]);
  int input_fd = command_in[1];
  int streams[2] = {command_out[0], command_err[0]};
  int cause = 0, leader_exited = 0, eof[2] = {0, 0}, credit[2] = {1, 1};
  int query_failed = 0, cleanup_ok = 0;
  int64_t kill_at = 0, finish_at = 0, natural_at = 0;
  int64_t runtime_at = now_ms() + (int64_t)timeout;
  size_t input_offset = 1;
  uint64_t output_bytes = 0;
  siginfo_t exit_info;
  memset(&exit_info, 0, sizeof(exit_info));

  if (setpgid(child, child) != 0 || getpgid(child) != child ||
      nonblocking(0) || nonblocking(1) || nonblocking(input_fd) ||
      nonblocking(streams[0]) || nonblocking(streams[1]) ||
      write(start_gate[1], "G", 1) != 1) {
    query_failed = 1;
    start_stop(child, 4, &cause, &kill_at, &finish_at);
  }
  close(start_gate[1]);

  unsigned char started[5] = {'S'};
  uint32_t child_be = htonl((uint32_t)child);
  memcpy(started + 1, &child_be, 4);
  packet(started, sizeof(started));
  unsigned char control[1024];
  size_t control_length = 0;

  for (;;) {
    int64_t now = now_ms();
    if (interrupted || !connected) start_stop(child, 1, &cause, &kill_at, &finish_at);
    if (now >= runtime_at) start_stop(child, 2, &cause, &kill_at, &finish_at);
    if (!leader_exited) {
      siginfo_t status;
      memset(&status, 0, sizeof(status));
      if (waitid(P_PID, (id_t)child, &status, WEXITED | WNOHANG | WNOWAIT) < 0) {
        if (errno != EINTR) {
          query_failed = 1;
          start_stop(child, 4, &cause, &kill_at, &finish_at);
        }
      } else if (status.si_pid == child) {
        exit_info = status;
        leader_exited = 1;
        natural_at = now + 500;
        close_fd(&input_fd);
        unsigned char exited[6] = {'X', status.si_code == CLD_EXITED ? 'e' : 's'};
        uint32_t code = htonl((uint32_t)status.si_status);
        memcpy(exited + 2, &code, 4);
        packet(exited, sizeof(exited));
      }
    }

    int members = leader_exited || cause ? group_members(child, leader_exited) : 1;
    if (members < 0) {
      query_failed = 1;
      start_stop(child, 4, &cause, &kill_at, &finish_at);
    }
    if (leader_exited && members == 0 && eof[0] && eof[1]) {
      cleanup_ok = !query_failed;
      break;
    }
    /* Consumer backpressure is not evidence of a lingering child. */
    if (leader_exited && cause == 0 && (!credit[0] || !credit[1])) natural_at = now + 500;
    if (leader_exited && cause == 0 && now >= natural_at)
      start_stop(child, 5, &cause, &kill_at, &finish_at);
    if (kill_at && now >= kill_at) {
      (void)kill(-child, SIGKILL);
      kill_at = 0;
    }
    if (finish_at && now >= finish_at) break;
    if (cause) close_fd(&input_fd);
    if (input_fd >= 0 && input_offset == input_length) close_fd(&input_fd);

    struct pollfd fds[5] = {
      {.fd = connected ? 0 : -1, .events = POLLIN},
      {.fd = connected && queued ? 1 : -1, .events = POLLOUT},
      {.fd = credit[0] || cause ? streams[0] : -1, .events = POLLIN},
      {.fd = credit[1] || cause ? streams[1] : -1, .events = POLLIN},
      {.fd = input_fd, .events = POLLOUT}
    };
    int polled = poll(fds, 5, 20);
    if (polled < 0 && errno != EINTR) start_stop(child, 4, &cause, &kill_at, &finish_at);
    if (connected && fds[0].revents) {
      ssize_t size = read(0, control + control_length, sizeof(control) - control_length);
      if (size == 0 || (size < 0 && errno != EAGAIN && errno != EINTR)) connected = 0;
      if (size > 0) control_length += (size_t)size;
      while (control_length >= 4) {
        uint32_t length;
        memcpy(&length, control, 4);
        length = ntohl(length);
        if (length == 0 || length > 2) { connected = 0; break; }
        if (control_length < 4 + length) break;
        if (control[4] == 'Q' && length == 1) {
          start_stop(child, 1, &cause, &kill_at, &finish_at);
        } else if (control[4] == 'A' && length == 2 && (control[5] == 'O' || control[5] == 'E')) {
          credit[control[5] == 'O' ? 0 : 1] = 1;
        } else connected = 0;
        control_length -= 4 + length;
        memmove(control, control + 4 + length, control_length);
      }
      if (control_length == sizeof(control)) connected = 0;
    }
    if (fds[1].revents) flush_output();
    if (input_fd >= 0 && fds[4].revents) {
      ssize_t size = write(input_fd, input + input_offset, input_length - input_offset);
      if (size > 0) input_offset += (size_t)size;
      else if (size < 0 && errno != EAGAIN && errno != EINTR) close_fd(&input_fd);
    }
    for (int i = 0; i < 2; ++i) {
      if (streams[i] < 0 || (!credit[i] && !cause) || !fds[i + 2].revents) continue;
      unsigned char frame[CHUNK + 1];
      frame[0] = i == 0 ? 'O' : 'E';
      ssize_t size = read(streams[i], frame + 1, CHUNK);
      if (size > 0) {
        output_bytes += (uint64_t)size;
        if (output_bytes > output_limit) start_stop(child, 3, &cause, &kill_at, &finish_at);
        if (!cause) {
          packet(frame, (size_t)size + 1);
          credit[i] = 0;
        }
      } else if (size == 0) {
        eof[i] = 1;
        close_fd(&streams[i]);
        unsigned char ended[2] = {'F', i == 0 ? 'O' : 'E'};
        packet(ended, sizeof(ended));
      } else if (errno != EAGAIN && errno != EINTR) {
        close_fd(&streams[i]);
        start_stop(child, 4, &cause, &kill_at, &finish_at);
      }
    }
  }

  close_fd(&input_fd);
  close_fd(&streams[0]);
  close_fd(&streams[1]);
  free(input);
  if (leader_exited) {
    int64_t reap_at = finish_at ? finish_at : natural_at;
    pid_t reaped = waitpid(child, NULL, WNOHANG);
    while (reaped < 0 && errno == EINTR && now_ms() < reap_at) {
      (void)poll(NULL, 0, 1);
      if (now_ms() >= reap_at) break;
      reaped = waitpid(child, NULL, WNOHANG);
    }
    if (reaped != child) cleanup_ok = 0;
  }
  unsigned char done[9] = {'D', (unsigned char)cause, (unsigned char)cleanup_ok,
                           (unsigned char)(eof[0] | (eof[1] << 1)), 0, 0, 0, 0, 0};
  if (leader_exited) {
    done[4] = exit_info.si_code == CLD_EXITED ? 'e' : 's';
    uint32_t code = htonl((uint32_t)exit_info.si_status);
    memcpy(done + 5, &code, 4);
  }
  packet(done, sizeof(done));
  int64_t flush_at = now_ms() + 500;
  while (connected && queued && now_ms() < flush_at) {
    struct pollfd output = {.fd = 1, .events = POLLOUT};
    if (poll(&output, 1, 20) > 0) flush_output();
  }
  return queued == 0 ? 0 : 81;
}
