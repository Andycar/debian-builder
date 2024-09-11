# Debian on SolidRun Boards - 32-bit ARM with FPU

This page provides instructions for installing official [Debian from debian.org](https://www.debian.org/) on SolidRun 32-bit arm platforms.

## Supported Devices

- Armada 388 SoM:
  - Clearfog Base (since Debian 9)
  - Clearfog Pro (since Debian 9)
- Armada 388 Clearfog GTR S4 (since Debian 10)
- Armada 388 Clearfog GTR L8 (since Debian 10)

## Creating Installer Media

SolidRun provides prebuilt installer disk images:

- [Debian Bookworm (12)](https://images.solid-run.com/Pure-Debian/armhf/12/)

Download an image above, decompress and write it to a suitable installation media such as USB flash drive or SD-Card, e.g. using `dd` or [etcher.io](https://etcher.io/)
The installer media **can not be used as installation destination**: E.g. when installing Debian to SD-Card, Installer must be on USB Drive.

Latest versions can always be prepared using the scripts in [this project](?tab=readme-ov-file#creating-installation-media).

## Install SoC Bootloader

### Armada 38x Clearfog Base / Pro / GTR

Most boards shipped without a suitable version of U-Boot preinstalled.

Armada 38x has several options for boot sources - for best Debian experience installation is recommended to either SPI Flash or eMMC hardware boot partition:

- [SPI Flash](https://github.com/SolidRun/Documentation/blob/bsp/a38x/u-boot.md#installing-automatically-spi-emmc-m2-ssd) (recommended if available)
- [eMMC boot0/1](https://github.com/SolidRun/Documentation/blob/bsp/a38x/u-boot.md#emmc-boot0-partition)

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
