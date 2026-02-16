.section .text.init
.align 6
.global _start

 #define SMEPMP
// #define NO_SMEPMP

_start:
    la t0, trap_handler
    csrw mtvec, t0

    # Configure PMP Regions
    # ========================================================
    # REGION 0: TOR (Execute,Read,Write)
    # ========================================================
    # Top of Range address:
    # Range: [0x00000000,_data_end or _tor_end)
    la t0, _data_end
    srli t0, t0, 2
    csrw pmpaddr0, t0       # end address of _data_end 

    # REGION 1: TOR (Execute,Read,Write)
    # ========================================================
    # Top of Range address:
    # Range: [_data_end or _tor_start, _tor_end)
    la t1, _tor_end
    srli t1, t1, 2
    csrw pmpaddr1, t1       # End address for TOR

 # Enable ...
# ========================================================
#ifdef SMEPMP
    # Enable Rule Lock Bypass
    # ========================================================
    # According to spec:
    # The Lockout Rule: If any PMP entry has its Lock bit (L)
    # set to 1 while mseccfg.RLB is 0, then the RLB bit becomes read-only 0.
    li t0, (1 << 2)    # RLB = 1
    csrw mseccfg, t0
#endif

    # ===== PMP CFG ======
    # pmpcfg0 = [pmp3cfg][pmp2cfg][pmp1cfg][pmp0cfg]
    #                             [Region1][Region0]
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
    # TOR mode, execute read, write, unlocked
    # Bits: L=0, A=01, X=1, W=1, R=1
    # Binary: 0b00001111
    # Hex: 0x0F

    # ===== Region 1 configuration: =======
    # ========================================================
    # TOR mode, execute read, write, locked
    # Bits: L=1, A=01, X=1, W=1, R=1
    # Binary: 0b10001111
    # Hex: 0x8F

    # Region 0 = 0x0F (TOR + Execute,Read,Write)
    # Region 1 = 0x8F (TOR + Locked + Execute,Read,Write)
    li t4, 0x00008F0F
    csrw pmpcfg0, t4

    # ==== M-MODE TESTS ====
    # ========================================================
    # Lock PMP regions for Machine Mode
    # ========================================================
    # Test Locked TOR Region (Execute, Read,Write)
    la s1, _tor_start
    li t0, 0xdeadbeef
    sw t0, 8(s1)           # SUCCESS: Write allowed
    lw t0, 8(s1)           # SUCCESS: Read allowed
    jalr s1                # SUCCESS: Execute allowed

    # Behavior of Locked PMP Region (L = 1)
    # ========================================================
    # Once the L bit is set for a PMP entry:
    # 1) The configuration (R/W/X/A/L bits) and address registers of that entry
    #    become immutable (writes are ignored).
    # 2) The region also applies to M-mode accesses.Normally PMP does NOT restrict M-mode.


    # ===== Region 1 configuration change: =======
    # ========================================================
    # TOR mode, execute read, write, locked
    # Bits: L=1, A=01, X=0, W=0, R=1
    # Binary: 0b10001001
    # Hex: 0x89
    # ========================================================


#ifdef SMEPMP
    # ========================================================
    # Since mseccfg.RLB is enable, this write must succed.
    # Verified this by reading back pmpcfg0.
    # If read value is previous one, the test fails.
    # ========================================================

    # Region 0 = 0x0F (TOR + Execute,Read,Write)
    # Region 1 = 0x89 (TOR + Locked + Read only after SMEPMP RLB enabled)
    li t4, 0x0000890F
    csrw pmpcfg0, t4      
    csrr t1, pmpcfg0        # Read back actual configuration
    bne t1, t4, fail_cfg_not_change   # if not equal, configuration not change failed -> error

#else 
    # ========================================================
    # Since Region 1 is locked, this write must be ignored.
    # Verified this by reading back pmpcfg0.
    # If the value changed, the test fails.
    # ========================================================

    # Region 0 = 0x0F (TOR + Execute,Read,Write)
    # Region 1 = 0x89 (TOR + Locked + Read)
    li t4, 0x0000890F
    csrw pmpcfg0, t4      
    csrr t1, pmpcfg0        # Read back actual configuration
    beq t1, t4, fail_cfg_change   # if equal, configuration changed failed -> error
#endif

    # ========================================================
    # Test after configuration change for Region 1
    # ========================================================
    # Test Locked TOR Region (Read)
    # Will trap occur If SMEPMP enabled because that change permissioned.Otherwise all success
    la s1, _tor_start
    li t0, 0xdeadbeef
    sw t0, 8(s1)           
    lw t0, 8(s1)           
    jalr s1                

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

/* ============================================================
  Trap Handler (M-mode)
  Enhanced Trap Handler (Handles Access Faults + Ecalls)
   ============================================================ */
.align 6
trap_handler:
    csrr t0, mcause

    # Access Faults: Instruction(1), Load(5), Store(7)
    li t1, 1 # Instruction Access Faults
    beq t0, t1, instruction_access_fault
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

instruction_access_fault:
    # skip the faulting instruction by skiping jump call
    csrw mepc, ra
    mret

handle_fault:
    # incremented mepc to skip the faulting instruction
    csrr t2, mepc
    addi t2, t2, 4
    csrw mepc, t2
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

fail_cfg_not_change:
fail_cfg_change:
fail:
    li gp, 2
    sw gp, tohost, t0
    j fail


.section .region_tor, "ax"
    nop                    # Valid instruction for jalr test
    ret
write_her: .word 0x12345678

.section .tohost,"aw",@progbits

.align 6
.global tohost
tohost: .dword 0
.size tohost, 8;

.align 6
.global fromhost
fromhost: .dword 0
.size fromhost, 8;
