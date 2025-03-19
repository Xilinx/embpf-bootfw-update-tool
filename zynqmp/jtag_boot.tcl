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
jtag_ready

# setting jtag mode moved to uart.tcl

targets -set -nocase -filter {name =~ "MicroBlaze PMU"}
catch {stop}; after 1000
puts stderr "INFO: Downloading zynqmp_pmufw ELF file to the target."
dow -force "bin/pmufw.elf"
after 2000
con

after 5000
targets -set -nocase -filter {name =~ "Cortex-A53*#0"}
rst -proc -clear-registers
after 2000
puts stderr "INFO: Downloading [lindex $argv 0] ELF file to the target."
dow -force "[lindex $argv 0]"
after 2000
con
after 4000; stop; catch {stop};

targets -set -nocase -filter {name =~ "*A53*#0"}
puts stderr "INFO: Downloading DTB: [lindex $argv 1] at 0x00100000"
dow -data  "[lindex $argv 1]" 0x00100000
after 2000

targets -set -nocase -filter {name =~ "*A53*#0"}
after 2000
puts stderr "INFO: Downloading u-boot ELF file to the target."
dow -force "bin/u-boot.elf"
after 2000

targets -set -nocase -filter {name =~ "*A53*#0"}
puts stderr "INFO: Downloading bl31 ELF file to the target."
after 2000
dow -force "bin/bl31.elf"
after 2000
con

# below line with "finished" is required for print_progress
puts "INFO: Jtag boot finished, u-boot should be started"
disconnect
exit

