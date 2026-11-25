---
name: wsl-host-ops
description: Operate a WSL2 distribution from both sides of the boundary. Size and move a VHDX against the physical disk, compact it after space is freed, attach an extra VHDX for model storage under /mnt/wsl with a UUID mount, check GPU passthrough (the CUDA and NVML libraries sit in /usr/lib/wsl/lib, where nvidia-smi is not on PATH by default), enable systemd --user with linger, and reclaim Docker space after checking what must be kept. Use when a WSL disk is filling or a VHDX must grow, move or shrink, when a second disk is needed for models, when the GPU is not visible inside WSL, when user services stop after the last login, or when Docker has filled the distribution. Do NOT use for crash recovery of an interrupted agent (use resume-after-crash), for choosing or serving local models (use local-llm-serving), for native Linux disk or LVM work, or for installing Windows GPU drivers.
license: Apache-2.0
metadata:
  version: "1.0.0"
  tags: "wsl2, wsl, vhdx, disk, compaction, sparse, mount, gpu, cuda, systemd, linger, docker, storage"
---

# WSL host operations

A WSL2 distribution is an ext4 filesystem inside a VHDX file on the Windows host. Three disks decide
whether it works: the physical volume that holds the VHDX, the VHDX's own maximum size, and the ext4
filesystem inside. Most failures come from the first one filling up. Check the host side before
touching the distribution.

## Critical boundaries

- **Read before you change.** Record the current state of the disks, the VHDX, the distribution and
  Docker before any step. Every destructive step below names its check first.
- **`wsl --shutdown` stops every distribution and every session.** Check first that no agent, build,
  download or long job is running in any distribution, and that no other session is using it. Ask the
  operator before shutting down.
- **Never `wsl --unregister`, `diskpart clean`, `mkfs` on a disk that holds data, or `docker volume
  prune` without an explicit go-ahead** for that specific disk or volume.
- **Back up before a move, compact or sparse change.** An export or a copy of the VHDX is the only way
  back from a failed move.
- **Do not install a Linux NVIDIA driver inside WSL.** The Windows driver provides the GPU. A Linux
  driver package overwrites the passthrough libraries.
- **The CLI moves between builds.** Flags such as `--manage`, `--resize`, `--move` and `--mount` exist on
  recent WSL releases only. Run `wsl.exe --version` and `wsl.exe --help` (or `wsl.exe --manage --help`)
  before relying on a flag, and say which build you checked.

## Where the commands run

| Side | How to reach it | Examples |
|---|---|---|
| Inside the distribution | The shell in WSL | `df`, `findmnt`, `lsblk`, `docker`, `systemctl --user` |
| Windows host, from WSL | The interop path. `wsl.exe` is often not on PATH; use `/mnt/c/Windows/System32/wsl.exe` and `/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe` | `wsl.exe --list --verbose`, `powershell.exe Get-Volume` |
| Windows host, elevated | An administrator PowerShell or diskpart session | `Optimize-VHD`, `diskpart`, `New-VHD` |

Prefer the interop path from WSL for reads. Run anything that writes to a VHDX from an elevated Windows
shell, with the distribution stopped.

## 1. Size against the physical disk

A dynamic VHDX grows to the largest size it has ever needed. It does not shrink when files are
deleted. Its maximum is a ceiling, not a reservation.

Read the host side:

```powershell
Get-Volume -DriveLetter <letter> | Select-Object DriveLetter, Size, SizeRemaining
Get-Item "<path-to-ext4.vhdx>" | Select-Object FullName, Length
Get-VHD -Path "<path-to-ext4.vhdx>" | Select-Object Path, VhdFormat, VhdType, Size, FileSize, MinimumSize
```

`Get-VHD` needs the Hyper-V PowerShell module. Without it, read `Length` and use `diskpart`.

Read the guest side:

```bash
df -h /
findmnt -no SOURCE,FSTYPE,SIZE,USED,AVAIL /
```

**Rule:** the free space on the host volume must cover the VHDX growth still possible (its maximum minus
its current file size) plus headroom of about 10 per cent. If it does not, free host space or move the
distribution before the host volume fills. A full host volume stops writes inside WSL, and that is a
common cause of a crashed session (see resume-after-crash).

The guest's `df` used space and the VHDX file size differ by whatever has been deleted but not yet
returned to the host. That difference is what compaction recovers.

## 2. Return freed space to the host

Two routes. Both need the distribution stopped for compaction.

