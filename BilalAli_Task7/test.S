.section .text.init
.align 6
.global _start

_start:
    la t0, trap_handler
    csrw mtvec, t0

    # Configure PMP Regions
    # ========================================================
    la t0, _data_end
    srli t0, t0, 2
    csrw pmpaddr0, t0       # end address of _data_end 

    # Region Config = 0x0C (TOR + Execute)
    li t4, 0x0000008C
    csrw pmpcfg0, t4

    nop
    # Jump to S-Mode
    # ========================================================
    li a0, 0         # 0 = Supervisor
    call switch_mode 
    nop
    #returned to M mode
    ecall

    # ========================================================
    # Enable Machine Mode Lockdown
    # ========================================================
    # According to spec:
    # If mseccfg.MML is set the system’s behavior changes
    li t0, 1     # MML = 1
    csrw mseccfg, t0

    # With MML Set Region 0 Rule become Execute only M mode
    nop      # work here because M mode has execute access
    
    # Jump to S-Mode
    # ========================================================
    li a0, 0         # 0 = Supervisor
    call switch_mode   
    nop    # when mret happen and this instruction execute will give instruction access fault

    j fail

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
    beq t0, t1, pass

    li t1, 9
    beq t0, t1, from_supervisor

    j fail

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



.section .tohost,"aw",@progbits

.align 6
.global tohost
tohost: .dword 0
.size tohost, 8;

.align 6
.global fromhost
fromhost: .dword 0
.size fromhost, 8;
