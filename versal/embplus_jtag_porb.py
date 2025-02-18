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


def get_ftdi_url(target_label="VE2302", target_interface="/1"):
    try:
        # Run the command and capture output (without sudo)
        result = subprocess.run(["ftdi_urls.py"], capture_output=True, text=True)
        output = result.stdout

        # Iterate through lines and look for the target device
        for line in output.splitlines():
            if target_label in line and target_interface in line:
                match = re.search(r"(ftdi://ftdi:4232:[^/]+/1)", line)
                if match:
                    return match.group(1)  # Return the matching FTDI URL

    except subprocess.CalledProcessError as e:
        print(f"Error running ftdi_urls.py: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)
    
    print("Error: No matching FTDI URL found.", file=sys.stderr)
    sys.exit(1)
    
    return None

if __name__ == "__main__":


    # Assign FTDI URL
    ftdi_url = get_ftdi_url()

    if ftdi_url:
        print(f"FTDI URL: {ftdi_url}")
    else:
        print("No matching FTDI URL found. should not reach here")
        sys.exit(1)
    
    gpio = GpioAsyncController()
    gpio.configure(ftdi_url, direction=0xC0)
    gpio.write(0x80)
    
    gpio = GpioAsyncController()
    gpio.configure(ftdi_url, direction=0x80)
    gpio.write(0x80)


