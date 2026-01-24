# OpenGPU Test Kernel: Floating-Point Operations
# ===============================================
# Tests all FPU operations on the OpenGPU.
#
# IEEE 754 single-precision encoding reference:
#   1.0  = 0x3F800000 (LUI 0x7F000)
#   2.0  = 0x40000000 (LUI 0x80000)
#   3.0  = 0x40400000 (LUI 0x80800)
#   4.0  = 0x40800000 (LUI 0x81000)
#   5.0  = 0x40A00000 (LUI 0x81400)
#   6.0  = 0x40C00000 (LUI 0x81800)
#   0.5  = 0x3F000000 (LUI 0x7E000)
#   -2.0 = 0xC0000000
#
# LUI loads imm21 << 11, so:
#   For 0x40000000, we need imm21 = 0x40000000 >> 11 = 0x80000

.kernel fp_test

# ============================================
# Load floating-point constants
# ============================================

# Load 2.0 into x10 (0x40000000)
LUI   x10, 0x80000    # x10 = 0x80000 << 11 = 0x40000000 (2.0)

# Load 3.0 into x11 (0x40400000)
LUI   x11, 0x80800    # x11 = 0x80800 << 11 = 0x40400000 (3.0)

# ============================================
# Test FP Arithmetic Operations
# ============================================

# FADD: x12 = x10 + x11 = 2.0 + 3.0 = 5.0 (0x40A00000)
FADD  x12, x10, x11

# FSUB: x13 = x11 - x10 = 3.0 - 2.0 = 1.0 (0x3F800000)
FSUB  x13, x11, x10

# FMUL: x14 = x10 * x11 = 2.0 * 3.0 = 6.0 (0x40C00000)
FMUL  x14, x10, x11

# ============================================
# Test FP Unary Operations
# ============================================

# FABS: x15 = |x10| = 2.0 (positive input stays same)
FABS  x15, x10

# FNEG: x16 = -x10 = -2.0 (0xC0000000)
FNEG  x16, x10

# ============================================
# Test FP Compare Operations
# ============================================

# FMIN: x17 = min(x10, x11) = min(2.0, 3.0) = 2.0
FMIN  x17, x10, x11

# FMAX: x18 = max(x10, x11) = max(2.0, 3.0) = 3.0
FMAX  x18, x10, x11

# FCMPLT: x19 = (x10 < x11) = (2.0 < 3.0) = 1
FCMPLT x19, x10, x11

# FCMPEQ: x20 = (x10 == x11) = (2.0 == 3.0) = 0
FCMPEQ x20, x10, x11

# FCMPLE: x21 = (x10 <= x11) = (2.0 <= 3.0) = 1
FCMPLE x21, x10, x11

# ============================================
# Test FP Conversions
# ============================================

# Integer to float: FCVTSW
ADDI  x7, x0, 7       # x7 = 7 (integer)
FCVTSW x22, x7        # x22 = 7.0 (0x40E00000)

# Float to integer: FCVTWS
FCVTWS x23, x12       # x23 = int(5.0) = 5 (integer)

# ============================================
# Store results to memory for verification
# ============================================
SW    x10, 0(x0)      # mem[0]  = input 2.0
SW    x11, 4(x0)      # mem[4]  = input 3.0
SW    x12, 8(x0)      # mem[8]  = FADD result (5.0)
SW    x13, 12(x0)     # mem[12] = FSUB result (1.0)
SW    x14, 16(x0)     # mem[16] = FMUL result (6.0)
SW    x16, 20(x0)     # mem[20] = FNEG result (-2.0)
SW    x19, 24(x0)     # mem[24] = FCMPLT result (1)
SW    x20, 28(x0)     # mem[28] = FCMPEQ result (0)
SW    x22, 32(x0)     # mem[32] = FCVTSW result (7.0)
SW    x23, 36(x0)     # mem[36] = FCVTWS result (5)

RET

# ============================================
# Expected Results:
# ============================================
# mem[0]  = 0x40000000 (2.0)
# mem[4]  = 0x40400000 (3.0)
# mem[8]  = 0x40A00000 (5.0)  - FADD
# mem[12] = 0x3F800000 (1.0)  - FSUB
# mem[16] = 0x40C00000 (6.0)  - FMUL
# mem[20] = 0xC0000000 (-2.0) - FNEG
# mem[24] = 0x00000001 (1)    - FCMPLT
# mem[28] = 0x00000000 (0)    - FCMPEQ
# mem[32] = 0x40E00000 (7.0)  - FCVTSW
# mem[36] = 0x00000005 (5)    - FCVTWS
