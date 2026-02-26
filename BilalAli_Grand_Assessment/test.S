# =================----text.init----start----=================
.section .text.init                                            
.align  3                                                   
.global _start                                             
_start:       
    # ========================================================
    #  Set M-mode trap vector
    # ========================================================
    # mtvec: M-mode trap vector for machine-level traps                                                      
    la t0, trap_handler_m
    csrw mtvec, t0

    # ========================================================
    # Delegate certain exceptions to HS-mode
    # medeleg: bits for exceptions which we want HS to handle
    # Bit mapping according to RISC-V Privileged Spec:
    #   Bit 8  -> Environment call from U-mode or VU-mode
    #   Bit 10 -> Environment call from VS-mode
    #   Bit 12 -> Instruction Page Fault
    #   Bit 13 -> Load page fault
    #   Bit 15 -> Store/AMO page fault
    # ========================================================
    li t0, (1<<8)|(1<<10)|(1<<12)|(1<<13)|(1<<15)
    csrw medeleg, t0

    /* ============================================================
        ==== Setting and Enabling hgatp (Sv39x4) ====
    ============================================================ */
    # Initialize HGATP for Guest-stage (G-stage) translation
    # hgatp holds:
    #   - mode (bits [63:60] for Sv48x4, Sv39x4 etc.)
    #   - PPN of root page table
    # ========================================================
    la t0, guest_root_page_table    # Root page table for G-stage
    srli t0, t0, 12                 # Convert to PPN (4KB aligned)
    li t1, (8<<60)                  # Sv39x4 mode = 8
    or t0, t0, t1
    csrw hgatp, t0                  # Initialize hgatp for G-stage translation

    /* ============================================================
        ==== Setup PTEs via function call ====
    ============================================================ */
    # We need to map THREE things in G-stage:
    #   1. guest_code  -> so guest can execute
    #   2. guest_user_code  -> so guest_user can execute
    #   3. load_data   -> so guest can store 0xDEADBEEF
    #   4. guest_vs_*_table  -> so VS-stage page table walk works
    #
    # All using identity mapping (guest PA = real PA)
    # ============================================================
    # Map guest_code in G-stage
    la  a0, guest_code           # VA to map
    la  a1, guest_code           # PA to map to (identity)
    li  a2, 0xDF                 # R=1 W=1 X=1 U=1 A=1 D=1 V=1
    call guest_pte_setup         # write G-stage leaf PTE

    # Map guest_user_code in G-stage
    la   a0, guest_user_code
    la   a1, guest_user_code   # PA to map to (identity)
    li   a2, 0xDF              # R=1 W=1 X=1 U=1 A=1 D=1 V=1
    call guest_pte_setup

    # Map vs_verification code in G-stage
    la   a0, vs_verification
    la   a1, vs_verification   # PA to map to (identity)
    li   a2, 0xDF              # R=1 W=1 X=1 U=1 A=1 D=1 V=1
    call guest_pte_setup

    # Map load_data in G-stage
    la   a0, load_data
    la   a1, load_data
    li   a2, 0xD7              # R=1 W=1 U=1 A=1 D=1 V=1 (no X)
    call guest_pte_setup

    # Map VS-stage root page table in G-stage
    # (hardware reads it during VS-stage page table walk)
    la   a0, guest_vs_root_page_table
    la   a1, guest_vs_root_page_table
    li   a2, 0xD7              # R=1 W=1 U=1 A=1 D=1 V=1
    call guest_pte_setup

    # Map VS-stage level-1 page table in G-stage
    la   a0, guest_vs_level_one_page_table
    la   a1, guest_vs_level_one_page_table
    li   a2, 0xD7             # R=1 W=1 U=1 A=1 D=1 V=1
    call guest_pte_setup

    # Map VS-stage level-0 page table in G-stage
    la   a0, guest_vs_level_zero_page_table
    la   a1, guest_vs_level_zero_page_table
    li   a2, 0xD7             # R=1 W=1 U=1 A=1 D=1 V=1
    call guest_pte_setup

    # ========================================================
    # fence AFTER all G-stage PTE writes
    # Spec says: HFENCE.GVMA after page table modifications
    # ========================================================
    hfence.gvma x0, x0

    # Jump to S-Mode and return on superviosor entry
    # ========================================================
    li a0, 0         # 0 = Supervisor
    call switch_mode 
# ============================================================

switch_mode:
    csrr t0, mstatus
