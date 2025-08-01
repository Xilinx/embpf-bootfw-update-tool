#!/bin/bash


#**********************************************************************
#
# Copyright (C) 2020 - 2021 Xilinx, Inc.
# Copyright (C) 2022 - 2024, Advanced Micro Devices, Inc.
# SPDX-License-Identifier: MIT
#
#**********************************************************************

cleanup(){
    kill "${COPROC_PID}" 2>/dev/null
    #exec {COPROC[0]}>&-
    #exec {COPROC[1]}>&-

    if [[ -n "${COPROC[0]+set}" ]]; then
        exec {COPROC[0]}>&- 2>/dev/null
    fi
    if [[ -n "${COPROC[1]+set}" ]]; then
        exec {COPROC[1]}>&- 2>/dev/null
    fi

    if [[ ! -z "${XSDB_PID}" ]]; then
        kill "${XSDB_PID}" 2>/dev/null
    fi

    ps ax | grep xsdb | grep uart.tcl | awk '{print $1}' | xargs --no-run-if-empty kill -9 2>/dev/null

    ps ax | grep xsdb | awk '{print $1}' | xargs --no-run-if-empty kill -9 2>/dev/null

    if $jtag_mux; then
    if [ -z "$remote_ip" ]; then
        sc_app -c getgpio -t SW3 >/dev/null
    else
        curl -s "http://${remote_ip}/cmdquery?sc_cmd=getgpio&target=SW3&params=" >/dev/null
    fi


    fi
    sleep 1
}
# Function to send strings to the JTAG UART
send_to_jtaguart() {
  local message="$1"
  echo "$message" >&"${COPROC[1]}"
  if $verbose; then
    echo "Sent to JTAG UART: $message"
  fi
}

read_line() {
    local iosource="$1"
    local timeout="$2"
    local line=""
    local char
    local input_fd

    if [ "$iosource" == "term" ]; then
        while IFS= read -r -t "$timeout" -n 1 character <&"${COPROC[0]}"; do
            # Stop reading if newline (\n) or carriage return (\r) is found
            if [[ "$character" == $'\r' || "$character" == $'\n' ]]; then
                echo "$line"
                return 0
            fi
            line+="$character"
        done
        if [[ -z "$line" ]]; then
            echo "Error: Timed out after $timeout seconds - script failed" >&2
            cleanup
            return 1
        fi
        echo "$line"
        return 0
    elif [ "$iosource" == "xsdb" ]; then
        IFS= read -r -t "$timeout" line
        if [ $? -ne 0 ]; then
            echo "Timed out after $timeout seconds - script failed" >&2
            cleanup
            return 1
        fi
        echo "$line"
        return 0
    else
        echo "Error: Unknown iosource '$iosource'" >&2
        cleanup
        return 1
    fi


}

#Blue progress bar
#BARSTR='\r\e[44;38;5;25m%s\e[0m%4.0f%%'

#Black and White progress bar
BARSTR='\r%s%4.0f%%'

match_output_print_prog() {
  local iosource="$1"
  local match_pattern="$2"
  local timeout="$3"
  local line


  if [ -z $COLUMNS ]; then
      PROG_WIDTH=80
  elif [ $COLUMNS -lt 85 ]; then
      PROG_WIDTH=$((COLUMNS - 5))
  else
      PROG_WIDTH=80
  fi

  print_progress=false
  while true; do
    if ! line=$(read_line "$iosource" "$timeout"); then
        echo "Error: Failed to read a line from $iosource, exiting..." >&2
        cleanup
        return 1
    fi

    if $verbose; then
        echo "received on $iosource:  $line"
    else
        if echo "$line" | grep -q "%" ; then
            print_progress=true
            val=$(echo $line | awk '{for(i=1;i<=NF;i++) if ($i ~ /^[0-9]+%$/) print substr($i, 1, length($i)-1)}')
            percentBar $val $PROG_WIDTH bar
            printf $BARSTR "$bar" $val
            if [ $val -eq 100 ]; then
                printf '\n'
                print_progress=false
            fi

        fi
    fi

    if echo "$line" | grep -q "SF: Detected" ; then
        flash_size_print=$(echo "$line" | awk '{for(i=1;i<=NF;i++) if ($i=="total") print $(i+1)}')
        flash_size_hex=$(printf "0x%X\n" $(( $flash_size_print * 1024 * 1024 )))
    fi
    if  echo "$line" | grep -q "Attempted to modify a protected sector";  then
        echo "Error: Attempted to modify a protected sector - the flash is locked and cannot be modified."
        cleanup
        return 1
    elif echo "$line" | grep -q "!= byte at" && echo "$line" | grep -vq "$spi_dma_busy_reg" ; then
        if $check_blank; then
            echo "Error: Flash is not blank: $line, blank check failed"
            cleanup
            return 1
        else
            echo "Error: Data mismatch, verification failed: $line"
            cleanup
            return 1
        fi
    elif echo "$line" | grep -q "$match_pattern"; then
        if $verbose; then
            echo "Match found on $iosource: $line"
        elif $print_progress; then # incase 100% doesnt print, use match to know its 100%
            percentBar 100 $PROG_WIDTH bar
            printf $BARSTR "$bar" 100
            printf '\n'
        fi
        return 0
    fi
  done
  echo "ERROR: should never see this line"
  cleanup
  return 1  # No match found
}



