#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Root privileges check
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "❌ Error: This script must be run as root"
        exit 1
    fi
}

# Function to check required utilities
check_dependencies() {
    local deps=("lsblk" "parted" "blkid" "findmnt")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing required utilities: ${missing[*]}"
        exit 1
    fi
}

# Function to show all disks
show_disks() {
    echo -e "\n${CYAN}=== DETECTED DISKS AND PARTITIONS ===${NC}"
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE,LABEL
    
    echo -e "\n${CYAN}=== FREE SPACE INFORMATION ===${NC}"
    
    # Get list of physical disks (excluding loop and zram)
    local disks=$(lsblk -dno NAME | grep -E '^(sd|nvme|vd)' | awk '{print "/dev/"$1}')
    
    for disk in $disks; do
        if [[ -b "$disk" ]]; then
            echo -e "\n${PURPLE}Disk: $disk${NC}"
            LANG=C parted -s "$disk" unit GB print free 2>/dev/null | grep -E "(Disk|Free Space)"
        fi
    done
}

# Function to select disk for management
select_disk() {
    local disks=$(lsblk -dno NAME | grep -E '^(sd|nvme|vd)' | awk '{print "/dev/"$1}')
    local disk_list=()
    local i=1
    
    echo -e "\n${CYAN}=== SELECT DISK FOR MANAGEMENT ===${NC}"
    
    for disk in $disks; do
        if [[ -b "$disk" ]]; then
            local size=$(lsblk -dno SIZE "$disk")
            local model=$(cat /sys/block/$(basename "$disk")/device/model 2>/dev/null || echo "Unknown")
            echo "$i. $disk ($size) - $model"
            disk_list+=("$disk")
            ((i++))
        fi
    done
    
    echo "0. Exit"
    
    while true; do
        read -p "Select disk [0-${#disk_list[@]}]: " choice
        
        if [[ "$choice" -eq 0 ]]; then
            log "Exiting..."
            exit 0
        fi
        
        if [[ "$choice" -ge 1 && "$choice" -le ${#disk_list[@]} ]]; then
            local selected_disk="${disk_list[$((choice-1))]}"
            echo -e "\n${GREEN}Selected disk: $selected_disk${NC}"
            manage_disk "$selected_disk"
            break
        else
            error "Invalid selection"
        fi
    done
}

# Function to get free space information for partition (FIXED)
get_partition_free_space() {
    local disk=$1
    local part_num=$2
    
    # Use LANG=C to ensure English output
    local disk_info=$(LANG=C parted -s "$disk" unit GB print free 2>/dev/null)
    
    if [[ $? -ne 0 ]]; then
        echo "0"
        return
    fi
    
    # Get disk size
    local disk_size=$(echo "$disk_info" | grep "^Disk $disk:" | awk '{print $3}' | sed 's/GB//')
    
    # Get selected partition end
    local part_end=$(echo "$disk_info" | grep -E "^ *$part_num " | awk '{print $3}' | sed 's/GB//')
    
    if [[ -z "$disk_size" || -z "$part_end" ]]; then
        echo "0"
        return
    fi
    
    # Calculate free space as difference between disk size and partition end
    local free_space=$(echo "$disk_size - $part_end" | bc -l 2>/dev/null)
    
    if [[ -z "$free_space" ]]; then
        echo "0"
        return
    fi
    
    # Round to 2 decimal places
    free_space=$(printf "%.2f" "$free_space" 2>/dev/null)
    
    # If value is very small, round to 0
    if [[ $(echo "$free_space < 0.01" | bc -l 2>/dev/null) -eq 1 ]]; then
        echo "0"
    else
        echo "$free_space"
    fi
}

# Function to check if partition is the last on disk
is_last_partition() {
    local disk=$1
    local part_num=$2
    
    # Get maximum partition number on disk
    local max_part=$(LANG=C parted -s "$disk" unit GB print 2>/dev/null | grep -E "^ *[0-9]+ " | awk '{print $1}' | sort -n | tail -1)
    
    [[ "$part_num" -eq "$max_part" ]]
}

# NEW FUNCTION: Fix GPT table
fix_gpt_table() {
    local disk=$1
    
    echo -e "\n${YELLOW}GPT table issue detected${NC}"
    echo "GPT backup is not at the end of the disk, which prevents partition expansion."
    
    read -p "Fix GPT table? (y/N): " fix_choice
    if [[ ! "$fix_choice" =~ ^[Yy]$ ]]; then
        return 1
    fi
    
    log "Fixing GPT table on disk $disk..."
    
    # Use parted to fix GPT
    if echo "Fix" | parted ---pretend-input-tty "$disk" print 2>/dev/null | grep -q "fixed"; then
        log "GPT table successfully fixed"
        return 0
    fi
    
    # Alternative method using sgdisk
    if command -v sgdisk &> /dev/null; then
        log "Attempting fix via sgdisk..."
        if sgdisk -e "$disk"; then
            log "GPT table successfully fixed with sgdisk"
            return 0
        fi
    fi
    
    # Last resort - interactive parted
    log "Attempting interactive fix via parted..."
    if parted "$disk" << EOF
print
Fix
print
quit
EOF
    then
        log "GPT table successfully fixed"
        return 0
    else
        error "Failed to fix GPT table"
        return 1
    fi
}

# Function to offer disk unmounting
unmount_partition_question() {
    local device=$1
    local mount_point=$2
    
    echo -e "\n${YELLOW}Partition $device is mounted at $mount_point${NC}"
    echo "For safe resizing, it's recommended to unmount the partition."
    
    while true; do
        read -p "Do you want to unmount the partition before expansion? (y/n): " unmount_choice
        case $unmount_choice in
            [Yy]* )
                log "Unmounting partition $device..."
                if umount "$device"; then
                    log "Partition $device successfully unmounted"
                    return 0
                else
                    error "Failed to unmount partition $device"
                    read -p "Continue without unmounting? (y/n): " continue_choice
                    if [[ "$continue_choice" =~ ^[Yy]$ ]]; then
                        warn "Continuing without unmounting - this may be unsafe"
                        return 1
                    else
                        log "Operation cancelled by user"
                        return 2
                    fi
                fi
                ;;
            [Nn]* )
                warn "Continuing without unmounting - this may be unsafe"
                return 1
                ;;
            * )
                echo "Please answer y (yes) or n (no)"
                ;;
        esac
    done
}

