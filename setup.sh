#!/usr/bin/env bash

# ==============================================================================
# [01] System Timezone
# ==============================================================================
timedatectl set-timezone Asia/Tehran

# ==============================================================================
# [02] Scheduled Reboot
# ==============================================================================
echo "0 6 * * * root /sbin/reboot" > /etc/cron.d/daily-reboot
chmod 644 /etc/cron.d/daily-reboot

# ==============================================================================
# [03] Swap Space
# ==============================================================================
if [ ! -f /swapfile ]; then
    fallocate -l 4G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
fi
grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
swapon -a

# ==============================================================================
# [04] Package Ecosystem
# ==============================================================================
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get dist-upgrade -y
apt-get install -y libpam-google-authenticator unattended-upgrades ethtool
apt-get autoremove --purge -y
apt-get clean

# ==============================================================================
# [05] SSH Armor & 2FA
# ==============================================================================
sed -i '/pam_google_authenticator\.so/d' /etc/pam.d/sshd
sed -i '/@include common-auth/a auth required pam_google_authenticator.so nullok' /etc/pam.d/sshd
rm -f /etc/ssh/sshd_config.d/50-google-authenticator.conf
cat << 'EOF' > /etc/ssh/sshd_config.d/01-google-authenticator.conf
UsePAM yes
PasswordAuthentication no
KbdInteractiveAuthentication yes
AuthenticationMethods keyboard-interactive
EOF
mkdir -p /run/sshd
sshd -t && systemctl try-reload-or-restart ssh ssh.socket
google-authenticator

# ==============================================================================
# [06] IPv6 AnyIP Route
# ==============================================================================
read -r -p "Enter routed IPv6 subnet prefix (e.g. 2001:db8::/64, leave blank to skip): " IPV6_PREFIX
IPV6_PREFIX="${IPV6_PREFIX//[[:space:]]/}"

if [ -n "$IPV6_PREFIX" ]; then
    cat << EOF > /etc/systemd/system/ipv6-anyip.service
[Unit]
Description=IPv6 AnyIP Subnet Local Route
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=ip -6 route replace local ${IPV6_PREFIX} dev lo
ExecStop=-ip -6 route del local ${IPV6_PREFIX} dev lo

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable ipv6-anyip.service
    systemctl restart ipv6-anyip.service
fi

# ==============================================================================
# [07] Log Minimization & Hardening
# ==============================================================================
mkdir -p /etc/systemd/journald.conf.d /etc/systemd/coredump.conf.d /etc/systemd/system.conf.d /etc/security/limits.d /etc/sysctl.d

rm -f /etc/systemd/journald.conf.d/custom.conf /etc/systemd/coredump.conf.d/disable.conf

cat << 'EOF' > /etc/systemd/journald.conf.d/99-custom.conf
[Journal]
Storage=volatile
Audit=no
RuntimeMaxUse=10M
RuntimeMaxFileSize=2M
MaxLevelStore=warning
ForwardToWall=no
EOF

cat << 'EOF' > /etc/systemd/coredump.conf.d/99-disable.conf
[Coredump]
Storage=none
ProcessSizeMax=0
EOF

cat << 'EOF' > /etc/systemd/system.conf.d/99-disable-coredump.conf
[Manager]
DefaultLimitCORE=0
EOF

cat << 'EOF' > /etc/security/limits.d/99-disable-coredump.conf
* soft core 0
* hard core 0
root soft core 0
root hard core 0
EOF

cat << 'EOF' > /etc/sysctl.d/99-disable-coredump.conf
fs.suid_dumpable = 0
kernel.core_pattern = |/bin/false
EOF
sysctl -q -p /etc/sysctl.d/99-disable-coredump.conf

systemctl mask --now rsyslog.service syslog.socket \
    systemd-journald-audit.socket systemd-coredump.socket \
    apport.service apport-autoreport.service whoopsie.service whoopsie.path 2>/dev/null || true

systemctl daemon-reexec
systemctl restart systemd-journald

