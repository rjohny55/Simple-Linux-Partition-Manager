#!/bin/bash

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Функция логирования
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Проверка прав root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "❌ Ошибка: Этот скрипт должен быть запущен с правами root"
        exit 1
    fi
}

# Функция проверки установленных утилит
check_dependencies() {
    local deps=("lsblk" "parted" "blkid" "findmnt")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Отсутствуют необходимые утилиты: ${missing[*]}"
        exit 1
    fi
}

# Функция показа всех дисков
show_disks() {
    echo -e "\n${CYAN}=== ОБНАРУЖЕННЫЕ ДИСКИ И РАЗДЕЛЫ ===${NC}"
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE,LABEL
    
    echo -e "\n${CYAN}=== ИНФОРМАЦИЯ О СВОБОДНОМ МЕСТЕ ===${NC}"
    
    # Получаем список физических дисков (исключая loop и zram)
    local disks=$(lsblk -dno NAME | grep -E '^(sd|nvme|vd)' | awk '{print "/dev/"$1}')
    
    for disk in $disks; do
        if [[ -b "$disk" ]]; then
            echo -e "\n${PURPLE}Диск: $disk${NC}"
            LANG=C parted -s "$disk" unit GB print free 2>/dev/null | grep -E "(Disk|Free Space)"
        fi
    done
}

