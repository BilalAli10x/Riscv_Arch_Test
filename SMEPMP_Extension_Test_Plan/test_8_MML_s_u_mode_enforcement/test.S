.section .region_tor, "aw"
main:   
   nop           
   nop
   ecall    # switch to m-mode
   nop      # <-- when reach this instruction give instruction access fault as region has no permisiion for m-mode
   ret

.section .text.init
.align 6
.global _start

_start:
    la t0, trap_handler
    csrw mtvec, t0
 
    # REGION 0: TOR 
    # ========================================================
    la t0, _data_end
    srli t0, t0, 2
    csrw pmpaddr0, t0       

    # REGION 1: TOR 
    # ========================================================
    la t1, _tor_end
    srli t1, t1, 2
    csrw pmpaddr1, t1       

    # ===== Region 1 configuration: =======
    # ========================================================
    # TOR mode
    # Bits: L=1, A=01, X=1, W=0, R=1
    # Binary: 0b10001101
    # Hex: 0x0D

    # Region 0 = 0x8D (TOR + Locked + Execute,Read)
    # Region 1 = 0x0D (TOR + unLocked + Execute,Read)
    li t4, 0x00000D8D
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
    # Region 1 => (M/S/U-mode Execute,Read) to (S/U-mode Execute,Read)
    # ========================================================

    # Jump to S-Mode
    # ========================================================
    li a0, 0         # 0 = Supervisor
    call switch_mode    # after mode switch return to main label  
  
    j fail

/* ============================================================
 Mode switch function
 a0 = 0 -> Supervisor   a0 = 1 -> User   Called only from M-mode
 ============================================================ */
switch_mode:
    csrr t0, mstatus
    li t1, ~(3 << 11)     # Cleared MPP bits of mstatus 11 and 12
    and t0, t0, t1
supervisor_mode:
    li t1, (1 << 11)      # MPP = S  set bit 12 to 1 and bit 11 is alreday 0 int0
    or t0, t0, t1
    csrw mstatus, t0

    la t2, main
    csrw mepc, t2
    mret

/* ============================================================
  Trap Handler (M-mode)
  Enhanced Trap Handler (Handles Access Faults + Ecalls)
   ============================================================ */
.align 6
trap_handler:
    csrr t0, mcause

    # Access Faults: Instruction(1)
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