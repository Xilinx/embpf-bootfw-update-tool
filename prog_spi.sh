#!/bin/bash


#**********************************************************************
#
# Copyright (C) 2020 - 2021 Xilinx, Inc.
# Copyright (C) 2022 - 2024, Advanced Micro Devices, Inc.
# SPDX-License-Identifier: MIT
#
#**********************************************************************





wait_for_uart_output() {
    local pattern="$1"
    while true; do
	if  grep -q "Attempted to modify a protected sector" "$uart_log_file"; then
            echo "Attempted to modify a protected sector - the flash is locked and cannot be modified."
            kill "$pico_pid"
	    kill "$tee_pid"
	    exit 1
        elif grep -q "$pattern" "$uart_log_file"; then
            echo "$pattern found in UART logfile $uart_log_file."
            return 0
        fi
        sleep 0.5  # Check every 500ms
    done
}


if [ -f /etc/profile.d/xsdb-variables.sh ]; then
    source /etc/profile.d/xsdb-variables.sh
    XSDB_PATH=$XILINX_VITIS
    XSDB=$XILINX_VITIS/xsdb
else 
    # Look for xsdb in the system and filter paths containing "bin/xsdb"
    XSDB_PATH=$(find / -iname xsdb 2>/dev/null | grep "/bin/xsdb" | head -n 1)
    XSDB=$XSDB_PATH

    #echo "Looking for xsdb binary"
    # Check if XSDB_PATH is found
    if [[ -n "$XSDB_PATH" ]]; then
        # Extract the directory part of the path (remove the 'xsdb' part)
        XSDB_DIR=$(dirname "$XSDB_PATH")

        # Add to PATH if not already in PATH
        if [[ ":$PATH:" != *":$XSDB_DIR:"* ]]; then
            export PATH="$XSDB_DIR:$PATH"
        #    echo "Added $XSDB_DIR to PATH"
        #else
        #    echo "$XSDB_DIR is already in PATH"
        fi
    else
        echo "xsdb binary not found."
        exit 1
    fi
fi

# check if picocom is installed
if ! command -v picocom &> /dev/null; then
    echo "Picocom is not installed. Installing it now..."
    if command -v apt &> /dev/null; then
        sudo apt install -y picocom
    else
        echo "Error: Unsupported package manager. Please install picocom manually."
        exit 1
    fi
#else
#    echo "Picocom is already installed."
fi

if ! command -v picocom &> /dev/null; then
	echo "Picocom installation failed, please install manually"
	exit 1
fi

detect_board() {
    eeprom=$(ls /sys/bus/i2c/devices/*/eeprom_cc*/nvmem 2> /dev/null)
    if [ -n "${eeprom}" ]; then
        boardid=$(ipmi-fru --fru-file=${eeprom} --interpret-oem-data | awk -F": " '/FRU Board Product/ { print tolower ($2) }')
        echo $boardid
    else
        echo "Unable to identify board type"
        exit 1
    fi
}

usage () {
    echo "Usage: $0 -i <path_to_boot.bin> -d <board_type>"
    echo "    -i <file>      : File to write to OSPI/QSPI"
    echo "    -d <board>     : Board type.  Supported values"
    echo "                     embplus, rhino, kria_k26, kria_k24c,"
    echo "                     kria_k24i, versal_eval"
    echo "    -p <port>      : Optional argument to override serial port"
    echo "    -b <boot_file> : Optional argument to override programming boot.bin"
    echo "    -h             : help"
    exit 1
}

# Initialize variables
path_to_boot_bin=""
device_type=""
dtb_file=""
jtag_mux=false

