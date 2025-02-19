#!/bin/bash


#**********************************************************************
#
# Copyright (C) 2020 - 2021 Xilinx, Inc.
# Copyright (C) 2022 - 2024, Advanced Micro Devices, Inc.
# SPDX-License-Identifier: MIT
#
#**********************************************************************

echo "Script started, look for \"Script completed\" for acknowledgement of completion of SPI programming"

cleanup(){
    kill "${COPROC_PID}"
    exec {COPROC[0]}>&-
    exec {COPROC[1]}>&-
    kill "${XSDB_PID}"
    sleep 1
}
# Function to send strings to the JTAG UART
send_to_jtaguart() {
  local message="$1"
  echo "$message" >&"${COPROC[1]}"
  echo "Sent to JTAG UART: $message"
}

match_jtaguart_output() {
  local pattern="$1"
  local timeout="$2"

  local pause=0.1

  while true; do
    
    IFS= read -r -t "$timeout" line <&"${COPROC[0]}"
    
    if [ $? -ne 0 ]; then
        echo "Timed out after $timeout seconds - script failed"
        cleanup
        exit 1
    fi

    echo "received on jtag_uart:  $line"
    if  echo "$line" | grep -q "Attempted to modify a protected sector";  then
        echo "Attempted to modify a protected sector - the flash is locked and cannot be modified."
        cleanup
	    exit 1
    elif echo "$line" | grep -q "$pattern"; then
      echo "Match found: $line"
      return 0  # Exit function when match is found
    fi
    sleep $pause
  done

  echo "ERROR: should never see this line"

  exit 1  # No match found
}

if [ -f /etc/profile.d/xsdb-variables.sh ]; then
    source /etc/profile.d/xsdb-variables.sh
    XSDB_PATH=$XILINX_VITIS
fi

if command -v xsdb >/dev/null 2>&1; then
    echo "xsdb is in PATH: $(command -v xsdb)"
    XSDB=$(which xsdb)
else 
    # Look for xsdb in the system and filter paths containing "bin/xsdb"
    XSDB_PATH=$(find /usr /opt /tools /home -iname xsdb 2>/dev/null | grep "/bin/xsdb" | head -n 1)
    XSDB=$XSDB_PATH

    #echo "Looking for xsdb binary"
    # Check if XSDB_PATH is found
    if [[ -n "$XSDB_PATH" ]]; then
        # Extract the directory part of the path (remove the 'xsdb' part)
        XSDB_DIR=$(dirname "$XSDB_PATH")

        # Add to PATH if not already in PATH
        if [[ ":$PATH:" != *":$XSDB_DIR:"* ]]; then
            export PATH="$XSDB_DIR:$PATH"
        fi
    else
        echo "xsdb binary not found in /usr /opt /tools or /home directory."
        echo "Please manually add XSDB to PATH and try again"
        exit 1
    fi
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
    echo "    -b <boot_file> : Optional argument to override programming boot.bin"
    echo "    -h             : help"
    exit 1
}

# Initialize variables
path_to_boot_bin=""
device_type=""
dtb_file=""
jtag_mux=false
embplus_reset=false

# Parse arguments
while getopts "d:i:p:b:h" arg; do
    case "$arg" in
        d)
            case ${OPTARG} in
                embplus)
                    binfile=${binfile:=bin/BOOT_embplus_jtaguart.bin}
                    device_type=versal
                    embplus_reset=true
                    ;;
                rhino)
                    binfile=${binfile:=bin/BOOT_rhino_jtaguart.bin}
                    device_type=versal
                    ;;
                kria_k26)
                    binfile=${binfile:=bin/zynqmp_fsbl_k26.elf}
                    dtb_file=bin/system_k26_jtag_uart.dtb
                    device_type=zynqmp
                    ;;
                kria_k24c)
                    binfile=${binfile:=bin/zynqmp_fsbl_k24c.elf}
                    dtb_file=bin/system_k24c_jtag_uart.dtb
                    device_type=zynqmp
                    ;;
                kria_k24i)
                    binfile=${binfile:=bin/zynqmp_fsbl_k24i.elf}
                    dtb_file=bin/system_k24i_jtag_uart.dtb
                    device_type=zynqmp
                    ;;
                versal_eval)
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