supervisor_mode:
    li t1, (1 << 11)      # MPP = 01 = S-mode (HS-mode) 
    or t0, t0, t1
    csrw mstatus, t0
    la t0,hypervisor_entry
    csrw mepc, t0
    mret                # -> jumps to hypervisor_entry in HS-mode
# =================----text.init----end----==================

# =================----text----start----=====================
.section .text                  # Defined in linker
.align 12                       # 4KB alignment
hypervisor_entry:
    # ==== IN THE Hypervisor (V=0, Priv=HS) ====

    # =======================================================
    #  Set HS-mode trap vector
    # ========================================================
    # stvec: HS-mode trap vector for supervisor-level traps
    la t0, trap_handler_s
    csrw stvec, t0          # Set HS-mode trap handler

    # ========================================================
    # Enable Virtual Supervisor mode for the guest
    # ========================================================
    # Set SPV = 1 in hstatus (bit 7)
    # This indicates "Supervisor Previous Virtualization"
    li t0, (1 << 7)        
    csrs hstatus, t0       

    # ========================================================
    # Set next privilege level for the guest
    # ========================================================
    # Set SPP = 1 in sstatus (bit 8)
    li t0, (1 << 8)        
    csrs sstatus, t0   

    /* ============================================================
        ==== Setting and Enabling vsatp (Sv39) ====
    ============================================================ */
    # Initialize VS-stage translation (guest first-stage
    # vsatp holds:
    #   - mode (bits [63:60] for Sv48, Sv39 etc.)
    #   - PPN of root page table
    la t0, guest_vs_root_page_table   # Load guest VS-mode root table (4KB)
    srli t0, t0, 12                   # Convert address to PPN
    li t1, (8 << 60)                  # Sv39 mode = 8
    or t0, t0, t1
    csrw vsatp, t0                    # Set VS-mode page table  

    /* ============================================================
        ==== Setup PTEs via function call ====
    ============================================================ */
    # Setup VS-stage page tables (vsatp = Sv39)
    # Map guest_code VA → guest_code PA (identity)
    # Map load_data VA  → load_data PA  (identity)
    # =============================================================
    # Map guest_code in VS-stage
    la   a0, guest_code        # VA to map
    la   a1, guest_code        # PA to map to (identity)
    li   a2, 0xCF              # R=1 W=1 X=1 A=1 D=1 V=1 (no U - VS stage)
    call guest_vs_pte_setup

    # Map guest_user_code in VS-stage
    # guest_user_code page -> VU-mode allowed, U=1
    la   a0, guest_user_code
    la   a1, guest_user_code
    li   a2, 0xDF              # U=1 -> VU-mode can execute 
    call guest_vs_pte_setup

    # Map vs_verification code in VS-stage
    la   a0, vs_verification
    la   a1, vs_verification   
    li   a2, 0xCF             # R=1 W=1 X=1 A=1 D=1 V=1 (no U - VS stage)
    call guest_vs_pte_setup

    # Map load_data in VS-stage
    la   a0, load_data
    la   a1, load_data
    li   a2, 0xC7              # R=1 W=1 A=1 D=1 V=1 (no U, no X)
    call guest_vs_pte_setup

    # =============================================================
    # fence AFTER all VS-stage PTE writes
    # =============================================================
    hfence.vvma x0, x0

    # ========================================================
    # Set guest entry point
    # ========================================================
    # Guest will start execution from this address when entering VS-mode
    la t0, guest_code      # Load guest label
    csrw sepc, t0         

    # ========================================================
    # Enter the guest
    # ========================================================
    # Execute sret to switch from HS-mode to VS-mode
    # CPU reads hstatus.SPVs and sstatus.SPP to determine next privilege and PC
    #   SPV = 1 in hstatus → sret sets V=1
    #   SPP = 1 in sstatus → sret sets privilege = supervisor
    # ========================================================
    sret          # → jumps to guest_code in VS-mode
# ============================================================

.align 12            
guest_code:
    # ==== IN THE Guest (V=1, Priv=VS) ====
    nop

    # ========================================================
    # Store test value at known address
    # ========================================================
    la t0, load_data       # Load address of known memory
    li t1, 0xDEADBEEF      # Test value
    sw t1, 0(t0)           # Store to memory

    # ========================================================
    # Set next privilege level VU-mode (User) for the guest
    # ========================================================
    # Set SPP = 0 in sstatus (bit 8)
    # Set SPP=0 in sstatus: next sret goes to User mode
    csrr t2, sstatus       # Read sstatus
    li t3, ~(1 << 8)       # Clear bit 8 (SPP)
    and t2, t2, t3
    csrw sstatus, t2       

    # Set sepc to next instruction (just after sret)
    la t0, guest_user_code
    csrw sepc, t0

    # Execute sret to jump to VU-mode
    sret
