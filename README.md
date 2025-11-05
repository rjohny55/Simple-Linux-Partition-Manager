**README.md:**
```markdown
# 🖥️ Simple Linux Partition Manager

**English** | [Russian](README_ru.md)

A simple and user-friendly bash script for managing disk partitions in Linux with an intuitive text-based interface.

## ✨ Features

- 📊 **View information** about disks and partitions
- 📏 **Resize partitions** with filesystem expansion
- ➕ **Create new** partitions
- ❌ **Delete** existing partitions
- 🔄 **Automatic expansion** of filesystems (ext2/3/4, XFS, BTRFS, NTFS)
- 🛡️ **Safe unmounting** before operations
- 🔧 **GPT table fixes** when needed
- 🎨 **Colorful output** for better readability

## 📋 Supported Filesystems

- **ext2/ext3/ext4** - full support
- **XFS** - expansion when mounted
- **BTRFS** - expansion when mounted
- **NTFS** - with `ntfsresize` utility
- **FAT32** - limited support

## 🚀 Quick Start

### Requirements
- Linux OS
- Root privileges
- Utilities: `lsblk`, `parted`, `blkid`, `findmnt`

### Installation & Run

```bash
# Download the script
git clone https://github.com/rjohny55/Simple-Linux-Partition-Manager.git
cd partition-manager

# Make executable
chmod +x slpm.sh

# Run as root
sudo ./slpm.sh
```

## 🎯 Usage

### Main Menu
After launch you'll see:
1. **List of all disks** with free space information
2. **Disk selection** for management
3. **Operations menu** for selected disk

### Available Operations
- 📊 **Disk Information** - detailed disk information
- 📋 **Partition Table** - current partition structure
- ➕ **Create Partition** - create new partition
- ❌ **Delete Partition** - remove existing partition
- 📏 **Resize Partition** - expand partition with GPT handling

## ⚠️ Important Warnings

- **Always backup** important data before partition operations
- **Do not interrupt** partition operations
- **Ensure** partition is unmounted or can be safely unmounted

## 🔧 Workflow Example

```bash
# Start the script
sudo ./slpm.sh

# Example of partition expansion:
# 1. Select disk /dev/sda
# 2. Choose "Resize partition"
# 3. Select partition 2 (last one)
# 4. Confirm unmounting
# 5. Choose expansion to all free space
# 6. Confirm operation
# 7. Script automatically expands partition and filesystem
```

## 🐛 Troubleshooting

### GPT Table Error
If you encounter:
```
Warning: Not all of the space available to /dev/sda appears to be used
```
The script will automatically offer to fix the GPT table.

### Mounted Partition
When mounted partition is detected, the script offers:
- Automatic unmounting
- Continue without unmounting (not recommended)
- Cancel operation

## 🤝 Contributing

We welcome contributions to the project!

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📄 License

This project is distributed under the MIT License. See `LICENSE` file for details.

## ⭐ Acknowledgments

- Developers of `parted`, `lsblk`, `resize2fs` utilities
- Linux community for invaluable resources
```

Также создам файл **LICENSE** (MIT лицензия):

```text
MIT License

Copyright (c) 2025 Simple Partition Manager

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
