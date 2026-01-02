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

log_only() {
	local msg="$1"
	if [[ $EUID -eq 0 && -n ${SUDO_UID-} ]]; then
		sudo -u "#$CALLER_UID" -g "#$CALLER_GID" sh -c 'printf "%b\n" "$1" >> "$2"' sh "$msg" "$LOG_FILE"
	else
		printf "%b\n" "$msg" >> "$LOG_FILE"
	fi
}

log_and_print() {
	local msg="$1"
	if [[ $EUID -eq 0 && -n ${SUDO_UID-} ]]; then
		# Terminal output happens as root (fine); file append happens as caller
		printf "%b\n" "$msg" | tee -a >(sudo -u "#$CALLER_UID" -g "#$CALLER_GID" cat >> "$LOG_FILE")
	else
		printf "%b\n" "$msg" | tee -a "$LOG_FILE"
	fi
}

# Erase level descriptions
ERASE_LVL_0_DESCRIPTION="Single-pass zero fill erase"
ERASE_LVL_1_DESCRIPTION="Single-pass random fill erase"
ERASE_LVL_2_DESCRIPTION="Seven-pass erase, consisting of zero fills and all-ones fills plus a final random fill"
ERASE_LVL_3_DESCRIPTION="Gutmann algorithm 35-pass erase"
ERASE_LVL_4_DESCRIPTION="Three-pass erase, consisting of two random fills plus a final zero fill"


# Ensure macOS
if [[ "$(uname -s)" != "Darwin" ]]; then
	tput bold; echo "This script is for macOS only."; tput sgr0
	exit 1
fi

# Export Homebrew paths
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# Ensure smartctl exists
if ! command -v smartctl >/dev/null 2>&1; then
	tput bold; echo "smartctl not installed."; tput sgr0
	echo "Install with: brew install smartmontools"
	exit 1
fi

# Defaults for flags assumed before processing arguments (which might change their values)
PRETEND_MODE=0
DISK_SPECIFIED=0
LEVEL_SPECIFIED=0
SKIP_CONFIRMATION=0
NO_LOGS=0
HAS_SERIAL=0
MODEL_SPECIFIED=0
LABEL_SPECIFIED=0

