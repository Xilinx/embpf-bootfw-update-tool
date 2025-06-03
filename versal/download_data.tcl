###############################################################################
# Copyright (c) 2022 - 2024, Advanced Micro Devices, Inc.  All rights reserved.
# SPDX-License-Identifier: MIT
###############################################################################

set script_dir [file dirname [info script]]
source "$script_dir/boot_mode.tcl"
jtag_ready  [lindex $argv 1]
targets -set -nocase -filter {name =~ "Versal*"}
after 2000
puts stderr "downloading flash content to DDR"
plm set-log-level 0
dow -force -data [lindex $argv 0]  0x80000
puts "content download to DDR finished"
disconnect
exit
