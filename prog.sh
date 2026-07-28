#!/bin/bash


#**********************************************************************
#
# Copyright (C) 2020 - 2021 Xilinx, Inc.
# Copyright (C) 2022 - 2026, Advanced Micro Devices, Inc.
# SPDX-License-Identifier: MIT
#
#**********************************************************************

echo "Version 6.0"

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



    if $scapp_support; then
	sc_cmd  setJTAGselect  FTDI || exit 1
    fi
    echo "INFO: JTAG Select set to FTDI, bootmode set to JTAG"
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

sc_cmd() {
    local cmd="$1"
    local target="${2:-}"
    local params="${3:-}"
    local field="${4:-}"
    local ret
    
    if [ -z "$remote_ip" ]; then
        ret=$(sc_app -c "$cmd" ${target:+-t "$target"} ${params:+-v "$params"})
    else
        ret=$(curl -s "http://${remote_ip}/cmdquery?sc_cmd=${cmd}&target=${target}&params=${params}")
    fi

    case "$cmd:$target:$params:$field" in
        version:::)
            if [ -z "$remote_ip" ]; then
                echo "$ret" | grep -i "Version" | awk '{print $2}'
            else
                echo "$ret" | awk 'BEGIN{IGNORECASE=1; FS="\"version\": *\""} {print $2}' | awk -F'"' '{print $1}'
            fi
            ;;

        geteeprom:onboard:summary:*)
            if [ -z "$remote_ip" ]; then
                echo "$ret" | grep "$field" | awk '{print $3}'
            else
                echo "$ret" | awk -F"\"$field\":" '{print $2}' | awk -F'"' '{print $2}'
            fi
            ;;

        *)
            #echo "$ret"
            ;;
    esac
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
            return 1
        fi
        echo "$line"
        return 0
    elif [ "$iosource" == "xsdb" ]; then
        IFS= read -r -t "$timeout" line
        if [ $? -ne 0 ]; then
            echo "Timed out after $timeout seconds - script failed" >&2
            return 1
        fi
        echo "$line"
        return 0
    else
        echo "Error: Unknown iosource '$iosource'" >&2
        return 1
    fi


}

#Blue progress bar
#BARSTR='\r\e[44;38;5;25m%s\e[0m%4.0f%%'

#Black and White progress bar
BARSTR='\r%s%4.0f%%'

check_crc_line() {
    local line="$1"
    local expected_crc
    local actual_crc

    # assumg U-Boot print CRC comparison lines like:
    #   crcs == 0xc09f0a31/0x8f2aa7a7
    if [[ "$line" =~ [Cc][Rr][Cc][Ss]?[[:space:]]*==[[:space:]]*(0x[0-9A-Fa-f]+)[[:space:]]*/[[:space:]]*(0x[0-9A-Fa-f]+) ]]; then
        expected_crc="${BASH_REMATCH[1]}"
        actual_crc="${BASH_REMATCH[2]}"

        if [[ "${expected_crc,,}" != "${actual_crc,,}" ]]; then
            echo "Error: CRC mismatch, verification failed: expected $expected_crc, actual $actual_crc" >&2
            cleanup
            return 1
        fi
    fi

    return 0
}

match_output_print_prog() {
  local iosource="$1"
  local match_pattern="$2"
  local timeout="$3"
  local noclean="$4"
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
	if [ -z "$noclean" ]; then
	    cleanup
	fi
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

    if ! check_crc_line "$line"; then
        return 1
    fi

    if echo "$line" | grep -q "SF: Detected" ; then
        flash_size_print=$(echo "$line" | awk '{for(i=1;i<=NF;i++) if ($i=="total") print $(i+1)}')
        flash_size_hex=$(printf "0x%X\n" $(( $flash_size_print * 1024 * 1024 )))
    fi
    if echo "$line" | grep -q ".gz"; then
	uboot_gz_filename=$(echo "$line" | awk '{print $2}')
	uboot_gz_size=$(echo "$line" | awk '{print $1}')
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
    elif echo "$line" | grep -q "Error: inflate"; then
	echo "ERROR: gzwrite errored with inflate error"
	cleanup
	return 1
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
    "$XSDB" -interactive "$@" | stdbuf -oL  tr '\r' '\n' | match_output_print_prog "xsdb" "finished" 60 || exit 1
}

