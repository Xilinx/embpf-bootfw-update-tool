###############################################################################
# Copyright (c) 2022 - 2024, Advanced Micro Devices, Inc.  All rights reserved.
# SPDX-License-Identifier: MIT
###############################################################################
set script_dir [file dirname [info script]]
source "$script_dir/jtag_ready.tcl"
jtag_ready

targets -set -nocase -filter {name =~ "PSU"}
# update multiboot to ZERO
mwr 0xffca0010 0x0
# change boot mode to JTAG
mwr 0xff5e0200 0x0100
# reset
rst -system
after 2000
targets -set -nocase -filter {name =~ "PSU"}
mwr  0xffca0038 0x1ff

targets -set -nocase -filter {name =~ "Cortex-A53 #0*"}
set sock [jtagterminal -start -socket]
puts $sock ;
vwait forever

