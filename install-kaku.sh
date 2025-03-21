#!/usr/bin/env bash
# Kaku Dotfiles Installation Script
# Created for user: karth878
# Date: 2025-03-21
# This script will install NixOS with the Kaku dotfiles on a selected disk

set -e  # Exit on any error

# Function to print colored text
print_color() {
    local color="$1"
    local text="$2"
    case "$color" in
        "red") echo -e "\e[31m$text\e[0m" ;;
        "green") echo -e "\e[32m$text\e[0m" ;;
        "yellow") echo -e "\e[33m$text\e[0m" ;;
        "blue") echo -e "\e[34m$text\e[0m" ;;
        *) echo "$text" ;;
    esac
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_color "red" "Please run this script as root (use sudo -i first)"
    exit 1
fi

# Display welcome message
clear
print_color "blue" "======================================================"
print_color "blue" "       Kaku Dotfiles NixOS Installation Script        "
print_color "blue" "======================================================"
echo
print_color "yellow" "WARNING: This script will ERASE ALL DATA on the selected disk."
print_color "yellow" "Make sure you have backups of any important data before proceeding."
echo
read -p "Press Enter to continue or Ctrl+C to abort..."

# List available disks
echo
print_color "green" "Available disks:"
echo

# Get disk list with relevant information
lsblk -o NAME,SIZE,MODEL,SERIAL,TYPE | grep -E 'disk' --color=never

echo
print_color "yellow" "Enter the disk you want to install to (e.g., nvme0n1 or sda):"
print_color "yellow" "DO NOT include the /dev/ prefix"
read DISK_NAME

# Validate disk exists
if [ ! -b "/dev/${DISK_NAME}" ]; then
    print_color "red" "Error: Disk /dev/${DISK_NAME} does not exist!"
    exit 1
fi

DISK="/dev/${DISK_NAME}"

# Double confirmation
echo
print_color "red" "WARNING! This will erase ALL DATA on ${DISK}!"
print_color "red" "Type the disk name again to confirm (e.g., nvme0n1 or sda):"
read CONFIRM_DISK

if [ "${DISK_NAME}" != "${CONFIRM_DISK}" ]; then
    print_color "red" "Disk names do not match. Aborting for safety."
    exit 1
fi

# Detect if we're dealing with an NVMe drive or SATA drive
if [[ $DISK_NAME == nvme* ]]; then
    PART_PREFIX="p"  # NVMe partitions are like nvme0n1p1
else
    PART_PREFIX=""   # SATA partitions are like sda1
fi

# Prepare for installation
print_color "green" "Step 1: Wiping the entire disk ${DISK} safely"
# Perform a secure wipe of the entire disk
dd if=/dev/zero of="${DISK}" bs=1M status=progress

print_color "green" "Step 2: Wiping disk signatures from ${DISK}"
wipefs -a "${DISK}"

print_color "green" "Step 3: Creating partitions"
# Create a new GPT partition table and partitions
{
    echo "o" # Create a new empty GPT partition table
    echo "y" # Confirm
    echo "n" # New partition
    echo ""  # Partition number (default)
    echo ""  # First sector (default)
    echo "+1G" # Last sector (1GB for EFI)
    echo "ef00" # EFI System
    echo "n" # New partition
    echo ""  # Partition number (default)
    echo ""  # First sector (default)
    echo ""  # Last sector (use rest of disk)
    echo "8300" # Linux filesystem
    echo "w" # Write changes
    echo "y" # Confirm
} | gdisk "${DISK}"

print_color "green" "Step 4: Formatting partitions"
sleep 1 # Give the kernel time to recognize the new partitions

# Format EFI partition
mkfs.fat -F 32 -n EFI "${DISK}${PART_PREFIX}1"

# Format system partition
mkfs.xfs -f -L NIXOS "${DISK}${PART_PREFIX}2"

print_color "green" "Step 5: Mounting partitions"
mount /dev/disk/by-label/NIXOS /mnt
mkdir -p /mnt/boot
mount /dev/disk/by-label/EFI /mnt/boot

print_color "green" "Step 6: Setting up Nix environment"
nix-shell -p nixVersions.stable git --run "
    print_color 'green' 'Step 7: Cloning the dotfiles'
    git clone --depth 1 https://github.com/linuxmobile/kaku /mnt/etc/nixos

    print_color 'green' 'Step 8: Generating hardware configuration'
    mkdir -p /mnt/etc/nixos/hosts/aesthetic
    nixos-generate-config --dir /mnt/etc/nixos/hosts/aesthetic --force
    rm -rf /mnt/etc/nixos/hosts/aesthetic/configuration.nix

    print_color 'green' 'Step 9: Installing NixOS'
    nixos-install

    print_color 'green' 'Step 10: Rebooting into the new system'
    reboot
"

# After rebooting, you will need to re-run this script to apply the dotfiles configuration.
print_color "green" "Installation completed! The system will now reboot."
print_color "yellow" "====================== IMPORTANT ======================\n"
print_color "yellow" "The default login credentials are:"
print_color "yellow" "  Username: nixos"
print_color "yellow" "  Password: nixos"
print_color "yellow" "\nAfter rebooting, log in and re-run this script with the '--rebuild' flag to apply the dotfiles configuration."
print_color "yellow" "=====================================================\n"

if [ "$1" == "--rebuild" ]; then
    print_color "green" "Step 11: Applying dotfiles configuration using nixos-rebuild"
    cd /etc/nixos/
    nixos-rebuild switch --flake .#aesthetic

    print_color "green" "Step 12: Activating Home Manager configuration"
    home-manager switch --flake 'github:linuxmobile/kaku#linudev@aesthetic'
fi

print_color "green" "Configuration applied successfully!"
print_color "yellow" "====================== IMPORTANT ======================\n"
print_color "yellow" "The default login credentials are:"
print_color "yellow" "  Username: nixos"
print_color "yellow" "  Password: nixos"
print_color "yellow" "\nDon't forget to change your password with:"
print_color "yellow" "  passwd YourUser"
print_color "yellow" "=====================================================\n"
