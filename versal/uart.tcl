###############################################################################
# Copyright (c) 2022 - 2024, Advanced Micro Devices, Inc.  All rights reserved.
# SPDX-License-Identifier: MIT
###############################################################################

connect
targets -set -nocase -filter {name =~ "Cortex-A72 #0*"}
set sock [jtagterminal -start -socket]
puts $sock ;
vwait forever