**Sparse mode (preferred where supported).** Sparse VHDs return space after TRIM, without a manual
compaction. Check the current state first, then enable on a backed-up distribution:

```bash
wsl.exe --manage <distro> --set-sparse true
```

Inside the distribution, `sudo fstrim -av` then reports what was trimmed. Sparse mode is not on in every
build; if the command is refused, use the compaction route.

**Compaction.** Free space inside the distribution first (Docker in section 6), then:

```bash
sudo fstrim -av                                  # inside WSL: pass free blocks down to the VHDX
wsl.exe --shutdown                               # host side, after asking the operator
```

```powershell
Optimize-VHD -Path "<path-to-ext4.vhdx>" -Mode Full          # Hyper-V module
# or, without Hyper-V tools, in an elevated diskpart session:
#   select vdisk file="<path-to-ext4.vhdx>"
#   attach vdisk readonly
#   compact vdisk
#   detach vdisk
```

Then compare `Get-Item ... Length` with the figure before. Record both.

## 3. Grow a VHDX

Grow the file on the host, then grow the filesystem inside. Whether the distribution must be stopped
depends on the build, so check `--help` and stop it if in doubt. Where the CLI offers it:

```bash
wsl.exe --manage <distro> --resize <size>        # for example 500GB; check --help on this build
```

Otherwise, from an elevated diskpart session with the distribution stopped:
`select vdisk file="<path>"` then `expand vdisk maximum=<MB>` (`maximum` is in megabytes). Inside WSL, find the root device and grow
the ext4 filesystem to fill it:

```bash
findmnt -no SOURCE /                             # for example /dev/sdX
sudo resize2fs /dev/sdX                          # grows to the device size; check with df afterwards
```

## 4. Move a distribution's VHDX

Use the CLI where it exists, otherwise export and import. Both keep a fallback.

```bash
wsl.exe --manage <distro> --move "<new-directory>"          # recent builds; check --help first
```

Export and import, as the fallback. It needs free space for the archive as well:

```bash
wsl.exe --export <distro> "<backup-path>.tar"               # keep the tar until the new copy has run
wsl.exe --import <distro> "<new-directory>" "<backup-path>.tar" --version 2
```

After either route: start the distribution, check `wsl.exe --list --verbose` shows the expected version,
check the default user is right (`whoami`, `/etc/wsl.conf` `[user]`), and check the VHDX is at the new
path. Only then delete the old copy. Do not use `--unregister` as a shortcut.

## 5. An extra VHDX for model storage

Keep large model files on a second disk so the system disk can be compacted and rebuilt independently.

**Create it on the host.** A fixed or dynamic VHDX, sized for the files it must hold plus growth:

```powershell
New-VHD -Path "<path>\models.vhdx" -SizeBytes 200GB -Dynamic
# or: diskpart > create vdisk file="<path>\models.vhdx" type=expandable maximum=204800
```

**Attach it to WSL without partitioning.** `--bare` presents the raw disk; the filesystem is made inside
WSL:

```bash
wsl.exe --mount --vhd "<path>\models.vhdx" --bare          # run from Windows, or via wsl.exe from WSL
```

**Inside WSL, make the filesystem only on a new, empty disk.** Confirm first that the disk has no
signature:

```bash
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,UUID               # identify the new disk; FSTYPE must be empty
sudo blkid /dev/sdX                                       # must print nothing before mkfs
sudo mkfs.ext4 -L models /dev/sdX                         # destructive: only on the new, empty disk
sudo blkid /dev/sdX                                       # now shows UUID and LABEL=models
```

**Mount under `/mnt/wsl` by UUID.** `/mnt/wsl` is a tmpfs that WSL creates at boot, so a directory under it
is recreated each time. Add an fstab entry that does not block boot if the disk is missing:

```bash
sudo mkdir -p /mnt/wsl/models
echo 'UUID=<uuid>  /mnt/wsl/models  ext4  defaults,noatime,nofail,x-systemd.device-timeout=10s  0  2' | sudo tee -a /etc/fstab
sudo mount -a && findmnt /mnt/wsl/models
```

**Keep it attached across restarts.** A `--mount` attachment does not survive `wsl --shutdown` or a host
restart. Re-attach from a Windows scheduled task that runs at user logon, before the distribution is
started. Then check, after a restart: `findmnt /mnt/wsl/models`. Device names (`/dev/sdX`) can change
between attachments, which is why the fstab entry uses the UUID.

