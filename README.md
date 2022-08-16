# os

Architecture Target: 64-bit ARMv8, i.e. aarch64/arm64
Hardware Target: Pi 3 Model B
RAM: 1GB

## Build Dependencies
- Zig Compiler
- LLVM
- QEMU for running in a virtual machine

## Confusing Behavior
- `-Drelease-small` doesn't output anything to UART but `-Drelease-fast` does

## Useful Commands
- Dump out the kernel ELF file:
  ```
  llvm-objdump --arch-name=aarch64 -D ./zig-out/bin/kernel.elf > ./obj.txt
  ```

- Run the kernel in QEMU:
  ```
  qemu-system-aarch64 -M raspi3b -serial null -chardev stdio,id=uart1 -serial chardev:uart1 -kernel ./zig-out/bin/kernel8.img

  # Or use Zig:
  zig build run
  ```

## Useful Resources
- Pi General - https://wiki.osdev.org/Raspberry_Pi_Bare_Bones
- Pi 3 - https://github.com/s-matyukevich/raspberry-pi-os
- Pi 4 - https://www.rpi4os.com/
