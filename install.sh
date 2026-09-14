#!/usr/bin/env bash
set -Eeuo pipefail

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }
trap 'printf "Installation stopped at line %s. Fix the error and rerun; no reboot was performed.\n" "$LINENO" >&2' ERR

confirmation_prompt() {
  local required=$1 action=$2 highlight='' reset=''
  if [[ -t 2 && ${TERM:-dumb} != dumb && -z ${NO_COLOR:-} ]]; then
    highlight=$'\033[1;93m'
    reset=$'\033[0m'
  fi
  printf '\n>>> Type exactly: %s%s%s\n    %s\n> ' \
    "$highlight" "$required" "$reset" "$action" >&2
}

usage() {
  cat <<'EOF'
Usage: sudo bash install.sh [FLAKE_HOST]

Run from an x86_64 NixOS live installer booted in UEFI mode, with network
access. Choose a disk to erase and prepare (ext4 by default, optional XFS or
Btrfs, optional swap), or skip preparation and use /mnt and /mnt/boot that
you already mounted. Erasure requires typing the selected disk path.
This script does not reboot.

Uses the local checkout containing this script, replaces its hardware
configuration with the generated target configuration, and installs a chosen
nixosConfigurations host directly from that checkout.
Omit FLAKE_HOST for an interactive menu. Installation requires confirmation.
After installation, prompts for passwords for the selected host's normal users.
Builds use one job and one core at a time to reduce installer memory usage.
EOF
}

# Keep partition numbering consistent with the manual: root, optional swap, ESP.
partition_path() {
  local disk=$1 number=$2
  if [[ $disk == *[0-9] ]]; then printf '%sp%s' "$disk" "$number"
  else printf '%s%s' "$disk" "$number"; fi
}

partition_disk() {
  local disk=$1 fs=$2 swap_gib=$3 esp_number=2 root_end=100%
  if (( swap_gib > 0 )); then
    esp_number=3
    root_end="-${swap_gib}GiB"
  fi
  parted --script "$disk" -- mklabel gpt
  parted --script "$disk" -- mkpart root "$fs" 512MiB "$root_end"
  if (( swap_gib > 0 )); then
    parted --script "$disk" -- mkpart swap linux-swap "$root_end" 100%
  fi
  parted --script "$disk" -- mkpart ESP fat32 1MiB 512MiB
  parted --script "$disk" -- set "$esp_number" esp on
  partprobe "$disk"
  udevadm settle
}

check_unused_disk() {
  local disk=$1 node mounts
  [[ -b $disk ]] || die "Not a block device: $disk"
  [[ $(lsblk -dnro TYPE "$disk") == disk ]] || die 'Select a whole disk.'
  [[ $(lsblk -dnro RO "$disk") == 0 ]] || die 'Disk is read-only.'
  mounts=$(lsblk -nr -o MOUNTPOINTS "$disk")
  [[ ! $mounts =~ [^[:space:]] ]] || die 'Disk has mounted filesystems or active swap. Unmount them yourself first.'
  # Also reject active LVM, RAID, or encrypted mappings, even if unmounted.
  while read -r node; do
    if compgen -G "/sys/class/block/${node##*/}/holders/*" >/dev/null; then
      die "Disk device $node has active holders; deactivate them first."
    fi
  done < <(lsblk -nrpo NAME "$disk")
}

