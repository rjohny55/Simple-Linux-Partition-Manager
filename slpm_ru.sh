#!/bin/bash

# ==========================================
# SIMPLE LINUX PARTITION MANAGER v1.2 
# ==========================================

# Строгий режим
set -o pipefail

# Цвета
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
        echo -e "${RED}Скрипт уже запущен! (PID: $PID)${NC}"
        exit 1
    else
        rm -f "$LOCKFILE"
    fi
fi
echo $$ > "$LOCKFILE"

# --- ПРОВЕРКИ ---
check_root() {
    if [[ $EUID -ne 0 ]]; then echo -e "${RED}Ошибка: Запустите с sudo!${NC}"; exit 1; fi
}

check_dependencies() {
    local deps=("lsblk" "parted" "bc" "grep" "awk" "sed" "tput")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then echo -e "${RED}Нет утилиты: $dep${NC}"; exit 1; fi
    done
}

# --- УТИЛИТЫ ---
pause() {
    echo -e "\n${WHITE}Нажмите Enter для продолжения...${NC}"
    read -r
}

print_header() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║       SIMPLE LINUX PARTITION MANAGER v1.2            ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
}

get_part_path() {
    local disk=$1
    local num=$2
    if [[ "$disk" =~ "nvme" || "$disk" =~ "mmcblk" ]]; then echo "${disk}p${num}"; else echo "${disk}${num}"; fi
}

sync_table() {
    echo -e "${CYAN}Синхронизация ядра...${NC}"
    partprobe "$1" 2>/dev/null
    udevadm settle 2>/dev/null || sleep 1
}

is_system_disk() {
    local disk=$1
    local root_src=$(findmnt -n -o SOURCE /)
    local root_pkname=$(lsblk -no PKNAME "$root_src" | head -1)
    [[ "$(basename "$disk")" == "$root_pkname" ]]
}

# --- ОПЕРАЦИИ ---

operation_expand() {
    local disk=$1
    print_header
    echo -e "${YELLOW}>>> РАСШИРЕНИЕ РАЗДЕЛА НА $disk${NC}\n"
    
    # Показываем таблицу с подсветкой свободного места
    LANG=C parted -s "$disk" unit GB print free | grep -E "^( |[0-9])" | \
        sed "s/Free Space/${GREEN}Free Space${NC}/g"
    echo ""
    
    read -p "Номер раздела (Enter - отмена): " part_num
    [[ -z "$part_num" ]] && return

    local part_dev=$(get_part_path "$disk" "$part_num")
    if [[ ! -b "$part_dev" ]]; then echo -e "${RED}Нет такого раздела!${NC}"; pause; return; fi

    # ПРОВЕРКА: Является ли раздел последним?
    local last_part=$(LANG=C parted -sm "$disk" print | grep -E "^[0-9]" | tail -1 | cut -d: -f1)
    if [[ "$part_num" != "$last_part" ]]; then
        echo -e "\n${RED}⚠️  ВНИМАНИЕ: Выбранный раздел ($part_num) НЕ является последним!${NC}"
        echo "Обычно расширять можно только последний раздел."
        echo "Расширение промежуточного раздела возможно ТОЛЬКО если сразу за ним есть удаленная область."
        echo "В противном случае parted выдаст ошибку."
        read -p "Вы точно хотите продолжить? (y/n): " force
        [[ "$force" != "y" ]] && return
    fi

    echo -e "\n1. Максимально (Безопасно)"
    echo "2. Ввести вручную"
    read -p "Выбор [1]: " choice
    
    local new_end=""
    if [[ "$choice" == "2" ]]; then
        read -p "Конец (напр. 50GB): " new_end
    else
        if LANG=C parted -s "$disk" print | grep -q "Partition Table: gpt"; then new_end="-34s"; else new_end="100%"; fi
    fi

    if LANG=C parted -s "$disk" resizepart "$part_num" "$new_end"; then
        sync_table "$disk"
        echo -e "${CYAN}Расширение файловой системы...${NC}"
        local fs=$(blkid -s TYPE -o value "$part_dev")
        case "$fs" in
            ext*) resize2fs "$part_dev" ;;
            xfs)  local mp=$(findmnt -n -o TARGET "$part_dev"); [[ -n "$mp" ]] && xfs_growfs "$mp" || echo -e "${YELLOW}XFS смонтируйте сначала!${NC}" ;;
            LVM*) 
                if pvresize "$part_dev"; then 
                    echo -e "${GREEN}PV успешно расширен${NC}"
                else 
                    echo -e "${RED}Ошибка pvresize (возможно, PV не инициализирован)${NC}"
                fi 
                ;;
            *) echo -e "${YELLOW}ФС $fs не поддерживается для авто-ресайза.${NC}" ;;
        esac
        echo -e "${GREEN}Готово!${NC}"
    else
        echo -e "${RED}Ошибка parted (возможно, мешает следующий раздел)${NC}"
    fi
    pause
}

