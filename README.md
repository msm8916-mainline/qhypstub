# qhypstub
[qhypstub] is an open-source `hyp` firmware stub for Qualcomm MSM8916/APQ8016
that allows using the virtualization functionality built into the ARM Cortex-A53
CPU cores. Unlike the original (proprietary) `hyp` firmware from Qualcomm,
it allows booting Linux/KVM or other hypervisors in EL2. **As a stub, it does not
implement any hypervisor functionality**, it just "bridges the gap" to easily allow
using other hypervisors like KVM in Linux.

Overall, it has the following advantages compared to the original firmware from Qualcomm:
- Boot [Linux]/KVM or other operating systems in EL2 to enable virtualization functionality
- Directly boot [U-Boot] (or another aarch64 bootloader), without going through aarch32 [LK (Little Kernel)]
  - This works partially also with Qualcomm's `hyp` firmware, but breaks SMP/CPUidle there
    due to a bug in the proprietary PSCI implementation (part of TrustZone/TZ). [qhypstub]
    contains a workaround that avoids the problem.
- Open-source
- Minimal runtime overhead (written entirely in assembly, 4 KiB of RAM required)

Given that [qhypstub] is mostly based on trial and error - assembling it step by step
until most things were working (see commit log) - it is hard to say if there are any
disadvantages (i.e. features broken when using qhypstub because it is missing
some functionality). I was not able to find any broken functionality so far.

## Supported devices
For now, [qhypstub] works only on MSM8916/APQ8016 devices that have **secure boot disabled**.
It has been successfully tested on the following devices:

  - DragonBoard 410c (db410c/apq8016-sbc)
  - BQ Aquaris X5 (paella/picmt/longcheer-l8910)
  - Xiaomi Redmi 2 (wt88047)
  - Alcatel Idol 3 (4.7) (idol347)
    - **Note:** Only some hardware revisions have secure boot disabled.

It is designed to be a true drop-in replacement for the original `hyp` firmware,
and therefore supports all of the following usage scenarios:

- primary aarch64 bootloader (e.g. [U-Boot]) - started directly in EL2
- primary aarch32 bootloader (e.g. [LK (Little Kernel)]) - started in EL1
  - OS started in aarch64 EL2: requires [Try jumping to aarch64 kernel in EL2 using hypervisor call] patch applied to LK
  - OS started in aarch64 EL1: happens only when patch in LK is missing
  - OS started in aarch32 EL1 (e.g. original 32-bit Linux 3.10 kernel from Qualcomm)

## Installation
**WARNING:** The `hyp` firmware runs before the bootloader that provides the Fastboot interface. Be prepared to recover
your board using other methods (e.g. EDL) in case of trouble. DO NOT INSTALL IT IF YOU DO NOT KNOW HOW TO RECOVER YOUR BOARD!

After [building](#building) qhypstub and signing it, it is simply flashed to the `hyp` partition, e.g. using Fastboot:

```
$ fastboot flash hyp qhypstub-test-signed.mbn
```

**WARNING:** `qhypstub-test-signed.mbn` **works only on devices with secure boot disabled**.
Firmware secure boot is separate from the secure boot e.g. in Android bootloaders
(for flashing custom Android boot images or kernels). Unfortunately, it is enabled
on most production devices and (theoretically) cannot be unlocked. In that case,
[qhypstub] cannot easily be used at the moment. Sorry.

## Building
[qhypstub] can be easily built with just an assembler and a linker, through the [Makefile](/Makefile):

```
$ make
```

Unless you are compiling it on a aarch64 system you will need to specify a cross compiler, e.g.:

```
$ make CROSS_COMPILE=aarch64-linux-gnu-
```

Even on devices without secure boot, the resulting ELF file must be signed with automatically generated test keys.
To do that, you can use [qtestsign], which will produce the `qhypstub-test-signed.mbn` that you flash to your device.

```
$ ./qtestsign.py hyp qhypstub.elf
```

**Tip:** If you clone [qtestsign] directly into your [qhypstub] clone, running `make` will also automatically sign the binary!

## Technical overview
TBD

## License
[qhypstub] is licensed under the [GNU General Public License, version 2]. It is mostly based on trial and error,
assembling it step by step until most things were working (see commit log). Since the Cortex-A53 is a standard
ARMv8-A CPU, the [ARM Architecture Reference Manual for Armv8-A] describes most of the registers that are used
to initialize EL2/EL1. Also, similar code can be found in [Linux] and [U-Boot].

[qhypstub]: https://github.com/msm8916-mainline/qhypstub
[Linux]: https://www.kernel.org
[LK (Little Kernel)]: https://git.linaro.org/landing-teams/working/qualcomm/lk.git
[U-Boot]: https://www.denx.de/wiki/U-Boot
[Try jumping to aarch64 kernel in EL2 using hypervisor call]: https://github.com/msm8916-mainline/lk2nd/commit/8d840ad94c60f1f5ab0a95e886839454e03d8b86.patch
[qtestsign]: https://github.com/msm8916-mainline/qtestsign
[GNU General Public License, version 2]: https://www.gnu.org/licenses/old-licenses/gpl-2.0.html
[ARM Architecture Reference Manual for Armv8-A]: https://developer.arm.com/documentation/ddi0487/latest/