# Функция выбора диска для управления
select_disk() {
    local disks=$(lsblk -dno NAME | grep -E '^(sd|nvme|vd)' | awk '{print "/dev/"$1}')
    local disk_list=()
    local i=1
    
    echo -e "\n${CYAN}=== ВЫБОР ДИСКА ДЛЯ УПРАВЛЕНИЯ ===${NC}"
    
    for disk in $disks; do
        if [[ -b "$disk" ]]; then
            local size=$(lsblk -dno SIZE "$disk")
            local model=$(cat /sys/block/$(basename "$disk")/device/model 2>/dev/null || echo "Unknown")
            echo "$i. $disk ($size) - $model"
            disk_list+=("$disk")
            ((i++))
        fi
    done
    
    echo "0. Выход"
    
    while true; do
        read -p "Выберите диск [0-${#disk_list[@]}]: " choice
        
        if [[ "$choice" -eq 0 ]]; then
            log "Выход..."
            exit 0
        fi
        
        if [[ "$choice" -ge 1 && "$choice" -le ${#disk_list[@]} ]]; then
            local selected_disk="${disk_list[$((choice-1))]}"
            echo -e "\n${GREEN}Выбран диск: $selected_disk${NC}"
            manage_disk "$selected_disk"
            break
        else
            error "Неверный выбор"
        fi
    done
}

# Функция получения информации о свободном месте для раздела (ИСПРАВЛЕННАЯ)
get_partition_free_space() {
    local disk=$1
    local part_num=$2
    
    # Используем LANG=C для гарантии английского вывода
    local disk_info=$(LANG=C parted -s "$disk" unit GB print free 2>/dev/null)
    
    if [[ $? -ne 0 ]]; then
        echo "0"
        return
    fi
    
    # Получаем размер диска
    local disk_size=$(echo "$disk_info" | grep "^Disk $disk:" | awk '{print $3}' | sed 's/GB//')
    
    # Получаем конец выбранного раздела
    local part_end=$(echo "$disk_info" | grep -E "^ *$part_num " | awk '{print $3}' | sed 's/GB//')
    
    if [[ -z "$disk_size" || -z "$part_end" ]]; then
        echo "0"
        return
    fi
    
    # Вычисляем свободное место как разницу между размером диска и концом раздела
    local free_space=$(echo "$disk_size - $part_end" | bc -l 2>/dev/null)
    
    if [[ -z "$free_space" ]]; then
        echo "0"
        return
    fi
    
    # Округляем до 2 знаков
    free_space=$(printf "%.2f" "$free_space" 2>/dev/null)
    
    # Если значение очень маленькое, округляем до 0
    if [[ $(echo "$free_space < 0.01" | bc -l 2>/dev/null) -eq 1 ]]; then
        echo "0"
    else
        echo "$free_space"
    fi
}

# Функция проверки, является ли раздел последним на диске
is_last_partition() {
    local disk=$1
    local part_num=$2
    
    # Получаем максимальный номер раздела на диске
    local max_part=$(LANG=C parted -s "$disk" unit GB print 2>/dev/null | grep -E "^ *[0-9]+ " | awk '{print $1}' | sort -n | tail -1)
    
    [[ "$part_num" -eq "$max_part" ]]
}

# НОВАЯ ФУНКЦИЯ: Исправление GPT таблицы
fix_gpt_table() {
    local disk=$1
    
    echo -e "\n${YELLOW}Обнаружена проблема с GPT таблицей${NC}"
    echo "GPT backup находится не в конце диска, что мешает расширению раздела."
    
    read -p "Исправить GPT таблицу? (y/N): " fix_choice
    if [[ ! "$fix_choice" =~ ^[Yy]$ ]]; then
        return 1
    fi
    
    log "Исправление GPT таблицы на диске $disk..."
    
    # Используем parted для исправления GPT
    if echo "Fix" | parted ---pretend-input-tty "$disk" print 2>/dev/null | grep -q "fixed"; then
        log "GPT таблица успешно исправлена"
        return 0
    fi
    
    # Альтернативный метод через sgdisk
    if command -v sgdisk &> /dev/null; then
        log "Попытка исправления через sgdisk..."
        if sgdisk -e "$disk"; then
            log "GPT таблица успешно исправлена с помощью sgdisk"
            return 0
        fi
    fi
    
    # Последний вариант - через parted с интерактивным вводом
    log "Попытка интерактивного исправления через parted..."
    if parted "$disk" << EOF
print
Fix
print
quit
EOF
    then
        log "GPT таблица успешно исправлена"
        return 0
    else
        error "Не удалось исправить GPT таблицу"
        return 1
    fi
}

# Функция предложения размонтировать диск
unmount_partition_question() {
    local device=$1
    local mount_point=$2
    
    echo -e "\n${YELLOW}Раздел $device смонтирован в $mount_point${NC}"
    echo "Для безопасного изменения размера рекомендуется размонтировать раздел."
    
    while true; do
        read -p "Хотите размонтировать раздел перед расширением? (y/n): " unmount_choice
        case $unmount_choice in
            [Yy]* )
                log "Размонтирование раздела $device..."
                if umount "$device"; then
                    log "Раздел $device успешно размонтирован"
                    return 0
                else
                    error "Не удалось размонтировать раздел $device"
                    read -p "Продолжить без размонтирования? (y/n): " continue_choice
                    if [[ "$continue_choice" =~ ^[Yy]$ ]]; then
                        warn "Продолжение без размонтирования - это может быть небезопасно"
                        return 1
                    else
                        log "Операция отменена пользователем"
                        return 2
                    fi
                fi
                ;;
            [Nn]* )
                warn "Продолжение без размонтирования - это может быть небезопасно"
                return 1
                ;;
            * )
                echo "Пожалуйста, ответьте y (да) или n (нет)"
                ;;
        esac
    done
}