prepare_storage() {
  local choice disk fs swap_answer swap_gib=0 confirmation disk_bytes
  local root_part esp_part swap_part esp_number=2
  local -a disks=()
  printf 'Available disks (check size, model, and mounted installer media):\n'
  lsblk -p -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL
  mapfile -t disks < <(lsblk -dnpo NAME,TYPE | awk '$2 == "disk" {print $1}')
  printf '\nChoose a disk to ERASE, or skip for already-mounted partitions.\n'
  PS3='Disk number (or choose skip): '
  select choice in "${disks[@]}" 'Skip: use mounted /mnt and /mnt/boot'; do
    [[ -n $choice ]] || { printf 'Choose a listed number.\n' >&2; continue; }
    if [[ $choice == 'Skip: use mounted /mnt and /mnt/boot' ]]; then return; fi
    disk=$choice
    break
  done
  [[ -n ${disk:-} ]] || die 'No disk selected.'
  check_unused_disk "$disk"
  if findmnt -rn -o TARGET | awk '$0 == "/mnt" || index($0, "/mnt/") == 1 {found=1} END {exit !found}'; then
    die 'Unmount existing targets under /mnt before preparing a new disk, or choose skip.'
  fi
  [[ -z $(swapon --show --noheadings --raw --output NAME) ]] || die 'Deactivate existing swap first so it is not added to the new hardware configuration.'
  read -r -p 'Root filesystem [ext4/xfs/btrfs] (default ext4): ' fs || die 'No filesystem selected.'
  fs=${fs:-ext4}
  case $fs in ext4|xfs|btrfs) ;; *) die 'Choose ext4, xfs, or btrfs.' ;; esac
  read -r -p 'Create swap? [y/N]: ' swap_answer || die 'No swap choice received.'
  case $swap_answer in
    y|Y|yes|YES)
      read -r -p 'Swap size in GiB (default 8): ' swap_gib || die 'No swap size received.'
      swap_gib=${swap_gib:-8}
      [[ $swap_gib =~ ^[1-9][0-9]{0,5}$ ]] || die 'Swap size must be a positive whole number of GiB.'
      esp_number=3 ;;
    n|N|no|NO|'') ;;
    *) die 'Answer y or n.' ;;
  esac
  for cmd in parted partprobe udevadm "mkfs.$fs" mkfs.fat mount; do
    command -v "$cmd" >/dev/null || die "Missing command: $cmd"
  done
  if (( swap_gib > 0 )); then command -v mkswap >/dev/null || die 'Missing command: mkswap'; fi
  disk_bytes=$(lsblk -bdnro SIZE "$disk")
  (( disk_bytes > (swap_gib + 2) * 1024 * 1024 * 1024 )) || die 'Disk is too small for this layout.'
  root_part=$(partition_path "$disk" 1)
  esp_part=$(partition_path "$disk" "$esp_number")
  swap_part=$(partition_path "$disk" 2)
  printf '\nERASE ALL DATA on %s\nRoot: %s (%s)\nSwap: %s GiB\nEFI: %s (FAT32, 1–512 MiB)\n' \
    "$disk" "$root_part" "$fs" "$swap_gib" "$esp_part"
  confirmation_prompt "$disk" 'to erase this disk and create the partitions.'
  read -r confirmation || die 'Confirmation required.'
  [[ $confirmation == "$disk" ]] || die 'Cancelled before erasing.'
  check_unused_disk "$disk"
  partition_disk "$disk" "$fs" "$swap_gib"
  [[ -b $root_part && -b $esp_part ]] || die 'Expected partition devices did not appear.'
  case $fs in
    ext4) mkfs.ext4 -F -L nixos "$root_part" ;;
    xfs) mkfs.xfs -f -L nixos "$root_part" ;;
    btrfs) mkfs.btrfs -f -L nixos "$root_part" ;;
  esac
  mkfs.fat -F 32 -n boot "$esp_part"
  if (( swap_gib > 0 )); then
    [[ -b $swap_part ]] || die 'Swap partition did not appear.'
    mkswap -L swap "$swap_part"
    swapon "$swap_part"
  fi
  mkdir -p /mnt
  mount "$root_part" /mnt
  mkdir -p /mnt/boot
  mount -o umask=077 "$esp_part" /mnt/boot
}

