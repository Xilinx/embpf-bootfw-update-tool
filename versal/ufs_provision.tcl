###############################################################################
# Copyright (c) 2022 - 2024, Advanced Micro Devices, Inc.  All rights reserved.
# SPDX-License-Identifier: MIT
###############################################################################

puts  "connect"
connect
puts  "set target"

targets -set -nocase -filter {name =~ "Cortex-A78AE #0.0*"}
puts  "stop"

stop

puts "connect to processor 0.1"
targets -set -nocase -filter {name =~ "Cortex-A78AE #0.1*"}

puts stderr "reseting processor"
rst -processor


puts stderr "download provision elf"
dow [lindex $argv 0]
con

after 10000
stop
rst -system
disconnect

puts stderr "UFS provision should be finished"
# below line is required for print_progress
puts "UFS provision should be finished"
exit
