.section .text
.global main 
main:
    # --- Now in S-Mode ---
    nop
    nop 
    # Try accessing address WITH permissions (Should work)
    li t5, 0x80001000
    lw t6, 0(t5)

    # Try accessing address WITHOUT permissions (Should FAULT)
    li t5, 0x80100000
    lw t6, 0(t5)               # <--- This triggers Load Page Fault (mcause 13)

    # Try accessing address WITHOUT permissions (Should FAULT)
    li t6, 0xdeadbeef
    sw t6, 0(t5)               # <--- This triggers Store Page Fault (mcause 15)

    # Instruction Page Fault Test
    li t0, 0x80200000
    jalr t0      # cause Instruction Page Fault (mcause 12)

    # Try accessing address WITH permissions (Should Work)
    li t5, 0x80200000
    lw t6, 0(t5)               

    nop
    ecall 
    j pass


.section .text.init
.align 6
.global _start

_start:
    la t0, trap_handler
    csrw mtvec, t0

/* ============================================================
     ==== Setting Page table Address in satp (Sv32) ====
 ============================================================ */
    la t0, page_table    # Point to our empty map
    srli t0, t0, 12            # Convert address to PPN
    csrw satp, t0              # Write to satp

/* ============================================================
     ==== Setup PTEs via function call ====
 ============================================================ */
    # 1. First Setup Root Page Table
    li a0, 0x80000000          # VA: 0x80000000
    la a1, level0_table        # PA: level0_table
    li a2, 0x00                # Perms: R=0, W=0, X=0, Accessed=0, Dirty=0 (Root PTE)
                               # Bit 1=R, 2=W, 3=X, 6=A, Bit 7=D -> 0xC1 (00000000) 
    li a3, 1                   # Level: 1 
    call setup_pte

    # 2. Added Entry in Leaf Page Table
    li a0, 0x80001000          # VA: 0x80000000
    li a1, 0x80001000          # PA: 0x80000000
    li a2, 0xCE                # Perms: R=1, W=1, X=1, Accessed=1, Dirty=1 (Leaf PTE)
                               # Bit 1=R, 2=W, 3=X, 6=A, Bit 7=D -> 0xC1 (11001110)
    li a3, 0                   # Level: 0 (Leaf Page)
    call setup_pte

    # 3. Added Entry in Leaf Page Table With No permission
    li a0, 0x80100000          # VA: 0x80000000
    li a1, 0x80000000          # PA: 0x80000000
    li a2, 0xC0                # Perms: R=0, W=0, X=0, Accessed=1, Dirty=1 (Leaf PTE)
                               # Bit 1=R, 2=W, 3=X, 6=A, Bit 7=D -> 0xC1 (11000000)
    li a3, 0                   # Level: 0 (Leaf Page)
    call setup_pte

    # 4. Non-executable page (R/W allowed but X=0)
    li a0, 0x80200000        # VA
    li a1, 0x80002000        # PA
    li a2, 0xC6              # Perms: R=1, W=1, X=0, Accessed=1, Dirty=1 (Leaf PTE)
                             # Bit 1=R, 2=W, 3=X, 6=A, Bit 7=D -> 0xC1 (11000110)
    li a3, 0
    call setup_pte

#  ============================================================ 
    nop

/* ============================================================
     ==== Enable Virtual Memory (Sv32) ====
 ============================================================ */
    csrr t0,satp
    li t1, 0x80000000          # Set MODE bit (bit 31) to 1 for Sv32
    or t0, t0, t1
    csrs satp, t0          # Write to satp
    sfence.vma                 # Flush TLB 

    # Jump to S-Mode
    # ========================================================
    li a0, 0         # 0 = Supervisor
    call switch_mode 