version_ge() {
    # usage: version_ge <A> <B>   -> returns 0 (true) if A >= B
    [ -n "$1" ] && [ -n "$2" ] || return 1
    local A="$1" B="$2"

    # sort -V puts lowest first. If A < B, then A will come first.
    if [ "$(printf '%s\n' "$A" "$B" | sort -V | head -n1)" = "$B" ]; then
        return 0  # A >= B
    else
        return 1  # A < B
    fi
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

    boardid=$(sc_cmd geteeprom onboard summary "Product Name")
    silicon_rev=$(sc_cmd geteeprom onboard summary "Silicon Revision")
    board_rev=$(sc_cmd geteeprom onboard summary "Board Revision")


    if [[ -z "$silicon_rev" || -z "$boardid" || -z "$board_rev" ]]; then
        echo "Error: Board ID ($boardid) or Silicon Revision($silicon_rev) or Board Revision($board_rev) not found or empty."  >&2
        return 1
    fi

    # VEK385 - ignore silicon rev. board rev matters
    # other eval boards - silicon rev matters
    if [[ "${boardid,,}" =~ vek385 ]]; then
	boardid="${boardid}_rev${board_rev:0:1}"
    else 
	if [ "$silicon_rev" != "PROD" ]; then
            boardid="${boardid}_${silicon_rev}"
	fi
    fi

    boardid=$(echo "$boardid" | tr '[:upper:]' '[:lower:]')

    echo $boardid
}



program_spi() {
    send_to_jtaguart "sf probe 0x0 0x0 0x0"
    match_output_print_prog "term" "SF: Detected" 10 || exit 1

    if $verbose; then
	echo "Flash size is $flash_size_hex"
    fi
    #kria QSPI size is 0x400_0000, embplus OSPI size is 0x1000_0000
    download_ddr_addr="0x30000000"
    zipfile_ddr_addr=$download_ddr_addr
    binfile_ddr_addr=$download_ddr_addr
    unzipped_binfile_ddr_addr="0x20000000" #if -i has a gzip file, location to unzip to - should be minimumly size of flash
    verify_ddr_addr="0x40000000" #location to copy SPI contents to during verify/blank check. should minimumly be flash size *2


    if $bdi_reserved_mem_check; then
	echo "Checking DDR work areas against U-Boot reserved ranges..."
	if ! bdi_guard_check \
             "$download_ddr_addr" "$unzipped_binfile_ddr_addr" "$verify_ddr_addr" \
             "$flash_size_hex"
	then
            echo "DDR overlap check failed. Refusing to proceed to protect reserved memory."
            cleanup
            exit 1
	fi
	echo "DDR overlap check passed."
    fi


    if $verify || $prog; then
	echo "Downloading flash image to DDR (step $step/$num_operations)"
	step=$(( step + 1 ))
	xsdb_cmd "${SCRIPT_PATH}"/${device_type}/download_data.tcl "$path_to_payload" "$remote_ip" "$download_ddr_addr"

	if [ "$format" == "gzip" ]; then
            binfile_ddr_addr=$unzipped_binfile_ddr_addr
            send_to_jtaguart "unzip $zipfile_ddr_addr $binfile_ddr_addr"
            match_output_print_prog "term" "Uncompressed size:" 120 || exit 1
	fi
    fi

    if $erase; then
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
	match_output_print_prog "term" "OK" 480 || exit 1
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


    if $prog; then
	echo "SPI Erasing and programming...this could take up to 5 minutes (step $step/$num_operations)"
	step=$(( step + 1 ))
	
	send_to_jtaguart "sf update $binfile_ddr_addr 0x0 $uncompressed_size_hex"
	match_output_print_prog "term" "written" 20  || exit 1
	echo "SPI written successfully."
    fi
    
    if $verify; then
	echo "Verifying (step $step/$num_operations)"
	step=$(( step + 1 ))
	send_to_jtaguart "sf read $verify_ddr_addr 0x0 $uncompressed_size_hex"
	match_output_print_prog "term" "OK" 480 || exit 1
	# Wait for SPI DMA to finish
	send_to_jtaguart "mw 10000 00 1"
	send_to_jtaguart "cmp.b $spi_dma_busy_reg 10000 1; while itest \$? != 0; do sleep 1; cmp.b $spi_dma_busy_reg 10000 1; done; echo DONE"
	match_output_print_prog "term" "^DONE" 120 || exit 1
	send_to_jtaguart "cmp.b $verify_ddr_addr $binfile_ddr_addr $uncompressed_size_hex"
	match_output_print_prog "term" "were the same" 120 || exit 1
	echo "Verification successful"
    fi
}

