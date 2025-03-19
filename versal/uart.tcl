###############################################################################
# Copyright (c) 2022 - 2024, Advanced Micro Devices, Inc.  All rights reserved.
# SPDX-License-Identifier: MIT
###############################################################################

set script_dir [file dirname [info script]]
source "$script_dir/boot_mode.tcl
jtag_ready
targets -set -nocase -filter {name =~ "Cortex-A72 #0*"}
set sock [jtagterminal -start -socket]
puts $sock ;
vwait forever

