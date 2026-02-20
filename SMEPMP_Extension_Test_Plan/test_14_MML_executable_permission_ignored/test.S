.section .region_tor, "aw"
   nop
   nop
   ret
load_data: .word 0xdeadbeef

.section .text.init
.align 6
.global _start

_start:
    la t0, trap_handler
    csrw mtvec, t0

    # ========================================================
    # Enable Machine Rule Locking Bypass
    # ========================================================
    # According to spec:
    # When mseccfg.RLB is 1 locked PMP rules may be removed/modified and locked PMP entries may be edited.
    li t0, (1 << 2)    # RLB = 1
    csrw mseccfg, t0
 
    # REGION 0: TOR 
    # ========================================================
    la t0, _data_end
    srli t0, t0, 2
    csrw pmpaddr0, t0       # end address of _data_end

    # REGION 1: TOR 
    # ========================================================
    # Top of Range address:
    # Range: [_data_end or _tor_start, _tor_end)
    la t1, _tor_end
    srli t1, t1, 2
    csrw pmpaddr1, t1       # End address for TOR

    # ===== Region 0 configuration: =======
    # ========================================================
    # TOR mode
    # Bits: L=1, A=01, X=1, W=0, R=1
    # Binary: 0b10001101
    # Hex: 0x8D

    # ===== Region 1 configuration: =======
    # ========================================================
    # TOR mode
    # Bits: L=1, A=01, X=0, W=0, R=1
    # Binary: 0b10001001
    # Hex: 0x89

    # Region 0 = 0x8D (TOR + Locked + Execute,Read)
    # Region 1 = 0x89 (TOR + Locked + Read)
    li t4, 0x0000898D
    csrw pmpcfg0, t4

    # ========================================================
    # Enable Machine Mode Lockdown
    # ========================================================
    # According to spec:
    # If mseccfg.MML is set the system’s behavior changes
    li t0, 1     # MML = 1
    csrs mseccfg, t0
    # ========================================================
    # After Enable MML permission automatic changes like
    # Region 0 => (M/S/U-mode Execute,Read) to (M-mode Execute,Read)
    # Region 1 => (M/S/U-mode Read) to (M-mode Read)
    # ========================================================

    la t0, load_data
    lw t1,0(t0)
    la t3, _tor_start
    jalr t3       # <-- after jump at this address will give instruction access fault as no execute permission still

    # ========================================================
    # According to spec Proposal Point 4(b) :
    /* Adding a rule with executable privileges that either is M-mode-only or a locked Shared-Region 
     is not possible and such pmpcfg writes are ignored, leaving pmpcfg unchanged.This restriction can
     be temporarily lifted by setting mseccfg.RLB e.g. during the boot process.*/
    #
    # ========================================================
    # Changing Region 0 permission to execute only
    # Changing Region 1 permission to execute shared 
    # ========================================================
    #
    # ===== Region 0 Reconfiguration: =======
    # ========================================================
    # TOR mode
    # Bits: L=1, A=01, X=1, W=0, R=0
    # Binary: 0b10001100
    # Hex: 0x8C
    #
    # ===== Region 1 Reconfiguration: =======
    # ========================================================
    # TOR mode
    # Bits: L=1, A=01, X=0, W=1, R=0
    # Binary: 0b10001010
    # Hex: 0x8A

    # Region 0 = 0x8C (TOR + Locked + Execute only)
    # Region 1 = 0x8A (TOR + Locked + Execute shared)
    li t4, 0x00008A8C
    csrw pmpcfg0, t4
    csrr t4, pmpcfg0    # read back to check is config changed. Will change because RLB is set.If RLB not set then new config ignore

    la t0, load_data
    lw t1,0(t0)   # <-- will give load access fault as permission change to shared execute
    la t3, _tor_start
    jalr t3       # <-- after jump at this address will execute 

    nop
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

.section .tohost,"aw",@progbits

.align 6
.global tohost
tohost: .dword 0
.size tohost, 8;

.align 6
.global fromhost
fromhost: .dword 0
.size fromhost, 8;