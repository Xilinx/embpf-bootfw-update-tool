###############################################################################
# Copyright (c) 2022 - 2024, Advanced Micro Devices, Inc.  All rights reserved.
# SPDX-License-Identifier: MIT
###############################################################################

set script_dir [file dirname [info script]]
source "$script_dir/jtag_ready.tcl"
jtag_ready [lindex $argv 1]

targets -set -nocase -filter {name =~ "PSU"}
after 2000
puts stderr "INFO: downloading flash content to DDR"
dow -force -data [lindex $argv 0]  0x80000
after 2000
puts "INFO: content download to DDR finished"

disconnect
exit
