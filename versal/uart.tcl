###############################################################################
# Copyright (c) 2022 - 2024, Advanced Micro Devices, Inc.  All rights reserved.
# SPDX-License-Identifier: MIT
###############################################################################

source versal/boot_mode.tcl
jtag_ready
targets -set -nocase -filter {name =~ "Cortex-A72 #0*"}
set sock [jtagterminal -start -socket]
puts $sock ;
vwait forever