if $jtag_mux; then
    gpioset $(gpiofind SYSCTLR_JTAG_S0)=0
    gpioset $(gpiofind SYSCTLR_JTAG_S1)=0
fi

if $embplus_reset; then
    chmod +x versal/embplus_jtag_porb.py
    if ! dpkg-query -W -f='${Status}' python3-ftdi 2>/dev/null | grep -q "install ok installed" ; then
        echo "python3-ftdi is not installed. Installing it now..."
        if command -v apt &> /dev/null; then
            sudo apt install python3-ftdi
        else
            echo "Error: Unsupported package manager. Please install python3-ftdi manually."
            exit 1
        fi
    fi

    if ! dpkg-query -W -f='${Status}' python3-ftdi 2>/dev/null | grep -q "install ok installed"; then
        echo "python3-ftdi installation failed, please install manually"
        exit 1
    fi
    sleep 1
    echo "Setting EmbPlus to JTAG mode and performing por_b reset"
    sudo modprobe -r  xclmgmt &> /dev/null
    sudo modprobe -r  xocl &> /dev/null
    python3 versal/embplus_jtag_porb.py
    sleep 1
fi

# Run the xsdb script to start jtag uart and capture the socket port
socket_file=tmp.socket
$XSDB ${device_type}/uart.tcl   &> $socket_file &
XSDB_PID=$!


rt=0
while [ "$SOCK" == "" ] && [ $rt -lt 10 ]; do
   SOCK=$(tail -n 1 $socket_file)
   rt=$(( rt + 1 ))
   sleep 1
done
echo $SOCK


# Check if the socket was created successfully
if [[ ! "$SOCK" =~ ^[0-9]+$ ]]; then
  echo "Failed to extract a valid JTAG UART socket number. Output was:"
  echo "$SOCK"
  exit 1
fi

echo "JTAG UART socket started on port $SOCK"

# Ensure no previous coprocess is interfering
if [[ -n "${COPROC[0]+set}" ]]; then
    exec {COPROC[0]}>&- 2>/dev/null
fi
if [[ -n "${COPROC[1]+set}" ]]; then
    exec {COPROC[1]}>&- 2>/dev/null
fi

coproc nc localhost $SOCK
COPROC_PID=$!

# Drain any old data from the read pipe
while IFS= read -r -t 0.1 junk <&"${COPROC[0]}"; do
    :  # Do nothing, just clear the buffer
done

$XSDB ${device_type}/jtag_boot.tcl $binfile $dtb_file


sleep 2  # Wait a moment for nc to initialize


send_to_jtaguart " " 
sleep 1
send_to_jtaguart " "
sleep 1
send_to_jtaguart " "
sleep 1


$XSDB ${device_type}/download_data.tcl $path_to_boot_bin

send_to_jtaguart "sf probe 0x0 0x0 0x0"

match_jtaguart_output "Detected" 10

echo
echo "SPI Erasing and programming...this could take up to 5 minutes"
echo

bin_size=$(stat --printf="%s" $path_to_boot_bin)
bin_size_hex=$(printf "%08x" $bin_size)

send_to_jtaguart "sf update 0x80000 0x0 $bin_size_hex"


match_jtaguart_output "written" 600
echo
echo "SPI written successfully."
echo

cleanup

if $jtag_mux; then
    gpioget $(gpiofind SYSCTLR_JTAG_S0) >/dev/null
    gpioget $(gpiofind SYSCTLR_JTAG_S1) >/dev/null
fi

echo
echo "Script completed"


exit 0

