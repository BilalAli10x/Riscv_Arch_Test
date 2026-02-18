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
    .data : ALIGN(0x1000) {
        _data_start = .;           
        *(.data)
        _data_end = .;            
    }
    .region_tor : ALIGN(0x1000) {
        _tor_start = .;     
        *(.region_tor)              
        _tor_end = .;        
    }

    .tohost : ALIGN(0x1000) {
        *(.tohost)
    }


    _end = .;
}