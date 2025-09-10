# Debian on SolidRun Boards - Layerscape LX2xxx

This page provides instructions for installing official [Debian from debian.org](https://www.debian.org/) on SolidRun Layerscape platforms.

## Supported Devices

- LX2160A COM-Express Type 7
  - Clearfog-CX
  - Honeycomb
- LX2162A SoM
  - Clearfog

## Creating Installer Media

SolidRun provides prebuilt installer disk images:

- [Debian Bookworm (13)](https://images.solid-run.com/Pure-Debian/arm64/13/)

Download an image above, decompress and write it to a suitable installation media such as USB flash drive or SD-Card, e.g. using `dd` or [etcher.io](https://etcher.io/)
The installer media **can not be used as installation destination**: E.g. when installing Debian to SD-Card, Installer must be on USB Drive.

Latest versions can always be prepared using the scripts in [this project](?tab=readme-ov-file#creating-installation-media).

## Install SoC Bootloader

- Set Boot-Switches for microSD according to our [Quick-Start Guide](https://solidrun.atlassian.net/wiki/spaces/developer/pages/197494288/HoneyComb+LX2+ClearFog+CX+LX2+Quick+Start+Guide#Boot-Select)

- Boot from microSD with an [image of ls-6.6..52-2.2.0 release](https://images.solid-run.com/LX2k/lx2160a_build/ls-6.6.52-2.2.0). Pick according to your hardware:

  - LX2162A Clearfog: `lx2162a_rev2_som_clearfog_multi_2000_650_2900_18_9_0-xxxxxxx.img.xz`

  - LX2160A Honeycomb:

    - DDR4-2400: `lx2160a_rev2_cex7_honeycomb_multi_2000_700_2400_8_5_2-xxxxxxx.img.xz`
    - DDR4-2600: `lx2160a_rev2_cex7_honeycomb_multi_2000_700_2600_8_5_2-xxxxxxx.img.xz`
    - DDR4-2900: `lx2160a_rev2_cex7_honeycomb_multi_2000_700_2900_8_5_2-xxxxxxx.img.xz`

  - LX2160A Clearfog-CX (board rev. 1.2+ with QSFP connector only):

    - DDR4-2400: `lx2160a_rev2_cex7_clearfog-cx_multi_2000_700_2400_8_5_2-xxxxxxx.img.xz`
    - DDR4-2600: `lx2160a_rev2_cex7_clearfog-cx_multi_2000_700_2600_8_5_2-xxxxxxx.img.xz`
    - DDR4-2900: `lx2160a_rev2_cex7_clearfog-cx_multi_2000_700_2900_8_5_2-xxxxxxx.img.xz`

- Install U-Boot to SPI Flash according to our [Reference BSP Documentation](https://github.com/SolidRun/lx2160a_build/tree/develop-ls-6.6.52-2.2.0?tab=readme-ov-file#spi-boot)

- Set Boot-Switches for SPI Flash according to our [Quick-Start Guide](https://solidrun.atlassian.net/wiki/spaces/developer/pages/197494288/HoneyComb+LX2+ClearFog+CX+LX2+Quick+Start+Guide#Boot-Select)

- Boot to U-Boot from SPI and configure for Debian:

  ```
  setenv boot_scripts boot.scr
  setenv bootargs arm-smmu.disable_bypass=0
  saveenv
  ```

## Boot Installer

- connect installation media
- connect serial console
- connect ethernet

Then power on.
U-Boot will start - showing a timeout prompt before cycling through known boot targets:

```
U-Boot 2024.04 (Jul 17 2024 - 07:26:18 +0000)

SoC:   MV88F6828-A0 at 1600 MHz
DRAM:  1 GiB (800 MHz, 32-bit, ECC not enabled)
Core:  38 devices, 22 uclasses, devicetree: separate
MMC:   mv_sdh: 0
Loading Environment from SPIFlash... SF: Detected w25q32 with page size 256 Bytes, erase size 4 KiB, total 4 MiB
OK
Model: SolidRun Clearfog A1
Board: SolidRun Clearfog Base
Net:   eth1: ethernet@70000, eth2: ethernet@30000, eth3: ethernet@34000
Hit any key to stop autoboot:  3
```

Boot targets can be inspected by printing the `boot_targets` variable from u-boot console:

```
=> print boot_targets
boot_targets=mmc0 usb0 scsi0 pxe dhcp
```

New units without an operating system on integrated storage will automatically boot into the debian installer media.
Boot of a specific media can be forced by combining a boot-target with `bootcmd_*`, e.g.:

    # boot from USB drive
    run bootcmd_usb0

## Known Issues / Workarounds

### SD-Card not accessible from Linux

Upstream corrupts pinmux at runtime as part of i2c bus recovery (see [here](https://lore.kernel.org/r/f32c5525-3162-4acd-880c-99fc46d3a63d@solid-run.com) for details).

LS-6.6.52-2.2.0 based SolidRun BSP includes a workaround, ensure to use binaries from [ls-6.6.52-2.2.0 branch](https://images.solid-run.com/LX2k/lx2160a_build/ls-6.6.52-2.2.0/).

### LX2162A Clearfog RJ45 ports not functional

The ethernet phy driving the 8x RJ45 ports is not yet supported in upstream Linux.
Use SFP ports or USB ethernet adapter for connectivty.
