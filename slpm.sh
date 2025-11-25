#!/bin/bash

# ==========================================
# SIMPLE LINUX PARTITION MANAGER v1.2 
# ==========================================

# Strict mode
set -o pipefail

# Colors
RED=$'\e[31m'
GREEN=$'\e[32m'
YELLOW=$'\e[33m'
BLUE=$'\e[34m'
CYAN=$'\e[36m'
WHITE=$'\e[37m'
PURPLE=$'\e[35m'
NC=$'\e[0m'
BOLD=$'\e[1m'

LOCKFILE="/tmp/partition_manager.lock"

# --- CLEANUP & TRAP ---
cleanup() {
    rm -f "$LOCKFILE"
    tput cnorm
    echo -e "${NC}"
    exit
}
trap cleanup EXIT INT TERM

# --- LOCKFILE CHECK ---
if [ -e "$LOCKFILE" ]; then
    PID=$(cat "$LOCKFILE")
    if ps -p "$PID" > /dev/null 2>&1; then
        echo -e "${RED}Script is already running! (PID: $PID)${NC}"
        exit 1
    else
        rm -f "$LOCKFILE"
    fi
fi
echo $$ > "$LOCKFILE"

# --- CHECKS ---
check_root() {
    if [[ $EUID -ne 0 ]]; then echo -e "${RED}Error: Run with sudo!${NC}"; exit 1; fi
}

check_dependencies() {
    local deps=("lsblk" "parted" "bc" "grep" "awk" "sed" "tput")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then echo -e "${RED}Missing utility: $dep${NC}"; exit 1; fi
    done
}

# --- UTILS ---
pause() {
    echo -e "\n${WHITE}Press Enter to continue...${NC}"
    read -r
}

print_header() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║        SIMPLE LINUX PARTITION MANAGER v1.2           ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
}

get_part_path() {
    local disk=$1
    local num=$2
    if [[ "$disk" =~ "nvme" || "$disk" =~ "mmcblk" ]]; then echo "${disk}p${num}"; else echo "${disk}${num}"; fi
}

sync_table() {
    echo -e "${CYAN}Syncing kernel tables...${NC}"
    partprobe "$1" 2>/dev/null
    udevadm settle 2>/dev/null || sleep 1
}

is_system_disk() {
    local disk=$1
    local root_src=$(findmnt -n -o SOURCE /)
    local root_pkname=$(lsblk -no PKNAME "$root_src" | head -1)
    [[ "$(basename "$disk")" == "$root_pkname" ]]
}

# --- OPERATIONS ---

operation_expand() {
    local disk=$1
    print_header
    echo -e "${YELLOW}>>> EXTEND PARTITION ON $disk${NC}\n"
    
    # Show table
    LANG=C parted -s "$disk" unit GB print free | grep -E "^( |[0-9])" | \
        sed "s/Free Space/${GREEN}Free Space${NC}/g"
    echo ""
    
    read -p "Partition number (Enter to cancel): " part_num
    [[ -z "$part_num" ]] && return

    local part_dev=$(get_part_path "$disk" "$part_num")
    if [[ ! -b "$part_dev" ]]; then echo -e "${RED}Partition not found!${NC}"; pause; return; fi

    # CHECK: Is it the last partition?
    local last_part=$(LANG=C parted -sm "$disk" print | grep -E "^[0-9]" | tail -1 | cut -d: -f1)
    if [[ "$part_num" != "$last_part" ]]; then
        echo -e "\n${RED}⚠️  WARNING: Partition ($part_num) is NOT the last one!${NC}"
        echo "Typically, you can only extend the last partition."
        echo "Extending a middle partition works ONLY if there is immediate free space after it."
        read -p "Do you really want to proceed? (y/n): " force
        [[ "$force" != "y" ]] && return
    fi

    echo -e "\n1. Maximize (Safe Mode)"
    echo "2. Manual size"
    read -p "Choice [1]: " choice
    
    local new_end=""
    if [[ "$choice" == "2" ]]; then
        read -p "New End (e.g. 50GB): " new_end
    else
        if LANG=C parted -s "$disk" print | grep -q "Partition Table: gpt"; then new_end="-34s"; else new_end="100%"; fi
    fi

    if LANG=C parted -s "$disk" resizepart "$part_num" "$new_end"; then
        sync_table "$disk"
        echo -e "${CYAN}Resizing filesystem...${NC}"
        local fs=$(blkid -s TYPE -o value "$part_dev")
        case "$fs" in
            ext*) resize2fs "$part_dev" ;;
            xfs)  local mp=$(findmnt -n -o TARGET "$part_dev"); [[ -n "$mp" ]] && xfs_growfs "$mp" || echo -e "${YELLOW}Mount XFS first!${NC}" ;;
            btrfs) local mp=$(findmnt -n -o TARGET "$part_dev"); [[ -n "$mp" ]] && btrfs filesystem resize max "$mp" || echo -e "${YELLOW}Mount Btrfs first!${NC}" ;;
            LVM*) 
                if pvresize "$part_dev"; then 
                    echo -e "${GREEN}PV resized successfully${NC}"
                else 
                    echo -e "${RED}pvresize failed (PV might not be initialized)${NC}"
                fi 
                ;;
            *) echo -e "${YELLOW}Filesystem $fs not supported for auto-resize.${NC}" ;;
        esac
        echo -e "${GREEN}Done!${NC}"
    else
        echo -e "${RED}Parted error (Blocked by another partition?)${NC}"
    fi
    pause
}

