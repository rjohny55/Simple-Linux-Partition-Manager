# SIMPLE LINUX PARTITION MANAGER v1.2 (SLPM)

![Version](https://img.shields.io/badge/version-1.2-blue) [![Bash](https://img.shields.io/badge/Bash-4.4%2B-green)](https://www.gnu.org/software/bash/) ![License](https://img.shields.io/badge/license-Apache-orange) [![Stars](https://img.shields.io/github/stars/rjohny55/Simple-Linux-Docker-Manager?style=social)](https://github.com/rjohny55/Simple-Linux-Docker-Manager)

**The simplest, safest and most user-friendly terminal-based partition manager written entirely in pure Bash.**

No ncurses, no extra dependencies — just a single script that works everywhere.

### Features (2025 edition)
- Never bricks GPT disks — automatically uses `-34s` instead of dangerous `100%`
- Resizes only the last partition (with clear warning if you pick another one)
- Proper 1 MiB alignment for all new partitions
- Create + instantly format: **ext4 · xfs · fat32 · swap**
- Auto-grow ext4, XFS filesystems and LVM Physical Volumes
- Free space highlighted in green
- Toggle zram/virtual devices with one key (`z`)
- System disk marked in red + big warning
- Prevents double launch + clean exit on Ctrl+C
- Works on SATA, NVMe, MMC, VirtIO, Xen, LXC — everywhere

### Installation

**Recommended one-liner (installs as `partman`):**
```bash
sudo curl -L https://raw.githubusercontent.com/rjohny55/Simple-Linux-Partition-Manager/main/slpm.sh \
  -o /usr/local/bin/partman && sudo chmod +x /usr/local/bin/partman
```

**Or classic way:**
```bash
git clone https://github.com/rjohny55/Simple-Linux-Partition-Manager.git
cd Simple-Linux-Partition-Manager
chmod +x slpm.sh
sudo ./slpm.sh
```

### Usage
```bash
sudo partman        # if installed via one-liner
# or
sudo ./slpm.sh
```

### Requirements
Only standard tools (present on every Linux):
- `lsblk`, `parted`, `util-linux`, `e2fsprogs`

Optional (for full functionality):
```bash
# Debian / Ubuntu
sudo apt install xfsprogs dosfstools lvm2

# Fedora / RHEL / AlmaLinux
sudo dnf install xfsprogs dosfstools lvm2
```

### License
Licensed under the **Apache License 2.0** — see [LICENSE](LICENSE) file.

```
SIMPLE LINUX PARTITION MANAGER v1.2
© 2025 rjohny55 — pure Bash, pure safety
```

Star on GitHub if you like it → https://github.com/rjohny55/Simple-Linux-Partition-Manager

---

## Русский

**Самый простой и самый безопасный менеджер разделов, написанный полностью на Bash.**

Никаких ncurses и тяжёлых зависимостей — один скрипт, который просто работает.

### Возможности (издание 2025 года)
- Никогда не ломает GPT — автоматически использует `-34s` вместо опасных `100%`
- Расширяет только последний раздел (с понятным предупреждением)
- Правильное выравнивание всех новых разделов (+1 МиБ)
- Создание + мгновенное форматирование: **ext4 · xfs · fat32 · swap**
- Автоматическое расширение ext4, XFS и LVM PV
- Свободное место подсвечивается зелёным
- Переключение zram-дисков одной клавишей `z`
- Системный диск красный + громкое предупреждение
- Защита от двойного запуска и чистый выход по Ctrl+C

### Установка

**Рекомендуемый one-liner (устанавливает как `partman`):**
```bash
sudo curl -L https://raw.githubusercontent.com/rjohny55/Simple-Linux-Partition-Manager/main/slpm.sh \
  -o /usr/local/bin/partman && sudo chmod +x /usr/local/bin/partman
```

**Классический способ:**
```bash
git clone https://github.com/rjohny55/Simple-Linux-Partition-Manager.git
cd Simple-Linux-Partition-Manager
chmod +x slpm.sh
sudo ./slpm.sh
```

### Запуск
```bash
sudo partman        # если установили one-liner'ом
# или
sudo ./slpm.sh
```

### Лицензия
**Apache License 2.0** — смотрите файл [LICENSE](LICENSE).

```
SIMPLE LINUX PARTITION MANAGER v1.2
© 2025 rjohny55 — чистый Bash, чистая безопасность
```

Ставьте звёздочку, если понравилось → https://github.com/rjohny55/Simple-Linux-Partition-Manager
