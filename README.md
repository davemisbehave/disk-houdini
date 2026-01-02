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
The script can be called without arguments:
```
./houdini.sh
```
Specify the `-h` (or `--help`) argument for a description of all the arguments and how to use them.
```
./houdini.sh -h
```

More info on usage and all arguments will follow...