provision_ufs() {

    echo "Run UFS provision elf, look at com0 for progress"
    #sc_cmd  setJTAGselect  SC || exit 1

    xsdb_cmd "${SCRIPT_PATH}"/${device_type}/ufs_provision.tcl "${SCRIPT_PATH}"/${device_type}/ufs_provision.elf
    
    echo "Booting again device over JTAG (step $step/$num_operations)"
    xsdb_cmd "${SCRIPT_PATH}"/${device_type}/jtag_boot.tcl "$binfile" "$dtb_file" "$remote_ip"

    sleep 2  # Wait a moment for nc to initialize

    # have to "flush" the uart or first command wont send correctly to u-boot on some platforms
    send_to_jtaguart " "
    sleep 1
    send_to_jtaguart " "
    sleep 1
    send_to_jtaguart " "
    sleep 1
    send_to_jtaguart "ufs init"
    send_to_jtaguart "scsi scan"
    send_to_jtaguart "scsi dev 0"


    
    if ! match_output_print_prog "term" "59.6 GB" 10 "noclean"; then
	echo "ERROR: UFS not provisioned to expected partition. 59.6GB partition not found. This is unexpected - quitting"
	cleanup
	exit 1
    fi

}


prep_ufs() {
    send_to_jtaguart "ufs init"
    send_to_jtaguart "scsi scan"


    if [ -z "$ufs_lun_num" ]; then
       if ! match_output_print_prog "term" "59.6 GB" 10 "noclean"; then
	   echo "UFS not provisioned to expected partition. 59.6GB partition not found. provisioning!"
	   provision_ufs
       fi
       ufs_lun_num="0"
    fi

    send_to_jtaguart "scsi dev $ufs_lun_num"
    download_ddr_addr="0x900000000" 

}

prep_emmc() {
    send_to_jtaguart "mmc dev 0 0"
    send_to_jtaguart "mmc rescan"
    download_ddr_addr="0x30000000" 

}
end_ufs() {
    send_to_jtaguart "scsi scan"
    send_to_jtaguart "part list scsi 0"
}

