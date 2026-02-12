.section .text.init
.align 6
.global _start

_start:
    la t0, trap_handler
    csrw mtvec, t0

    # Configure PMP Regions
    # ========================================================

    # REGION 0: TOR (Execute Only)
    # ========================================================
    # Top of Range address:
    # Range: [_tor_start, _tor_end)
    la t0, _tor_start
    srli t0, t0, 2
    csrw pmpaddr0, t0       # Start address for TOR

    la t0, _tor_end
    srli t0, t0, 2
    csrw pmpaddr1, t0       # End address for TOR


    # REGION 1: NAPOT (Read Only, 4KB aligned)
    # ========================================================
    # 4KB region = 0x1000 size
    # Calculation: (Base >> 2) | ((4096/8) - 1) 
    # (4096/8) - 1 = 511 = 0x1FF
    la t1, _napot_start
    srli t1, t1, 2
    ori t1, t1, 0x1FF      # Apply 4KB NAPOT mask
    csrw pmpaddr2, t1

    # ===== PMP CFG ======
    # pmpcfg0 = [pmp3cfg][pmp2cfg][pmp1cfg][pmp0cfg]
    #                    [Region1][Region0]
    # ========================================================
    # Each region needs 8 bits in pmpcfg0: [L][00][A][X][W][R]
    # L = Lock bit (0 = unlocked, 1 = locked)
    # 00 = Reserved
    # A = Address Matching (01 = TOR)
    # X = Execute permission
    # W = Write permission
    # R = Read permission
    # ========================================================

    # ===== Region 0 configuration: =======
    # ========================================================
    # TOR mode, execute only, unlocked
    # Bits: L=0, A=01, X=1, W=0, R=0
    # Binary: 0b00001100
    # Hex: 0x0C

    # ===== Region 1 configuration: =======
    # NAPOT mode, read only, unlocked
    # Bits: L=0, A=11, X=0, W=0, R=1
    # Binary: 0b00011001
    # Hex: 0x19

    # Region 0 = 0x0C (TOR + Execute)
    # Region 1 = 0x19 (NAPOT + Read)
    li t2, 0x00190C00
    csrw pmpcfg0, t2

    # Jump to S-Mode
    # ========================================================
    li a0, 0         # 0 = Supervisor
    call switch_mode 
switch_mode_fault_start:
    nop
switch_mode_fault_end:
     /* while returning to lower mode instruction access fault happen because 
      default deny" or whitelist security model for lower privilege levels. 
      When an address does not match any configured PMP region for S and U mode 
      is Default Deny and for M mode is Default Allow*/

    # ==== S-MODE TESTS ====
    # After trap_handler resolves the Instruction Fault, we arrive here:
    
    # Test TOR Region (Execute Only)
    la s1, _tor_start
    lw t0, 0(s1)           # FAULT: Load Access (mcause 5)
    sw t0, 0(s1)           # FAULT: Store Access (mcause 7)
    jalr s1                # SUCCESS: Execute allowed

    # Test NAPOT Region (Read Only)
    la s2, _napot_start
    lw t0, 0(s2)           # SUCCESS: Read allowed
    sw t0, 0(s2)           # FAULT: Store Access (mcause 7)
    jalr s2                # FAULT: Instruction Access (mcause 1)

    nop

    # Return to M-mode to apply Lock
    ecall    # Triggers from_supervisor handler

    # ==== M-Mode Restriction ====
    # ========================================================
    # Lock PMP regions for Machine Mode
    # ========================================================
    # Set Lock bit (L=1) for both regions
    # Region 0 (TOR + Execute) = 0x0C | 0x80 = 0x8C
    # Region 1 (NAPOT + Read)   = 0x19 | 0x80 = 0x99
    li t2, 0x00998C00
    csrrs zero,pmpcfg0, t2   # now all rules apply to M mode also
    nop

    # ==== M-MODE TESTS ====
    # Now in M-mode, these will fault because the L-bit is set.

    # Test Locked TOR Region (Execute Only)
    la s1, _tor_start
    lw t0, 0(s1)           # FAULT: Load Access (mcause 5) - even in M-mode!
    sw t0, 0(s1)           # FAULT: Store Access (mcause 7)
    jalr s1                # SUCCESS: Execute allowed

    # Test Locked NAPOT Region (Read Only)
    la s2, _napot_start
    lw t0, 0(s2)           # SUCCESS: Read allowed
    sw t0, 0(s2)           # FAULT: Store Access (mcause 7)
    jalr s2                # FAULT: Instruction Access (mcause 1)

    j pass

