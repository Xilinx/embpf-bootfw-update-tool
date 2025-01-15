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

echo "Script started, look for \"Script completed\" for acknowledgement of completion of SPI programming"


# Look for xsdb in the system and filter paths containing "bin/xsdb"
XSDB_PATH=$(sudo find / -iname xsdb 2>/dev/null | grep "/bin/xsdb" | head -n 1)

echo "Looking for xsdb binary"
# Check if XSDB_PATH is found
if [[ -n "$XSDB_PATH" ]]; then
    # Extract the directory part of the path (remove the 'xsdb' part)
    XSDB_DIR=$(dirname "$XSDB_PATH")
    
    # Add to PATH if not already in PATH
    if [[ ":$PATH:" != *":$XSDB_DIR:"* ]]; then
        export PATH="$XSDB_DIR:$PATH"
        echo "Added $XSDB_DIR to PATH"
    else
        echo "$XSDB_DIR is already in PATH"
    fi
else
    echo "xsdb binary not found."
    exit 1
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
else
    echo "Picocom is already installed."
fi

if ! command -v picocom &> /dev/null; then
	echo "Picocom installation failed, please install manually"
	exit 1
fi


# Initialize variables
path_to_boot_bin=""
device_type=""

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -embplus)
            device_type="embplus"
            ;;
        -rhino)
            device_type="rhino"
            ;;
        -kria_k26)
            device_type="kria_k26"
            ;;
        -kria_k24c)
            device_type="kria_k24c"
            ;;
        -kria_k24i)
            device_type="kria_k24i"
            ;;
        *)
            path_to_boot_bin="$1"
            ;;
    esac
    shift
done

# Check if path_to_boot_bin is empty or device_type is not set
if [ -z "$path_to_boot_bin" ] || [ -z "$device_type" ]; then
    echo "Usage: $0 <path_to_boot.bin> -embplus|-rhino|-kria_k26|-kria_k24c|-kria_k24i"
    exit 1
fi

# Check if the file exists at path_to_boot_bin
if [ ! -f "$path_to_boot_bin" ]; then
    echo "Error: File '$path_to_boot_bin' does not exist."
    exit 1
fi


# Check if the bootbin file has been copied over
if [ "$device_type" = "embplus" ]; then
    if [ ! -f bin/BOOT_embplus.bin ]; then
        echo "Error: File bin/BOOT_embplus.bin does not exist, please download bin.zip from release area in the repo and place in this folder"
        exit 1
    fi
elif [ "$device_type" = "rhino" ]; then
    if [ ! -f bin/BOOT_rhino.bin ]; then
        echo "Error: File bin/BOOT_rhino.bin does not exist, please download bin.zip from release area in the repo and place in this folder"
        exit 1
    fi
elif [ "$device_type" = "kria_k26" ]; then
    if [ ! -f bin/zynqmp_fsbl_k26.elf ]; then
        echo "Error: File bin/zynqmp_fsbl_k26.elf does not exist, please download bin.zip from release area in the repo and place in this folder"
        exit 1
    fi
elif [ "$device_type" = "kria_k24i" ]; then
    if [ ! -f bin/zynqmp_fsbl_k24i.elf ]; then
        echo "Error: File bin/BOOT_rhino.bin does not exist, please download bin.zip from release area in the repo and place in this folder"
        exit 1
    fi
elif [ "$device_type" = "kria_k24c" ]; then
    if [ ! -f bin/zynqmp_fsbl_k24c.elf  ]; then
        echo "Error: File bin/BOOT_rhino.bin does not exist, please download bin.zip from release area in the repo and place in this folder"
        exit 1
    fi
fi

# Print the chosen options
echo "Boot bin path: $path_to_boot_bin"
echo "Device type: $device_type"




# Configure the serial port
# Set uart_dev based on device_type
if [ "$device_type" = "embplus" ]; then
    uart_dev="/dev/ttyUSB2"
elif [ "$device_type" = "rhino" ]; then
    uart_dev="/dev/ttyUSB1"
elif [ "$device_type" = "kria_k26" ]; then
    uart_dev="/dev/ttyUSB1"
elif [ "$device_type" = "kria_k24i" ]; then
    uart_dev="/dev/ttyUSB1"
elif [ "$device_type" = "kria_k24c" ]; then
    uart_dev="/dev/ttyUSB1"
fi

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


picocom "$uart_dev" -b 115200 | tee "$uart_log_file" &
tee_pid=$!  # Save the process ID to kill it later if needed
pico_pid=$(jobs -p | tail -n 2 | head -n 1)



if [ "$device_type" = "embplus" ]; then
    xsdb versal/jtag_boot.tcl bin/BOOT_embplus.bin
elif [ "$device_type" = "rhino" ]; then
    xsdb versal/jtag_boot.tcl bin/BOOT_rhino.bin
elif [ "$device_type" = "kria_k26" ]; then
    xsdb zynqmpsoc/jtag_boot.tcl bin/zynqmp_fsbl_k26.elf bin/system_k26.dtb
elif [ "$device_type" = "kria_k24c" ]; then
    xsdb zynqmpsoc/jtag_boot.tcl bin/zynqmp_fsbl_k24c.elf bin/system_k24c.dtb
elif [ "$device_type" = "kria_k24i" ]; then
    xsdb zynqmpsoc/jtag_boot.tcl bin/zynqmp_fsbl_k24i.elf bin/system_k24i.dtb
fi


echo -en "\r" > $uart_dev
sleep 1
echo -en "\r" > $uart_dev
sleep 1
echo -en "\r" > $uart_dev
sleep 1


if [ "$device_type" = "embplus" ] || [ "$device_type" = "rhino" ]; then
    xsdb versal/download_data.tcl $path_to_boot_bin
elif [ "$device_type" = "kria_k26" ] || [ "$device_type" = "kria_k24c" ] || [ "$device_type" = "kria_k24i" ]; then
    xsdb zynqmpsoc/download_data.tcl $path_to_boot_bin
fi


echo -en "sf probe 0x0 0x0 0x0\r" > $uart_dev
wait_for_uart_output "Detected"
echo
echo "SPI found. Erasing... this could take up to 2 minutes"
echo

if [ "$device_type" = "embplus" ] || [ "$device_type" = "rhino" ]; then
    echo -en "sf erase 0x0 0x7fe0000\r" > "$uart_dev"
elif [ "$device_type" = "kria_k26" ] || [ "$device_type" = "kria_k24c" ] || [ "$device_type" = "kria_k24i" ]; then
    echo -en "  sf erase 0x0 0x3ff0000\r" > "$uart_dev"
fi


wait_for_uart_output "Erased"
echo
echo "SPI erased, programming...this could take up to 5 minutes"
echo

if [ "$device_type" = "embplus" ] || [ "$device_type" = "rhino" ]; then
    echo -en "sf write 0x80000 0x0 0x8000000\r" > "$uart_dev"
elif [ "$device_type" = "kria_k26" ] || [ "$device_type" = "kria_k24c" ] || [ "$device_type" = "kria_k24i" ]; then
    echo -en "sf write 0x80000 0x0 0x4000000\r" > "$uart_dev"
fi


wait_for_uart_output "Written"
echo
echo "SPI written successfully."
echo

# Clean up: stop the UART logging
kill "$pico_pid"
kill "$tee_pid"



#stty -F  $uart_dev 115200 echo
#echo "${uart_dev} echo turned back on"

echo
echo "Script completed"
exit 0

