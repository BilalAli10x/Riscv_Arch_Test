.section .text.init
.align 6
.global _start

_start:
    #  Set trap vector 
    la t0, trap_handler
    csrw mtvec, t0
    ecall
    # M -> U
    li a0, 1        # 1 = USER
    call switch_mode

#switched to U mode
    ecall

# returned to S mode
verify_s_mode:
    csrr t0, sstatus
    ecall

    # returned to M mode
    nop
    
    # M -> S again
    li a0, 0           # 0 = Supervisor 
    call switch_mode

    #switched to S mode
    # S -> U
    call user_mode_switch

#switched to U mode
verify_u_mode:
    ecall   # U -> S

    # returned to S mode
    ecall

# returned to M mode
verify_m_mode:
    csrr t0, mstatus
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
  Handles:
   - ECALL from U -> return to S
   - ECALL from S -> return to M
   ============================================================ */
.align 6
trap_handler:
    csrr t0, mcause
    # slli t0, t0, 1
    # srli t0, t0, 1         # cleared msb bit 31 no need in this case as only exceptions
    li t1, 8
    beq t0, t1, from_user

    li t1, 9
    beq t0, t1, from_supervisor

    j fail

from_user:
    # Advance mepc 
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

.section .tohost,"aw",@progbits

.align 6
.global tohost
tohost: .dword 0
.size tohost, 8;

.align 6
.global fromhost
fromhost: .dword 0
.size fromhost, 8;

