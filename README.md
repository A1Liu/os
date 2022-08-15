# os

Architecture Target: 64-bit ARMv8, i.e. aarch64/arm64
Hardware Target: Pi 3 Model B
RAM: 1GB

## Useful Resources
- Pi General - https://wiki.osdev.org/Raspberry_Pi_Bare_Bones
- Pi 3 - https://github.com/s-matyukevich/raspberry-pi-os
- Pi 4 - https://www.rpi4os.com/

## Useful Commands
- Dump out the kernel ELF file:

  `zig build kernel && llvm-objdump --arch-name=aarch64 -D ./zig-out/bin/kernel.elf > ./obj.txt`
