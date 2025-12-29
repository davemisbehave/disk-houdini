#!/usr/bin/env zsh

################################################################################
# Script:   houdini.sh
# Author:   Dave Misbehave
# Created:  Dec. 2025
#
# This zsh script is a tool to securely erase disks on macOS.
################################################################################

# Treat unset variables as errors (-u) and fail pipe on any command (-o pipefail)
set -uo pipefail

# Directory to store logs of each erase process
LOG_DIRECOTRY="$HOME/Format Logs"

# Erase level descriptions
ERASE_LVL_0_DESCRIPTION="Single-pass zero fill erase"
ERASE_LVL_1_DESCRIPTION="Single-pass random fill erase"
ERASE_LVL_2_DESCRIPTION="Seven-pass erase, consisting of zero fills and all-ones fills plus a final random fill"
ERASE_LVL_3_DESCRIPTION="Gutmann algorithm 35-pass erase"
ERASE_LVL_4_DESCRIPTION="Three-pass erase, consisting of two random fills plus a final zero fill"

# Ensure macOS
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script is for macOS only."
  exit 1
fi

# Export Homebrew paths
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# Ensure smartctl exists
if ! command -v smartctl >/dev/null 2>&1; then
  echo "smartctl not installed."
  echo "Install with: brew install smartmontools"
  exit 1
fi

# Ensure sudo or root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run with sudo or as root. Exiting script."
    exit 1
fi

# Determine boot disk
BOOT_DISK="$(diskutil info / | awk -F': *' '/Part of Whole/ {print $2; exit}')"

# List connected drives
diskutil list

# Select disk
tput bold; read "?Enter disk number: " DISK_NUMBER; tput sgr0

# Store full path to disk file
DISK_FILE="/dev/disk$DISK_NUMBER"

# Check if specified disk exists
if [[ ! -e "$DISK_FILE" ]]; then
    tput bold; echo "$DISK_FILE device node does not exist. Exiting script."; tput sgr0
	exit 1
fi

# Refuse to erase boot disk
if [[ "$DISK_FILE" == "/dev/$BOOT_DISK" ]]; then
    tput bold; echo "Cannot to securely erase the boot disk ($BOOT_DISK). Exiting script"; tput sgr0
    exit 1
fi

# Select erase level
echo '\n'"Erase levels:"
echo "0 - $ERASE_LVL_0_DESCRIPTION."
echo "1 - $ERASE_LVL_1_DESCRIPTION."
echo "2 - $ERASE_LVL_2_DESCRIPTION."
echo "3 - $ERASE_LVL_3_DESCRIPTION."
echo "4 - $ERASE_LVL_4_DESCRIPTION."
tput bold; read "?Enter erase level [0 - 4]: " ERASE_LEVEL; tput sgr0

# Check if selected erase level is valid
if [[ ! $ERASE_LEVEL == [0-4] ]]; then
    tput bold; echo "Invalid erase level. Exiting script."; tput sgr0
	exit 1
fi

# Assign erase level description
case "$ERASE_LEVEL" in
	0)	ERASE_LVL_DESCRIPTION=$ERASE_LVL_0_DESCRIPTION ;;
	1)	ERASE_LVL_DESCRIPTION=$ERASE_LVL_1_DESCRIPTION ;;
	2)	ERASE_LVL_DESCRIPTION=$ERASE_LVL_2_DESCRIPTION ;;
	3)	ERASE_LVL_DESCRIPTION=$ERASE_LVL_3_DESCRIPTION ;;
	4)	ERASE_LVL_DESCRIPTION=$ERASE_LVL_4_DESCRIPTION ;;
esac

# Determine disk serial number
if smartctl -i $DISK_FILE >/dev/null 2>&1; then
    HAS_SERIAL=1
    DISK_SERIAL=$(smartctl -i $DISK_FILE | awk -F'Serial Number:[[:space:]]*' '/Serial Number/ {print $2}')
else
    HAS_SERIAL=0
    DISK_SERIAL=none
fi
# Determine disk model
DISK_MODEL=$(diskutil info $DISK_FILE | awk -F': *' '/Device \/ Media Name/ {print $2}')
# Determine disk size
DISK_SIZE=$(diskutil info "/dev/disk4" | awk -F': *| \\(' '/Disk Size/ {print $2}')