# Функция расширения файловой системы
expand_filesystem() {
    local device=$1
    
    # Проверяем, существует ли устройство
    if [[ ! -b "$device" ]]; then
        warn "Устройство $device не найдено, пропускаем расширение ФС"
        return 1
    fi
    
    # Определяем тип файловой системы
    local fs_type=$(blkid -s TYPE -o value "$device" 2>/dev/null)
    local mount_point=$(findmnt -n -o TARGET "$device" 2>/dev/null)
    
    echo -e "\n${BLUE}Расширение файловой системы...${NC}"
    echo "Устройство: $device"
    echo "Тип ФС: ${fs_type:-неизвестен}"
    echo "Точка монтирования: ${mount_point:-не смонтирован}"
    
    case "$fs_type" in
        "ext4"|"ext3"|"ext2")
            if [[ -n "$mount_point" ]]; then
                # Для смонтированных ext* файловых систем
                log "Расширение смонтированной ext* ФС..."
                if resize2fs "$device"; then
                    log "Файловая система успешно расширена"
                else
                    error "Ошибка расширения ФС"
                fi
            else
                # Для несмонтированных - проверяем с помощью e2fsck
                log "Проверка ФС перед расширением..."
                if e2fsck -f -p "$device"; then
                    log "Расширение несмонтированной ext* ФС..."
                    if resize2fs "$device"; then
                        log "Файловая система успешно расширена"
                    else
                        error "Ошибка расширения ФС"
                    fi
                else
                    error "Ошибка проверки ФС"
                fi
            fi
            ;;
        "xfs")
            if [[ -n "$mount_point" ]]; then
                log "Расширение XFS ФС..."
                if xfs_growfs "$mount_point"; then
                    log "XFS файловая система успешно расширена"
                else
                    error "Ошибка расширения XFS ФС"
                fi
            else
                warn "XFS можно расширить только когда она смонтирована"
            fi
            ;;
        "btrfs")
            if [[ -n "$mount_point" ]]; then
                log "Расширение Btrfs ФС..."
                if btrfs filesystem resize max "$mount_point"; then
                    log "Btrfs файловая система успешно расширена"
                else
                    error "Ошибка расширения Btrfs ФС"
                fi
            else
                warn "Btrfs можно расширить только когда она смонтирована"
            fi
            ;;
        "ntfs")
            if command -v ntfsresize &> /dev/null; then
                log "Расширение NTFS ФС..."
                if ntfsresize -b "$device"; then
                    log "NTFS файловая система успешно расширена"
                else
                    error "Ошибка расширения NTFS ФС"
                fi
            else
                warn "Утилита ntfsresize не установлена"
            fi
            ;;
        "vfat"|"fat32")
            warn "FAT32 не поддерживает онлайн-расширение"
            ;;
        *)
            warn "Автоматическое расширение ФС типа '$fs_type' не поддерживается"
            echo "Выполните расширение вручную для $device"
            ;;
    esac
}

