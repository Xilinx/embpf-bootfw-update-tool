#!/usr/bin/env python3

###############################################################################
# Copyright (c) 2022 - 2024, Advanced Micro Devices, Inc.  All rights reserved.
# SPDX-License-Identifier: MIT
###############################################################################


import sys

from pyftdi.gpio import (GpioAsyncController,
                         GpioSyncController,
                         GpioMpsseController)

if __name__ == "__main__":
    ftdi_url = "ftdi://ftdi:4232:000000000000/1"
    
    gpio = GpioAsyncController()
    gpio.configure(ftdi_url, direction=0xC0)
    gpio.write(0x80)
    
    gpio = GpioAsyncController()
    gpio.configure(ftdi_url, direction=0x80)
    gpio.write(0x80)