program_ufs_emmc() {


    if $payload_in_usb; then
	send_to_jtaguart "usb start"
	send_to_jtaguart "fatls usb 0"
	gz_in_usb="0"
	if ! match_output_print_prog "term" ".gz" 10 "noclean"; then
	    send_to_jtaguart "fatls usb 1"
	    match_output_print_prog "term" ".gz" 10  || exit 1
	    gz_in_usb="1"
	fi
	if [ "$uboot_gz_filename" != "$path_to_payload" ]; then
	    echo "ERROR: file name in USB: $uboot_gz_filename does not match file name supplied in -i: $path_to_payload"
	    cleanup
	    exit 1
	fi 
	compressed_size=$uboot_gz_size
	compressed_size_hex=$(printf "0x%08x" $compressed_size)
    fi

    if $bdi_reserved_mem_check; then	
	echo "Checking DDR work areas against U-Boot reserved ranges..."
	if ! bdi_guard_check \
             "$download_ddr_addr" "$download_ddr_addr" "$download_ddr_addr" \
             "$compressed_size"
	then
            echo "ERROR: DDR overlap check failed. Refusing to proceed to protect reserved memory."
            cleanup
            exit 1
	fi
	echo "DDR overlap check passed."
    fi

    if $prog; then
	if $payload_in_usb; then
	    echo "Using file from USB - file must be in USB0:1 or USB1:1, and file name must match -i input"
	    echo "There's no error checking for presence of file in USB in this script"
	    send_to_jtaguart "fatload usb $gz_in_usb:1 $download_ddr_addr $path_to_payload"
	    match_output_print_prog "term" "bytes read" 600  || exit 1
	    send_to_jtaguart "echo compressed file size is \${filesize}"
	    send_to_jtaguart "gzwrite $devta $ufs_lun_num $download_ddr_addr \${filesize} 0x100000 0"
	else
	    if [ "$format" != "gzip" ]; then
		echo "ERROR: UFS/eMMC programming requires a gzip input file in -i"
		cleanup
		exit 1
	    fi

	    gzfile="$path_to_payload"

	    echo "Compressed:   $compressed_size bytes"
	    echo "Uncompressed: $uncompressed_size bytes"

	    echo "Downloading image to DDR (step $step/$num_operations)"
	    step=$(( step + 1 ))
	    echo "download image to ddr through XSDB. this could take a while   (step $step/$num_operations)"

	    xsdb_cmd "${SCRIPT_PATH}"/${device_type}/download_data.tcl "$path_to_payload" "$remote_ip" "$download_ddr_addr"

	    echo "UFS/eMMC programming...this could take up to 5 minutes (step $step/$num_operations)"
	    step=$(( step + 1 ))
	
	    send_to_jtaguart "gzwrite $devta $ufs_lun_num $download_ddr_addr $compressed_size_hex 0x100000 0"	
	    
	fi

	match_output_print_prog "term" "crc" 600  || exit 1
	echo "$devtarget written successfully."
    fi
    
}




usage () {
    echo "Default Usage: $0 -i <path_to_boot.bin> -d <board_type>"
    echo "    -S             : target SPI memory - this is default if no -S or -U is present"
    echo "    -U             : target UFS memory. Currently only support:"
    echo "                     VEK385"
    echo "    -E             : target eMMC memory. Currently only support:"
    echo "                     Kria platforms: kria_k26, kria_k24c, kria_k24i"
    echo "    -i <file>      : Payload file to write into OSPI/QSPI/UFS"
    echo "                     if SPI - can be a .bin or a gzip of the .bin file"
    echo "                     if UFS/eMMC, have to be a gzip of the wic image"
    echo "    -d <board>     : Board type.  Supported values"
    echo "                     embplus(defaults to 4616), embplus_4616"
    echo "		       embplus_5050, embplus_5050a"
    echo "                     rhino, v80"
    echo "                     kria_k26, kria_k24c, kria_k24i"
    echo "                     versal_eval"
    echo "    -b <boot_file> : Optional argument to override jtag boot.bin, for Versal only"
    echo "    -s <SOCK #>    : Optional argument to specify remote uart SOCK number"
    echo "    -p             : Optional argument program SPI, this is set by default except"
    echo "                     if -v or -b is present"
    echo "    -v             : verification of flash content, if -pv are both present,"
    echo "                     tool will program and verify. if only -v is set, tool will"
    echo "                     verify content of SPI against -i  <file> without programming"
    echo "    -c             : check if flash is blank/erased"
    echo "    -e             : erase flash"
    echo "    -u             : indicate for UFS programming, that the wic.gz file in -i option"
    echo "                     is in USB drive. Supported only for UFS programming"
    echo "    -V             : verbose logging"
    echo "    -M             : optional argument to add memory check to make sure DDR used"
    echo "                     by script does not overlap u-boot reserved memory region"
    echo "    -w             : optional argument to connect to remote hardware server, use"
    echo "                     IP address or machine name shown by hw_server (without :3121)."
    echo "                     not supported for embplus/rhino systems"
    echo "    -h             : help"
    echo "Example usages:"
    echo "to program SPI in verbose mode:"
    echo "     $0 -i <path_to_boot.bin> -d <board_type> -V"
    echo "to program SPI with explicit -p and in verbose mode:"
    echo "     $0 -p -i -V <path_to_boot.bin> -d <board_type>"
    echo "to program SPI and verify:"
    echo "     $0 -pv -i <path_to_boot.bin> -d <board_type>"
    echo "to verify SPI only:"
    echo "     $0 -v -i <path_to_boot.bin> -d <board_type>"
    echo "to check if SPI is blank:"
    echo "     $0 -c -d <board_type>"
    echo "to erase SPI:"
    echo "     $0 -e -d <board_type>"
    echo "to erase and check that SPI is blank:"
    echo "     $0 -ec -d <board_type>"
    echo "to program a remote hw_server target in verbose mode"
    echo "     $0 -Vp -d <board_type> -i <path_to_boot.bin> -w <remote machine name or IP addr> "
    echo "to program UFS in verbose mode:"
    echo "     $0 -i <path_to_boot.bin> -d versal_eval -V -U"
    echo "to program eMMC in verbose mode:"
    echo "     $0 -i <path_to_boot.bin> -d <board_type> -V -E"
 
    exit 1
}


