.PHONY: all clean run debug build readelf

# Toolchain
TOOLCHAIN := riscv64-unknown-elf
CC       := $(TOOLCHAIN)-gcc
OBJDUMP  := $(TOOLCHAIN)-objdump
READELF  := $(TOOLCHAIN)-readelf

# Architecture
ARCH := rv32i_zicsr_zifencei_smepmp
ABI  := ilp32

# -----------------------
# Mode (SMEPMP / NO_SMEPMP)
MODE ?=

ifeq ($(MODE),)
    CFLAGS_MODE :=
else
    CFLAGS_MODE := -D$(MODE)
endif

# Files
SRC    := test.S
ELF    := test.elf
DISASM := test.disass
LINKER := link.ld

# Default target
all: $(ELF) $(DISASM)

# Build (explicit)
build: $(ELF)
# Compile & Link
$(ELF): $(SRC) $(LINKER)
	@$(CC) -march=$(ARCH) -mabi=$(ABI) -nostdlib -T $(LINKER) $(CFLAGS_MODE) $< -o $@

# Disassemble
$(DISASM): $(ELF)
	@$(OBJDUMP) -D $< > $@

# Read ELF info
readelf: $(ELF)
	@$(READELF) -a $<

# Run on Spike
run: $(ELF)
	@echo "Running test with Spike..."
	@spike --isa=rv32i_smepmp -l --log-commits $< 1>spike.out 2>spike.log
	@echo "✓ Spike execution complete (check spike.log)"

# Debug on Spike
debug: $(ELF)
	@spike --isa=rv32i_smepmp -d -l --log-commits $<

clean:
	rm -f $(ELF) $(DISASM) spike.out spike.log
