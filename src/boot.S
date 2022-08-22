#include "shared_values.h"

# Execution starts here
.global _start
.type _start, @function
_start:
  mrs     x1, mpidr_el1
  and     x1, x1, 3

  # Check processor ID is main core, else hang
  cbz     x1, main_core

# We're not on the main core, so infinite loop
proc_hang:
  wfe
  b       proc_hang

# Reduce privelege of the Kernel down to EL1. Since
# QEMU starts at EL2, but the Raspberry Pi 3b starts
# at EL3, we need to do some silly shit here.
main_core:
  ldr   x0, =SCTLR_VALUE_MMU_DISABLED
  msr   sctlr_el1, x0

  ldr   x0, =CPACR_VALUE
  msr   cpacr_el1, x0

  mrs x0, CurrentEL
  lsr x0, x0, 2
  cmp x0, 3
  bne check_drop_from_2

  ldr   x0, =SCR_VALUE
  msr   scr_el3, x0

  ldr   x0, =SPSR_VALUE
  msr   spsr_el3, x0

  adr   x0, main_core_el1
  msr   elr_el3, x0
  b drop_from_2

check_drop_from_2:
  cmp x0, 2
  bne proc_hang

  ldr   x0, =SPSR_VALUE
  msr   spsr_el2, x0

  adr   x0, main_core_el1
  msr   elr_el2, x0

drop_from_2:
  ldr   x0, =HCR_VALUE
  msr   hcr_el2, x0

  eret

main_core_el1:
  # Set stack to start below our code
  ldr     x1, =_start
  mov     sp, x1

  # Clean the BSS section
  # ADR is technically a real instruction that adds an immediate,
  # but in this case, we defined __bss_start in the link as a label,
  # so the assembler interprets it as a pseudo-op, and does a
  # PC-relative computation to calculate the address of __bss_start
  adr     x1, __bss_start
  adr     x2, __bss_end

bss_init_loop:
  str     xzr, [x1], 8
  cmp     x1, x2
  blt     bss_init_loop    // Loop if non-zero

start_kernel:
  # Jump to our kernel main, should be noreturn
  bl      main
  # Just in case, halt the main core too
  b       proc_hang
