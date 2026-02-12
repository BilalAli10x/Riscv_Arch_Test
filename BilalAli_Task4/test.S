.section .text.init
.align 6
.global _start

_start:
    # ===========================================================
    # - FS = OFF(00), CLEAN(01), DIRTY(11)
    # - SD = 1 if any of FS, XS, VS = DIRTY
    # -----------------------------------------------------------

    # ===========================================================
    # Initial state: FS=OFF
    # ===========================================================
    csrr t0, mstatus
    li t1, ~(3 << 13)      # cleared FS[14:13] bits
    and t0, t0, t1
    csrw mstatus, t0

    # ----------------------
    # Checking is FS=OFF
    # ----------------------
    csrr t2, mstatus
    srli t3, t2, 13          # shift FS to LSB
    andi t3, t3, 0x3         # mask 2 bits
    li t4, 0x0
    bne t3, t4, fail_fs_off  # if not 00, fail
    # SD should be 0 if FS off as other extensions also disabled
    srli t5, t2, 31        # SD = mstatus[31]
    bnez t5, fail_sd_off

    # ===========================================================
    # Set FS=CLEAN
    # ===========================================================
    csrr t0, mstatus        
    li t1, ~(3 << 13)       # mask to clear FS[14:13]
    and t0, t0, t1          
    li t1, (1 << 13)       # FS[14:13] bit to = 01 (CLEAN)
    or t0, t0, t1           
    csrw mstatus, t0        

    # ----------------------
    # Verifying is FS=CLEAN
    # ----------------------
    csrr t3, mstatus
    srli t4, t3, 13
    andi t4, t4, 0x3
    li t5, 0x1
    bne t4, t5, fail_fs_clean
    # SD should still be 0
    srli t6, t3, 31
    bnez t6, fail_sd_clean

    # ===========================================================
    # Set FS=DIRTY (write FP register) 
    # ===========================================================
    li t0, 0x12345678
    fmv.w.x ft0, t0           # writing FP reg triggers FS=DIRTY

    # ----------------------
    # Verifying is FS=DIRTY
    # ----------------------
    csrr t1, mstatus
    srli t2, t1, 13
    andi t2, t2, 0x3
    li t3, 0x3
    bne t2, t3, fail_fs_dirty
    # SD should become 1
    srli t4, t1, 31
    beqz t4, fail_sd_dirty

# Test PASS
pass:
    li gp, 1
    sw gp, tohost, t0
    j pass

# Test FAIL Labels
fail_fs_off:
fail_sd_off:
fail_fs_clean:
fail_sd_clean:
fail_fs_dirty:
fail_sd_dirty:
    li gp, 2
    sw gp, tohost, t0
    j fail_sd_dirty

.section .tohost,"aw",@progbits
.align 6
.global tohost
tohost: .dword 0
.size tohost, 8;

.align 6
.global fromhost
fromhost: .dword 0
.size fromhost, 8;
