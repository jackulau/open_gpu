# OpenGPU Test Kernel: Parallel Reduction Patterns
# ================================================
# Demonstrates various reduction operations common in GPU computing.
#
# This kernel includes:
#   1. Sum reduction (sequential baseline)
#   2. Max reduction
#   3. Min reduction
#   4. Product reduction
#
# Memory layout:
#   0x0000-0x003F: Input array (16 elements)
#   0x0040: Sum result
#   0x0044: Max result
#   0x0048: Min result
#   0x004C: Product result
#
# Test data (initialized externally):
#   arr = [5, 3, 8, 1, 9, 2, 7, 4, 6, 10, 12, 11, 15, 13, 14, 16]
#   Expected: sum=136, max=16, min=1, product=(overflow for 32-bit)

.kernel reduction

# Initialize parameters
ADDI    x7, x0, 16          # N = 16 elements
ADDI    x8, x0, 0           # loop counter i = 0
ADDI    x9, x0, 0           # base address = 0x0000

# Initialize reduction variables
ADDI    x10, x0, 0          # sum = 0
LW      x11, 0(x9)          # max = arr[0]
LW      x12, 0(x9)          # min = arr[0]
ADDI    x13, x0, 1          # product = 1

# ============================================
# Main reduction loop
# ============================================
reduce_loop:
    # Calculate address: addr = base + i * 4
    SLLI    x14, x8, 2          # offset = i * 4
    ADD     x15, x9, x14        # addr = base + offset

    # Load current element
    LW      x16, 0(x15)         # x16 = arr[i]

    # --- Sum reduction ---
    ADD     x10, x10, x16       # sum += arr[i]

    # --- Max reduction ---
    # if (arr[i] > max) max = arr[i]
    SLT     x17, x11, x16       # x17 = (max < arr[i]) ? 1 : 0
    BEQ     x17, x0, skip_max   # if not greater, skip
    ADD     x11, x0, x16        # max = arr[i]
skip_max:

    # --- Min reduction ---
    # if (arr[i] < min) min = arr[i]
    SLT     x17, x16, x12       # x17 = (arr[i] < min) ? 1 : 0
    BEQ     x17, x0, skip_min   # if not less, skip
    ADD     x12, x0, x16        # min = arr[i]
skip_min:

    # --- Product reduction ---
    MUL     x13, x13, x16       # product *= arr[i]

    # Increment and loop
    ADDI    x8, x8, 1           # i++
    BLT     x8, x7, reduce_loop # if i < N, continue

# ============================================
# Store results
# ============================================
ADDI    x18, x0, 0x40       # result base address
SW      x10, 0(x18)         # mem[0x40] = sum
SW      x11, 4(x18)         # mem[0x44] = max
SW      x12, 8(x18)         # mem[0x48] = min
SW      x13, 12(x18)        # mem[0x4C] = product

RET


# ============================================
# Parallel Tree Reduction (Warp-Level)
# ============================================
# This section demonstrates warp-level parallel reduction
# using shuffle instructions (requires warp support)
#
# For a 32-thread warp, parallel reduction takes log2(32) = 5 steps
# Each step halves the active data by combining pairs
#
# Note: SHFLDN instruction not yet in assembler, shown as pseudocode

.kernel parallel_sum_warp

# Load element for this thread
# x7 = data[threadIdx]
SLLI    x8, x1, 2           # offset = threadIdx * 4
LW      x7, 0(x8)           # x7 = data[threadIdx]

# Step 1: Combine with thread+16
# x9 = shfl_down(x7, 16)   # SHFLDN x9, x7, 16
# ADD x7, x7, x9

# Step 2: Combine with thread+8
# x9 = shfl_down(x7, 8)    # SHFLDN x9, x7, 8
# ADD x7, x7, x9

# Step 3: Combine with thread+4
# x9 = shfl_down(x7, 4)    # SHFLDN x9, x7, 4
# ADD x7, x7, x9

# Step 4: Combine with thread+2
# x9 = shfl_down(x7, 2)    # SHFLDN x9, x7, 2
# ADD x7, x7, x9

# Step 5: Combine with thread+1
# x9 = shfl_down(x7, 1)    # SHFLDN x9, x7, 1
# ADD x7, x7, x9

# Thread 0 now has the sum
# Store if threadIdx == 0
BNE     x1, x0, done
SW      x7, 0(x0)           # store final sum

done:
RET
