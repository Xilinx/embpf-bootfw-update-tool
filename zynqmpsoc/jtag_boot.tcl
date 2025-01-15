################################################################################
#Description      : This script is used to boot the board 
#					till u-boot in jtag mode
#Author           : Sharathk
#
#
################################################################################

puts stderr "Starting the script..."
connect
targets -set -nocase -filter {name =~ "PSU"}
# update multiboot to ZERO
mwr 0xffca0010 0x0
# change boot mode to JTAG
mwr 0xff5e0200 0x0100
# reset
rst -system
after 2000
targets -set -nocase -filter {name =~ "PSU"}
mwr  0xffca0038 0x1ff
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
puts stderr "INFO: Loading image: [lindex $argv 1] at 0x00100000"
#system.dtb
dow -data  "[lindex $argv 1]" 0x00100000
after 2000

targets -set -nocase -filter {name =~ "*A53*#0"}
puts stderr "INFO: Downloading u-boot ELF file to the target."
after 2000
dow -force "bin/u-boot.elf"
after 2000

targets -set -nocase -filter {name =~ "*A53*#0"}
puts stderr "INFO: Downloading bl31 ELF file to the target."
after 2000
dow -force "bin/bl31.elf"
after 2000
con
puts stderr "u-boot should be started"