# Function to expand filesystem
expand_filesystem() {
    local device=$1
    
    # Check if device exists
    if [[ ! -b "$device" ]]; then
        warn "Device $device not found, skipping FS expansion"
        return 1
    fi
    
    # Determine filesystem type
    local fs_type=$(blkid -s TYPE -o value "$device" 2>/dev/null)
    local mount_point=$(findmnt -n -o TARGET "$device" 2>/dev/null)
    
    echo -e "\n${BLUE}Expanding filesystem...${NC}"
    echo "Device: $device"
    echo "FS type: ${fs_type:-unknown}"
    echo "Mount point: ${mount_point:-not mounted}"
    
    case "$fs_type" in
        "ext4"|"ext3"|"ext2")
            if [[ -n "$mount_point" ]]; then
                # For mounted ext* filesystems
                log "Expanding mounted ext* FS..."
                if resize2fs "$device"; then
                    log "Filesystem successfully expanded"
                else
                    error "Filesystem expansion error"
                fi
            else
                # For unmounted - check with e2fsck
                log "Checking FS before expansion..."
                if e2fsck -f -p "$device"; then
                    log "Expanding unmounted ext* FS..."
                    if resize2fs "$device"; then
                        log "Filesystem successfully expanded"
                    else
                        error "Filesystem expansion error"
                    fi
                else
                    error "FS check error"
                fi
            fi
            ;;
        "xfs")
            if [[ -n "$mount_point" ]]; then
                log "Expanding XFS FS..."
                if xfs_growfs "$mount_point"; then
                    log "XFS filesystem successfully expanded"
                else
                    error "XFS filesystem expansion error"
                fi
            else
                warn "XFS can only be expanded when mounted"
            fi
            ;;
        "btrfs")
            if [[ -n "$mount_point" ]]; then
                log "Expanding Btrfs FS..."
                if btrfs filesystem resize max "$mount_point"; then
                    log "Btrfs filesystem successfully expanded"
                else
                    error "Btrfs filesystem expansion error"
                fi
            else
                warn "Btrfs can only be expanded when mounted"
            fi
            ;;
        "ntfs")
            if command -v ntfsresize &> /dev/null; then
                log "Expanding NTFS FS..."
                if ntfsresize -b "$device"; then
                    log "NTFS filesystem successfully expanded"
                else
                    error "NTFS filesystem expansion error"
                fi
            else
                warn "ntfsresize utility not installed"
            fi
            ;;
        "vfat"|"fat32")
            warn "FAT32 does not support online expansion"
            ;;
        *)
            warn "Automatic expansion of '$fs_type' filesystem type is not supported"
            echo "Perform manual expansion for $device"
            ;;
    esac
}