# Initialize variables
path_to_payload=""
device_type=""
dtb_file=""
flash_size_hex=""
embplus_reset=false
ospi_boot=false
scapp_support=false
verify=false
prog=false
erase=false
devtarget="SPI"
devta=""
check_blank=false
b_flag_set=false
i_flag_set=false
remote_uart=0
SCRIPT_PATH=$(dirname $0)
verbose=false
num_operations=2
spi_dma_busy_reg=""
remote_ip=""
sc_app_ver=""
jtag_gpio="SW3"
bdi_reserved_mem_check=false
payload_in_usb=false
uboot_gz_filename=""
uboot_gz_size=""
ufs_lun_num=""
gz_in_usb="0"

# Parse arguments
while getopts "d:i:l:b:s:w:pvhceVMUESu" arg; do
    case "$arg" in
	S)
	    devtarget="SPI"
	    ;;
	U)
	    devtarget="UFS"
	    devta="scsi"
	    ;;
	E)
	    devtarget="EMMC"
	    devta="mmc"
	    ufs_lun_num=0
	    ;;
        p)
            num_operations=$(( num_operations + 1 ))
            prog=true
            ;;
        w)
            remote_ip=${OPTARG}
            echo "remote_ip is $remote_ip"
            ;;
        d)
            case ${OPTARG} in

		embplus|embplus_*)
		    device_type=versal
		    embplus_reset=true
		    spi_dma_busy_reg="f1011808"
		    
		    binfile="${SCRIPT_PATH}/bin/BOOT_${OPTARG}_jtaguart.bin"
		    ospi_boot=true
		    ;;
                rhino)
                    binfile="${SCRIPT_PATH}/bin/BOOT_rhino_jtaguart.bin"
                    device_type=versal
                    spi_dma_busy_reg="f1011808"
                    ;;
                v80)
                    binfile="${SCRIPT_PATH}/bin/BOOT_v80_jtaguart.bin"
                    device_type=versal
                    spi_dma_busy_reg="f1011808"
                    ospi_boot=true
                    ;;
                kria_k26)
                    binfile="${SCRIPT_PATH}/bin/zynqmp_fsbl_k26.elf"
                    dtb_file="${SCRIPT_PATH}/bin/system_k26_jtag_uart.dtb"
                    device_type=zynqmp
                    spi_dma_busy_reg="FF0F0808"
                    ;;
                kria_k24c)
                    binfile="${SCRIPT_PATH}/bin/zynqmp_fsbl_k24c.elf"
                    dtb_file="${SCRIPT_PATH}/bin/system_k24c_jtag_uart.dtb"
                    device_type=zynqmp
                    spi_dma_busy_reg="FF0F0808"
                    ;;
                kria_k24i)
                    binfile="${SCRIPT_PATH}/bin/zynqmp_fsbl_k24i.elf"
                    dtb_file="${SCRIPT_PATH}/bin/system_k24i_jtag_uart.dtb"
                    device_type=zynqmp
                    spi_dma_busy_reg="FF0F0808"
                    ;;
                versal_eval)
                    #bin file and boardid detection moved to
                    # later as script need to intepret -w first.
                    device_type=versal
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
	u)
	    payload_in_usb=true
	    if [ "$devtarget" = "SPI" ]; then
		echo "ERROR: usb input not supported for SPI programming"
		usage
	    fi
	    ;;
	l)
	    ufs_lun_num="${OPTARG}"
	    echo "WARN: LUNs chosen is $ufs_lun_num, will not do UFS provision."
	    echo "      there's no error checking to see if the LUN exist or is big enough - write will fail if chosen LUN is not big enough"

	    if [ "$devtarget" = "SPI" ]; then
		echo "ERROR: LUNs input not supported for SPI programming"
		usage
	    fi
	    ;;
        i)
            i_flag_set=true
            path_to_payload="${OPTARG}"
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
            erase=true
            ;;
	M)
	    bdi_reserved_mem_check=true
	    
	    if [ -f "${SCRIPT_PATH}/ddr_reserved_mem_check.sh" ]; then
		. "${SCRIPT_PATH}/ddr_reserved_mem_check.sh"
	    else
		echo "Error: ddr_reserved_mem_check.sh not found"
		exit 1
	    fi
	    ;;
        *)
            echo "Unknown argument $OPTARG"
            usage
            ;;
    esac
