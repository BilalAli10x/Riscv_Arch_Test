OUTPUT_ARCH( "riscv" )
ENTRY(_start)

PHDRS
{
    text PT_LOAD FLAGS(5);    /* Read (4) + Execute (1) = 5 */
    data PT_LOAD FLAGS(6);    /* Read (4) + Write (2) = 6 */
}

SECTIONS
{
  /* Text sections with Read and Execute permissions */
  . = 0x80000000;   
  .text.init : { *(.text.init) } :text
  . = ALIGN(0x1000);
  .tohost : { *(.tohost) } :text
  . = ALIGN(0x1000);
  .text : { *(.text) } :text
  . = ALIGN(0x1000);
  .page_region : { *(.page_region) } :text
  . = ALIGN(0x1000);
  /* Data sections with Read and Write permissions */
  .data : { *(.data) } :data
  .bss : { *(.bss) } :data
  _end = .;
}
