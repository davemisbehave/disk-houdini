# Disk-Houdini
Disk-Houdini is a magician with a very particular trick: it makes your data vanish without a trace.

## Seriously, though
Disk-Houdini is a zsh script for macOS that aims to make using `diskutil secureErase`, to securely erase disks, more convenient.
A log file is written for each secure erase operation, for accountability (or not, optionally).

## Target OS
This script is targeted at macOS with zsh, so macOS Cataline 10.15 or above should work.
It was written and tested on macOS Tahoe 26.

## Prerequisites
### Software
The only thing needed, that is not already included with macos is `smartctl`.
The easiest way to install this is using [Homebrew](https://brew.sh).
```
brew install smartmontools
```
### Privileges
The user that runs the script must be a sudoer, or be root.
The script itself does not need to be run with sudo, but some commands in it are called with sudo, so a password is still necessary in most cases.

## Usage
### Without Arguments
The script can be called as is, without arguments. The script will guide the user through choosing a disk and erase level, with a final confirmation required before erasing.
```
./houdini.sh
```
### With Arguments
The following arguments can optionally be specified
#### `-h` / `--help`
This shows a summary of the available arguments and exits the script. Any other arguments are ignored if -h or --help is specified.
#### `-p` / `--pretend`
Pretend Mode (Dry-run). Does not make actual changes to the disk.
#### `-s` / `--skip`
Skip user confirmation before erasing.
#### `-nl` / `--nolog`
Do not write log file.
#### `-d` <disk> / `--disk` <disk>
Specify target disk file.
#### `-lv` <level> / `--level` <level>
Specify erase level [0 - 4].
- 0: Single-pass zero fill erase
- 1: Single-pass random fill erase
- 2: Seven-pass erase, consisting of zero fills and all-ones fills plus a final random fill
- 3: Gutmann algorithm 35-pass erase
- 4: Three-pass erase, consisting of two random fills plus a final zero fill.
#### `-la` <label> / `--label` <label>
Specify label. This might be any custom label, for any purpose. It will be part of the log file's file name, and be documented inside the log file. This might be something like "discard after erasing" or "blue external hard drive", for example.
#### `-m` <model> / `--model` <model>
This lets you manually specify a disk model. It will take precedence over the automatically determined model name, which is not always helpful or accurate.
#### `-sn` <serial> / `--serial` <serial>
This lets you manually specify a disk serial number. It will take precedence over the automatically determined serial, which is not always helpful or accurate, or can often not be read at all.
### Examples
#### Help
```
./houdini.sh --help
```
### Pretend/Practice run with erase level 2

```
./houdini.sh -p --level 2
```
### Disk `/dev/disk4` selected, no log file
```
./houdini.sh -d /dev/disk4 -nl
```
## Log File
A log file is written as soon as the erase process starts, unless the `-p` / `--pretend` option is enabled.
The location of the log file is in a folder inside the home directory of the caller (even if it is called with sudo):
```
~/Houdini Logs/
```
If the script is run as real root (not with sudo), then the log folder is:
```
/Users/shared/Houdini Logs/
```
