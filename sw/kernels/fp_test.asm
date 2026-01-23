# OpenGPU Test Kernel: Floating-Point Operations
# ===============================================
# Tests floating-point arithmetic operations.
#
# NOTE: This kernel requires FPU support which is not yet implemented.
# The FP instructions are defined in RTL (pkg_opengpu.sv) but not
# yet in the assembler. This file serves as a template/specification
# for when FP support is added.
#
# FP Opcodes (from RTL):
#   FADD  = 0x20  - Floating-point add
#   FSUB  = 0x21  - Floating-point subtract
#   FMUL  = 0x22  - Floating-point multiply
#   FDIV  = 0x23  - Floating-point divide
#   FMADD = 0x24  - Fused multiply-add: rd = rs1*rs2 + rs3
#   FMSUB = 0x25  - Fused multiply-sub: rd = rs1*rs2 - rs3
#   FSQRT = 0x26  - Square root
#   FABS  = 0x27  - Absolute value
#   FNEG  = 0x28  - Negate
#   FMIN  = 0x29  - Minimum
#   FMAX  = 0x2A  - Maximum
#   FCVTWS = 0x2B - Convert float to int
#   FCVTSW = 0x2C - Convert int to float
#   FCMPEQ = 0x2D - Compare equal
#   FCMPLT = 0x2E - Compare less than
#   FCMPLE = 0x2F - Compare less or equal
#
# Memory layout (IEEE 754 single-precision):
#   0x0000: float a = 3.14159
#   0x0004: float b = 2.71828
#   0x0008: float c (output: a + b)
#   0x000C: float d (output: a * b)
#   0x0010: float e (output: sqrt(a))
#   0x0014: int f (output: int(a))

.kernel fp_test

# ============================================
# Integer-only placeholder until FPU is ready
# ============================================
# This uses integer operations as a standin to test kernel structure.
# Replace with FP ops when assembler support is added.

# Load test values (as integers for now)
ADDI    x7, x0, 314         # placeholder for 3.14
ADDI    x8, x0, 271         # placeholder for 2.71

# Placeholder operations (integer standin for FP)
ADD     x9, x7, x8          # standin for FADD
SW      x9, 8(x0)           # store result

MUL     x10, x7, x8         # standin for FMUL
SW      x10, 12(x0)         # store result

# Store original values for reference
SW      x7, 0(x0)           # store a
SW      x8, 4(x0)           # store b

RET

# ============================================
# FP Test Cases (pseudocode for future)
# ============================================
# When FP is implemented, replace above with:
#
# .kernel fp_test_real
#
# # Load FP values
# LW      x7, 0(x0)           # x7 = a (3.14159 as float bits)
# LW      x8, 4(x0)           # x8 = b (2.71828 as float bits)
#
# # Test FADD: c = a + b
# FADD    x9, x7, x8          # x9 = 3.14159 + 2.71828 = 5.85987
# SW      x9, 8(x0)           # store c
#
# # Test FSUB: d = a - b
# FSUB    x10, x7, x8         # x10 = 3.14159 - 2.71828 = 0.42331
# SW      x10, 12(x0)         # store d
#
# # Test FMUL: e = a * b
# FMUL    x11, x7, x8         # x11 = 3.14159 * 2.71828 = 8.53973
# SW      x11, 16(x0)         # store e
#
# # Test FDIV: f = a / b
# FDIV    x12, x7, x8         # x12 = 3.14159 / 2.71828 = 1.15573
# SW      x12, 20(x0)         # store f
#
# # Test FSQRT: g = sqrt(a)
# FSQRT   x13, x7             # x13 = sqrt(3.14159) = 1.77245
# SW      x13, 24(x0)         # store g
#
# # Test FABS: h = abs(-a)
# FNEG    x14, x7             # x14 = -a
# FABS    x15, x14            # x15 = abs(-a) = a
# SW      x15, 28(x0)         # store h
#
# # Test FMIN/FMAX
# FMIN    x16, x7, x8         # x16 = min(a, b) = b
# FMAX    x17, x7, x8         # x17 = max(a, b) = a
# SW      x16, 32(x0)         # store min
# SW      x17, 36(x0)         # store max
#
# # Test conversion
# FCVTWS  x18, x7             # x18 = int(a) = 3
# SW      x18, 40(x0)         # store as integer
#
# ADDI    x19, x0, 42         # x19 = 42 (integer)
# FCVTSW  x20, x19            # x20 = float(42) = 42.0
# SW      x20, 44(x0)         # store as float
#
# # Test FMADD: fma = a * b + c
# LW      x21, 8(x0)          # load c
# FMADD   x22, x7, x8, x21    # x22 = a*b + c
# SW      x22, 48(x0)         # store fma result
#
# # Test comparisons
# FCMPEQ  x23, x7, x8         # x23 = (a == b) ? 1 : 0 = 0
# FCMPLT  x24, x8, x7         # x24 = (b < a) ? 1 : 0 = 1
# FCMPLE  x25, x7, x7         # x25 = (a <= a) ? 1 : 0 = 1
# SW      x23, 52(x0)         # store eq result
# SW      x24, 56(x0)         # store lt result
# SW      x25, 60(x0)         # store le result
#
# RET