# Function to resize partition
resize_partition() {
    local disk=$1
    
    echo -e "\n${YELLOW}📏 RESIZE PARTITION ON $disk${NC}"
    
    # Show current partition table
    echo -e "\n${CYAN}Current partition table:${NC}"
    LANG=C parted -s "$disk" unit GB print free 2>/dev/null
    
    # Get list of partitions
    local partitions=$(LANG=C parted -s "$disk" unit GB print 2>/dev/null | grep -E "^ *[0-9]+ " | awk '{print $1}')
    
    if [[ -z "$partitions" ]]; then
        error "No partitions on disk"
        return 1
    fi
    
    echo -e "\n${CYAN}Available partitions:${NC}"
    for part in $partitions; do
        local part_info=$(LANG=C parted -s "$disk" unit GB print 2>/dev/null | grep "^ *$part ")
        local part_start=$(echo "$part_info" | awk '{print $2}')
        local part_end=$(echo "$part_info" | awk '{print $3}')
        local part_size=$(echo "$part_info" | awk '{print $4}')
        local part_fs=$(echo "$part_info" | awk '{print $5}')
        
        # Get free space after partition
        local free_space=$(get_partition_free_space "$disk" "$part")
        
        # Check if partition is last
        local is_last=$(is_last_partition "$disk" "$part" && echo " (last)" || echo "")
        
        echo "  $part. Size: $part_size, FS: $part_fs$is_last"
        if [[ "$free_space" != "0" ]]; then
            echo -e "     💾 ${GREEN}Free space after partition: ${free_space}GB${NC}"
        fi
    done
    
    read -p "Enter partition number to resize: " part_num
    
    # Check if partition exists
    if ! echo "$partitions" | grep -q "^$part_num$"; then
        error "Partition $part_num does not exist"
        return 1
    fi
    
    # Get selected partition information
    local part_info=$(LANG=C parted -s "$disk" unit GB print 2>/dev/null | grep "^ *$part_num ")
    local part_start=$(echo "$part_info" | awk '{print $2}')
    local part_end=$(echo "$part_info" | awk '{print $3}')
    local part_size=$(echo "$part_info" | awk '{print $4}')
    local free_space=$(get_partition_free_space "$disk" "$part_num")
    
    echo -e "\n${YELLOW}Partition $part_num information:${NC}"
    echo "  Start: $part_start"
    echo "  End: $part_end" 
    echo "  Current size: $part_size"
    
    # Check if partition is last
    if ! is_last_partition "$disk" "$part_num"; then
        error "Partition $part_num is not the last on disk. Expansion is only possible for the last partition."
        return 1
    fi
    
    if [[ "$free_space" == "0" ]]; then
        error "No free space to expand this partition"
        return 1
    fi
    
    echo -e "  ${GREEN}Free space after partition: ${free_space}GB${NC}"
    
    # Determine partition device
    local part_device=""
    if [[ "$disk" =~ nvme ]]; then
        part_device="${disk}p${part_num}"
    else
        part_device="${disk}${part_num}"
    fi
    
    # Check if partition is mounted
    local mount_point=$(findmnt -n -o TARGET "$part_device" 2>/dev/null)
    if [[ -n "$mount_point" ]]; then
        # USE NEW FUNCTION FOR UNMOUNT OFFER
        unmount_partition_question "$part_device" "$mount_point"
        local unmount_result=$?
        
        if [[ $unmount_result -eq 2 ]]; then
            # User cancelled operation
            return 1
        fi
    fi
    
    echo -e "\n${CYAN}Select action:${NC}"
    echo "1. Expand partition to all free space (+${free_space}GB)"
    echo "2. Expand by specified size"
    echo "3. Cancel"
    
    read -p "Select action [1-3]: " action_choice
    
    case $action_choice in
        1)
            # Expand to all free space
            local new_end="100%"
            echo -e "\n${YELLOW}Expanding partition $part_num to all free space (+${free_space}GB)${NC}"
            ;;
        2)
            read -p "Enter new partition size (e.g.: +10GB or 500GB): " custom_size
            if [[ -z "$custom_size" ]]; then
                error "No size specified"
                return 1
            fi
            local new_end="$custom_size"
            ;;
        3)
            log "Operation cancelled"
            return 0
            ;;
        *)
            error "Invalid selection"
            return 1
            ;;
    esac
    
    echo -e "\n${RED}⚠️  WARNING: This will change partition size!${NC}"
    echo "Device: $part_device"
    echo "New partition end: $new_end"
    read -p "Continue? (y/N): " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        # Execute partition resize
        echo -e "\n${BLUE}Performing resize...${NC}"
        
        # Use parted for resize
        if LANG=C parted -s "$disk" resizepart "$part_num" "$new_end"; then
            log "Partition size successfully changed"
            
            # Update partition information
            partprobe "$disk" 2>/dev/null
            sleep 2  # Give system time to update
            
            # Expand filesystem if supported
            expand_filesystem "$part_device"
            
            # Show result
            echo -e "\n${GREEN}✅ Partition successfully expanded${NC}"
            echo -e "\n${CYAN}Updated partition table:${NC}"
            LANG=C parted -s "$disk" unit GB print free 2>/dev/null
            
        else
            # Handle GPT table error
            if LANG=C parted -s "$disk" resizepart "$part_num" "$new_end" 2>&1 | grep -q "you can fix the GPT"; then
                if fix_gpt_table "$disk"; then
                    log "Retrying resize after GPT fix..."
                    if LANG=C parted -s "$disk" resizepart "$part_num" "$new_end"; then
                        log "Partition size successfully changed after GPT fix"
                        
                        # Update partition information
                        partprobe "$disk" 2>/dev/null
                        sleep 2
                        
                        # Expand filesystem
                        expand_filesystem "$part_device"
                        
                        # Show result
                        echo -e "\n${GREEN}✅ Partition successfully expanded${NC}"
                        echo -e "\n${CYAN}Updated partition table:${NC}"
                        LANG=C parted -s "$disk" unit GB print free 2>/dev/null
                    else
                        error "Error changing partition size even after GPT fix"
                        return 1
                    fi
                else
                    error "Failed to fix GPT table"
                    return 1
                fi
            else
                error "Error changing partition size"
                return 1
            fi
        fi
    else
        log "Operation cancelled"
    fi
}

