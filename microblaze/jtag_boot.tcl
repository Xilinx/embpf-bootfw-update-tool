################################################################################
#Description      : This script is used to boot the board 
#					till u-boot in jtag mode
#Author           : Sharathk
#
#
################################################################################

puts "Starting the script..."
set script_dir [file dirname [info script]]

source "$script_dir/jtag_ready.tcl"
jtag_ready [lindex $argv 2]

# setting jtag mode moved to uart.tcl

puts stderr "INFO: Programming device with PDI"
device program [lindex $argv 0]
after 2000

puts stderr "INFO: Selecting MicroBlaze-V Hart target"
targets -set -nocase -filter {name =~ "Hart*" && parent =~ "*USER2*"} -timeout 10

puts stderr "INFO: Downloading FIT image to DDR at 0x80200000"
dow -data [lindex $argv 1] 0x80200000
after 1000

puts stderr "INFO: Downloading SPL to BRAM at 0x00000000"
# Derive SPL name from PDI name: mbv_<board>.pdi → mbv_<board>_spl.bin
set pdi_name [file tail [lindex $argv 0]]
set spl_name [string map {".pdi" "_spl.bin"} $pdi_name]
dow -data "$script_dir/../bin/$spl_name" 0x00000000

catch {con}

# below line with "finished" is required for print_progress
puts "INFO: Jtag boot finished, u-boot should be started"
disconnect
exit