operation_create() {
    local disk=$1
    print_header
    echo -e "${YELLOW}>>> CREATE PARTITION ON $disk${NC}\n"
    LANG=C parted -s "$disk" unit GB print free | grep -E "Free Space" | sed "s/Free Space/${GREEN}Free Space${NC}/g"
    echo ""
    
    read -p "Size (e.g. 10GB or 100%): " size
    [[ -z "$size" ]] && return
    
    # FS Selection
    echo -e "Filesystem Type:"
    echo " 1) ext4 (Linux)"
    echo " 2) xfs  (Linux)"
    echo " 3) btrfs (Linux)"
    echo " 4) fat32 (EFI/USB)"
    echo " 5) swap"
    echo " 6) none (Unformatted)"
    read -p "Choice [1]: " fs_choice
    
    local fs_type="ext4"
    case $fs_choice in
        2) fs_type="xfs" ;;
        3) fs_type="btrfs" ;;
        4) fs_type="fat32" ;;
        5) fs_type="linux-swap" ;;
        6) fs_type="" ;;
    esac

    # Auto start calc
    local last_end=$(LANG=C parted -sm "$disk" unit s print 2>/dev/null | grep -E '^[0-9]+:' | tail -1 | cut -d: -f3 | sed 's/s//')
    local start_pos
    [[ -n "$last_end" ]] && start_pos="$((last_end + 2048))s" || start_pos="2048s"

    # Create
    if LANG=C parted -s "$disk" mkpart primary "$fs_type" "$start_pos" "$size"; then
        sync_table "$disk"
        echo -e "${GREEN}Partition created.${NC}"
        
        local new_num=$(LANG=C parted -sm "$disk" print | tail -1 | cut -d: -f1)
        local new_dev=$(get_part_path "$disk" "$new_num")
        
        # Format
        if [[ -n "$fs_type" ]]; then
            read -p "Format as $fs_type? (y/n): " yn
            if [[ "$yn" == "y" ]]; then
                case "$fs_type" in
                    ext4) mkfs.ext4 -F "$new_dev" ;;
                    xfs)  mkfs.xfs -f "$new_dev" ;;
                    btrfs) mkfs.btrfs -f "$new_dev" ;;
                    fat32) mkfs.fat -F32 -I "$new_dev" ;;
                    linux-swap) 
                        mkswap "$new_dev"
                        read -p "Activate swap now? (y/n): " sw
                        [[ "$sw" == "y" ]] && swapon "$new_dev"
                        ;;
                esac
            fi
        fi
    else
        echo -e "${RED}Creation failed${NC}"
    fi
    pause
}

