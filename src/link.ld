ENTRY(_start)

SECTIONS {
  . = 0x80000;     /* Kernel load address for AArch64 */

  .text : {
    *(.text)
  }

  .rodata : {
    *(.rodata)
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

  /DISCARD/ : { *(.comment) *(.gnu*) *(.note*) *(.eh_frame*) }
}
__bss_size = (__bss_end - __bss_start)>>3;
