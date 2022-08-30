ENTRY(_start)

/* NOTE: This script is NOT done. There's almost certainly still some section that
 * isn't being properly placed in the binary. Literally over half the bugs
 * I've had so far have been caused by some rogue section that was labeled
 * `.bss.bullshit` instead of `.bss` .
 *
 *                            - Albert Liu, Aug 28, 2022 Sun 17:03 EDT
 */

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
    *(.data .data.*)
  }

  . = ALIGN(0x8);

  __bss_start = .;
  .bss : {
    *(COMMON)
    *(.bss)
    *(.bss*)
  }

  . = ALIGN(0x1000);
  __bss_end = .;
}
