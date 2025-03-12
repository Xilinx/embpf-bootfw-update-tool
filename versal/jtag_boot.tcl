###############################################################################
# Copyright (c) 2022 - 2024, Advanced Micro Devices, Inc.  All rights reserved.
# SPDX-License-Identifier: MIT
###############################################################################

source versal/boot_mode.tcl
jtag_ready
targets -set -nocase -filter {name =~ "Versal*"}
switch_to_jtag
puts stderr "programming device with jtag boot files to start u-boot"
device program [lindex $argv 0]
plm set-log-level 0
puts stderr "Jtag boot finished, u-boot should be started"
# below line is required for print_progress
puts "Jtag boot finished, u-boot should be started"
con
disconnect
exit