# ============================================================

.align 12                    # NEW PAGE
guest_user_code:           
    # ==== IN THE Guest User-mode (V=1, Priv=VU) ====
    nop
    # ========================================================
    # Pass VS memory address in a0
    # ========================================================
    la a0, load_data       # Pass the address of stored test value

    # ========================================================
    # Execute ecall to trap to HS-mode (Hypervisor)
    # ========================================================
    li a1, 1
    ecall
# ============================================================

# ============================================================
# trap_handler_s — HS-mode trap handler
# ============================================================
trap_handler_s:
    # ==== IN THE Guest ( Priv=HS) ====

    # ========================================================
    # ecall from VS-mode
    # scause = 10 = environment call from S/VS-mode
    # Execute ecall to M-mode
    # ========================================================
    csrr t0, scause
    li   t1, 10
    bne  t0, t1, 1f     # not vs ecall cause 
    li   t1, 2
    bne  a1, t1, test_fail
    ecall
    # ========================================================
    # Write success to tohost
    # ========================================================
    j test_pass        

1:
    # ========================================================
    # Verify this is ecall from VU-mode
    # scause = 8 = environment call from U/VU-mode
    # ========================================================
    li   t1, 1
    bne  a1, t1, test_fail
    
    csrr t0, scause
    li   t1, 8
    bne  t0, t1, test_fail     # wrong cause -> fail

    # ========================================================
    # Set SPVP so that acccessing VS memory work
    # hstatus.SPVP=0
    # ========================================================
    li t0, (1<<8)
    csrr t1, hstatus
    or t0, t0, t1
    csrw hstatus, t0

    # ========================================================
    # Read load_data using HLV (hypervisor load)
    # HLV accesses guest memory through two-stage translation
    # SPVP controls privilege level for HLV access
    # ========================================================
    mv t0, a0
    hlv.wu t1, (t0)            # load word from guest memory

    # ========================================================
    # Verify value = 0xDEADBEEF
    # If guest stored correctly through both stages,
    # HLV must read back the same value
    # ========================================================
    li   t2, 0xDEADBEEF
    bne  t1, t2, test_fail     # wrong value -> fail

    # ========================================================
    # Modify value = add 0x100 t0 0xDEADBEEF = 0xDEADBFEF
    # Use HSV.W to write back
    # ========================================================
    li t3, 0x100
    add t1,t1,t3
    hsv.w t1, (t0)
     
    # ========================================================
    # Set next privilege level for the guest
    # ========================================================
    # Set SPP = 1 in sstatus (bit 8)
    li t0, (1 << 8)        
    csrs sstatus, t0  

    # ========================================================
    # Set VS verification code entry point
    # ========================================================
    # Guest will start execution from this address when entering VS-mode again
    la t0, vs_verification    
    csrw sepc, t0    

    # ========================================================
    # Verify fetched instruction from VS code region 
    # ========================================================
    la t0, guest_code       # Load address of guest_code 
    hlvx.wu t1, 0(t0)           # Load inbstruction from memory
    li t2, 0x13
    bne t1,t2,test_fail

    # ========================================================
    # Enter the guest
    # ========================================================
    # Execute sret to switch from HS-mode to VS-mode
    # CPU reads hstatus.SPVs and sstatus.SPP to determine next privilege and PC
    #   SPV = 1 in hstatus → sret sets V=1
    #   SPP = 1 in sstatus → sret sets privilege = supervisor
    # ========================================================
    sret          # → jumps to vs_verification in VS-mode
# ============================================================

.align  12
vs_verification:
    # ==== IN THE Guest (V=1, Priv=VS) ====

    # ========================================================
    # Load modified value 
    # ========================================================
    la t0, load_data       # Load address of known memory
    lwu t1, 0(t0)           # Load from memory

    # ========================================================
    # Verify is loaded value = 0xDEADBFEF
    # ========================================================
    li t2, 0xDEADBFEF      # modified value
    bne  t1, t2, test_fail     # wrong value -> fail

    # ========================================================
    # Execute ecall to trap to HS-mode (Hypervisor)
    # ========================================================
    li a1, 2
    ecall
# ============================================================

