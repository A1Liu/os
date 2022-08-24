ENTRY(_start)

SECTIONS {
  . = 0x80000;     /* Kernel load address for AArch64 */

  .text : {
    *(.text)
    *(.text.*)
  }

  /* Align to page */
  . = ALIGN(0x1000);

  .rodata : {
    *(.rodata .rodata.*)
  }

  . = ALIGN(0x1000);

  .data : {
    *(.data)
  }

  . = ALIGN(0x8);

  __bss_start = .;
  .bss : {
    *(COMMON)
    *(.bss)
    *(.bss*)
  }
  __bss_end = .;
}
