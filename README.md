# Embedded Platform BootFW Update Tool

## NOTE: Stable version of this utility with corresponding readme and bin folder are in the release area. This readme corresponds to V4.0 release.

This repository provides a utility to update AMD ACAP's (Adaptive Compute Acceleration Platform aka Adaptive SoC) flash device (OSPI or QSPI) with boot firmware in supported platforms. The current supported platforms are:

* [Embedded+](https://www.amd.com/en/products/embedded/embedded-plus.html) products
   * [Edge+ VPR-4616](https://www.sapphiretech.com/en/commercial/edge-plus-vpr_4616) Versal OSPI update
   * Rhino Versal OSPI update
* Kria production SOM QSPI update (K26, K24c, K24i)
* Versal OSPI update for the following Versal Eval platforms:
     * VHK158, production silicon
     * VEK280, ES1, production silicon
     * VRK160, ES1 silicon
     * VEK385, revA, revB

## External Components and one time setup Required

### On Embedded+ based platforms

Current Embedded+ platforms have a Versal and a Ryzen device. Versal firmware update expects that Ryzen is already running Ubuntu, as the firmware update would be performed from Ryzen. The Ryzen is the Linux host on Embedded+ platforms. Therefore, all the components required to either log onto Ryzen Ubuntu via keyboard+mouse+monitor, network access and ssh, is required and not listed below.

On Embedded Plus platform, there are capabilities to set bootmode to JTAG and reset the board through FTDI GPIO and that is being leveraged by the script.

On Rhino platform, there isnt a way to set bootmode using FTDI GPIO. Therefore, if there's program already in OSPI that prevents subsequent programs to access OSPI or DDR, script will not work. In that case, set bootmode to JTAG on the board using physical jumpers, power cycle, and then use this utility again.

### On Versal Evaluation platforms

On Versal eval platforms such as VHK158, there's a system controller that has access to Versal. System Controller will be the Linux host on these platform to run this utility to update Versal's OSPI.

### On Kria platforms

Kria platforms only has a Versal device, thus an external Linux host connected to
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

In the current code base - if the host Linux has network access to github.com - the bin.zip is automatically downloaded, and unzipped into the right directly. However, if there is network restrictions - then manual download method specified in previous paragraph is required.

*** Important! You must download and use the bin.zip file from release area for Kria and embedded plus platforms. Do not copy your own boot.bin files to the bin/ folder. Do not use the BOOT*.bin files in bin/ folder as an input to -i . They are jtag boot binary files created to boot u-boot with jtag uart instead of physical uart ***

Make ```prog_spi.sh``` executable:

      ```
      sudo chmod +x prog_spi.sh
      ```

## Programming Flash Device

Move <boot.bin> that you want to program into OSPI onto filesystem on Ryzen/host OS Ubuntu.

prog_spi.sh is used to program OSPI:

```
Default Usage: ./prog_spi.sh -i <path_to_boot.bin> -d <board_type>
    -i <file>      : Bin file to write into OSPI/QSPI, can be a .bin or a gzip of the .bin file
    -d <board>     : Board type.  Supported values
                     embplus, rhino, kria_k26, kria_k24c,
                     kria_k24i, versal_eval
    -b <boot_file> : Optional argument to override jtag boot.bin, for Versal only
    -s <SOCK #>    : Optional argument to specify remote uart SOCK number
    -p             : Optional argument program SPI, this is set by default except if -v or -b is present
    -v             : verification of flash content, if -pv are both present, tool will program and verify. if only -v is set, tool will  verify content of SPI against -i  <file> without programming
    -c             : check if flash is blank/erased
    -e             : erase flash
    -V             : verbose logging
    -w             : optional argument to connect to remote hardware server, use IP address or machine name shown by hw_server (without :3121), not supported for embplus"
    -M		   : optional argument to add memory check to make sure DDR used by script does not overlap u-boot reserved memory region
    -h             : help
Example usages:
to program in verbose mode:
     ./prog_spi.sh -i <path_to_boot.bin> -d <board_type> -V
to program with explicit -p and in verbose mode:
     ./prog_spi.sh -p -i -V <path_to_boot.bin> -d <board_type>
to program and verify:
     ./prog_spi.sh -pv -i <path_to_boot.bin> -d <board_type>
to verify only:
     ./prog_spi.sh -v -i <path_to_boot.bin> -d <board_type>
to check if SPI is blank:
     ./prog_spi.sh -c -d <board_type>
to erase:
     ./prog_spi.sh -e -d <board_type>
to erase and check that SPI is blank:
     ./prog_spi.sh -ec -d <board_type>
to program a remote hw_server target in verbose mode"
     ./prog_spi.sh -Vp -d <board_type> -i <path_to_boot.bin> -w <remote machine name or IP addr> "
```

execute this command to program OSPI:

for Embedded+:
```
./prog_ospi.sh -i <boot.bin> -d embplus
```

for RHINO:
```
./prog_ospi.sh -i <boot.bin> -d rhino
```

for Kria Production SOM:
```
#k26c or k26i:
./prog_spi.sh -i <boot.bin> -d kria_k26
#k24c:
./prog_spi.sh -i <boot.bin> -d kria_k24c
#k24i:
./prog_spi.sh -i <boot.bin> -d kria_k24i
```

for VHK158/VEK280/VEK385, use -d versal_eval and script will automatically check if it is running on one of the supported systems:
```
./prog_spi.sh -i <boot.bin> -d versal_eval
```

When the script finishes (in about 4 minutes), the flash will have been updated with <boot.bin>.

### Advanced users

#### -b option

For other versal-based systems, you may create your own boot.bin file that boots u-boot over jtag uart, and then use -b <boot_file> to pass in the boot.bin. The u-boot created must use jtag uart instead of physical uart, and have access to DDR and OSPI. The command would look like below for a Versal based board:

```
./prog_spi.sh -i <boot.bin to program into OSPI> -d versal_eval -b <boot.bin that uses jtag uart>
```

#### -w option

The -w option allows you to connect the target system on one machine that may not be able to run this script, and then run this script from a diff machine to program, erase, or verify OSPI. Make sure to start hw_server through default port 3121 on the machine connected to target machine.

If the target machine is a Versal eval platform, then hw_server is automatically started on the system controller for Versal eval platform. curl command over port 80 is used to call sc_app/sc_cmd on system controller to control the system. the IP address passed in through -w is that of the system controller.

The -w option is not supported for embplus platform due to the need to directly access GPIOs to put the system in JTAG mode and the system lack a default http server to enable curl commands, like that of SC for Versal eval platform.

## Known issues and Debug Tips

* Intermittent OSPI update timeout on Versal Devices:
    Occassionally updating the OSPI in Versal encounters timeout during the programming process:
    ```
  	    received on term:  Updating, 1% 780335 B/sjedec_spi_nor flash@0: flash operation timed out
	    received on term:
	    received on term:  SPI flash failed in write step
    ```

    or:

    ```
	    received on term:  Updating, 54% 2021462 B/sQSPI: QSPI is still busy after poll for 5000 ms.
	    received on term:  
	    received on term:  SPI flash failed in erase step
    ```

    The issue occurs sporadically, approximately once every 20 to 30 update attepts - and is generally transcient. 
    workaround: re-run the programming command, the update typically succeeds on a subsequent attempt. 

* If the script is stopped during execution, Versal may get in an indeterminate state. If you have issues running the script subsequently, power cycle the platform (not just a reboot) and try the script again.

* The tool will attempt to put the Versal in JTAG bootmode - via FTDI if that is available on the platform and always via XSDB. If the platform is in OSPI mode and OSPI already contains boot code that prevents access to DDR and OSPI from the utility - you may need to change platform to JTAG bootmode via hardware jumpers to prevent OSPI code from executing.

* You may ignore the "rlwrap" warnings.

* On the Embedded Plus platform only, the Versal device and the System Controller share an I²C bus without an arbiter. Depending on the firmware programmed on each subsystem, a race condition may occur between the System Controller and the Versal, resulting in a non-functional I²C bus. This script relies on the I²C bus, and when the race condition occurs you may see errors such as:
  
  ERROR: failed to connect to socket: Connection refused
  
  Error: Board ID or Silicon Revision not found or empty.
  
  Error: Script failed - Unable to identify board type.

  Workaround: To avoid the I²C race condition, hold the Versal in reset until the System Controller has fully booted, it then allows programming of a new BOOT.BIN file.
  


# License
(C) Copyright 2024, Advanced Micro Devices Inc.\
SPDX-License-Identifier: MIT