percentBar ()  {
    local prct totlen=$((8*$2)) lastchar barstring blankstring;
    printf -v prct %.2f "$1"
    ((prct=10#${prct/.}*totlen/10000, prct%8)) &&
        printf -v lastchar '\\U258%X' $(( 16 - prct%8 )) ||
            lastchar=''
    printf -v barstring '%*s' $((prct/8)) ''
    printf -v barstring '%b' "${barstring// /\\U2588}$lastchar"
    printf -v blankstring '%*s' $(((totlen-prct)/8)) ''
    printf -v "$3" '%s%s' "$barstring" "$blankstring"
}

xsdb_cmd () {
    $XSDB -interactive $* | stdbuf -oL  tr '\r' '\n' | match_output_print_prog "xsdb" "finished" 60 || exit 1
}

if [ -f /etc/profile.d/xsdb-variables.sh ]; then
    source /etc/profile.d/xsdb-variables.sh
    XSDB_PATH=$XILINX_VITIS
fi

if command -v xsdb >/dev/null 2>&1; then
    #echo "xsdb is in PATH: $(command -v xsdb)"
    XSDB=$(which xsdb)
else
    # Look for xsdb in the system and filter paths containing "bin/xsdb"
    echo "Looking for xsdb executables on disk... if it takes too long, consider adding it to PATH and try again"
    XSDB_PATH=$(sudo find /usr /opt /tools /home -type f -iname xsdb 2>/dev/null | head -n 1)
    XSDB=$XSDB_PATH

    echo "Finished looking for xsdb binary"
    # Check if XSDB_PATH is found
    if [[ -n "$XSDB_PATH" ]]; then
        # Extract the directory part of the path (remove the 'xsdb' part)
        XSDB_DIR=$(dirname "$XSDB_PATH")
        echo "Found xsdb binary in $XSDB_DIR"

        # Add to PATH if not already in PATH
        if [[ ":$PATH:" != *":$XSDB_DIR:"* ]]; then
            export PATH="$XSDB_DIR:$PATH"
        fi
    else
        echo "Error: xsdb binary not found in /usr /opt /tools or /home directory."
        echo "       Script failed - please manually add XSDB to PATH and try again"
        exit 1
    fi
fi


detect_board() {


    if [ -z "$remote_ip" ]; then
        if ! command -v sc_app &> /dev/null; then
            echo "Error: Script failed - sc_app command not found. Please run versal_eval with updated system controller images."  >&2
            return 1
        fi

        boardid=$(sc_app -c board)
        silicon_rev=$(sc_app -c geteeprom -t onboard -v summary | grep "Silicon Revision"| awk '{print $3}')
    else

        silicon_rev_all=$(curl -s "http://${remote_ip}/cmdquery?sc_cmd=geteeprom&target=onboard&params=summary")
        # echo "silicon_rev_all is ${silicon_rev_all}"  >&2
        boardid=$(echo ${silicon_rev_all} | awk -F'"Product Name":' '{print $2}' | awk -F'"' '{print $2}')
        silicon_rev=$(echo ${silicon_rev_all} | awk -F'"Silicon Revision":' '{print $2}' | awk -F'"' '{print $2}')
    fi

    if [[ -z "$silicon_rev" || -z "$boardid" ]]; then
        echo "Error: Board ID or Silicon Revision not found or empty."  >&2
        return 1
    fi

    if [ "$silicon_rev" != "PROD" ]; then
        boardid="${boardid}_${silicon_rev}"
    fi

    boardid=$(echo "$boardid" | tr '[:upper:]' '[:lower:]')

    echo $boardid
}

usage () {
    echo "Default Usage: $0 -i <path_to_boot.bin> -d <board_type>"
    echo "    -i <file>      : Bin file to write into OSPI/QSPI, can be a .bin or a gzip of the .bin file"
    echo "    -d <board>     : Board type.  Supported values"
    echo "                     embplus, rhino, kria_k26, kria_k24c,"
    echo "                     kria_k24i, versal_eval"
    echo "    -b <boot_file> : Optional argument to override jtag boot.bin, for Versal only"
    echo "    -s <SOCK #>    : Optional argument to specify remote uart SOCK number"
    echo "    -p             : Optional argument program SPI, this is set by default except if -v or -b is present"
    echo "    -v             : verification of flash content, if -pv are both present, tool will program and verify. if only -v is set, tool will  verify content of SPI against -i  <file> without programming"
    echo "    -c             : check if flash is blank/erased"
    echo "    -e             : erase flash"
    echo "    -V             : verbose logging"
    echo "    -w             : optional argument to connect to remote hardware server, use IP address or machine name shown by hw_server (without :3121). not supported for embplus system"
    echo "    -h             : help"
    echo "Example usages:"
    echo "to program in verbose mode:"
    echo "     $0 -i <path_to_boot.bin> -d <board_type> -V"
    echo "to program with explicit -p and in verbose mode:"
    echo "     $0 -p -i -V <path_to_boot.bin> -d <board_type>"
    echo "to program and verify:"
    echo "     $0 -pv -i <path_to_boot.bin> -d <board_type>"
    echo "to verify only:"
    echo "     $0 -v -i <path_to_boot.bin> -d <board_type>"
    echo "to check if SPI is blank:"
    echo "     $0 -c -d <board_type>"
    echo "to erase:"
    echo "     $0 -e -d <board_type>"
    echo "to erase and check that SPI is blank:"
    echo "     $0 -ec -d <board_type>"
    echo "to program a remote hw_server target in verbose mode"
    echo "     $0 -Vp -d <board_type> -i <path_to_boot.bin> -w <remote machine name or IP addr> "
    exit 1
}


# Initialize variables
path_to_boot_bin=""
device_type=""
dtb_file=""
jtag_mux=false
flash_size_hex=""
embplus_reset=false
scapp_support=false
verify=false
prog_spi=false
check_blank=false
erase_spi=false
b_flag_set=false
i_flag_set=false
remote_uart=0
SCRIPT_PATH=$(dirname $0)
verbose=false
num_operations=2
spi_dma_busy_reg=""
remote_ip=""

# Parse arguments
while getopts "d:i:b:s:w:pvhceV" arg; do
    case "$arg" in
        p)
            num_operations=$(( num_operations + 1 ))
            prog_spi=true
            ;;
        w)
            remote_ip=${OPTARG}
            echo "remote_ip is $remote_ip"
            ;;
        d)
            case ${OPTARG} in
                embplus)
                    binfile=${binfile:="${SCRIPT_PATH}"/bin/BOOT_embplus_jtaguart.bin}
                    device_type=versal
                    embplus_reset=true
                    spi_dma_busy_reg="f1011808"
                    ;;
                rhino)
                    binfile=${binfile:="${SCRIPT_PATH}"/bin/BOOT_rhino_jtaguart.bin}
                    device_type=versal
                    spi_dma_busy_reg="f1011808"
                    ;;
                kria_k26)
                    binfile=${binfile:="${SCRIPT_PATH}"/bin/zynqmp_fsbl_k26.elf}
                    dtb_file="${SCRIPT_PATH}"/bin/system_k26_jtag_uart.dtb
                    device_type=zynqmp
                    spi_dma_busy_reg="FF0F0808"
                    ;;
                kria_k24c)
                    binfile=${binfile:="${SCRIPT_PATH}"/bin/zynqmp_fsbl_k24c.elf}
                    dtb_file="${SCRIPT_PATH}"/bin/system_k24c_jtag_uart.dtb
                    device_type=zynqmp
                    spi_dma_busy_reg="FF0F0808"
                    ;;
                kria_k24i)
                    binfile=${binfile:="${SCRIPT_PATH}"/bin/zynqmp_fsbl_k24i.elf}
                    dtb_file="${SCRIPT_PATH}"/bin/system_k24i_jtag_uart.dtb
                    device_type=zynqmp
                    spi_dma_busy_reg="FF0F0808"
                    ;;
                versal_eval)
                    #bin file and boardid detection moved to
                    # later as script need to intepret -w first.
                    device_type=versal
                    jtag_mux=true
                    scapp_support=true
                    spi_dma_busy_reg="f1011808"
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
            b_flag_set=true
            overwrite_binfile=$OPTARG
            ;;
        i)
            i_flag_set=true
            path_to_boot_bin="${OPTARG}"
            if [ ! -e "$path_to_boot_bin" ]; then
                echo
                echo "Unable to find file $path_to_boot_bin"
                echo
                usage
            fi
            ;;
        s)
            remote_uart=${OPTARG}
            ;;
        v)
            verify=true
            num_operations=$(( num_operations + 1 ))
            ;;
        c)
            check_blank=true
            ;;
        h)
            usage
            ;;
        V)
            verbose=true
            ;;
        e)
            erase_spi=true
            ;;
        *)
            echo "Unknown argument $OPTARG"
            usage
            ;;
    esac