if [[ ${1:-} == --help || ${1:-} == -h ]]; then usage; exit 0; fi
(( $# <= 1 )) || die 'Expected at most one flake host. Use --help.'
[[ ${1:-} != -* ]] || die 'Unknown option. Use --help.'
(( EUID == 0 )) || die 'Run with sudo from the NixOS live installer.'
for cmd in git nix nixos-generate-config nixos-install nixos-enter mountpoint findmnt cp mktemp lsblk awk swapon; do
  command -v "$cmd" >/dev/null || die "Missing command: $cmd (for Git, run: nix-shell -p git)."
done
[[ $(uname -m) == x86_64 ]] || die 'This repository targets x86_64-linux.'
[[ -d /sys/firmware/efi ]] || die 'Boot the live installer in UEFI mode for this repository.'
source_repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
[[ -d $source_repo/.git && -f $source_repo/flake.nix ]] || die 'Run the script from a full repository clone (not a linked Git worktree).'
prepare_storage
mountpoint -q /mnt || die 'Mount the target root filesystem at /mnt first.'
mountpoint -q /mnt/boot || die 'Mount the target EFI system partition at /mnt/boot first.'
[[ $(findmnt -n -o FSTYPE --mountpoint /mnt/boot) == vfat ]] || die '/mnt/boot must be a FAT EFI system partition.'

repo=$source_repo
cd "$repo"

# nixos-install and its child Nix processes also need flakes enabled on live media.
export NIX_CONFIG="${NIX_CONFIG:-}
extra-experimental-features = nix-command flakes"
host_list=$(nix eval --raw --no-write-lock-file .#nixosConfigurations \
  --apply 'configs: builtins.concatStringsSep "\n" (builtins.attrNames configs)')
[[ -n $host_list ]] || die 'No NixOS configurations found in the flake.'
mapfile -t hosts <<< "$host_list"
host=${1:-}
if [[ -z $host ]]; then
  printf 'Choose a flake configuration:\n'
  PS3='Configuration number: '
  select host in "${hosts[@]}"; do
    [[ -n $host ]] && break
    printf 'Choose one of the listed numbers.\n' >&2
  done
fi
valid=false
for candidate in "${hosts[@]}"; do
  if [[ $host == "$candidate" ]]; then valid=true; break; fi
done
[[ $valid == true ]] || die "Unknown or missing flake host: $host"

findmnt -R /mnt
printf '\nRepository: %s\nFlake: .#%s\n' "$repo" "$host"
printf 'Review modules/system/boot.nix, drives.nix, and users.nix for this machine.\n'
printf 'This will replace the checkout hardware configuration and install to /mnt.\n'
confirmation_prompt install 'to install the selected host to /mnt.'
read -r confirmation || die 'Confirmation required.'
[[ $confirmation == install ]] || die 'Cancelled.'

# Generate outside the checkout so the generated configuration.nix cannot
# overwrite the repository configuration. Keep a backup on every attempt.
nixos-generate-config --root /mnt
backup=$(mktemp /mnt/etc/nixos/hardware-configuration.repo-backup.XXXXXX)
cp -p hardware-configuration.nix "$backup"
cp /mnt/etc/nixos/hardware-configuration.nix hardware-configuration.nix
printf 'Previous repository hardware configuration saved to %s\n' "$backup"
# Read actual account names from the selected configuration, including any
# edits made at the confirmation prompt. System/service accounts are excluded.
user_list=$(nix eval --raw --no-write-lock-file ".#nixosConfigurations.\"$host\".config.users.users" \
  --apply 'users: builtins.concatStringsSep "\n" (map (user: user.name) (builtins.filter (user: user.isNormalUser) (builtins.attrValues users)))')
[[ -n $user_list ]] || die 'The selected host has no normal user configured.'
mapfile -t login_users <<< "$user_list"
for login_user in "${login_users[@]}"; do
  [[ $login_user =~ ^[a-zA-Z_][a-zA-Z0-9_.-]*\$?$ ]] || die "Unsupported login name: $login_user"
done
# The existing tracked hardware file is included by Git flakes even when dirty.
printf 'Installing with one build job and one core to reduce memory pressure.\n'
nixos-install --flake ".#$host" --max-jobs 1 --cores 1
for login_user in "${login_users[@]}"; do
  printf '\nSet the login password for %s on the installed system:\n' "$login_user"
  nixos-enter --root /mnt -c "passwd -- '$login_user'" || \
    die "Installation succeeded, but password setup failed. Before rebooting, run: sudo nixos-enter --root /mnt -c \"passwd -- '$login_user'\""
done
printf '\nInstallation and user password setup completed.\n'
printf 'The updated checkout remains at %s; save it before reboot if it is on live media.\n' "$repo"
printf 'When ready, run: reboot\n'