# =============================================================
# trap_handler_m — M-mode trap handler 
# =============================================================
trap_handler_m:
    csrr t0, mcause
    # ========================================================
    # Verify this is ecall from HS-mode
    # scause = 9 = environment call from HS/S-mode
    # ========================================================
    li t1, 9
    beq t0, t1, from_supervisor

    j test_fail        # any other M-mode trap = unexpected = fail

from_supervisor:
    # incremented mepc to skip the faulting instruction
    csrr t2, mepc
    addi t2, t2, 4
    csrw mepc, t2
    mret
# =============================================================

# =============================================================
# test_pass / test_fail
# =============================================================
test_pass:
    li   a0, 1
    j    write_tohost

test_fail:
    li   a0, 2
    j    write_tohost

write_tohost:
    la   t5, tohost
    sd   a0, 0(t5)
    j    write_tohost
# ============================================================

# ===============================================================
# Guest hgatp PTE setup
# ===============================================================
# guest_pte_setup - Write ONE leaf PTE into G-stage page tables
# ===============================================================
# Arguments:
#   a0 = guest physical address to map (VA for G-stage lookup)
#   a1 = real physical address to map to
#   a2 = permission bits (U MUST be 1 for G-stage)
#
# G-stage uses Sv39x4:
#   VPN[2] = bits [40:30] = 11 bits  ← wider than normal Sv39
#   VPN[1] = bits [29:21] = 9 bits
#   VPN[0] = bits [20:12] = 9 bits
#
# This function sets up ALL three levels automatically
# using a simple direct-write approach
# ===============================================================
guest_pte_setup:
    # Get G-stage root table address from hgatp
    csrr t0, hgatp
    li   t1, 0xfffffffffff  # 44-bit PPN mask
    and  t0, t0, t1
    slli t0, t0, 12         # t0 = root table physical address

    # Calculate VPN[2] index (11 bits for Sv39x4)
    # In Sv39x4, VPN[2] is bits [40:30] (11 bits)
    srli t2, a0, 30
    li   t3, 0x7FF          # 11-bit mask
    and  t2, t2, t3         # Extract 11-bit VPN[2]
    slli t2, t2, 3          # × 8 bytes per PTE
    add  t4, t0, t2         # t4 = address of root PTE slot in 16KiB root table

    # Check if root PTE already has a valid entry
    ld   t5, 0(t4)
    andi t6, t5, 1          # check valid bit
    bnez t6, guest_setup_level1     # already valid -> follow it

    # Root PTE is empty -> create pointer to guest_level_one_page_table table
    la   t5, guest_level_one_page_table
    srli t5, t5, 12
    slli t5, t5, 10        # position PPN in PTE format
    ori  t5, t5, 0x01      # valid=1, R=W=X=0 -> non-leaf
    sd   t5, 0(t4)         # write into root PTE

guest_setup_level1:
    # Follow root PTE to level-1 table
    ld   t5, 0(t4)
    srli t5, t5, 10
    slli t5, t5, 12       # t5 = level-1 table address

    # Calculate VPN[1] index (9 bits)
    srli t2, a0, 21
    andi t2, t2, 0x1FF
    slli t2, t2, 3
    add  t4, t5, t2       # t4 = address of level-1 PTE slot

    # Check if level-1 PTE already exists
    ld   t5, 0(t4)
    andi t6, t5, 1
    bnez t6, guest_setup_level0

    # Level-one PTE is empty -> create pointer to guest_level_zero_page_table table
    la   t5, guest_level_zero_page_table
    srli t5, t5, 12
    slli t5, t5, 10
    ori  t5, t5, 0x01     # valid=1, R=W=X=0 -> non-leaf
    sd   t5, 0(t4)        # write into level-1 PTE

guest_setup_level0:
    # Follow level-1 PTE to level-0 table
    ld   t5, 0(t4)
    srli t5, t5, 10
    slli t5, t5, 12       # t5 = level-0 table address

    # Calculate VPN[0] index (9 bits)
    srli t2, a0, 12
    andi t2, t2, 0x1FF
    slli t2, t2, 3
    add  t4, t5, t2       # t4 = address of leaf PTE slot

    # write leaf PTE into level-zero
    srli t5, a1, 12       # PPN of target physical address
    slli t5, t5, 10       # position in PTE format
    or   t5, t5, a2       # add permission bits
    sd   t5, 0(t4)        # write leaf PTE

    ret
# ============================================================

