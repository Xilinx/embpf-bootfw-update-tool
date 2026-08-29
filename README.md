# Embedded Platform Flash Update Tool

## NOTE: Stable version of this utility with corresponding readme and bin folder are in the release area. This readme corresponds to V7.2 release.

This repository provides a utility to update AMD ACAP's (Adaptive Compute Acceleration Platform aka Adaptive SoC) flash device (OSPI, QSPI, UFS or eMMC) with boot firmware or disk image in supported platforms. The current supported platforms are:

* [Embedded+](https://www.amd.com/en/products/embedded/embedded-plus.html) products
   * [Edge+ VPR-4616](https://www.sapphiretech.com/en/commercial/edge-plus-vpr_4616) Versal OSPI update
   * [Edge+ VPR-5050](https://www.sapphiretech.com/en/commercial/edge-plus-vpr_5050) Versal OSPI update
   * [Edge+ VPR-5050a](https://www.sapphiretech.com/en/commercial/edge-plus-vpr_5050a) Versal OSPI update
   * Rhino Versal OSPI update
* Kria production SOM QSPI and eMMC update (K26, K24c, K24i)
* Versal Eval platforms:
     * VRK160 : OSPI update
     * VRK165 : OSPI update
     * VEK385, revA: OSPI update
     * VEK385, revB: OSPI and UFS update
     * VEK386, OSPI and UFS update
     * VPK360, OSPI update
* Spartan UltraScale+
     * SCU200
* Versal OSPI update for Alveo Acelerator
     * V80


Note that below boards are unsupported in this version due to older System Controller image and sc_app version - use V5.0 release:

* VHK158, production silicon
* VEK280, ES1, production silicon



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

Ryzen or host OS Ubuntu must have HW_server (download [2024.1 here](https://account.amd.com/en/forms/downloads/xef.html?filename=Vivado_HW_Server_Lin_2024.1_0522_2023.tar.gz) or [2024.2 here](https://account.amd.com/en/forms/downloads/xef.html?filename=Vivado_HW_Server_Lin_2024.2_1113_1001.tar) or [2025.1 here](https://account.amd.com/en/forms/downloads/xef.html?filename=Vivado_HW_Server_Lin_2025.1_0530_0145.tar) or [2025.2 here](https://account.amd.com/en/forms/downloads/xef.html?filename=Vivado_HW_Server_Lin_2025.2_1114_2157.tar)) or [Vivado_lab](https://www.xilinx.com/support/download.html) installed to provide XSDB tool. HW_server has smaller footprint than Vivado_lab, so if neither are already installed, choose HW_server. To check to see if Vivado_Lab or HWSRVR has been installed, see if they can be found on the system:

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

prog_spi.sh is used to program OSPI. It can also be used to program UFS and eMMC on supported platforms.

```
Default Usage: ./prog.sh -i <path_to_boot.bin> -d <board_type>
    -S             : target SPI memory - this is default if no -S or -U is present
    -U             : target UFS memory. Currently only support:
                     VEK385
    -E             : target eMMC memory. Currently only support:
                     Kria platforms: kria_k26, kria_k24c, kria_k24i
    -i <file>      : Payload file to write into OSPI/QSPI/UFS
                     if SPI - can be a .bin or a gzip of the .bin file
                     if UFS/eMMC, have to be a gzip of the wic image
    -d <board>     : Board type.  Supported values
                     embplus(defaults to 4616), embplus_4616
		       embplus_5050, embplus_5050a
                     rhino, v80
                     kria_k26, kria_k24c, kria_k24i
                     versal_eval, mbv(MicroBlaze-V)
    -b <boot_file> : Optional argument to override jtag boot.bin, for Versal only
    -s <SOCK #>    : Optional argument to specify remote uart SOCK number
    -p             : Optional argument program SPI, this is set by default except
                     if -v or -b is present
    -a             : Optional argument for address of start of SPI programming in hex
                     this is default 0x0
    -v             : verification of flash content, if -pv are both present,
                     tool will program and verify. if only -v is set, tool will
                     verify content of SPI against -i  <file> without programming
    -c             : check if flash is blank/erased
    -e             : erase flash
    -u             : indicate for UFS programming, that the wic.gz file in -i option
                     is in USB drive. Supported only for UFS programming
    -V             : verbose logging
    -M             : optional argument to add memory check to make sure DDR used - in 7.0 and newer release this is default
    -N             : optional argument to remove memory check that make sure DDR used
                     by script does not overlap u-boot reserved memory region
    -w             : optional argument to connect to remote hardware server, use
                     IP address or machine name shown by hw_server (without :3121).
                     not supported for embplus/rhino systems
    -h             : help
Example usages:
to program SPI in verbose mode:
     ./prog.sh -i <path_to_boot.bin> -d <board_type> -V
to program SPI with explicit -p and in verbose mode:
     ./prog.sh -p -i -V <path_to_boot.bin> -d <board_type>
to program SPI and verify:
     ./prog.sh -pv -i <path_to_boot.bin> -d <board_type>
to verify SPI only:
     ./prog.sh -v -i <path_to_boot.bin> -d <board_type>
to check if SPI is blank:
     ./prog.sh -c -d <board_type>
to erase SPI:
     ./prog.sh -e -d <board_type>
to erase and check that SPI is blank:
     ./prog.sh -ec -d <board_type>
to program SPI and verify on MicroblazeV based board (scu200) and program starting addr 0xA0000 instead of 0x0:
     ./prog.sh -pv -i <path_to_binary> -d mbv -a 0xA0000
to program a remote hw_server target in verbose mode
     ./prog.sh -Vp -d <board_type> -i <path_to_boot.bin> -w <remote machine name or IP addr> 
to program UFS in verbose mode:
     ./prog.sh -i <path_to_boot.bin> -d versal_eval -V -U
to program eMMC in verbose mode:
     ./prog.sh -i <path_to_boot.bin> -d <board_type> -V -E
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

for Kria Production SOM, to program QSPI:
```
#k26c or k26i:
./prog_spi.sh -i <boot.bin> -d kria_k26
#k24c:
./prog_spi.sh -i <boot.bin> -d kria_k24c
#k24i:
./prog_spi.sh -i <boot.bin> -d kria_k24i
```

for VHK158/VEK280/VEK385/VRK160/VRK165/VEK386/VPK360, use -d versal_eval and script will automatically check if it is running on one of the supported systems:
```
./prog_spi.sh -i <boot.bin> -d versal_eval
```

for SCU200, use -d mbv and MicroBlaze based system may require starting address to be something other than 0x0 (such as 0xA0000):
```
./prog_spi.sh -i <boot.bin> -d mbv -a 0xA0000
```

When the script finishes (in about 4 minutes), the flash will have been updated with <boot.bin>.

For eMMC and UFS programming, it is recommended to use -verbose mode to monitor progress, as wic images are much larger, downloading the .gz file and writing to memory takes on the scale of 30 minutes, depending on wic image size and JTAG connection speed.

for Kria Production SOM, to program eMMC:
```
#k26c or k26i:
./prog_spi.sh -i <wic.gz> -d kria_k26 -E -V
#k24c:
./prog_spi.sh -i <wic.gz> -d kria_k24c -E -V
#k24i:
./prog_spi.sh -i <wic.gz> -d kria_k24i -E -V
```
for VEK385, to program UFS:
```
./prog_spi.sh -i <wic.gz> -d versal_eval -U -V
```


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

* Script does not support programing OSPI on systems with multiple possible targets. For an example, it does not support programming on a host with more than 1 V80 cards.

* certificate error:
	The script need to download bin.zip file from github, and if timestamp on the OS is not correct, it may fail with certification error:

	```
		Connecting to github.com|140.82.114.4|:443... connected.
		ERROR: The certificate of ‘github.com’ is not trusted.
		ERROR: The certificate of ‘github.com’ is not yet activated.
	```

	To fix it, manually set time to the correct time, example:

	```
		sudo date -s "2026-02-10 03:30:00"
	```
* Intermittent Versal target errors
	On some Versal platforms, intermittent errors may occur where xsdb is unable to connect to the target:
	```
		Switching to JTAG boot mode: AHB AP transaction error, DAP status 0x30000023
	```

	If this occurs, rerun the command. If the issue persists, power-cycle the platform and try again.

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
    or:
    
    ```
    	Error: Script failed to extract a valid JTAG UART socket number. 
		Output was: ERROR: Could not find a suitable Cortex-A72 or A78 core SC 0x0 FTDI 0x1 EXT 0x2 
    ```

    The issue occurs sporadically, approximately once every 20 to 30 update attepts - and is generally transcient. 
    workaround: re-run the programming command, the update typically succeeds on a subsequent attempt. 

* If the script is stopped during execution, Versal may get in an indeterminate state. If you have issues running the script subsequently, power cycle the platform (not just a reboot) and try the script again.

* The tool will attempt to put the Versal in JTAG bootmode - via FTDI if that is available on the platform and always via XSDB. If the platform is in OSPI mode and OSPI already contains boot code that prevents access to DDR and OSPI from the utility - you may need to change platform to JTAG bootmode via hardware jumpers to prevent OSPI code from executing.

* You may ignore the "rlwrap" warnings.

* on the embplus platforms, the Linux image sometimes requires privileged access to FTDI. If this error is seen, rerun prog_spi.sh call with sudo:

  ```ValueError: The device has no langid (permission issue, no string descriptors supported or device error)```

* On the versal_eval platform only, the Versal device and the System Controller share an I²C bus without an arbiter. Depending on the firmware programmed on each subsystem, a race condition may occur between the System Controller and the Versal, resulting in a non-functional I²C bus. This script relies on the I²C bus, and when the race condition occurs you may see errors such as:
  
  ERROR: failed to connect to socket: Connection refused
  
  Error: Board ID or Silicon Revision not found or empty.
  
  Error: Script failed - Unable to identify board type.

  Workaround: To avoid the I²C race condition, hold the Versal in reset until the System Controller has fully booted, it then allows programming of a new BOOT.BIN file.
  
* in UFS/eMMC programming - incorrect size reported by `gzwrite` for images larger than 4 GiB

  For gzip-compressed images with an uncompressed size larger than 4 GiB, `gzwrite` may report messages such as:

  ```text
  uncompressed 4958212096 of 663244800
  crcs == 0xf839413b/0xf839413b
  ```

  This does **not** indicate a programming failure.

  The gzip format stores the original file size in a 32-bit field (ISIZE), which contains only:

  ```text
  uncompressed_size mod 2^32
  ```

  For files larger than 4 GiB, the true uncompressed size cannot be determined from the gzip file alone. As a result, `gzwrite` may display the truncated ISIZE value (`663244800` bytes in this example) instead of the actual size (`4958212096` bytes). This is an inherent limitation of the gzip format.

  `gzwrite` continues decompressing until the end of the gzip stream, so programming is not affected. The matching CRC values confirm successful decompression.



# License
(C) Copyright 2024, Advanced Micro Devices Inc.\
SPDX-License-Identifier: MIT
