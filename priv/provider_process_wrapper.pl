use strict;
use warnings;
use Errno qw(EPERM);
use Fcntl qw(O_APPEND O_CREAT O_WRONLY);
use POSIX qw(setsid);

my ($stderr_path, $executable, @args) = @ARGV;

if (!defined($stderr_path) || !defined($executable)) {
  die "usage: provider_process_wrapper.pl STDERR_PATH EXECUTABLE [ARG ...]\n";
}

sysopen(STDERR, $stderr_path, O_WRONLY | O_CREAT | O_APPEND, 0600)
  or die "open stderr capture: $!\n";

# Isolate descendants from the BEAM process group so terminate can signal -PID.
# EPERM means this process is already a session/group leader, which is enough.
unless (setsid() != -1) {
  die "create provider process group: $!\n" unless $!{EPERM};
}

exec {$executable} $executable, @args;
die "exec provider: $!\n";