rm -rf /var/log/journal /var/crash/* /var/log/installer 2>/dev/null || true
find /var/log -type f \( -name "*.gz" -o -name "*.xz" -o -name "*.zst" -o -name "*.bz2" -o -name "*.[0-9]*" -o -name "*.old" -o -name "*.bak" \) -delete 2>/dev/null || true
find /var/log -type f -name "*.log" -exec truncate -c -s 0 {} + 2>/dev/null || true
truncate -c -s 0 /var/log/syslog /var/log/messages /var/log/dmesg /var/log/wtmp /var/log/btmp /var/log/lastlog /var/log/faillog /var/log/mail.* 2>/dev/null || true
chmod 664 /var/log/wtmp 2>/dev/null || true
chmod 660 /var/log/btmp 2>/dev/null || true
chown root:utmp /var/log/wtmp /var/log/btmp 2>/dev/null || true

# ==============================================================================
# [08] Unattended Upgrades
# ==============================================================================
mkdir -p /etc/apt/apt.conf.d /etc/dpkg/dpkg.cfg.d /etc/needrestart/conf.d /etc/systemd/system/apt-daily.timer.d /etc/systemd/system/apt-daily-upgrade.timer.d

cat << 'EOF' > /etc/dpkg/dpkg.cfg.d/force-conf
force-confdef
force-confold
EOF

cat << 'EOF' > /etc/needrestart/conf.d/override.conf
$nrconf{restart} = 'a';
$nrconf{kernelhints} = 0;
EOF

rm -f /etc/apt/apt.conf.d/52unattended-upgrades-local

cat << 'EOF' > /etc/apt/apt.conf.d/50unattended-upgrades
Unattended-Upgrade::Origins-Pattern {
    "origin=*";
};
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::SyslogEnable "false";
APT::AutoRemove::PurgeConfiguration "true";
DPkg::Lock::Timeout "120";
Acquire::Retries "3";
Acquire::http::Timeout "30";
Acquire::https::Timeout "30";
EOF

cat << 'EOF' > /etc/apt/apt.conf.d/20auto-upgrades
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "1";
APT::Periodic::MaxSize "100";
EOF

cat << 'EOF' > /etc/systemd/system/apt-daily.timer.d/override.conf
[Timer]
OnCalendar=
OnCalendar=*-*-* 04:00:00
RandomizedDelaySec=0
Persistent=true
EOF

cat << 'EOF' > /etc/systemd/system/apt-daily-upgrade.timer.d/override.conf
[Timer]
OnCalendar=
OnCalendar=*-*-* 05:00:00
RandomizedDelaySec=0
Persistent=true
EOF

systemctl daemon-reload
systemctl enable --now apt-daily.timer apt-daily-upgrade.timer unattended-upgrades.service

dpkg-query -W -f='${db:Status-Status} ${binary:Package}\n' 2>/dev/null | awk '$1=="config-files"{print $2}' | xargs -r dpkg --purge 2>/dev/null || true
apt-get clean

# ==============================================================================
# [09] Kernel & Network Tuning
# ==============================================================================
mkdir -p /etc/modules-load.d /etc/modprobe.d /etc/security/limits.d /etc/sysctl.d /etc/systemd/system.conf.d

cat << 'EOF' > /etc/modules-load.d/99-network.conf
nf_conntrack
tcp_bbr
sch_fq
EOF

echo "options nf_conntrack hashsize=65536" > /etc/modprobe.d/nf_conntrack.conf
modprobe nf_conntrack
modprobe tcp_bbr
modprobe sch_fq
echo 65536 > /sys/module/nf_conntrack/parameters/hashsize

cat << 'EOF' > /etc/security/limits.d/99-master-tuning.conf
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
* soft nproc 524288
* hard nproc 524288
root soft nproc 524288
root hard nproc 524288
* soft memlock unlimited
* hard memlock unlimited
root soft memlock unlimited
root hard memlock unlimited
EOF

cat << 'EOF' > /etc/systemd/system.conf.d/99-master-tuning.conf
[Manager]
DefaultLimitNOFILE=1048576
DefaultLimitNPROC=524288
DefaultLimitMEMLOCK=infinity
DefaultTasksMax=infinity
EOF

cat << 'EOF' > /etc/sysctl.d/99-master-tuning.conf
fs.file-max = 2097152
fs.nr_open = 2097152
fs.inotify.max_user_instances = 8192
fs.inotify.max_user_watches = 524288

net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.core.netdev_budget = 600
net.core.netdev_budget_usecs = 4000
net.core.rps_sock_flow_entries = 32768
net.core.rmem_max = 4194304
net.core.wmem_max = 4194304
net.core.default_qdisc = fq

net.ipv4.tcp_congestion_control = bbr
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.default.forwarding = 1
net.ipv6.conf.all.accept_ra = 2
net.ipv6.conf.default.accept_ra = 2
net.ipv4.ip_nonlocal_bind = 1
net.ipv6.ip_nonlocal_bind = 1

net.ipv4.neigh.default.gc_thresh1 = 2048
net.ipv4.neigh.default.gc_thresh2 = 4096
net.ipv4.neigh.default.gc_thresh3 = 8192
net.ipv6.neigh.default.gc_thresh1 = 2048
net.ipv6.neigh.default.gc_thresh2 = 4096
net.ipv6.neigh.default.gc_thresh3 = 8192

net.ipv4.tcp_rmem = 4096 87380 4194304
net.ipv4.tcp_wmem = 4096 65536 4194304
net.ipv4.tcp_mem = 65536 131072 262144

net.ipv4.ip_local_port_range = 10240 65535
net.ipv4.tcp_max_tw_buckets = 262144
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_rfc1337 = 1

net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_fastopen_blackhole_timeout_sec = 60

net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 15
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_retries2 = 8
net.ipv4.tcp_orphan_retries = 2
net.ipv4.tcp_max_orphans = 65536

net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_base_mss = 1024

net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192

net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

net.netfilter.nf_conntrack_max = 262144
net.netfilter.nf_conntrack_tcp_be_liberal = 1
net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 30
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 30
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 15
net.netfilter.nf_conntrack_tcp_timeout_established = 600
net.netfilter.nf_conntrack_tcp_timeout_syn_recv = 30
net.netfilter.nf_conntrack_tcp_timeout_syn_sent = 30
net.netfilter.nf_conntrack_udp_timeout = 30
net.netfilter.nf_conntrack_udp_timeout_stream = 120
net.netfilter.nf_conntrack_generic_timeout = 60
net.netfilter.nf_conntrack_icmp_timeout = 10

vm.swappiness = 10
vm.vfs_cache_pressure = 50
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
vm.max_map_count = 524288
vm.min_free_kbytes = 65536
EOF

rm -f /etc/sysctl.d/99-custom.conf
sysctl --system

ulimit -n 1048576
ulimit -u 524288

systemctl disable --now hardware-tuning.service 2>/dev/null || true
rm -f /etc/systemd/system/hardware-tuning.service /usr/local/sbin/hardware-tuning.sh

cat << 'EOF' > /etc/systemd/system/network-tuning.service
[Unit]
Description=Network Queue and RPS Tuning
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c '\
for dev in /sys/class/net/*; do \
    iface=${dev##*/}; \
    [ "$iface" = "lo" ] && continue; \
    [ -d "$dev/queues" ] || continue; \
    ip link set dev "$iface" txqueuelen 10000 2>/dev/null || true; \
    ethtool -K "$iface" gro on gso on tso on 2>/dev/null || true; \
    for q in "$dev"/queues/rx-*; do \
        [ -w "$q/rps_cpus" ] && echo 3 > "$q/rps_cpus" 2>/dev/null || true; \
        [ -w "$q/rps_flow_cnt" ] && echo 32768 > "$q/rps_flow_cnt" 2>/dev/null || true; \
    done; \
    for q in "$dev"/queues/tx-*; do \
        [ -w "$q/xps_cpus" ] && echo 3 > "$q/xps_cpus" 2>/dev/null || true; \
    done; \
done; \
exit 0'

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl daemon-reexec
systemctl enable --now network-tuning.service

# ==============================================================================
# [10] UFW Firewall
# ==============================================================================
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw default allow routed
ufw logging off
ufw allow 22
ufw allow 80
ufw allow 443
ufw allow 8080
ufw allow 8880
ufw --force enable

# ==============================================================================
# [11] Application Gateway
# ==============================================================================
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
x-ui

# ==============================================================================
# [12] Script Self-Deletion
# ==============================================================================
[ -f "$0" ] && rm -f "$0" 2>/dev/null || true