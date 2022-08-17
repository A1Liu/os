ENTRY(_start)

SECTIONS {
  . = 0x80000;     /* Kernel load address for AArch64 */

  .text : {
    *(.text)
  }

  .rodata : {
    *(.rodata .rodata.*)
  }

  .data : {
    *(.data)
  }

  .bss (NOLOAD) : {
    . = ALIGN(16);
    __bss_start = .;
    *(COMMON)
    *(.bss)
    __bss_end = .;
  }

  _end = .;
}