done

# Need to detect boards after figuring out if this has a remote_ip or not - thus moving out of arg parsing block
if $scapp_support; then
    BOARD=$(detect_board)
    if [ -z "$BOARD" ]; then
        echo "Error: Script failed - Unable to identify board type."
        exit 1
    fi
    echo "Detected board type $BOARD"
    binfile="${SCRIPT_PATH}"/bin/BOOT_${BOARD}.bin
    binfile=${binfile:="${SCRIPT_PATH}"/bin/BOOT_${BOARD}.bin}

fi

# Check if path_to_boot_bin is empty or device_type is not set
if [ -z "$device_type" ]; then
    echo "Device type not specified"
    usage
fi


if ! $check_blank && ! $verify && ! $erase_spi && ! $prog_spi; then
    prog_spi=true
    num_operations=$(( num_operations + 1 ))
    echo "Default to programming flash"
fi

if $check_blank && $erase_spi; then
    num_operations=$(( num_operations + 1 ))
fi

if $check_blank || $erase_spi; then
    if $verify; then
        echo "-v and -c/e cannot be set at the same time"
        usage
    fi
    if $prog_spi; then
        echo "-p and -c/e cannot be set at the same time"
        usage
    fi
    if $i_flag_set; then
        echo "-c and -e option does not require -i input file, please check and try again"
        usage
    fi
