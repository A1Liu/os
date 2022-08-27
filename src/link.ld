ENTRY(_start)

SECTIONS {
  . =    0xffff000000080000;     /* Kernel load address for AArch64 */

  .text : {
    *(.text)
    *(.text.*)
  }

  /* Align to page */
  . = ALIGN(0x1000);
  __rodata_start = .;

  .rodata : {
    *(.rodata .rodata.*)
  }

  .got : {
    *(.got)
  }

  /* Align to page, so that we can have a different set of access permissions */
  . = ALIGN(0x1000);
  __data_start = .;

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
