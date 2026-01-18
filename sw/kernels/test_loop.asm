# OpenGPU Test Kernel: Loop
# ==========================
# Computes sum of 1 to 10
# Expected result: x8 = 55 stored at memory address 0
#
# Algorithm:
#   sum = 0
#   for i = 1 to 10:
#     sum += i
#   return sum (should be 55)

.kernel test_loop

# Initialize
ADDI    x7, x0, 10      # x7 = N = 10
ADDI    x8, x0, 0       # x8 = sum = 0
ADDI    x9, x0, 1       # x9 = i = 1

loop:
    ADD     x8, x8, x9      # sum += i
    ADDI    x9, x9, 1       # i++
    BLT     x9, x7, loop    # if i < N, continue (note: this jumps back if i <= 10)
    BEQ     x9, x7, loop    # handle i == N case

# Store result
SW      x8, 0(x0)       # mem[0] = sum = 55

# Done
RET