done

if $i_flag_set; then
    if [ ! -e "$path_to_payload" ] && [ "$payload_in_usb" = false ]; then
        echo
        echo "ERROR: unable to find file $path_to_payload"
        echo
        usage
    fi
fi

if $scapp_support; then
    if [ -z "$remote_ip" ]; then
	if ! command -v sc_app &> /dev/null; then
            echo "Error: Script failed - sc_app command not found. Please run versal_eval with updated system controller images."  >&2
            return 1
	fi
    fi
    
    sc_app_ver=$(sc_cmd version)
 
    if version_ge "$sc_app_ver" "1.25"; then
	echo "sc_app version is $sc_app_ver"
    else
	echo "Error: This version require sc_app of version 1.25 or newer."
	echo "Please use embpf-bootfw-update-tool release 4.0 or older for older sc_app support"
	cleanup
	exit 1
    fi

    BOARD=$(detect_board)
    if [ -z "$BOARD" ]; then
        echo "Error: Script failed - Unable to identify board type."
        exit 1
    fi
    echo "Detected board type $BOARD"
    binfile="${SCRIPT_PATH}"/bin/BOOT_${BOARD}.bin
    
   if [[ "${BOARD,,}" =~ vrk16 ]]; then
	jtag_gpio="SW8"
   fi

fi

# Check if path_to_payload is empty or device_type is not set
if [ -z "$device_type" ]; then
    echo "Device type not specified"
    usage
fi


if ! $check_blank && ! $verify && ! $erase && ! $prog; then
    prog=true
    num_operations=$(( num_operations + 1 ))
    echo "Default to programming $devtarget"
fi

if [[ "$devtarget" == "UFS" ]] && { $erase || $check_blank || $verify; }; then
    echo "ERROR: Erasing/checking/verifying UFS currently not supported"
    cleanup
    exit 1
fi

if $check_blank && $erase; then
    num_operations=$(( num_operations + 1 ))
fi

if $check_blank || $erase; then
    if $verify; then
        echo "-v and -c/e cannot be set at the same time"
        usage
    fi
    if $prog; then
        echo "-p and -c/e cannot be set at the same time"
        usage
    fi
    if $i_flag_set; then
        echo "-c and -e option does not require -i input file, please check and try again"
        usage
    fi
else
    if [ -z "$path_to_payload" ] ; then
        echo "File to program into SPI or to verify against SPI not specified with -i"
        usage
    fi
fi


if $prog; then
        echo "Operation programming $devtarget enabled"
fi
if $erase; then
        echo "Operation erasing $devtarget enabled"
fi
if $verify; then
        echo "Operation verifying $devtarget enabled"
fi
if $check_blank; then
        echo "Operation check if $devtarget is blank enabled"
fi

if $b_flag_set; then
    binfile=$overwrite_binfile
fi