# Parse arguments
while getopts "d:i:p:b:h" arg; do
    case "$arg" in
        d)
            case ${OPTARG} in
                embplus)
                    uart_dev=${uart_dev:="/dev/ttyUSB2"}
                    binfile=${binfile:=bin/BOOT_embplus.bin}
                    device_type=versal
                    ;;
                rhino)
                    uart_dev=${uart_dev:="/dev/ttyUSB1"}
                    binfile=${binfile:=bin/BOOT_rhino.bin}
                    device_type=versal
                    ;;
                kria_k26)
                    uart_dev=${uart_dev:="/dev/ttyUSB1"}
                    binfile=${binfile:=bin/zynqmp_fsbl_k26.elf}
                    dtb_file=bin/system_k26.dtb
                    device_type=zynqmp
                    ;;
                kria_k24c)
                    uart_dev=${uart_dev:="/dev/ttyUSB1"}
                    binfile=${binfile:=bin/zynqmp_fsbl_k24c.elf}
                    dtb_file=bin/system_k24c.dtb
                    device_type=zynqmp
                    ;;
                kria_k24i)
                    uart_dev=${uart_dev:="/dev/ttyUSB1"}
                    binfile=${binfile:=bin/zynqmp_fsbl_k24i.elf}
                    dtb_file=bin/system_k24i.dtb
                    device_type=zynqmp
                    ;;
                versal_eval)
                    uart_dev=${uart_dev:="/dev/ttyPS1"}
                    BOARD=$(detect_board)
                    echo "Detected board type $BOARD"
                    binfile=bin/BOOT_${BOARD}.bin
                    binfile=${binfile:=bin/BOOT_${BOARD}.bin}
                    device_type=versal
                    jtag_mux=true
                    ;;
                *)
                    echo
                    echo "Unknown device ${OPTARG}"
                    echo
                    usage
                    ;;
            esac
            ;;

        p)
            uart_dev=$OPTARG
            ;;
        b)
            binfile=$OPTARG
            ;;
        i)
            path_to_boot_bin="${OPTARG}"
            if [ ! -e "$path_to_boot_bin" ]; then
                echo
                echo "Unable to find file $path_to_boot_bin"
                echo
                usage
            fi
            ;;
        h)
            usage
            ;;
    esac
done

if [ $UID -ne 0 ]; then
    echo "Must be root"
    exit 1
fi

# Check if path_to_boot_bin is empty or device_type is not set
if [ -z "$path_to_boot_bin" ] || [ -z "$device_type" ]; then
    usage
fi

# Check if the bootbin file has been copied over
if [ ! -f $binfile ]; then
   echo "Error: File $binfile does not exist, please download bin.zip from release area in the repo and place in this folder"
   exit 1
fi

# Print the chosen options
echo "Boot bin path: $path_to_boot_bin"
echo "Device type: $device_type"


echo "Script started, look for \"Script completed\" for acknowledgement of completion of SPI programming"

uart_log_file="uart_output.log"
if [ -f "$uart_log_file" ]; then
    rm "$uart_log_file"
fi

#echo "turning off ${uart_dev} echo"
#stty -F  $uart_dev 115200 -ignbrk -brkint -ignpar -parmrk -inpck -istrip -inlcr -igncr -icrnl -ixon -ixoff -iuclc -ixany -imaxbel -iutf8 -opost -olcuc -ocrnl onlcr -onocr -onlret -ofill -ofdel nl0 cr0 tab0 bs0 vt0 ff0 -isig -icanon -iexten -echo echoe echok -echonl -noflsh -xcase -tostop -echoprt echoctl echoke -flusho -extproc


if lsof "$uart_dev" &> /dev/null; then
    echo "Error: Device $uart_dev is already in use by another program. Please stop the program before trying the script again"
    exit 1
fi

if $jtag_mux; then
    gpioset $(gpiofind SYSCTLR_JTAG_S0)=0
    gpioset $(gpiofind SYSCTLR_JTAG_S1)=0
fi

picocom "$uart_dev" -q -b 115200 | tee "$uart_log_file" &
tee_pid=$!  # Save the process ID to kill it later if needed
pico_pid=$(jobs -p | tail -n 2 | head -n 1)

$XSDB ${device_type}/jtag_boot.tcl $binfile $dtb_file

echo -en "\r" > $uart_dev
sleep 1
echo -en "\r" > $uart_dev
sleep 1
echo -en "\r" > $uart_dev
sleep 1


$XSDB ${device_type}/download_data.tcl $path_to_boot_bin

echo -en "sf probe 0x0 0x0 0x0\r" > $uart_dev
wait_for_uart_output "Detected"

echo
echo "SPI Erasing and programming...this could take up to 5 minutes"
echo

bin_size=$(stat --printf="%s" $path_to_boot_bin)
bin_size_hex=$(printf "%08x" $bin_size)

echo -en "sf update 0x80000 0x0 $bin_size_hex\r" > "$uart_dev"

wait_for_uart_output "written"
echo
echo "SPI written successfully."
echo

# Clean up: stop the UART logging
kill "$pico_pid"
kill "$tee_pid"

#stty -F  $uart_dev 115200 echo
#echo "${uart_dev} echo turned back on"

if $jtag_mux; then
    gpioget $(gpiofind SYSCTLR_JTAG_S0)
    gpioget $(gpiofind SYSCTLR_JTAG_S1)
fi

echo
echo "Script completed"
exit 0

