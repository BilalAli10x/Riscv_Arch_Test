OUTPUT_ARCH("riscv")
ENTRY(_start)

SECTIONS
{
    . = 0x80000000;

    .text.init : ALIGN(0x1000) {
        _text_init_start = .;     
        *(.text.init)              
        _text_init_end = .;        
    }
    .text : ALIGN(0x1000) {
        _text_start = .;     
        *(.text)              
        _text_end = .;        
    }
    .check : ALIGN(0x1000) {
        *(.check)              
    }

    .data : ALIGN(0x1000) {
        _data_start = .;           
        *(.data)
        _data_end = .;            
    }


    .tohost : ALIGN(0x1000) {
        *(.tohost)
    }

    _end = .;
}