else
    if [ -z "$path_to_boot_bin" ] ; then
        echo "File to program into SPI or to verify against SPI not specified with -i"
        usage
    fi
fi


if $prog_spi; then
        echo "Operation programming SPI enabled"
fi
if $erase_spi; then
        echo "Operation erasing SPI enabled"
fi
if $verify; then
        echo "Operation verifying SPI enabled"
fi
if $check_blank; then
        echo "Operation check if SPI is blank enabled"
fi

if $b_flag_set; then
    binfile=$overwrite_binfile
fi


if ! $check_blank && ! $erase_spi; then
    # check -i for symbolic link
    if [ -L "$path_to_boot_bin" ]; then
        actual_target=$(readlink -f "$path_to_boot_bin")
        echo "$path_to_boot_bin is a symbolic link to $actual_target"
        path_to_boot_bin="$actual_target"
        if [ ! -e "$path_to_boot_bin" ]; then
                    echo "Unable to find file $path_to_boot_bin"
        fi
    fi

    # find size of -i input, accounting for gzip format
    format=$(file "$path_to_boot_bin" | awk '{print $2}')
    if [ "$format" == "gzip" ]; then    
        bin_size=$(file "$path_to_boot_bin" | awk '{print $NF}')

        file_cur_ver=$(file --version | head -n1 | awk -F'-' '{print $2}')
        file_req_ver="5.40"
        if [ "$(printf '%s\n' "$file_req_ver" "$file_cur_ver" | sort -V | head -n1)" != "$file_req_ver" ]; then
            echo "file version $file_cur_ver is too old. using gzip -l"
            bin_size=$(gzip -l "$path_to_boot_bin" | awk 'NR==2 {print $2}')
        fi

    else
        bin_size=$(stat -c "%s" "$path_to_boot_bin")
    fi
    bin_size_hex=$(printf "0x%08x" $bin_size)
    echo "Size of bin file to program is 0x$bin_size_hex"