/* ============================================================
 Mode switch function
 a0 = 0 -> Supervisor   a0 = 1 -> User   Called only from M-mode
 ============================================================ */
switch_mode:
    csrr t0, mstatus
    li t1, ~(3 << 11)     # Cleared MPP bits of mstatus 11 and 12
    and t0, t0, t1

    beqz a0, supervisor_mode  # if argument is 0 then switch to supervisor if not zero go to next instruction

user_mode:
    li t1, (0 << 11)      # MPP = U set bit of mstatus 11 to 0
    or t0, t0, t1
    csrw mstatus, t0

    csrw mepc, ra
    mret

supervisor_mode:
    li t1, (1 << 11)      # MPP = S  set bit 12 to 1 and bit 11 is alreday 0 int0
    or t0, t0, t1
    csrw mstatus, t0

    csrw mepc, ra
    mret

user_mode_switch:
    # Set SPP=0 (user)
    csrr t1, sstatus
    li t2, ~(1 << 8)        # clear SPP (next mode = U)
    and t1, t1, t2
    csrw sstatus, t1

    csrw sepc, ra
    sret

/* ============================================================
  Trap Handler (M-mode)
  Enhanced Trap Handler (Handles Access Faults + Ecalls)
   ============================================================ */
.align 6
trap_handler:
    csrr t0, mcause

    # Access Faults: Instruction(1), Load(5), Store(7)
    li t1, 1 # Instruction Access Faults
    beq t0, t1, handle_instruction_fault
    li t1, 5 # Load Access Faults
    beq t0, t1, handle_fault
    li t1, 7 # Store Access Faults
    beq t0, t1, handle_fault

    # Task 1: Handling Ecalls
    li t1, 8
    beq t0, t1, from_user

    li t1, 9
    beq t0, t1, from_supervisor

    j fail

handle_fault:
    # incremented mepc to skip the faulting instruction
    csrr t2, mepc
    addi t2, t2, 4
    csrw mepc, t2
    mret

handle_instruction_fault:
    csrr t3, mepc 

    la t4, switch_mode_fault_start
    la t5, switch_mode_fault_end

    # Was the fault caused by entering lower privilege mode?
    blt t3, t4, instruction_access_fault
    bge t3, t5, instruction_access_fault

    # ===== Default Deny configuration: =======
    # ========================================================
    # TOR mode, execute ,read,write, unlocked
    # Bits: L=0, A=01, X=1, W=1, R=1
    # Binary: 0b00001111
    # Hex: 0x0F

    # Default Deny Region = 0x0F (TOR + Execute,Read,Write)
    li t6, 0x0000000F
    csrrs zero,pmpcfg0, t6

    mret

instruction_access_fault:
    # skip the faulting instruction by skiping jump call
    csrw mepc, ra
    mret

from_user:
    # advance mepc 
    csrr t0, mepc
    addi t0, t0, 4
    csrw mepc, t0

    # Set MPP=01 (Supervisor)
    csrr t1, mstatus
    li t2, ~(3 << 11)        # clear bits [12:11]
    and t1, t1, t2
    li t2, (1 << 11)         # set MPP=01
    or t1, t1, t2
    csrw mstatus, t1

    mret

from_supervisor:
    csrr t0, mepc
    addi t0, t0, 4
    csrw mepc, t0

    # Set MPP=11 (Machine)
    csrr t1, mstatus
    li t2, ~(3 << 11)        # clear bits [12:11]
    and t1, t1, t2
    li t2, (3 << 11)         # set MPP=11
    or t1, t1, t2
    csrw mstatus, t1

    mret

pass:
    li gp, 1
    sw gp, tohost, t0
    j pass

fail:
    li gp, 2
    sw gp, tohost, t0
    j fail


.section .region_tor, "ax"
    nop                    # Valid instruction for jalr test
    ret

.section .region_napot, "aw"
    .word 0xDEADBEEF       # Valid data for lb test


.section .tohost,"aw",@progbits

.align 6
.global tohost
tohost: .dword 0
.size tohost, 8;

.align 6
.global fromhost
fromhost: .dword 0
.size fromhost, 8;

