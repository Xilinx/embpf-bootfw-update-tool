# Embedded Platform BootFW Update Tool

This repository provides a utility to update AMD ACAP's (Adaptive Compute Acceleration Platform aka Adaptive SoC) flash device (OSPI or QSPI) with boot firmware in supported platforms. The current supported platforms are:

* [Embedded+](https://www.amd.com/en/products/embedded/embedded-plus.html) products
   * [Edge+ VPR-4616](https://www.sapphiretech.com/en/commercial/edge-plus-vpr_4616) Versal OSPI update
* Rhino Versal OSPI update
* Kria production SOM QSPI update (K26, K24c, K24i)

## External Components and one time setup Required

### On Embedded+ based platforms

Current Embedded+ platforms have a Versal and a Ryzen device. Versal firmware update expects that Ryzen is already running Ubuntu, as the firmware update would be performed from Ryzen. Therefore, all the components required to either log onto Ryzen Ubuntu via keyboard+mouse+monitor, network access and ssh, is required and not listed below.

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

Lastly, clone this repo on Ryzen's Ubuntu.  Find ```prog_spi.sh``` in the cloned folder. Then look in the "tag" area of this repo, choose the latest release, download the ```bin.zip``` files from the release, unzip and place the bin/ folder in the same folder as ```prog_spi.sh```. (You may also download source code from the tagged release instead of cloning it).

Make ```prog_spi.sh``` executable:

      ```
      sudo chmod +x prog_spi.sh
      ```

## Programming Flash Device

Move <boot.bin> that you want to program into OSPI onto filesystem on Ryzen/host OS Ubuntu.

execute this command to program OSPI:

for Embedded+:
```
sudo ./prog_spi.sh <boot.bin> -embplus
```

for RHINO:
```
sudo ./prog_spi.sh <boot.bin> -rhino
```

for Kria Production SOM:
```
#k26c or k26i:
sudo ./prog_spi.sh <boot.bin> -kria_k26
#k24c:
sudo ./prog_spi.sh <boot.bin> -kria_k24c
#k24i:
sudo ./prog_spi.sh <boot.bin> -kria_k24i
```

When the script finishes (in about 4 minutes), the flash will have been updated with <boot.bin>.

## Known issues and Debug Tips

* If the script is stopped during execution, Versal may get in an indeterminate state. If you have issues running the script subsequently, power cycle the platform (not just a Ryzen reboot) and try the script again.

* Uncluttered uart output from Versal is also captured in uart_output.log in the same folder. You may read it for debugging purposes.

* You may ignore the "rlwrap" warnings.

# License
(C) Copyright 2024, Advanced Micro Devices Inc.\
SPDX-License-Identifier: MIT
