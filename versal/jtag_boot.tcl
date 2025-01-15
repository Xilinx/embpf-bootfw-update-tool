###############################################################################
# Copyright (c) 2022 - 2024, Advanced Micro Devices, Inc.  All rights reserved.
# SPDX-License-Identifier: MIT
###############################################################################

source versal/boot_mode.tcl
connect
targets -set -nocase -filter {name =~ "Versal*"}
switch_to_jtag
puts "programming device to start u-boot"
device program [lindex $argv 0]
puts "device program, u-boot started, prepare to program flash to DDR"
con


