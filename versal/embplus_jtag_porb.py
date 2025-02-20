#!/usr/bin/env python3

###############################################################################
# Copyright (c) 2022 - 2024, Advanced Micro Devices, Inc.  All rights reserved.
# SPDX-License-Identifier: MIT
###############################################################################


import sys
import subprocess
import re

from pyftdi.gpio import (GpioAsyncController,
                         GpioSyncController,
                         GpioMpsseController)



if __name__ == "__main__":

    with open("/sys/bus/usb/devices/3-1.4/serial", "r") as file:
        serial = file.read().strip()
    ftdi_url = f"ftdi://ftdi:4232:{serial}/1"

    print(f"FTDI URL: {ftdi_url}")
    
    gpio = GpioAsyncController()
    gpio.configure(ftdi_url, direction=0xC0)
    gpio.write(0x80)
    
    gpio = GpioAsyncController()
    gpio.configure(ftdi_url, direction=0x80)
    gpio.write(0x80)