/* ============================================================
    ==== Function: setup_pte ====
    a0 = Virtual Address (VA)
    a1 = Physical Address (PA)
    a2 = Permissions (R, W, X bits)
    a3 = Level (1 for Megapage, 0 for 4KB page)
 ==============================================================
    ==== (Sv32 Specification Algorithm) ====
    Spec 4.3.2 Virtual Address Translation Process:
    1. Let a be satp.ppn × PAGESIZE, and let i = LEVELS − 1. (Sv32 LEVELS=2)
    2. Let pte be the value of the PTE at address a + va.vpn[i] × PTESIZE.
    3. If pte.v = 0, or if pte.r = 0 and pte.w = 1, stop and raise page-fault.
    4. Otherwise, the PTE is valid. If pte.r = 1 or pte.x = 1, go to step 5. 
       Otherwise, this PTE is a pointer to the next level of the page table. 
       Let i = i − 1. Let a = pte.ppn × PAGESIZE. Go to step 2.
 ============================================================ */
setup_pte:
    # Step 1: Let a be satp.ppn * 4096
    # Get Root Table address from satp 
    csrr t0, satp               # Read satp register
    li   t1, 0x003FFFFF         # Mask to get PPN field [21:0]
    and  t0, t0, t1             # Extract PPN
    slli t0, t0, 12             # t0 = satp.ppn * 4096 (Base Address)

    # Step 2 (i=1): va.vpn[1] = va[31:22]
    srli t2, a0, 22             # Extract VPN[1] (Top 10 bits of VA)
    slli t2, t2, 2              # VPN index * 4 bytes (PTESIZE)
    add  t3, t0, t2             # t3 = Physical Address of the PTE (a + va.vpn[1]*4)
    li   t1, 1
    beq  a3, t1, calculate_pte_addr   # If Level 1 (Megapage/Pointer), skip Level 0

setup_level0:
    # Step 4: Let a = pte.ppn * 4096 (Transition to Level 0)
    lw t0, 0(t3)
    srli t0, t0, 10             # Extract PPN from PTE
    slli t0, t0, 12             # t0 = pte.ppn * 4096 (Base Address)

    # Step 2 (i=0): va.vpn[0] = va[21:12]
    srli t2, a0, 12             # Shifted VA to get VPN[0]
    andi t2, t2, 0x3FF          # Mask 10 bits for Level 0 index
    slli t2, t2, 2              # VPN index * 4 bytes (PTESIZE)
    add  t3, t0, t2             # t3 = Physical Address of the PTE (a + va.vpn[0]*4)

    j calculate_pte_addr

calculate_pte_addr:    
    #  ==== Construct the PTE value (Figure 4.18) ====
    # Step 5: Construct the leaf/pointer PTE
    # Sv32 PTE PPN [31:10] = Physical Address [31:12]
    # Sv32 PTE PPN [31:10] = Physical Address [31:12]
    srli t4, a1, 12             # Get PPN
    slli t4, t4, 10             # Shift to PTE.PPN position

    # Set Mandatory Flag 
    # Bit 0=V -> 0x01 (00000001)
    ori  t4, t4, 0x01           # Set Valid=1 (Step 3)
    or   t4, t4, a2             # Set R/W/X/A/D permissions    
    sw   t4, 0(t3)              # Store 4-byte PTE into memory
    ret

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

    la t0,main
    csrw mepc, t0
    mret

/* ============================================================
  Trap Handler (M-mode)
  Enhanced Trap Handler (Handles Access Faults + Ecalls)
   ============================================================ */
.align 6
trap_handler:
    csrr t0, mcause

    # Page Fault Codes:  Instruction(12), Load(13), Store(15)
    li t1, 12   # Instruction Page Fault
    beq t0, t1, handle_instruction_page_fault
    li t1, 13
    beq t0, t1, handle_page_fault
    li t1, 15
    beq t0, t1, handle_page_fault

    # Ecalls: User(8), Supervisor(9)
    li t1, 8  # User Ecall exception
    beq t0, t1, from_user
    li t1, 9  # Supervisor Ecall exception
    beq t0, t1, from_supervisor

    j fail

handle_instruction_page_fault:
    # Skip the faulting instruction
    csrw mepc, ra
    mret

handle_page_fault:
    # Skip the faulting instruction
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

.section .data
.align 12                  # Page tables MUST be 4KB aligned
page_table:
    .fill 1024, 4, 0       # 4KB of zeros (No mappings)
.align 12
level0_table:
    .fill 1024, 4, 0      # 4KB of zeros (No mappings)

.section .check,"aw"
.align 12
exec_page:
    nop
    ret