# Функция изменения размера раздела
resize_partition() {
    local disk=$1
    
    echo -e "\n${YELLOW}📏 ИЗМЕНЕНИЕ РАЗМЕРА РАЗДЕЛА НА $disk${NC}"
    
    # Показываем текущую таблицу разделов
    echo -e "\n${CYAN}Текущая таблица разделов:${NC}"
    LANG=C parted -s "$disk" unit GB print free 2>/dev/null
    
    # Получаем список разделов
    local partitions=$(LANG=C parted -s "$disk" unit GB print 2>/dev/null | grep -E "^ *[0-9]+ " | awk '{print $1}')
    
    if [[ -z "$partitions" ]]; then
        error "На диске нет разделов"
        return 1
    fi
    
    echo -e "\n${CYAN}Доступные разделы:${NC}"
    for part in $partitions; do
        local part_info=$(LANG=C parted -s "$disk" unit GB print 2>/dev/null | grep "^ *$part ")
        local part_start=$(echo "$part_info" | awk '{print $2}')
        local part_end=$(echo "$part_info" | awk '{print $3}')
        local part_size=$(echo "$part_info" | awk '{print $4}')
        local part_fs=$(echo "$part_info" | awk '{print $5}')
        
        # Получаем свободное место после раздела
        local free_space=$(get_partition_free_space "$disk" "$part")
        
        # Проверяем, является ли раздел последним
        local is_last=$(is_last_partition "$disk" "$part" && echo " (последний)" || echo "")
        
        echo "  $part. Размер: $part_size, ФС: $part_fs$is_last"
        if [[ "$free_space" != "0" ]]; then
            echo -e "     💾 ${GREEN}Свободно после раздела: ${free_space}GB${NC}"
        fi
    done
    
    read -p "Введите номер раздела для изменения размера: " part_num
    
    # Проверяем, что раздел существует
    if ! echo "$partitions" | grep -q "^$part_num$"; then
        error "Раздел $part_num не существует"
        return 1
    fi
    
    # Получаем информацию о выбранном разделе
    local part_info=$(LANG=C parted -s "$disk" unit GB print 2>/dev/null | grep "^ *$part_num ")
    local part_start=$(echo "$part_info" | awk '{print $2}')
    local part_end=$(echo "$part_info" | awk '{print $3}')
    local part_size=$(echo "$part_info" | awk '{print $4}')
    local free_space=$(get_partition_free_space "$disk" "$part_num")
    
    echo -e "\n${YELLOW}Информация о разделе $part_num:${NC}"
    echo "  Начало: $part_start"
    echo "  Конец: $part_end" 
    echo "  Текущий размер: $part_size"
    
    # Проверяем, является ли раздел последним
    if ! is_last_partition "$disk" "$part_num"; then
        error "Раздел $part_num не является последним на диске. Расширение возможно только для последнего раздела."
        return 1
    fi
    
    if [[ "$free_space" == "0" ]]; then
        error "Нет свободного места для расширения этого раздела"
        return 1
    fi
    
    echo -e "  ${GREEN}Свободное место после раздела: ${free_space}GB${NC}"
    
    # Определяем устройство раздела
    local part_device=""
    if [[ "$disk" =~ nvme ]]; then
        part_device="${disk}p${part_num}"
    else
        part_device="${disk}${part_num}"
    fi
    
    # Проверяем, смонтирован ли раздел
    local mount_point=$(findmnt -n -o TARGET "$part_device" 2>/dev/null)
    if [[ -n "$mount_point" ]]; then
        # ИСПОЛЬЗУЕМ ФУНКЦИЮ ДЛЯ ПРЕДЛОЖЕНИЯ РАЗМОНТИРОВАНИЯ
        unmount_partition_question "$part_device" "$mount_point"
        local unmount_result=$?
        
        if [[ $unmount_result -eq 2 ]]; then
            # Пользователь отменил операцию
            return 1
        fi
    fi
    
    echo -e "\n${CYAN}Выберите действие:${NC}"
    echo "1. Расширить раздел на все свободное место (+${free_space}GB)"
    echo "2. Расширить на указанный размер"
    echo "3. Отмена"
    
    read -p "Выберите действие [1-3]: " action_choice
    
    case $action_choice in
        1)
            # Расширяем на все свободное место
            local new_end="100%"
            echo -e "\n${YELLOW}Расширение раздела $part_num на все свободное место (+${free_space}GB)${NC}"
            ;;
        2)
            read -p "Введите новый размер раздела (например: +10GB или 500GB): " custom_size
            if [[ -z "$custom_size" ]]; then
                error "Не указан размер"
                return 1
            fi
            local new_end="$custom_size"
            ;;
        3)
            log "Операция отменена"
            return 0
            ;;
        *)
            error "Неверный выбор"
            return 1
            ;;
    esac
    
    echo -e "\n${RED}⚠️  ВНИМАНИЕ: Это изменит размер раздела!${NC}"
    echo "Устройство: $part_device"
    echo "Новый конец раздела: $new_end"
    read -p "Продолжить? (y/N): " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        # Выполняем изменение размера раздела
        echo -e "\n${BLUE}Выполняем изменение размера...${NC}"
        
        # Используем parted для изменения размера
        if LANG=C parted -s "$disk" resizepart "$part_num" "$new_end"; then
            log "Размер раздела успешно изменен"
            
            # Обновляем информацию о разделах
            partprobe "$disk" 2>/dev/null
            sleep 2  # Даем время системе обновиться
            
            # Расширяем файловую систему, если это поддерживается
            expand_filesystem "$part_device"
            
            # Показываем результат
            echo -e "\n${GREEN}✅ Раздел успешно расширен${NC}"
            echo -e "\n${CYAN}Обновленная таблица разделов:${NC}"
            LANG=C parted -s "$disk" unit GB print free 2>/dev/null
            
        else
            # Обработка ошибки GPT таблицы
            if LANG=C parted -s "$disk" resizepart "$part_num" "$new_end" 2>&1 | grep -q "you can fix the GPT"; then
                if fix_gpt_table "$disk"; then
                    log "Повторная попытка изменения размера после исправления GPT..."
                    if LANG=C parted -s "$disk" resizepart "$part_num" "$new_end"; then
                        log "Размер раздела успешно изменен после исправления GPT"
                        
                        # Обновляем информацию о разделах
                        partprobe "$disk" 2>/dev/null
                        sleep 2
                        
                        # Расширяем файловую систему
                        expand_filesystem "$part_device"
                        
                        # Показываем результат
                        echo -e "\n${GREEN}✅ Раздел успешно расширен${NC}"
                        echo -e "\n${CYAN}Обновленная таблица разделов:${NC}"
                        LANG=C parted -s "$disk" unit GB print free 2>/dev/null
                    else
                        error "Ошибка при изменении размера раздела даже после исправления GPT"
                        return 1
                    fi
                else
                    error "Не удалось исправить GPT таблицу"
                    return 1
                fi
            else
                error "Ошибка при изменении размера раздела"
                return 1
            fi
        fi
    else
        log "Операция отменена"
    fi
}