# Function to create partition
create_partition() {
    local disk=$1
    
    echo -e "\n${YELLOW}Creating new partition on $disk${NC}"
    
    # Show current disk state
    echo -e "\n${CYAN}Current partition table:${NC}"
    LANG=C parted -s "$disk" unit GB print free 2>/dev/null
    
    # Determine available free space
    local free_space=$(LANG=C parted -s "$disk" unit GB print free 2>/dev/null | grep "Free Space" | tail -1 | awk '{print $3}' | sed 's/GB//')
    
    if [[ "$free_space" == "0" ]]; then
        error "No free space on disk to create partition"
        return 1
    fi
    
    echo "Available free space: ${free_space}GB"
    
    read -p "Enter partition size (e.g.: 10GB or 100%): " size
    read -p "Enter partition type (primary/extended/logical) [primary]: " part_type
    part_type=${part_type:-primary}
    
    read -p "Enter filesystem (ext4/ntfs/fat32) [ext4]: " fs_type
    fs_type=${fs_type:-ext4}
    
    echo -e "\n${RED}WARNING: This will change partition table!${NC}"
    read -p "Continue? (y/N): " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        # Determine start position (after last partition)
        local last_sector=$(LANG=C parted -s "$disk" unit GB print 2>/dev/null | grep -E "^ *[0-9]+ " | tail -1 | awk '{print $3}')
        
        if [[ -n "$last_sector" ]]; then
            local start_pos="$last_sector"
        else
            local start_pos="0%"
        fi
        
        echo "Creating partition: type=$part_type, FS=$fs_type, size=$size"
        
        if LANG=C parted -s "$disk" mkpart "$part_type" "$fs_type" "$start_pos" "$size"; then
            log "Partition successfully created"
            
            # Update partition information
            partprobe "$disk" 2>/dev/null
            
            # Show result
            echo -e "\n${GREEN}✅ Partition successfully created${NC}"
            echo -e "\n${CYAN}Updated partition table:${NC}"
            LANG=C parted -s "$disk" unit GB print 2>/dev/null
            
        else
            error "Error creating partition"
        fi
    else
        log "Operation cancelled"
    fi
}

