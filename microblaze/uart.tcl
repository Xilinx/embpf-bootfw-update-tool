###############################################################################
# Copyright (c) 2022 - 2024, Advanced Micro Devices, Inc.  All rights reserved.
# SPDX-License-Identifier: MIT
###############################################################################

set script_dir [file dirname [info script]]

source "$script_dir/jtag_ready.tcl"
jtag_ready  [lindex $argv 0]

if {[catch {targets -set -nocase -filter {name =~ "*RISC-V at USER2*"} -timeout 10}]} {
    puts "ERROR: Could not find RISC-V at USER2 target for JTAG UART"
    exit 1
}

set sock [jtagterminal -start -socket]
puts $sock ;
flush stdout
vwait forever

