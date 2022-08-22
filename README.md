# os

- Architecture Target: 64-bit ARMv8, i.e. aarch64/arm64
- Hardware Target: Michelle's Pi 3 Model B
- RAM: 1GB

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

  # Or use Zig:
  zig build dump
  ```

- Run the kernel in QEMU:
  ```
  qemu-system-aarch64 -M raspi3b -serial null -chardev stdio,id=uart1 -serial chardev:uart1 -kernel ./zig-out/bin/kernel8.img

  # Or use Zig:
  zig build run
  ```

## Useful Resources
- Aarch64 Calling Convention - https://hev.cc/3052.html
- Pi General - https://wiki.osdev.org/Raspberry_Pi_Bare_Bones
- Pi 3 - https://github.com/s-matyukevich/raspberry-pi-os
- Pi 4 - https://www.rpi4os.com/
- Some maybe-useful ARMv8 info - https://m.youtube.com/watch?v=6OfIzhuw1RE
