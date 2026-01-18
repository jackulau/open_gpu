# OpenGPU Test Kernel: Arithmetic Operations
# ============================================
# Tests basic arithmetic operations
# Expected result: x10 = 42 stored at memory address 0
#
# Calculation:
#   x7 = 10
#   x8 = 20
#   x9 = x7 + x8 = 30
#   x10 = x9 + 12 = 42
#   mem[0] = x10 = 42

.kernel test_arithmetic

# Load immediate values
ADDI    x7, x0, 10      # x7 = 10
ADDI    x8, x0, 20      # x8 = 20

# Test ADD
ADD     x9, x7, x8      # x9 = 10 + 20 = 30

# Test ADDI
ADDI    x10, x9, 12     # x10 = 30 + 12 = 42

# Store result to memory
SW      x10, 0(x0)      # mem[0] = 42

# Test SUB
SUB     x11, x10, x7    # x11 = 42 - 10 = 32
SW      x11, 4(x0)      # mem[4] = 32

# Test MUL
ADDI    x12, x0, 3      # x12 = 3
MUL     x13, x7, x12    # x13 = 10 * 3 = 30
SW      x13, 8(x0)      # mem[8] = 30

# Test logical operations
ADDI    x14, x0, 0xFF   # x14 = 255
ADDI    x15, x0, 0x0F   # x15 = 15
AND     x16, x14, x15   # x16 = 255 & 15 = 15
SW      x16, 12(x0)     # mem[12] = 15

OR      x17, x14, x15   # x17 = 255 | 15 = 255
SW      x17, 16(x0)     # mem[16] = 255

# Test shift
SLLI    x18, x7, 2      # x18 = 10 << 2 = 40
SW      x18, 20(x0)     # mem[20] = 40

SRLI    x19, x14, 4     # x19 = 255 >> 4 = 15
SW      x19, 24(x0)     # mem[24] = 15

# Done
RET
