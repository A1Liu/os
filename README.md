# os

- Architecture Target: 64-bit ARMv8, i.e. aarch64/arm64
- Hardware Target: Michelle's Pi 3 Model B
- RAM: 1GB

## Build Dependencies
- Zig Compiler
- LLVM for `llvm-objdump` and `lldb`
- QEMU for running in a virtual machine

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
- Pi 3 Tutorial - https://github.com/s-matyukevich/raspberry-pi-os
- Another Pi 3 Tutorial - https://github.com/bztsrc/raspi3-tutorial/
- Aarch64 Calling Convention - https://hev.cc/3052.html
- Aarch64 barriers - https://developer.arm.com/documentation/100941/0101/Barriers
- Aarch64 shareability - https://developer.arm.com/documentation/den0024/a/Memory-Ordering/Memory-attributes/Cacheable-and-shareable-memory-attributes
- Aarch64 Address Translation Stage (different from levels) - https://developer.arm.com/documentation/102142/0100/Stage-2-translation
- Buddy allocator example code - https://github.com/a2liu/dumboss/blob/main/kern/memory.c
- Pi General - https://wiki.osdev.org/Raspberry_Pi_Bare_Bones
- Pi 4 - https://www.rpi4os.com/
- Quick-reference for instructions - https://courses.cs.washington.edu/courses/cse469/19wi/arm64.pdf
- Some maybe-useful ARMv8 info - https://m.youtube.com/watch?v=6OfIzhuw1RE
- Frame buffer - https://forums.raspberrypi.com/viewtopic.php?t=155825
- Ask GPU where its memory is - https://forums.raspberrypi.com/viewtopic.php?t=209388

## Doc Sources
- `RPi Model 3B+ Peripherals Manual.pdf` - https://github.com/raspberrypi/documentation/files/1888662/BCM2837-ARM-Peripherals.-.Revised.-.V2-1.pdf
- `ARM Clang Reference Manual.pdf` - https://documentation-service.arm.com/static/5f0db3ca62665459ec77bc02
- `ARMv8 Reference Manual.pdf` - https://documentation-service.arm.com/static/60119835773bb020e3de6fee
- `RPi Beginner Guide.pdf` - https://magpi.raspberrypi.com/books/beginners-guide-4th-ed

## Code Organization

Concept                 | Location
---                     | ---
Boot-up                 | `src/boot.S`
System Timer            | `src/interrupts.zig`
Interrupt Vectors       | `src/interrrupts.zig`
Page Table Init         | `src/boot.S`
MMU Protections         | `src/memory.zig`
Page Allocator          | `src/memory.zig`
Task Scheduler          | `src/scheduler.zig`
Mini-UART Handler       | `src/mmio.zig`
Linker Script           | `src/link.ld`
Frame Buffer            | `src/framebuffer.zig`
Mailboxes               | `src/mmio.zig`

## To Do
- Safety
  - Fix timer overflow
- Allocator
  - safety checks in allocator
  - handle GPU memory addresses in the allocator
- Debugging
  - switch from mini-uart to uart
  - receive data in UART
  - Debug shell
- Userspace Exe
  - remove identity mapping
  - FAT32 handler
  - syscalls and user-space executables
  - page mapping utilities
  - IPC queue?