if ! $check_blank && ! $erase && ! $payload_in_usb; then
    # check -i for symbolic link
    if [ -L "$path_to_payload" ]; then
        actual_target=$(readlink -f "$path_to_payload")
        echo "$path_to_payload is a symbolic link to $actual_target"
        path_to_payload="$actual_target"
        if [ ! -e "$path_to_payload" ]; then
                    echo "Unable to find file $path_to_payload"
        fi
    fi

    # find size of -i input, accounting for gzip format
    format=$(file "$path_to_payload" | awk '{print $2}')
    if [ "$format" == "gzip" ]; then    
        uncompressed_size=$(file "$path_to_payload" | awk '{print $NF}')
	compressed_size=$(stat -c "%s" "$path_to_payload")
	compressed_size_hex=$(printf "0x%08x" $compressed_size)

        file_cur_ver=$(file --version | head -n1 | awk -F'-' '{print $2}')
        file_req_ver="5.40"
        if [ "$(printf '%s\n' "$file_req_ver" "$file_cur_ver" | sort -V | head -n1)" != "$file_req_ver" ]; then
            echo "file version $file_cur_ver is too old. using gzip -l"
            uncompressed_size=$(gzip -l "$path_to_payload" | awk 'NR==2 {print $2}')
        fi
    else
        uncompressed_size=$(stat -c "%s" "$path_to_payload")
    fi
    uncompressed_size_hex=$(printf "0x%08x" $uncompressed_size)
    echo "Size of input file to program is 0x$uncompressed_size_hex"
fi

# Check if the bootbin file has been copied over
if [ ! -f "$binfile" ]; then
   echo "File "$binfile" does not exist, auto downloading bin.zip"
   wget -O bin.zip https://github.com/Xilinx/embpf-bootfw-update-tool/releases/download/v6.0/bin.zip
   unzip -o bin.zip -d "${SCRIPT_PATH}"
   if [ ! -f "$binfile" ]; then
       if $b_flag_set; then
	   echo "Error: File "$binfile" passed through -b does not exist, script failed"
	   exit 1
       else
	   echo "Error: File "$binfile" does not exist and auto download failed"
	   echo "       please manually download bin.zip from release area in the"
	   echo "       https://github.com/Xilinx/embpf-bootfw-update-tool"
	   echo "       repo and place in this folder. Script failed"
	   exit 1
       fi
   fi
fi

if $verbose; then
    echo "Script started, look for \"Script completed\" for acknowledgement of completion of SPI programming"
fi

# Print the chosen options
echo "Boot bin path: $path_to_payload"
echo "Device type: $device_type"




if $scapp_support; then
    sc_cmd setJTAGselect SC || exit 1
fi



if $scapp_support; then
    sc_cmd setbootmode JTAG || exit 1
    sc_cmd reset || exit 1
fi

if $embplus_reset; then

    if [ -n "$remote_ip" ]; then
        echo "-w option is not supported for embplus platform, please run directly on embplug target platform, script failed."
        exit 1
    fi

    chmod +x "${SCRIPT_PATH}/versal/embplus_jtag_porb.py"
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
    python3 "${SCRIPT_PATH}/versal/embplus_jtag_porb.py"
    sleep 1
fi

if [ $remote_uart -ne 0 ]; then
  SOCK=$remote_uart
else
    # Run the xsdb script to start jtag uart and capture the socket port
    socket_file=tmp.socket
    $XSDB "${SCRIPT_PATH}"/${device_type}/uart.tcl "$remote_ip" &> $socket_file 2>/dev/null &  
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



if [[ "$devtarget" == "SPI" ]]; then
    program_spi
elif [[ "$devtarget" == "UFS" ]]; then
    prep_ufs
    program_ufs_emmc
    end_ufs
elif [[ "$devtarget" == "EMMC" ]]; then
    prep_emmc
    program_ufs_emmc
fi


if $ospi_boot; then
    echo "Booting from OSPI"
    $XSDB "${SCRIPT_PATH}"/${device_type}/ospi_boot.tcl
fi

cleanup

if $verbose; then
    echo
    echo "Script completed"
fi

exit 0

