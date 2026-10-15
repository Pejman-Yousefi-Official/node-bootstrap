# node-bootstrap

An automated provisioning, hardening, and kernel-tuning script for Linux nodes running high-concurrency routing and proxy workloads (3x-ui).

---

### Target Environment

Calibrated for clean **Hetzner Cloud VPS** instances with the following OS and hardware baseline:

* **OS:** Ubuntu 26.04 LTS
* **Hardware:** 2 vCPUs, 4 GB RAM, 40 GB NVMe/SSD

Kernel parameters, multi-queue network packet steering (RPS/XPS), memory limits, and volatile journal policies are tuned specifically for this resource profile.

---

### Quick Run

Execute as `root` on a fresh server installation:

```bash
curl -sSL https://raw.githubusercontent.com/Pejman-Yousefi-Official/node-bootstrap/main/setup.sh -o setup.sh && bash setup.sh
```

> **Note:** The installation is largely unattended but includes brief interactive prompts during steps **`[05]`** (2FA enrollment), **`[06]`** (IPv6 prefix), and **`[11]`** (panel database). A system reboot is recommended upon completion to load the upgraded kernel.

---

### What It Does

The script executes 12 automated steps from a base OS installation to a production-ready node:

* **`[01] System Timezone`**  
  Sets the system timezone to `Asia/Tehran`.

* **`[02] Scheduled Reboot`**  
  Schedules a daily system reboot at 06:00 AM via cron.

* **`[03] Swap Space`**  
  Allocates, activates, and persists a 4 GB swap file.

* **`[04] Package Ecosystem`**  
  Updates apt repositories, applies distribution upgrades, installs core dependencies, and purges unused packages.

* **`[05] SSH Armor & 2FA`**  
  Enforces two-factor authentication (Password + TOTP) via PAM keyboard-interactive and prompts for 2FA enrollment.

* **`[06] IPv6 AnyIP Route`**  
  Binds the routed IPv6 subnet prefix to the local loopback interface (`lo`) via a persistent systemd service.

* **`[07] Log Minimization & Hardening`**  
  Restricts journald logs to volatile RAM (max 10 MB), disables core dumps, and truncates persistent log files.

* **`[08] Unattended Upgrades`**  
  Schedules non-interactive automated package upgrades daily at 04:00 AM (download) and 05:00 AM (install).

* **`[09] Kernel & Network Tuning`**  
  Enables TCP BBR with `fq`, configures multi-core packet steering (RPS/XPS), and expands socket buffers, connection tracking, and file descriptor limits.

* **`[10] UFW Firewall`**  
  Applies default-deny inbound and allow-routed policies, disables firewall logging, and opens ports `22`, `80`, `443`, `8080`, and `8880`.

* **`[11] Application Gateway`**  
  Installs and initializes the 3x-ui proxy management panel.

* **`[12] Script Self-Deletion`**  
  Removes the local `setup.sh` installer script upon completion.