# Функция создания раздела
create_partition() {
    local disk=$1
    
    echo -e "\n${YELLOW}Создание нового раздела на $disk${NC}"
    
    # Показываем текущее состояние диска
    echo -e "\n${CYAN}Текущая таблица разделов:${NC}"
    LANG=C parted -s "$disk" unit GB print free 2>/dev/null
    
    # Определяем доступное свободное место
    local free_space=$(LANG=C parted -s "$disk" unit GB print free 2>/dev/null | grep "Free Space" | tail -1 | awk '{print $3}' | sed 's/GB//')
    
    if [[ "$free_space" == "0" ]]; then
        error "На диске нет свободного места для создания раздела"
        return 1
    fi
    
    echo "Доступное свободное место: ${free_space}GB"
    
    read -p "Введите размер раздела (например: 10GB или 100%): " size
    read -p "Введите тип раздела (primary/extended/logical) [primary]: " part_type
    part_type=${part_type:-primary}
    
    read -p "Введите файловую систему (ext4/ntfs/fat32) [ext4]: " fs_type
    fs_type=${fs_type:-ext4}
    
    echo -e "\n${RED}ВНИМАНИЕ: Это изменит таблицу разделов!${NC}"
    read -p "Продолжить? (y/N): " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        # Определяем начальную позицию (после последнего раздела)
        local last_sector=$(LANG=C parted -s "$disk" unit GB print 2>/dev/null | grep -E "^ *[0-9]+ " | tail -1 | awk '{print $3}')
        
        if [[ -n "$last_sector" ]]; then
            local start_pos="$last_sector"
        else
            local start_pos="0%"
        fi
        
        echo "Создание раздела: тип=$part_type, ФС=$fs_type, размер=$size"
        
        if LANG=C parted -s "$disk" mkpart "$part_type" "$fs_type" "$start_pos" "$size"; then
            log "Раздел успешно создан"
            
            # Обновляем информацию о разделах
            partprobe "$disk" 2>/dev/null
            
            # Показываем результат
            echo -e "\n${GREEN}✅ Раздел успешно создан${NC}"
            echo -e "\n${CYAN}Обновленная таблица разделов:${NC}"
            LANG=C parted -s "$disk" unit GB print 2>/dev/null
            
        else
            error "Ошибка при создании раздела"
        fi
    else
        log "Операция отменена"
    fi
}

