#include "shared_values.h"

.global asdfasdf
asdfasdf:
  ldr x0, =SCTLR_VALUE_MMU_DISABLED
  msr sctlr_el1, x0

  ldr x0, =HCR_VALUE
  msr hcr_el2, x0

  ldr x0, =SCR_VALUE
  msr scr_el3, x0

  ldr x0, =SPSR_VALUE
  msr spsr_el3, x0

  adr x0, el1_entry
  msr elr_el3, x0

  eret
