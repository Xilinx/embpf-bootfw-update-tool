# Embedded Platform BootFW Update Tool

## NOTE: Stable version of this utility with corresponding readme and bin folder are in the release area. This readme corresponds to V2.0 release.

This repository provides a utility to update AMD ACAP's (Adaptive Compute Acceleration Platform aka Adaptive SoC) flash device (OSPI or QSPI) with boot firmware in supported platforms. The current supported platforms are:

* [Embedded+](https://www.amd.com/en/products/embedded/embedded-plus.html) products
   * [Edge+ VPR-4616](https://www.sapphiretech.com/en/commercial/edge-plus-vpr_4616) Versal OSPI update
* Rhino Versal OSPI update
* Kria production SOM QSPI update (K26, K24c, K24i)

## External Components and one time setup Required

### On Embedded+ based platforms

Current Embedded+ platforms have a Versal and a Ryzen device. Versal firmware update expects that Ryzen is already running Ubuntu, as the firmware update would be performed from Ryzen. Therefore, all the components required to either log onto Ryzen Ubuntu via keyboard+mouse+monitor, network access and ssh, is required and not listed below.

On Embedded Plus platform, there are capabilities to set bootmode to JTAG and reset the board through FTDI GPIO and that is being leveraged by the script.

On Rhino platform, there isnt a way to set bootmode using FTDI GPIO. Therefore, if there's program already in OSPI that prevents subsequent programs to access OSPI or DDR, script will not work. In that case, set bootmode to JTAG on the board using physical jumpers, power cycle, and then use this utility again.

### On Kria platforms

Kria platforms only has a Versal device, thus a Linux host connected to
the Kria platform via USB cable is required.

### On all platforms

Ryzen or host OS Ubuntu must have HW_server (download [2024.1 here](https://account.amd.com/en/forms/downloads/xef.html?filename=Vivado_HW_Server_Lin_2024.1_0522_2023.tar.gz) or [2024.2 here](https://account.amd.com/en/forms/downloads/xef.html?filename=Vivado_HW_Server_Lin_2024.2_1113_1001.tar)) or [Vivado_lab](https://www.xilinx.com/support/download.html) installed to provide XSDB tool. HW_server has smaller footprint than Vivado_lab, so if neither are already installed, choose HW_server. To check to see if Vivado_Lab or HWSRVR has been installed, see if they can be found on the system:

```
sudo find / -iname Vivado_Lab
sudo find / -iname HWSRVR
```

These are the steps to install HW_server if none of them are installed:

1. uncompress downloaded installation file
2. Make installation files executable:
      ```
      chmod +x installLibs.sh && chmod +x xsetup
      ```
3. Run the installation scripts with superuser permissions:
      ```
      sudo ./installLibs.sh
      sudo ./xsetup
      ```
4. Click through menus
5. Run driver installation:
      ```
      sudo <HWSERVERInstall Dir>/data/xicom/cable_drivers/lin64/install_script/install_drivers/install_drivers
      ```
6. reboot the system,  this is required because we cannot physically unplug the cable as instructed by the installation process
      ```
      sudo reboot
      ```

### (all platforms) Download  and set up Utility

Lastly, go to [Releases](https://github.com/Xilinx/embpf-bootfw-update-tool/releases), find the latest release (V2.0), download it's "Source code" and "bin.zip". Unzip them in your Linux host.  Find ```prog_spi.sh``` in the source code folder. Then place the bin/ folder from bin.zip in the same folder as ```prog_spi.sh```.

*** Important! You must download and use the bin.zip file from release area for Kria and embedded plus platforms. Do not copy your own boot.bin files to the bin/ folder. Do not use the BOOT*.bin files in bin/ folder as an input to -i . They are special binary files created to boot u-boot with jtag uart instead of physical uart ***

Make ```prog_spi.sh``` executable:

      ```
      sudo chmod +x prog_spi.sh
      ```

## Programming Flash Device

Move <boot.bin> that you want to program into OSPI onto filesystem on Ryzen/host OS Ubuntu.

prog_spi.sh is used to program OSPI:

```
Usage: ./prog_spi.sh -i <path_to_boot.bin> -d <board_type>
    -i <file>      : File to write to OSPI/QSPI
    -d <board>     : Board type.  Supported values
                     embplus, rhino, kria_k26, kria_k24c,
                     kria_k24i, versal_eval
    -b <boot_file> : Optional argument to override programming boot.bin
    -h             : help
```

execute this command to program OSPI:

for Embedded+:
```
sudo ./prog_ospi.sh -i <boot.bin> -d embplus
```

for RHINO:
```
sudo ./prog_ospi.sh -i <boot.bin> -d rhino
```

for Kria Production SOM:
```
#k26c or k26i:
sudo ./prog_spi.sh -i <boot.bin> -d kria_k26
#k24c:
sudo ./prog_spi.sh -i <boot.bin> -d kria_k24c
#k24i:
sudo ./prog_spi.sh -i <boot.bin> -d kria_k24i
```

When the script finishes (in about 4 minutes), the flash will have been updated with <boot.bin>.

### Advanced users

For other systems, you may create your own boot.bin file that boots u-boot over jtag uart, and then use -b <boot_file> to pass in the boot.bin. The u-boot created must use jtag uart instead of physical uart, and have access to DDR and OSPI. The command would look like below for a Versal based board:

```
sudo ./prog_spi.sh -i <boot.bin to program into OSPI> -d versal_eval -b <boot.bin that uses jtag uart>
```

## Known issues and Debug Tips

* Current version of script depends on physical uart to interact with u-boot. the UART may not always enumerate to the same /dev/ttyUSB*. to overwrite it in the case that it enumerates to a different device than what the script assumed, use -p flag to overwrite uart device location, such as:

``` sudo ./prog_ospi.sh -i <boot.bin> -d rhino -p /dev/ttyUSB0```

* If the script is stopped during execution, Versal may get in an indeterminate state. If you have issues running the script subsequently, power cycle the platform (not just a Ryzen reboot) and try the script again.

* You may ignore the "rlwrap" warnings.

# License
(C) Copyright 2024, Advanced Micro Devices Inc.\
SPDX-License-Identifier: MIT