# Function to delete partition
delete_partition() {
    local disk=$1
    
    echo -e "\n${YELLOW}Deleting partition on $disk${NC}"
    
    # Show current partition table
    echo -e "\n${CYAN}Current partition table:${NC}"
    LANG=C parted -s "$disk" unit GB print 2>/dev/null
    
    # Get list of partitions
    local partitions=$(LANG=C parted -s "$disk" unit GB print 2>/dev/null | grep -E "^ *[0-9]+ " | awk '{print $1}')
    
    if [[ -z "$partitions" ]]; then
        error "No partitions to delete on disk"
        return 1
    fi
    
    echo -e "\n${CYAN}Available partitions:${NC}"
    for part in $partitions; do
        local part_info=$(LANG=C parted -s "$disk" unit GB print 2>/dev/null | grep "^ *$part ")
        local part_size=$(echo "$part_info" | awk '{print $4}')
        local part_fs=$(echo "$part_info" | awk '{print $5}')
        echo "  $part. Size: $part_size, FS: $part_fs"
    done
    
    read -p "Enter partition number to delete: " part_num
    
    # Check if partition exists
    if ! echo "$partitions" | grep -q "^$part_num$"; then
        error "Partition $part_num does not exist"
        return 1
    fi
    
    # Determine partition device
    local part_device=""
    if [[ "$disk" =~ nvme ]]; then
        part_device="${disk}p${part_num}"
    else
        part_device="${disk}${part_num}"
    fi
    
    # Check if partition is mounted
    local mount_point=$(findmnt -n -o TARGET "$part_device" 2>/dev/null)
    if [[ -n "$mount_point" ]]; then
        error "Partition $part_device is mounted at $mount_point"
        echo "First unmount the partition: umount $part_device"
        return 1
    fi
    
    echo -e "\n${RED}⚠️  WARNING: This will delete partition and all data on it!${NC}"
    echo "Partition to delete: $part_device"
    read -p "Continue? (y/N): " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        if LANG=C parted -s "$disk" rm "$part_num"; then
            log "Partition successfully deleted"
            
            # Update partition information
            partprobe "$disk" 2>/dev/null
            
            # Show result
            echo -e "\n${GREEN}✅ Partition successfully deleted${NC}"
            echo -e "\n${CYAN}Updated partition table:${NC}"
            LANG=C parted -s "$disk" unit GB print 2>/dev/null
            
        else
            error "Error deleting partition"
        fi
    else
        log "Operation cancelled"
    fi
}

# Function to manage disk via parted
manage_disk() {
    local disk=$1
    
    while true; do
        echo -e "\n${CYAN}=== DISK MANAGEMENT: $disk ===${NC}"
        echo "1. 📊 Show disk information"
        echo "2. 📋 Show partition table"
        echo "3. ➕ Create new partition"
        echo "4. ❌ Delete partition"
        echo "5. 📏 Resize partition"
        echo "6. 🔙 Back to disk selection"
        echo "0. 🚪 Exit"
        
        read -p "Select action [0-6]: " action
        
        case $action in
            1)
                echo -e "\n${YELLOW}Disk information:${NC}"
                fdisk -l "$disk"
                ;;
            2)
                echo -e "\n${YELLOW}Partition table:${NC}"
                LANG=C parted -s "$disk" unit GB print
                ;;
            3)
                create_partition "$disk"
                ;;
            4)
                delete_partition "$disk"
                ;;
            5)
                resize_partition "$disk"
                ;;
            6)
                return
                ;;
            0)
                log "Exiting..."
                exit 0
                ;;
            *)
                error "Invalid selection"
                ;;
        esac
    done
}

# Main function
main() {
    clear
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════╗"
    echo "║           SIMPLE PARTITION MANAGER          ║"
    echo "║                   LINUX                      ║"
    echo "╚══════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    # Checks
    check_root
    check_dependencies
    
    # Welcome message
    echo -e "${CYAN}"
    echo "This script will help you manage disk partitions."
    echo "Be careful - wrong actions can lead to data loss!"
    echo -e "${NC}"
    
    while true; do
        show_disks
        select_disk
    done
}

# Interrupt handling
trap 'echo -e "\n"; error "Script interrupted"; exit 130' INT TERM

# Start main function
main "$@"
