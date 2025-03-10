###############################################################################
# Copyright (c) 2022 - 2024, Advanced Micro Devices, Inc.  All rights reserved.
# SPDX-License-Identifier: MIT
###############################################################################

source zynqmp/jtag_ready.tcl
jtag_ready
targets -set -nocase -filter {name =~ "PSU"}
after 2000
puts "downloading flash content to DDR"
dow -force -data [lindex $argv 0]  0x80000
puts "content downloaded to DDR, prepare to write to flash"
disconnect
exit