fi

# Check if the bootbin file has been copied over
if [ ! -f "$binfile" ]; then
   if $b_flag_set; then
       echo "Error: File "$binfile" passed through -b does not exist, script failed"
       exit 1
   fi
   echo "File "$binfile" does not exist, auto downloading bin.zip"
   wget https://github.com/Xilinx/embpf-bootfw-update-tool/releases/download/v3.0/bin.zip
   unzip bin.zip -d "${SCRIPT_PATH}"
   if [ ! -f "$binfile" ]; then
       echo "Error: File "$binfile" does not exist and auto download failed"
       echo "       please manually download bin.zip from release area in the"
       echo "       repo and place in this folder. Script failed"
       exit 1
    fi
fi

if $verbose; then
    echo "Script started, look for \"Script completed\" for acknowledgement of completion of SPI programming"
fi

# Print the chosen options
echo "Boot bin path: $path_to_boot_bin"
echo "Device type: $device_type"


if $jtag_mux; then
    if [ -z "$remote_ip" ]; then
        sc_app -c setgpio -t SW3 -v 0
    else
        return_string=$(curl -s "http://${remote_ip}/cmdquery?sc_cmd=setgpio&target=SW3&params=0")
        if echo "$return_string" | grep -qi "ERROR"; then
            echo "Error detected for sc_cmd setgpio: $return_string"
            exit 1
        fi
    fi
fi

if $scapp_support; then
    if [ -z "$remote_ip" ]; then
        sc_app -c setbootmode -t JTAG
        sc_app -c reset
    else
        return_string=$(curl -s "http://${remote_ip}/cmdquery?sc_cmd=setbootmode&target=JTAG&params=")
        if echo "$return_string" | grep -qi "ERROR"; then
            echo "Error detected for sc_cmd setbootmode: $return_string"
            exit 1
        fi
        return_string=$(curl -s "http://${remote_ip}/cmdquery?sc_cmd=reset&target=&params=")
        if echo "$return_string" | grep -qi "ERROR"; then
            echo "Error detected for sc_cmd reset: $return_string"
            exit 1
        fi
    fi

fi

if $embplus_reset; then

    if [ -n "$remote_ip" ]; then
        echo "-w option is not supported for embplus platform, please run directly on embplug target platform, script failed."
        exit 1
    fi

    chmod +x versal/embplus_jtag_porb.py
    if ! dpkg-query -W -f='${Status}' python3-ftdi 2>/dev/null | grep -q "install ok installed" ; then
        echo "python3-ftdi is not installed. Installing it now..."
        if command -v apt &> /dev/null; then
            sudo apt install python3-ftdi
        else
            echo "Error: Unsupported package manager. Please install python3-ftdi"
            echo "       manually. Script failed."
            exit 1
        fi
    fi

    if ! dpkg-query -W -f='${Status}' python3-ftdi 2>/dev/null | grep -q "install ok installed"; then
        echo "Error: python3-ftdi installation failed, please install manually"
        echo "       Script failed."
        exit 1
    fi
    sleep 1
    echo "Setting EmbPlus to JTAG mode and performing por_b reset"
    sudo modprobe -r  xclmgmt &> /dev/null
    sudo modprobe -r  xocl &> /dev/null
    python3 versal/embplus_jtag_porb.py
    sleep 1
fi

if [ $remote_uart -ne 0 ]; then
  SOCK=$remote_uart
else
    # Run the xsdb script to start jtag uart and capture the socket port
    socket_file=tmp.socket
    $XSDB "${SCRIPT_PATH}"/${device_type}/uart.tcl "$remote_ip" &> $socket_file &
    XSDB_PID=$!

    rt=0
    while [ "$SOCK" == "" ] && [ $rt -lt 10 ]; do
    SOCK=$(tail -n 1 $socket_file)
    rt=$(( rt + 1 ))
    sleep 1
    done

    # Check if the socket was created successfully
    if [[ ! "$SOCK" =~ ^[0-9]+$ ]]; then
    echo "Error: Script failed to extract a valid JTAG UART socket number."
    echo "       Output was: $SOCK"
    cleanup
    exit 1
  fi

  if $verbose; then
    echo "JTAG UART socket started on port $SOCK"
  fi
fi


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