Keep the model directory out of any backup that copies the whole distribution. Model files are large and
re-downloadable.

## 6. Check GPU passthrough

Passthrough needs the Windows NVIDIA driver, which provides `/dev/dxg` and the libraries WSL exposes in
`/usr/lib/wsl/lib`. Check each layer in order:

```bash
ls -l /dev/dxg                                          # the WSL GPU device; absent means no passthrough
ls /usr/lib/wsl/lib | grep -E 'libcuda|libnvidia-ml'    # the CUDA and NVML libraries WSL provides
ls -l /usr/lib/wsl/lib/nvidia-smi                        # present when the driver ships it
/usr/lib/wsl/lib/nvidia-smi                              # full path: nvidia-smi is not on PATH by default
```

To use the tool without the full path, add the directory to the user's shell profile, not the system
path:

```bash
export PATH="/usr/lib/wsl/lib:$PATH"
```

If `/dev/dxg` is missing or `nvidia-smi` reports no devices, check on the host: the driver version,
Windows updates, and whether the GPU is in use by a Windows application that holds it exclusively. Do not
fix it inside WSL by installing a Linux driver.

## 7. systemd, user services and linger

With `[boot] systemd=true` in `/etc/wsl.conf`, systemd is PID 1 and `systemctl --user` works. Check:

```bash
ps -p 1 -o comm=                         # prints systemd when enabled
systemctl --user status                  # fails with "Failed to connect to bus" when systemd is not PID 1
loginctl show-user "$USER" -p Linger     # Linger=yes keeps user units running with no login session
```

Enable linger for the user with `sudo loginctl enable-linger <user>` and re-check. Changes to
`/etc/wsl.conf` take effect only after `wsl.exe --shutdown` and a restart of the distribution.

Linger keeps user services running after the last login session closes, but it does not prevent WSL from
stopping the distribution's VM. Check on the build in use: `wsl.exe --list --verbose` shows Running or
Stopped. If a service must run continuously, verify it survives a session closing and does not depend on
an open terminal.

## 8. Reclaim Docker space, keeping what must stay

Docker stores images, containers, volumes and build cache under its data root, which is usually on the
distribution's VHDX. Find it first:

```bash
docker info -f '{{.DockerRootDir}}'
docker system df -v                      # sizes of images, containers, volumes and build cache
docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
docker compose ls 2>/dev/null
```

**Decide what must be kept, with the operator, before any prune:**

- Running containers and the images they use (`docker ps`).
- Stopped containers that hold state or that the operator still wants (`docker ps -a`, restart policies).
- Named volumes that hold data, especially databases and model caches. `docker system df -v` lists sizes
  and which containers use each volume. Treat every volume as data until shown otherwise.
- Images tagged for a deployment, and build cache a current build relies on.

Then reclaim in order of risk, lowest first, each step confirmed:

```bash
docker image prune                                  # dangling images only; no tagged images
docker builder prune --keep-storage 10GB            # build cache beyond a retained size
docker container prune                              # stopped containers, only if the operator agrees
```

Volumes last, and only from an explicit list the operator has approved:

```bash
docker volume ls -f dangling=true                   # review every name before removing any
```

Do not use `docker system prune -a --volumes` on a host that holds state. It removes unused images, all
stopped containers and unused volumes in one step.

After pruning, the freed space is inside the VHDX but not yet on the host. Return it with `fstrim` and a
compaction (section 2), with the distribution stopped.

## 9. Verify after any change

- Host: `Get-Item ... Length` is smaller (after compaction) or the expected size (after growth), and the
  host volume's `SizeRemaining` has moved the right way.
- Guest: `df -h /` and `findmnt` match the plan; the models mount is present; `docker info` answers.
- Services: `systemctl --user` answers; the expected user services are active.
- GPU: `/dev/dxg` present and `/usr/lib/wsl/lib/nvidia-smi` reports the device.
- Record each figure with its command and the time it was read. Figures from before a shutdown are stale
  after it.

## Neighbours

- **resume-after-crash** (claude-skills-ai-engineering group) recovers an agent's work after a reboot or crash. A full VHDX or a full host
  volume is a common cause of such a crash. Use it once the distribution is back, to reconcile the work.
- **local-llm-serving** (claude-skills-ai-engineering group) decides what models to run, how to place GGUF files and how llama-swap uses the
  GPU. This skill provides the disk and the GPU path that serving depends on; that skill owns the serving
  configuration.