# Read back settings for confirmation
echo '\n'"The secure erase will proceed with the following parameters:"
echo "Disk:"'\t''\t'"$DISK_FILE"
echo "Model:"'\t''\t'"$DISK_MODEL"
if [[ $HAS_SERIAL -eq 0 ]]; then
    echo "Serial Number:"'\t'"$DISK_SERIAL"
fi
echo "Size:"'\t''\t'"$DISK_SIZE"
echo "Erase level:"'\t'"$ERASE_LEVEL ($ERASE_LVL_DESCRIPTION)"
echo "Current partition map for $DISK_FILE:"
diskutil list $DISK_FILE

# Ask user to confirm
tput bold; read "?Type 'tak' and press enter to start erasing: " CONFIRMATION; tput sgr0
[[ $CONFIRMATION == "tak" ]] || {
    tput bold; echo "No secure erase was performed. Exiting script."; tput sgr0
    exit 1
}

# Unmount disk
diskutil unmountDisk $DISK_FILE
STATUS=$?
if [[ $STATUS -ne 0 ]]; then
    tput bold; echo "Could not unmount $DISK_FILE. Exiting script."; tput sgr0
    exit 1
fi

# Create format log directory if it doesn't already exist
mkdir -p $LOG_DIRECOTRY

# Set file name
if [[ $HAS_SERIAL -eq 1 ]]; then
    LOG_FILE=$LOG_DIRECOTRY/$DISK_MODEL-$DISK_SERIAL-$(date "+%Y-%m-%d-%H-%M-%S").log
else
    LOG_FILE=$LOG_DIRECOTRY/$DISK_MODEL-$(date "+%Y-%m-%d-%H-%M-%S").log
fi

# Log disk info
echo "Model:"'\t''\t'"$DISK_MODEL" >> $LOG_FILE
echo "Serial Number:"'\t'"$DISK_SERIAL" >> $LOG_FILE
echo "Size:"'\t''\t'"$DISK_SIZE" >> $LOG_FILE
echo "Erase level:"'\t'"$ERASE_LEVEL ($ERASE_LVL_DESCRIPTION)" >> $LOG_FILE

# Print the time and date the erase process was started at
echo '\n'"Starting secure erase on $(date)" | tee -a $LOG_FILE

# Record start time (epoch seconds)
START_EPOCH=$(date +%s)

# Perform secure erase
diskutil secureErase $ERASE_LEVEL $DISK_FILE
STATUS=$?
#STATUS=0
#echo "-> PRETENDING TO ERASE $DISK_FILE <-" | tee -a $LOG_FILE
#sleep 3

# Record end time and date
END_DATE=$(date)
END_EPOCH=$(date +%s)

# Print the time and date the erase process was concluded at
tput bold
if [[ $STATUS -eq 0 ]]; then
    echo "Secure erase completed successfully on $END_DATE" | tee -a $LOG_FILE
else
    echo "Secure erase failed (exit code: $status) on $END_DATE" | tee -a $LOG_FILE
fi
tput sgr0

# Calculate elapsed time
ELAPSED=$((END_EPOCH - START_EPOCH))
DAYS=$((ELAPSED / 86400))
REMAINDER=$((ELAPSED % 86400))
HOURS=$((REMAINDER / 3600))
REMAINDER=$((REMAINDER % 3600))
MINUTES=$((REMAINDER / 60))
SECONDS=$((REMAINDER % 60))

# Print formatted duration
if (( DAYS > 0 )); then
    echo "Elapsed time: ${DAYS}d ${HOURS}h ${MINUTES}m ${SECONDS}s" | tee -a $LOG_FILE
elif (( HOURS > 0 )); then
    echo "Elapsed time: ${HOURS}h ${MINUTES}m ${SECONDS}s" | tee -a $LOG_FILE
elif (( MINUTES > 0 )); then
    echo "Elapsed time: ${MINUTES}m ${SECONDS}s" | tee -a $LOG_FILE
else
    echo "Elapsed time: ${SECONDS}s" | tee -a $LOG_FILE
fi

# Done
echo "klolthxbye"
