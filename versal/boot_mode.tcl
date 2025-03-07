###############################################################################
# Copyright (c) 2022 - 2024, Advanced Micro Devices, Inc.  All rights reserved.
# SPDX-License-Identifier: MIT
###############################################################################


proc jtag_ready {} {
    connect

    set retry 0
    while {$retry < 25} {
        if {[string first "closed" "[jtag targets]"] != -1} {
            after 100
            incr retry
        } else {
            break
        }
    }
}

#
# Switch to JTAG boot mode #
#
proc switch_to_jtag {} {
	puts "Switching to jtag boot mode"
	# Enable ISO
	# PMC_GLOBAL.DOMAIN_ISO_CNTRL.{
	# VCCAUX_VCCRAM[18]=0x1, VCCRAM_SOC[17]=0x1, VCCAUX_SOC[16]=0x1,
	# PL_SOC[15]=0x1, PMC_SOC[14]=0x1, PMC_SOC_NPI[13]=0x1, PMC_PL[12]=0x1, 
	# PMC_PL_TEST[11]=0x1, PMC_PL_CFRAME[10]=0x0, PMC_LPD[9]=0x1, PMC_LPD_DFX[8]=0x1,  
	# LPD_PL[6]=0x1, LPD_PL_TEST[5]=0x1, LPD_CPM[4]=0x1, 
	# LPD_CPM_DFX[3]=0x1, FPD_SOC[2]=0x1, FPD_PL[1]=0x1, FPD_PL_TEST[0]=0x1}
	mwr -force 0xf1120000 0xffbff

	# Switch to JTAG boot mode
	# BOOT_MODE_USER.{alt_boot_mode[15:12]=0xe use_alt[8]=0x1, boot_mode[3:0]}
	mwr -force 0xf1260200 0x0100

	# Set Multi-boot address to 0
	mwr -force 0xF1110004 0x0

	# SYSMON_REF_CTRL is switched to NPI by user PDI so ensure its
	# switched back
	mwr -force 0xF1260138 0

	# RST_NONPS.{NOC_RESET[6]=0x1, NOC_POR[5]=0x1, NPI_RESET[4]=0x1, 
	# SYS_RST_1[2]=0x01, SYS_RST_2[1]=0x01, SYS_RST_3[0]=0x01}
	mwr -force 0xF1260320 0x77

	# Perform reset
	rst -system
}




#
# Set Versal to OSPI bootmode using XSDB/XSCT
# Switch to QSPI boot mode #
#
proc boot_ospi { } {
	puts "Switching to OSPI boot mode"

	tar -set -filter {name =~ "Versal *"}

	# Enable ISO
	# PMC_GLOBAL.DOMAIN_ISO_CNTRL.{
	# VCCAUX_VCCRAM[18]=0x1, VCCRAM_SOC[17]=0x1, VCCAUX_SOC[16]=0x1,
	# PL_SOC[15]=0x1, PMC_SOC[14]=0x1, PMC_SOC_NPI[13]=0x1, PMC_PL[12]=0x1, 
	# PMC_PL_TEST[11]=0x1, PMC_PL_CFRAME[10]=0x0, PMC_LPD[9]=0x1, PMC_LPD_DFX[8]=0x1,  
	# LPD_PL[6]=0x1, LPD_PL_TEST[5]=0x1, LPD_CPM[4]=0x1, 
	# LPD_CPM_DFX[3]=0x1, FPD_SOC[2]=0x1, FPD_PL[1]=0x1, FPD_PL_TEST[0]=0x1}
	mwr -force 0xf1120000 0xffbff

	# Switch to OSPI mode
	# BOOT_MODE_USER.{alt_boot_mode[15:12]=0xe use_alt[8]=0x1, boot_mode[3:0]}
	mwr 0xf1260200 0x08100
	mrd 0xf1260200

	# Set PMC_MULTI_BOOT address to 0
	mwr -force 0xf1110004 0x0

	# SYSMON_REF_CTRL is switched to NPI by user PDI so ensure its
	#  switched back
	mwr -force 0xf1260138 0

	# RST_NONPS.{NOC_RESET[6]=0x1, NOC_POR[5]=0x1, NPI_RESET[4]=0x1, 
	# SYS_RST_1[2]=0x01, SYS_RST_2[1]=0x01, SYS_RST_3[0]=0x01}
	mwr -force 0xf1260320 0x77

	# Perform reset
	tar -set -filter {name =~ "PMC"}
	#rst
	rst -type pmc-srst
	after 10
	tar -set -filter {name =~ "Versal *"}
	mrd -force 0xf1120000
}

