#!/usr/bin/env python3

from pyftdi.gpio import GpioAsyncController

if __name__ == "__main__":
    # If exactly one matching FTDI 0403:6011 is connected, this is enough.
    ftdi_url = "ftdi://0x403:0x6011/1"

    print(f"FTDI URL: {ftdi_url}")

    gpio = GpioAsyncController()
    gpio.configure(ftdi_url, direction=0xC0)
    gpio.write(0x80)
    gpio.close()

    gpio = GpioAsyncController()
    gpio.configure(ftdi_url, direction=0x80)
    gpio.write(0x80)
    gpio.close()

