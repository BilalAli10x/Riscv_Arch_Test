# Configuration
CC           = riscv64-unknown-elf-gcc
OBJDUMP      = riscv64-unknown-elf-objdump
CFLAGS       = -march=rv64gh -mabi=lp64 -mcmodel=medany -nostdlib -mno-relax
LDFLAGS      = -T link.ld
SPIKE_FLAGS  = -m8796093022208 --isa=rv64gch -l --log-commits

# Files
SOURCE       = test.S
ELF_FILE     = test.elf
DISASM_FILE  = test.disass
# Default target
all: build disasm

# Compile the test
build: $(ELF_FILE)

$(ELF_FILE): $(SOURCE) link.ld
	@echo "Compiling $(SOURCE)..."
	$(CC) $(CFLAGS) $(LDFLAGS) $(SOURCE) -o $(ELF_FILE)
	@echo "✓ Build complete: $(ELF_FILE)"

# Generate disassembly
disasm: $(DISASM_FILE)

$(DISASM_FILE): $(ELF_FILE)
	@echo "Generating disassembly..."
	$(OBJDUMP) -D $(ELF_FILE) > $(DISASM_FILE)
	@echo "✓ Disassembly complete: $(DISASM_FILE)"

# Run with Spike simulator
run: $(ELF_FILE)
	@echo "Running test with Spike..."
	spike $(SPIKE_FLAGS) $(ELF_FILE) 1>spike.out 2>spike.log
	@echo "✓ Spike execution complete (check spike.log)"

debug: $(ELF_FILE)
	spike $(SPIKE_FLAGS) -d $(ELF_FILE) 

# Run complete test suite
test: build disasm run
	@echo "✓ All tests completed"

# Clean build artifacts
clean:
	@echo "Cleaning..."
	rm -f $(ELF_FILE) $(DISASM_FILE) *.log *.out
	@echo "✓ Clean complete"

# Show help
help:
	@echo "Available targets:"
	@echo "  all       - Compile and generate disassembly (default)"
	@echo "  compile   - Compile the test"
	@echo "  disasm    - Generate disassembly"
	@echo "  run-spike - Run test with Spike simulator"
	@echo "  run-sail  - Run test with SAIL simulator"
	@echo "  test      - Run complete test suite"
	@echo "  clean     - Remove build artifacts"
	@echo "  help      - Show this help message"

.PHONY: all build disasm run test clean help
