"""Fixed resource/privilege probes; guest output is diagnostic, never workflow authority."""
import stat

init = b'''#!/bin/sh
set -e
B=/bin/busybox
$B mount -t devtmpfs devtmpfs /dev
$B mount -t proc proc /proc
$B mount -t sysfs sysfs /sys
$B mount -t cgroup2 none /sys/fs/cgroup
echo '+pids +memory +cpu' > /sys/fs/cgroup/cgroup.subtree_control
$B mkdir /sys/fs/cgroup/work
C=/sys/fs/cgroup/work
echo 32 > "$C/pids.max"
echo 67108864 > "$C/memory.max"
echo 0 > "$C/memory.swap.max"
echo 1 > "$C/memory.oom.group"
echo '50000 100000' > "$C/cpu.max"
$B chmod 1777 /tmp
echo "WATCHDOG_LIMITS $($B cat "$C/pids.max") $($B cat "$C/memory.max") $($B cat "$C/memory.swap.max") $($B cat "$C/cpu.max")"
echo "WATCHDOG_SELF $($B cat /proc/self/cgroup)"
/bin/sh /launch &
i=0
while [ "$i" -lt 8 ]; do $B sleep 1; i=$((i+1)); done
echo WATCHDOG_DEADLINE
for field in pids.current pids.peak memory.current memory.peak; do
    echo "WATCHDOG_VALUE $field $($B cat "$C/$field")"
done
for field in pids.events memory.events cpu.stat; do
    while read key value; do echo "WATCHDOG_EVENT $field $key $value"; done < "$C/$field"
done
echo 1 > "$C/cgroup.kill"
i=0
while [ "$i" -lt 20 ]; do
    if $B grep -q '^populated 0$' "$C/cgroup.events"; then
        echo WATCHDOG_EMPTY
        $B poweroff -f
    fi
    $B sleep 0.1
    i=$((i+1))
done
echo WATCHDOG_CLOSURE_FAILED
$B poweroff -f
'''

launcher = b'''#!/bin/sh
set -e
echo $$ > /sys/fs/cgroup/work/cgroup.procs
ulimit -c 0
ulimit -n 64
exec /bin/busybox su -s /bin/sh -c 'exec /bin/busybox setpriv --nnp /bin/sh /worker' worker
'''

worker = b'''#!/bin/sh
B=/bin/busybox
while read key value; do
    case "$key" in Uid:|Gid:|CapInh:|CapPrm:|CapEff:|CapAmb:|NoNewPrivs:) echo "WORKER_STATUS $key $value";; esac
done < /proc/self/status
echo "WORKER_GROUP $($B cat /proc/self/cgroup)"
if (kill -9 1) 2>/dev/null; then echo WORKER_ESCAPE signal; else echo WORKER_DENIED signal; fi
if (echo 99 > /sys/fs/cgroup/work/pids.max) 2>/dev/null; then echo WORKER_ESCAPE policy; else echo WORKER_DENIED policy; fi
if (echo $$ > /sys/fs/cgroup/cgroup.procs) 2>/dev/null; then echo WORKER_ESCAPE migrate; else echo WORKER_DENIED migrate; fi
/bin/busybox setsid /bin/sh -c 'echo "WORKER_SESSION $(/bin/busybox cat /proc/self/cgroup)"; exec /bin/busybox sleep 30' &
echo WORKER_READY
case "$($B cat /proc/cmdline)" in
    *cc_probe=memory*) $B dd if=/dev/zero of=/tmp/pressure bs=1048576 count=128 2>/dev/null;;
    *) (while :; do :; done) >/dev/null 2>&1 &
       i=0; while [ "$i" -lt 80 ]; do $B sleep 30 >/dev/null 2>&1 & i=$((i+1)); done;;
esac
while :; do $B sleep 1; done
'''

files = [
    ('etc', stat.S_IFDIR | 0o755, b''),
    ('etc/passwd', stat.S_IFREG | 0o644, b'root:!:0:0::/:/bin/sh\nworker:!:1000:1000::/tmp:/bin/sh\n'),
    ('etc/group', stat.S_IFREG | 0o644, b'root:x:0:\nworker:x:1000:\n'),
    ('launch', stat.S_IFREG | 0o555, launcher),
    ('worker', stat.S_IFREG | 0o555, worker),
]


def verify(lines, mode):
    """Verify fixed probe observations, without trusting them as native closure."""
    text = b''.join(lines).decode(errors='strict').replace('\r\n', '\n')
    assert 'WORKER_ESCAPE' not in text and 'WATCHDOG_CLOSURE_FAILED' not in text
    assert 'WATCHDOG_SELF 0::/' in text.splitlines() and 'WORKER_GROUP 0::/work' in text.splitlines()
    assert 'WATCHDOG_LIMITS 32 67108864 0 50000 100000' in text
    for field in ('Uid:', 'Gid:'):
        value = next(line.split()[2:] for line in text.splitlines() if line.startswith('WORKER_STATUS ' + field))
        assert value == ['1000'] * 4
    for field in ('CapInh:', 'CapPrm:', 'CapEff:', 'CapAmb:'):
        assert 'WORKER_STATUS ' + field + ' 0000000000000000' in text
    assert 'WORKER_STATUS NoNewPrivs: 1' in text
    for operation in ('signal', 'policy', 'migrate'):
        assert 'WORKER_DENIED ' + operation in text
    if mode == 'watchdog_owner_loss':
        return  # Keeper death still has no native stop proof.
    assert 'WORKER_SESSION 0::/work' in text.splitlines()
    assert 'WATCHDOG_DEADLINE' in text and 'WATCHDOG_EMPTY' in text
    values = {parts[1]: int(parts[2]) for line in text.splitlines()
              if (parts := line.split()) and parts[0] == 'WATCHDOG_VALUE'}
    assert 0 < values['pids.peak'] <= 32
    if mode == 'watchdog_memory':
        oom = next(int(line.split()[3]) for line in text.splitlines()
                   if line.startswith('WATCHDOG_EVENT memory.events oom_kill '))
        assert oom > 0
    else:
        maximum = next(int(line.split()[3]) for line in text.splitlines()
                       if line.startswith('WATCHDOG_EVENT pids.events max '))
        assert maximum > 0
        throttled = next(int(line.split()[3]) for line in text.splitlines()
                         if line.startswith('WATCHDOG_EVENT cpu.stat nr_throttled '))
        assert throttled > 0