operation_create() {
    local disk=$1
    print_header
    echo -e "${YELLOW}>>> СОЗДАНИЕ РАЗДЕЛА НА $disk${NC}\n"
    LANG=C parted -s "$disk" unit GB print free | grep -E "Free Space" | sed "s/Free Space/${GREEN}Free Space${NC}/g"
    echo ""
    
    read -p "Размер (напр. 10GB или 100%): " size
    [[ -z "$size" ]] && return
    
    # Выбор ФС
    echo -e "Тип файловой системы:"
    echo " 1) ext4 (Linux)"
    echo " 2) xfs  (Linux)"
    echo " 3) fat32 (EFI/Flash)"
    echo " 4) swap (Подкачка)"
    echo " 5) none (Без формата)"
    read -p "Выбор [1]: " fs_choice
    
    local fs_type="ext4"
    case $fs_choice in
        2) fs_type="xfs" ;;
        3) fs_type="fat32" ;;
        4) fs_type="linux-swap" ;; # Для parted тип называется linux-swap
        5) fs_type="" ;;           # parted не укажет тип ФС
    esac

    # Авто-расчет старта
    local last_end=$(LANG=C parted -sm "$disk" unit s print 2>/dev/null | grep -E '^[0-9]+:' | tail -1 | cut -d: -f3 | sed 's/s//')
    local start_pos
    [[ -n "$last_end" ]] && start_pos="$((last_end + 2048))s" || start_pos="2048s"

    # Создание
    # Для parted синтаксис: mkpart [part-type] [fs-type] start end
    # part-type нужен для MBR (primary/logical), для GPT он игнорируется (все primary)
    if LANG=C parted -s "$disk" mkpart primary "$fs_type" "$start_pos" "$size"; then
        sync_table "$disk"
        echo -e "${GREEN}Раздел создан.${NC}"
        
        local new_num=$(LANG=C parted -sm "$disk" print | tail -1 | cut -d: -f1)
        local new_dev=$(get_part_path "$disk" "$new_num")
        
        # Форматирование
        if [[ -n "$fs_type" ]]; then
            read -p "Выполнить форматирование ($fs_type)? (y/n): " yn
            if [[ "$yn" == "y" ]]; then
                case "$fs_type" in
                    ext4) mkfs.ext4 -F "$new_dev" ;;
                    xfs)  mkfs.xfs -f "$new_dev" ;;
                    fat32) mkfs.vfat -I "$new_dev" ;;
                    linux-swap) 
                        mkswap "$new_dev"
                        read -p "Подключить swap сразу? (y/n): " sw
                        [[ "$sw" == "y" ]] && swapon "$new_dev"
                        ;;
                esac
            fi
        fi
    else
        echo -e "${RED}Ошибка создания${NC}"
    fi
    pause
}

operation_delete() {
    local disk=$1
    print_header
    echo -e "${YELLOW}>>> УДАЛЕНИЕ РАЗДЕЛА НА $disk${NC}\n"
    LANG=C parted -s "$disk" unit GB print | grep -E "^ [0-9]"
    echo ""
    read -p "Номер раздела для УДАЛЕНИЯ: " part_num
    [[ -z "$part_num" ]] && return
    
    local part_dev=$(get_part_path "$disk" "$part_num")
    if findmnt "$part_dev" >/dev/null; then echo -e "${RED}Раздел смонтирован! Нельзя удалить.${NC}"; pause; return; fi

    echo -e "${RED}ВНИМАНИЕ: ДАННЫЕ БУДУТ УТЕРЯНЫ НАВСЕГДА!${NC}"
    read -p "Введите 'del' для подтверждения: " confirm
    if [[ "$confirm" == "del" ]]; then
        LANG=C parted -s "$disk" rm "$part_num"
        sync_table "$disk"
        echo -e "${GREEN}Удалено.${NC}"
    fi
    pause
}

menu_disk_actions() {
    local disk=$1
    while true; do
        print_header
        echo -e "Выбран диск: ${CYAN}${BOLD}$disk${NC}"
        if is_system_disk "$disk"; then echo -e "${RED}⚠️  ЭТО СИСТЕМНЫЙ ДИСК! ОСТОРОЖНО!${NC}"; fi
        echo "--------------------------------------------------------"
        echo -e "${WHITE}Структура:${NC}"
        lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT "$disk" | sed '1d' | head -n 10
        echo "..."
        echo "--------------------------------------------------------"
        echo -e "${BOLD}ДЕЙСТВИЯ:${NC}"
        echo -e "  1. 📏 Расширить раздел"
        echo -e "  2. ➕ Создать раздел"
        echo -e "  3. ❌ Удалить раздел"
        echo -e "  4. 📄 Полная инфо (parted)"
        echo "--------------------------------------------------------"
        echo -e "  ${YELLOW}0. 🔙 Назад${NC}"
        echo ""
        read -p "Ваш выбор > " action
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

# --- ГЛАВНОЕ МЕНЮ ---
main_menu() {
    tput civis
    local SHOW_ZRAM=0
    
    while true; do
        print_header
        local devices=()
        printf "  %-4s %-12s %-10s %-25s\n" "№" "Диск" "Размер" "Модель"
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

        if [ ${#devices[@]} -eq 0 ]; then echo "   Диски не найдены!"; fi
        
        echo "--------------------------------------------------------"
        local zram_txt="показать"; [[ "$SHOW_ZRAM" -eq 1 ]] && zram_txt="скрыть"
        echo -e "  ${PURPLE}z. ZRAM ($zram_txt)${NC}"
        echo -e "  ${YELLOW}0. Выход${NC}"
        echo ""
        
        tput cnorm; read -p "Номер > " choice; tput civis
        
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

# --- ЗАПУСК ---
check_root
check_dependencies
main_menu