# Функция удаления раздела
delete_partition() {
    local disk=$1
    
    echo -e "\n${YELLOW}Удаление раздела на $disk${NC}"
    
    # Показываем текущую таблицу разделов
    echo -e "\n${CYAN}Текущая таблица разделов:${NC}"
    LANG=C parted -s "$disk" unit GB print 2>/dev/null
    
    # Получаем список разделов
    local partitions=$(LANG=C parted -s "$disk" unit GB print 2>/dev/null | grep -E "^ *[0-9]+ " | awk '{print $1}')
    
    if [[ -z "$partitions" ]]; then
        error "На диске нет разделов для удаления"
        return 1
    fi
    
    echo -e "\n${CYAN}Доступные разделы:${NC}"
    for part in $partitions; do
        local part_info=$(LANG=C parted -s "$disk" unit GB print 2>/dev/null | grep "^ *$part ")
        local part_size=$(echo "$part_info" | awk '{print $4}')
        local part_fs=$(echo "$part_info" | awk '{print $5}')
        echo "  $part. Размер: $part_size, ФС: $part_fs"
    done
    
    read -p "Введите номер раздела для удаления: " part_num
    
    # Проверяем, что раздел существует
    if ! echo "$partitions" | grep -q "^$part_num$"; then
        error "Раздел $part_num не существует"
        return 1
    fi
    
    # Определяем устройство раздела
    local part_device=""
    if [[ "$disk" =~ nvme ]]; then
        part_device="${disk}p${part_num}"
    else
        part_device="${disk}${part_num}"
    fi
    
    # Проверяем, смонтирован ли раздел
    local mount_point=$(findmnt -n -o TARGET "$part_device" 2>/dev/null)
    if [[ -n "$mount_point" ]]; then
        error "Раздел $part_device смонтирован в $mount_point"
        echo "Сначала размонтируйте раздел: umount $part_device"
        return 1
    fi
    
    echo -e "\n${RED}⚠️  ВНИМАНИЕ: Это удалит раздел и все данные на нем!${NC}"
    echo "Удаляемый раздел: $part_device"
    read -p "Продолжить? (y/N): " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        if LANG=C parted -s "$disk" rm "$part_num"; then
            log "Раздел успешно удален"
            
            # Обновляем информацию о разделах
            partprobe "$disk" 2>/dev/null
            
            # Показываем результат
            echo -e "\n${GREEN}✅ Раздел успешно удален${NC}"
            echo -e "\n${CYAN}Обновленная таблица разделов:${NC}"
            LANG=C parted -s "$disk" unit GB print 2>/dev/null
            
        else
            error "Ошибка при удалении раздела"
        fi
    else
        log "Операция отменена"
    fi
}

# Функция управления диском через parted
manage_disk() {
    local disk=$1
    
    while true; do
        echo -e "\n${CYAN}=== УПРАВЛЕНИЕ ДИСКОМ: $disk ===${NC}"
        echo "1. 📊 Показать информацию о диске"
        echo "2. 📋 Показать таблицу разделов"
        echo "3. ➕ Создать новый раздел"
        echo "4. ❌ Удалить раздел"
        echo "5. 📏 Изменить размер раздела"
        echo "6. 🔙 Вернуться к выбору диска"
        echo "0. 🚪 Выход"
        
        read -p "Выберите действие [0-6]: " action
        
        case $action in
            1)
                echo -e "\n${YELLOW}Информация о диске:${NC}"
                fdisk -l "$disk"
                ;;
            2)
                echo -e "\n${YELLOW}Таблица разделов:${NC}"
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
                log "Выход..."
                exit 0
                ;;
            *)
                error "Неверный выбор"
                ;;
        esac
    done
}

# Основная функция
main() {
    clear
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════╗"
    echo "║           ПРОСТОЙ МЕНЕДЖЕР РАЗДЕЛОВ         ║"
    echo "║                   LINUX                      ║"
    echo "╚══════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    # Проверки
    check_root
    check_dependencies
    
    # Приветственное сообщение
    echo -e "${CYAN}"
    echo "Этот скрипт поможет вам управлять разделами дисков."
    echo "Будьте осторожны - неправильные действия могут привести к потере данных!"
    echo -e "${NC}"
    
    while true; do
        show_disks
        select_disk
    done
}

# Обработка прерывания
trap 'echo -e "\n"; error "Скрипт прерван"; exit 130' INT TERM

# Запуск основной функции
main "$@"
