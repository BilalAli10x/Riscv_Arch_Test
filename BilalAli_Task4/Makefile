.PHONY: all clean run
# Default: build ELF + disassembly
all: $(ELF) $(DISASM)
# Toolchain 
TOOLCHAIN := riscv64-unknown-elf
CC       := $(TOOLCHAIN)-gcc
OBJDUMP  := $(TOOLCHAIN)-objdump

# Target architecture & ABI 
ARCH := rv32g
ABI  := ilp32

# Source and output
SRC    := test.S
ELF    := test.elf
DISASM := test.disass
LINKER := link.ld

# Compile & link
build: clean $(ELF) 
$(ELF): $(SRC) $(LINKER) 
	@$(CC) -march=$(ARCH) -mabi=$(ABI) -nostdlib -T $(LINKER) $(SRC) -o $@

# Disassemble
$(DISASM): $(ELF)
	@$(OBJDUMP) -D $< > $@

# Run on Spike
run: $(ELF) $(DISASM)
	@spike --isa=rv32ifd -l --log-commits $< 1>spike.out 2>spike.log
#  -d  interactive debug mode
#  --log-commits  show output
#  -l  actual instruction
# --isa=rv32ifd: enable integer + F + D extensions for FS/SD runtime test

debug: $(ELF) 
	@spike --isa=rv32ifd -d --log-commits -l $< 
# Clean
clean:
	@rm -f $(ELF) $(DISASM) spike.out spike.log