operation_delete() {
    local disk=$1
    print_header
    echo -e "${YELLOW}>>> DELETE PARTITION ON $disk${NC}\n"
    LANG=C parted -s "$disk" unit GB print | grep -E "^ [0-9]"
    echo ""
    read -p "Partition number to DELETE: " part_num
    [[ -z "$part_num" ]] && return
    
    local part_dev=$(get_part_path "$disk" "$part_num")
    if findmnt "$part_dev" >/dev/null; then echo -e "${RED}Partition is mounted! Cannot delete.${NC}"; pause; return; fi

    echo -e "${RED}WARNING: DATA WILL BE LOST FOREVER!${NC}"
    read -p "Type 'del' to confirm: " confirm
    if [[ "$confirm" == "del" ]]; then
        LANG=C parted -s "$disk" rm "$part_num"
        sync_table "$disk"
        echo -e "${GREEN}Deleted.${NC}"
    fi
    pause
}

menu_disk_actions() {
    local disk=$1
    while true; do
        print_header
        echo -e "Selected Disk: ${CYAN}${BOLD}$disk${NC}"
        if is_system_disk "$disk"; then echo -e "${RED}⚠️  SYSTEM DISK! BE CAREFUL!${NC}"; fi
        echo "--------------------------------------------------------"
        echo -e "${WHITE}Layout:${NC}"
        lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT "$disk" | sed '1d' | head -n 10
        echo "..."
        echo "--------------------------------------------------------"
        echo -e "${BOLD}ACTIONS:${NC}"
        echo -e "  1. 📏 Extend Partition"
        echo -e "  2. ➕ Create Partition"
        echo -e "  3. ❌ Delete Partition"
        echo -e "  4. 📄 Full Info (Parted)"
        echo "--------------------------------------------------------"
        echo -e "  ${YELLOW}0. 🔙 Back${NC}"
        echo ""
        read -p "Choice > " action
        case $action in
            1) operation_expand "$disk" ;;
            2) operation_create "$disk" ;;
            3) operation_delete "$disk" ;;
            4) print_header; LANG=C parted -s "$disk" unit GB print free; pause ;;
            0) return ;;
            *) ;;
        esac
    done
}

# --- MAIN MENU ---
main_menu() {
    tput civis
    local SHOW_ZRAM=0
    
    while true; do
        print_header
        local devices=()
        printf "  %-4s %-12s %-10s %-25s\n" "#" "Device" "Size" "Model"
        echo "--------------------------------------------------------"

        local i=0
        while read -r name size model; do
            if [[ "$name" == *"zram"* ]]; then
                if [[ "$SHOW_ZRAM" -eq 0 ]]; then continue; fi
                model="Virtual Device"
            fi

            local full_path="/dev/$name"
            devices+=("$full_path")
            
            local label=""
            if is_system_disk "$full_path"; then label="${RED}(System)${NC}";
            elif [[ "$name" == *"zram"* ]]; then label="${PURPLE}(RAM)${NC}"; fi
            
            printf "  ${BOLD}%-4s${NC} %-12s %-10s %-25s %s\n" \
                "$((i+1))." "$full_path" "$size" "${model:-Unknown}" "$label"
            ((i++))
        done < <(lsblk -dno NAME,SIZE,MODEL -e 7,11)

        if [ ${#devices[@]} -eq 0 ]; then echo "   No disks found!"; fi
        
        echo "--------------------------------------------------------"
        local zram_txt="Show"; [[ "$SHOW_ZRAM" -eq 1 ]] && zram_txt="Hide"
        echo -e "  ${PURPLE}z. ZRAM ($zram_txt)${NC}"
        echo -e "  ${YELLOW}0. Exit${NC}"
        echo ""
        
        tput cnorm; read -p "Select > " choice; tput civis
        
        if [[ "$choice" == "z" || "$choice" == "Z" ]]; then
            if [[ "$SHOW_ZRAM" -eq 0 ]]; then SHOW_ZRAM=1; else SHOW_ZRAM=0; fi; continue
        fi
        if [[ "$choice" == "0" ]]; then cleanup; fi
        
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#devices[@]}" ]; then
            tput cnorm
            menu_disk_actions "${devices[$((choice-1))]}"
            tput civis
        fi
    done
}

# --- RUN ---
check_root
check_dependencies
main_menu
