###############################################################################
# Copyright (c) 2022 - 2024, Advanced Micro Devices, Inc.  All rights reserved.
# SPDX-License-Identifier: MIT
###############################################################################

set script_dir [file dirname [info script]]
source "$script_dir/boot_mode.tcl"
jtag_ready  [lindex $argv 1]
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