while (( $# > 0 )); do
    ARG="$1"

    case $ARG in
		-h|--help)
			tput bold; echo "Usage:"; tput sgr0
			echo '\t'"$0 [-h|--help] [-p|--pretend] [-s|--skip] [-nl|--nolog] [-d|--disk <disk>] [-lv|--level <level>] [-la|--label <label>] [-m|--model <model>] [-sn|--serial <serial>]"
            
            tput bold; echo '\n'"Description:"; tput sgr0
			echo '\t'"This script performs a secure erase on a disk and creates"
			echo '\t'"a log file to go along with it."

			tput bold; echo '\n'"Options:"; tput sgr0
			echo '\t'"[-h  | --help]		Show this help message and exit."
			echo '\t'"[-p  | --pretend]	Pretend Mode (Dry-run). Does not make actual changes to the disk."
			echo '\t'"[-s  | --skip]		Skip user confirmation before erasing."
			echo '\t'"[-nl | --nolog]		Do not write log file."
			echo '\t'"[-d  | --disk] <disk>	Specify target disk file."
			echo '\t'"[-lv | --level] <level>	Specify erase level [0 - 4]."
			echo '\t'"[-la | --label] <label>	Specify label."
			echo '\t'"[-m  | --model] <model>	Specify disk model."
			echo '\t'"[-sn | --serial] <ser>	Specify disk serial number."

			tput bold; echo '\n'"Examples:"; tput sgr0
			
			echo '\t'"$0"
			echo '\t'"$0 --help"
			echo '\t'"$0 -p"
			echo '\t'"$0 -d /dev/disk4"
			echo '\t'"$0 -nl --disk /dev/disk5"
			echo '\t'"$0 -d /dev/disk6 -lv 2 -s --pretend"
			echo '\t'"$0"' -m "SSD-69-NI-CE" -sn "42LOL123456789" -la "Discard"'
            exit 1
            ;;
		-p|--pretend)
            PRETEND_MODE=1
            ;;
		-s|--skip)
            SKIP_CONFIRMATION=1
            ;;
		-nl|--nolog)
            NO_LOGS=1
            ;;
		-d|--disk)
            if [[ $DISK_SPECIFIED -eq 0 ]]; then
                if (( $# > 1 )); then
                    # Store next argument (disk file name)
                    DISK_FILE="$2"
                    # Skip the next argument in the next iteration
                    shift
					# Flag disk as specified
                    DISK_SPECIFIED=1
                else
                    echo "No disk specified for -d option. Exiting script."
                    exit 1
				fi
			else
				echo "-d/--disk option specified multiple times. Exiting script."
			fi
			;;
		-lv|--level)
            if [[ $LEVEL_SPECIFIED -eq 0 ]]; then
                if (( $# > 1 )); then
                    # Store next argument (erase level)
					ERASE_LEVEL="$2"
                    # Skip the next argument in the next iteration
                    shift
					# Flag level as specified
					LEVEL_SPECIFIED=1
                else
                    echo "No level specified for -lv/--level option. Exiting script."
                    exit 1
				fi
			else
				echo "-lv/--level option specified multiple times. Exiting script."
			fi
			;;
		-la|--label)
            if [[ $LABEL_SPECIFIED -eq 0 ]]; then
                if (( $# > 1 )); then
                    # Store next argument (label)
					LABEL="$2"
                    # Skip the next argument in the next iteration
                    shift
					# Flag label as specified
					LABEL_SPECIFIED=1
                else
                    echo "No label specified for -la/--label option. Exiting script."
                    exit 1
				fi
			else
				echo "-la/--label option specified multiple times. Exiting script."
			fi
			;;
		-m|--model)
            if [[ $MODEL_SPECIFIED -eq 0 ]]; then
                if (( $# > 1 )); then
                    # Store next argument (model name)
					DISK_MODEL="$2"
                    # Skip the next argument in the next iteration
                    shift
					# Flag model as specified
					MODEL_SPECIFIED=1
                else
                    echo "No model specified for -m/--model option. Exiting script."
                    exit 1
				fi
			else
				echo "-m/--model option specified multiple times. Exiting script."
			fi
			;;
		-sn|--serial)
            if [[ $HAS_SERIAL -eq 0 ]]; then
                if (( $# > 1 )); then
                    # Store next argument (erase level)
					DISK_SERIAL="$2"
                    # Skip the next argument in the next iteration
                    shift
					# Flag serial as specified
					HAS_SERIAL=1
                else
                    echo "No serial specified for -sn/--serial option. Exiting script."
                    exit 1
				fi
			else
				echo "-sn/--serial option specified multiple times. Exiting script."
			fi
			;;
		*)
			echo "Error: Invalid argument detected: $ARG"
			exit 1
			;;
	esac

	# Move to the next argument
	shift
done

# Determine boot disk
BOOT_DISK="$(diskutil info / | awk -F': *' '/Part of Whole/ {print $2; exit}')"

# If no disk was specified with -d, ask the user interactively
if [[ DISK_SPECIFIED -eq 0 ]]; then
	# List connected drives
	diskutil list

	# Select disk
	tput bold; read "?Enter disk number: " DISK_NUMBER; tput sgr0

	# Store full path to disk file
	DISK_FILE="/dev/disk$DISK_NUMBER"
fi

# Check if specified disk exists
if [[ ! -e "$DISK_FILE" ]]; then
    tput bold; echo "$DISK_FILE device node does not exist. Exiting script."; tput sgr0
	exit 1
fi

# Refuse to erase boot disk
if [[ "$DISK_FILE" == "/dev/$BOOT_DISK" ]]; then
    tput bold; echo "Cannot securely erase the boot disk ($BOOT_DISK). Exiting script"; tput sgr0
    exit 1
fi

# If no erase level was specified with -lv, ask the user interactively
if [[ LEVEL_SPECIFIED -eq 0 ]]; then
	# Select erase level
	echo '\n'"Erase levels:"
	echo "0 - $ERASE_LVL_0_DESCRIPTION."
	echo "1 - $ERASE_LVL_1_DESCRIPTION."
	echo "2 - $ERASE_LVL_2_DESCRIPTION."
	echo "3 - $ERASE_LVL_3_DESCRIPTION."
	echo "4 - $ERASE_LVL_4_DESCRIPTION."
	tput bold; read "?Enter erase level [0 - 4]: " ERASE_LEVEL; tput sgr0
fi

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

# If no serial number was specified with the -sn/--serial argument
if [[ $HAS_SERIAL -eq 0 ]]; then
	# Determine disk serial number
	if smartctl -i $DISK_FILE >/dev/null 2>&1; then
		HAS_SERIAL=1
		DISK_SERIAL=$(smartctl -i $DISK_FILE | awk -F'Serial Number:[[:space:]]*' '/Serial Number/ {print $2}')
	else
		DISK_SERIAL=none
	fi
fi

# If no model name was specified with the -m/--model argument
if [[ $MODEL_SPECIFIED -eq 0 ]]; then
	# Determine disk model
	DISK_MODEL=$(diskutil info $DISK_FILE | awk -F': *' '/Device \/ Media Name/ {print $2}')
fi

# Determine disk size
DISK_SIZE=$(diskutil info $DISK_FILE | awk -F': *| \\(' '/Disk Size/ {print $2}')

# Read back settings for confirmation
if [[ $DISK_SPECIFIED -eq 0 || $LEVEL_SPECIFIED -eq 0 ]]; then
	printf '\n'
fi
if [[ $PRETEND_MODE -eq 0 ]]; then
	echo "The secure erase will proceed with the following parameters:"
else
	echo "The pretended secure erase will proceed with the following parameters:"
fi
echo "Disk:"'\t''\t'"$DISK_FILE"
echo "Model:"'\t''\t'"$DISK_MODEL"
if [[ $HAS_SERIAL -eq 1 ]]; then
    echo "Serial Number:"'\t'"$DISK_SERIAL"
fi
if [[ $LABEL_SPECIFIED -eq 1 ]]; then
    echo "Label:"'\t''\t'"$LABEL"
fi
echo "Size:"'\t''\t'"$DISK_SIZE"
echo "Erase level:"'\t'"$ERASE_LEVEL ($ERASE_LVL_DESCRIPTION)"
echo "Current partition map for $DISK_FILE:"
diskutil list $DISK_FILE

# Ask user to confirm
if [[ $PRETEND_MODE -eq 1 ]]; then
	echo "Pretend option enabled: Secure erase will be simulated. No data on $DISK_FILE will be changed."
fi

# Ask user for confirmation, unless overridden with -s argument
if [[ $SKIP_CONFIRMATION -eq 0 ]]; then
	tput bold; read "?Type 'tak' and press enter to start erasing: " CONFIRMATION; tput sgr0
	[[ $CONFIRMATION == "tak" ]] || {
		tput bold; echo "No secure erase was performed. Exiting script."; tput sgr0
    exit 1
	}
fi

# Keep the console output tidy
printf '\n'

# Unmount disk, or pretend to, depending on whether pretend mode (-p/--pretend) is specified
if [[ $PRETEND_MODE -eq 0 ]]; then
	sudo diskutil unmountDisk force $DISK_FILE
	STATUS=$?
	if [[ $STATUS -ne 0 ]]; then
		tput bold; echo "Could not unmount $DISK_FILE. Exiting script."; tput sgr0
		exit 1
	fi
else
	echo "** Pretending to unmount $DISK_FILE **"
	sleep 1
fi

# Check if -nl (no logs option) is specified
if [[ $NO_LOGS -eq 1 ]]; then
	# Set /dev/null as file to write logs to if the -nl (no logs) option was specified
	LOG_FILE=/dev/null
else
	# Set label for file name
	if [[ $LABEL_SPECIFIED -eq 1 ]]; then
		# Prepend a dash to the label for the file name
		FILE_LABEL="-$LABEL"
	else
		# Blank label
		FILE_LABEL=""
	fi
	
	# Determine who is running the script (sudo/no sudo, root)
	if [[ $EUID -eq 0 ]]; then
		if [[ -n "$SUDO_USER" ]]; then
			# Running as root via sudo (original user: $SUDO_USER)
			# Record the home folder, user- and group ID of the original user that called sudo (not root's)
			CALLER_HOME=$(eval echo "~$SUDO_USER")
			CALLER_UID=$SUDO_UID
			CALLER_GID=$SUDO_GID
		else
			# Running as root (not via sudo)
			# Record the shared user's home directory, rather than root's
			CALLER_HOME=/Users/Shared
			# Set GID to wheel and UID to root, as is customary for the shared user's files/folders
			CALLER_UID=$EUID
			CALLER_GID=$(dscl . -read /Groups/wheel PrimaryGroupID | awk '{print $2}')
		fi
	else
		# Running as non-root user (no sudo)
		# Record the home folder, UID and GID of the caller
		CALLER_HOME=$HOME
		CALLER_UID=$EUID
		CALLER_GID=$(id -g)
	fi
	
	# Directory to store logs of each erase process
	LOG_DIRECTORY="$CALLER_HOME/Houdini Logs"

	# Check whether a something (file, folder, ...) exists with the name of the log directory
	if [[ -e $LOG_DIRECTORY ]]; then
		# Ensure pre-existing log dir is actually a directory
		if [[ -d $LOG_DIRECTORY ]]; then
			# Determine log directory and file UID and GID
			LOG_DIR_UID=$(stat -f %u $LOG_DIRECTORY)
			LOG_DIR_GID=$(stat -f %g $LOG_DIRECTORY)
		
			# Check if the UID or GID of the log folder are not correct
			if [[ "$LOG_DIR_UID" -ne "$CALLER_UID" || "$LOG_DIR_GID" -ne "$CALLER_GID" ]]; then
				# Set correct permissions for log folder
				sudo chown "$CALLER_UID:$CALLER_GID" $LOG_DIRECTORY
			fi
		else
			tput bold
			echo "Cannot write log files to $LOG_DIRECTORY as it is not a directory."
			echo "Exiting script without making changes to $DISK_FILE."
			tput sgr0
			exit 1
		fi
	fi
	
	# Create a file name based on disk info and date
	if [[ $HAS_SERIAL -eq 1 ]]; then
		# Set file name (with serial number)
		LOG_FILE=$LOG_DIRECTORY/$DISK_MODEL-$DISK_SERIAL$FILE_LABEL-$(date "+%Y-%m-%d-%H-%M-%S").log
	else
		# Set file name (without serial number)
		LOG_FILE=$LOG_DIRECTORY/$DISK_MODEL$FILE_LABEL-$(date "+%Y-%m-%d-%H-%M-%S").log
	fi
	
	# Create directory and file in a way the caller can write to
	if [[ $EUID -eq 0 ]]; then
		# Create file and folder with proper permissions (prevents them from being root-owned if called with sudo)
		sudo -u "#$CALLER_UID" -g "#$CALLER_GID" mkdir -p -- "$LOG_DIRECTORY"
		sudo -u "#$CALLER_UID" -g "#$CALLER_GID" sh -c ': >> "$1"' sh "$LOG_FILE"
	else
		mkdir -p -- $LOG_DIRECTORY
		: >> "$LOG_FILE"
	fi
	
	# Determine log file UID and GID
	LOG_FILE_UID=$(stat -f %u "$LOG_FILE")
	LOG_FILE_GID=$(stat -f %g "$LOG_FILE")
	
	# Check if the UID or GID of the log file are not correct
	if [[ "$LOG_FILE_UID" -ne "$CALLER_UID" || "$LOG_FILE_GID" -ne "$CALLER_GID" ]]; then
		# Set correct permissions for log file
		sudo chown "$CALLER_UID:$CALLER_GID" "$LOG_FILE"
	fi
fi

# Log disk info
log_only "Model:\t\t$DISK_MODEL"
log_only "Serial Number:\t$DISK_SERIAL"
if [[ $LABEL_SPECIFIED -eq 1 ]]; then
    log_only "Label:\t\t$LABEL"
fi
log_only "Size:\t\t$DISK_SIZE"
log_only "Erase level:\t$ERASE_LEVEL ($ERASE_LVL_DESCRIPTION)\n"

# Print the time and date the erase process was started at
if [[ $PRETEND_MODE -eq 0 ]]; then
	log_and_print "Starting secure erase on $(date)"
else
	log_and_print "Starting pretend-secure erase on $(date)"
fi

# Record start time (epoch seconds)
START_EPOCH=$(date +%s)

# Perform secure erase
if [[ $PRETEND_MODE -eq 0 ]]; then
	sudo diskutil secureErase $ERASE_LEVEL $DISK_FILE
	STATUS=$?
else
	STATUS=0
	echo "** PRETENDING TO ERASE $DISK_FILE **"
	sleep 3
fi

# Record end time and date
END_DATE=$(date)
END_EPOCH=$(date +%s)

# Print the time and date the erase process was concluded at
tput bold
if [[ $STATUS -eq 0 ]]; then
	if [[ $PRETEND_MODE -eq 0 ]]; then
		log_and_print "Secure erase completed successfully on $END_DATE"
	else
		log_and_print "Pretend-secure erase completed successfully on $END_DATE."
	fi
else
	if [[ $PRETEND_MODE -eq 0 ]]; then
		log_and_print "Secure erase failed (exit code: $STATUS) on $END_DATE"
	else
		log_and_print "Pretend-secure erase failed (exit code: $STATUS) on $END_DATE"
	fi
fi
tput sgr0

if [[ $PRETEND_MODE -eq 1 ]]; then
	log_and_print "Pretend option enabled: No changes were made to the disk."
fi

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
	log_and_print "Elapsed time: ${DAYS}d ${HOURS}h ${MINUTES}m ${SECONDS}s"
elif (( HOURS > 0 )); then
	log_and_print "Elapsed time: ${HOURS}h ${MINUTES}m ${SECONDS}s"
elif (( MINUTES > 0 )); then
	log_and_print "Elapsed time: ${MINUTES}m ${SECONDS}s"
else
	log_and_print "Elapsed time: ${SECONDS}s"
fi

# Done
echo "klolthxbye"
