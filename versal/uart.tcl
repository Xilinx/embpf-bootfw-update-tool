###############################################################################
# Copyright (c) 2022 - 2024, Advanced Micro Devices, Inc.  All rights reserved.
# SPDX-License-Identifier: MIT
###############################################################################

set script_dir [file dirname [info script]]

source "$script_dir/boot_mode.tcl"
jtag_ready  [lindex $argv 0]

if {[catch {targets -set -nocase -filter {name =~ "Cortex-A72* #0*"}}]} {
    if {[catch {targets -set -nocase -filter {name =~ "Cortex-A78* #0.0*"}}]} {
        puts "ERROR: Could not find a suitable Cortex-A72 or A78 core"
        exit 1
    }
}

set sock [jtagterminal -start -socket]
puts $sock ;
vwait forever