# ===============================================================
# Guest VS vsatp PTE setup
# ===============================================================
# guest_vs_pte_setup - Write ONE leaf PTE into VS-stage page tables
# ===============================================================
# Arguments:
#   a0 = guest virtual address to map
#   a1 = guest physical address to map to
#   a2 = permission bits
#
# VS-stage uses Sv39:
#   VPN[2] = bits [38:30] = 9 bits  <- normal Sv39
#   VPN[1] = bits [29:21] = 9 bits
#   VPN[0] = bits [20:12] = 9 bits
# ===============================================================
guest_vs_pte_setup:
    # Get VS-stage root table address from vsatp
    csrr t0, vsatp
    li   t1, 0xfffffffffff
    and  t0, t0, t1
    slli t0, t0, 12       # t0 = VS root table address

    # Calculate VPN[2] index (9 bits for Sv39)
    srli t2, a0, 30
    andi t2, t2, 0x1FF    # 9-bit mask <- different from G-stage
    slli t2, t2, 3
    add  t4, t0, t2       # t4 = root PTE slot address

    # Check if root PTE already exists
    ld   t5, 0(t4)
    andi t6, t5, 1
    bnez t6, guest_vs_setup_level1

    # Root PTE is empty -> create pointer to guest_vs_level_one_page_table table
    la   t5, guest_vs_level_one_page_table
    srli t5, t5, 12
    slli t5, t5, 10       # position PPN in PTE format
    ori  t5, t5, 0x01     # valid=1, R=W=X=0 -> non-leaf
    sd   t5, 0(t4)        # write into root PTE

guest_vs_setup_level1:
    # Follow root PTE to level-1 table
    ld   t5, 0(t4)
    srli t5, t5, 10
    slli t5, t5, 12      # t5 = level-1 table address

    # Calculate VPN[1] index (9 bits)
    srli t2, a0, 21
    andi t2, t2, 0x1FF
    slli t2, t2, 3
    add  t4, t5, t2     # t4 = address of level-1 PTE slot

    # Check if level-1 PTE already exists
    ld   t5, 0(t4)
    andi t6, t5, 1
    bnez t6, guest_vs_setup_level0

    # Level-one PTE is empty -> create pointer to guest_vs_level_zero_page_table table
    la   t5, guest_vs_level_zero_page_table
    srli t5, t5, 12
    slli t5, t5, 10
    ori  t5, t5, 0x01    # valid=1, R=W=X=0 -> non-leaf
    sd   t5, 0(t4)       # write into level-1 PTE

guest_vs_setup_level0:
    # Follow level-1 PTE to level-0 table
    ld   t5, 0(t4)
    srli t5, t5, 10
    slli t5, t5, 12     # t5 = level-0 table address

    # Calculate VPN[0] index (9 bits)
    srli t2, a0, 12
    andi t2, t2, 0x1FF
    slli t2, t2, 3 
    add  t4, t5, t2     # t4 = address of leaf PTE slot

    # write leaf PTE into level-zero
    srli t5, a1, 12     # PPN of target physical address
    slli t5, t5, 10     # position in PTE format
    or   t5, t5, a2     # add permission bits
    sd   t5, 0(t4)      # write leaf PTE

    ret
# ===================----text----end----=========================


# ===================----DATA----start----=======================
.section .data                           
.global data
.align 12                  
load_data:
    .word 0x12345678     # will be overwritten by guest
# ===================----DATA----end----=========================

# ===================----page_region----start----================
.section .page_region,"aw",@progbits                       
.global page_region
.align 14   # 16 KiB alignment (2^14) for Sv39x4 root
guest_root_page_table:
    .space 16384          # 8 bytes space per PTE for 2048 entries. (16k total size for root page table)
.align 12                  # Page tables MUST be 4KB aligned
guest_level_one_page_table:
    .space 4096                 # 8 bytes space per PTE for 512 entries. (4k total size for L1 page table)
guest_level_zero_page_table:
    .space 4096                 # 8 bytes space prt PTE for 512 entries. (4k total size for L2 page table)

guest_vs_root_page_table:
    .space 4096                 # 8 bytes space per PTE for 512 entries. (4k total size for root page table)
guest_vs_level_one_page_table:
    .space 4096                 # 8 bytes space per PTE for 512 entries. (4k total size for L1 page table)
guest_vs_level_zero_page_table:
    .space 4096                 # 8 bytes space prt PTE for 512 entries. (4k total size for L2 page table)
# ===================----page_region----end----==================

# ===================----HTIF----start----=======================
.section .tohost,"aw",@progbits;                                 
.align 6; .global tohost; tohost: .dword 0; .size tohost, 8;         
.align 6; .global fromhost; fromhost: .dword 0; .size fromhost, 8;   
# ===================----HTIF----end----=========================