step=1
echo "Booting device over JTAG (step $step/$num_operations)"
step=$(( step + 1 ))
xsdb_cmd "${SCRIPT_PATH}"/${device_type}/jtag_boot.tcl "$binfile" "$dtb_file" "$remote_ip"


sleep 2  # Wait a moment for nc to initialize

# have to "flush" the uart or first command wont send correctly to u-boot on some platforms
send_to_jtaguart " "
sleep 1
send_to_jtaguart " "
sleep 1
send_to_jtaguart " "
sleep 1

send_to_jtaguart "sf probe 0x0 0x0 0x0"
match_output_print_prog "term" "SF: Detected" 10 || exit 1

if $verbose; then
    echo "Flash size is $flash_size_hex"
fi
#kria QSPI size is 0x400_0000, embplus OSPI size is 0x1000_0000
zipfile_ddr_addr="0x80000" #this is set in download_data.tcl
binfile_ddr_addr="0x80000" #this is set in download_data.tcl
unzipped_binfile_ddr_addr="0x20000000" #if -i has a gzip file, location to unzip to - should be minimumly size of flash
verify_ddr_addr="0x40000000" #location to copy SPI contents to during verify/blank check. should minimumly be flash size *2


if $verify || $prog_spi; then
    echo "Downloading flash image to DDR (step $step/$num_operations)"
    step=$(( step + 1 ))
    xsdb_cmd "${SCRIPT_PATH}"/${device_type}/download_data.tcl "$path_to_boot_bin" "$remote_ip"

    if [ "$format" == "gzip" ]; then
        binfile_ddr_addr=$unzipped_binfile_ddr_addr
        send_to_jtaguart "unzip $zipfile_ddr_addr $binfile_ddr_addr"
        match_output_print_prog "term" "Uncompressed size:" 120 || exit 1
    fi
fi

if $erase_spi; then
    echo "Erase Flash (step $step/$num_operations)"
    step=$(( step + 1 ))
    send_to_jtaguart "sf erase 0 $flash_size_hex"
    match_output_print_prog "term" "OK" 240 || exit 1
    echo "Erase successful - flash is now erased"
fi

if $check_blank; then
    echo "Check to see if flash is blank (step $step/$num_operations)"
    step=$(( step + 1 ))
    send_to_jtaguart "sf read $verify_ddr_addr 0 $flash_size_hex"
    match_output_print_prog "term" "OK" 120 || exit 1
    send_to_jtaguart "mw.b $binfile_ddr_addr 0xff $flash_size_hex"
    sleep 10 # wait for mw to finish 
    # Wait for SPI DMA to finish
    send_to_jtaguart "mw 10000 00 1"
    send_to_jtaguart "cmp.b $spi_dma_busy_reg 10000 1; while itest \$? != 0; do sleep 1; cmp.b $spi_dma_busy_reg 10000 1; done; echo DONE"
    match_output_print_prog "term" "^DONE" 120 || exit 1
    send_to_jtaguart "cmp.b $verify_ddr_addr $binfile_ddr_addr $flash_size_hex"
    match_output_print_prog "term" "were the same" 120 || exit 1
    echo "Blank check successful - flash is blank/erased"
fi


if $prog_spi; then
    echo "SPI Erasing and programming...this could take up to 5 minutes (step $step/$num_operations)"
    step=$(( step + 1 ))

    send_to_jtaguart "sf update $binfile_ddr_addr 0x0 $bin_size_hex"
    match_output_print_prog "term" "written" 20  || exit 1
    echo "SPI written successfully."
fi

if $verify; then
    echo "Verifying (step $step/$num_operations)"
    step=$(( step + 1 ))
    send_to_jtaguart "sf read $verify_ddr_addr 0x0 $bin_size_hex"
    match_output_print_prog "term" "OK" 120 || exit 1
    # Wait for SPI DMA to finish
    send_to_jtaguart "mw 10000 00 1"
    send_to_jtaguart "cmp.b $spi_dma_busy_reg 10000 1; while itest \$? != 0; do sleep 1; cmp.b $spi_dma_busy_reg 10000 1; done; echo DONE"
    match_output_print_prog "term" "^DONE" 120 || exit 1
    send_to_jtaguart "cmp.b $verify_ddr_addr $binfile_ddr_addr $bin_size_hex"
    match_output_print_prog "term" "were the same" 120 || exit 1
    echo "Verification successful"
fi

cleanup

if $verbose; then
    echo
    echo "Script completed"
fi

exit 0

