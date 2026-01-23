# OpenGPU Test Kernel: Matrix Multiplication
# ==========================================
# Computes C = A x B for NxN matrices using tiled algorithm
#
# This is a simplified version for simulation/testing.
# Uses 4x4 matrices with 4x4 thread blocks.
#
# Register usage:
#   x1  = threadIdx (built-in)
#   x2  = blockIdx (built-in)
#   x3  = blockDim (built-in)
#   x7  = tx (thread x position within block)
#   x8  = ty (thread y position within block)
#   x9  = col (global column index)
#   x10 = row (global row index)
#   x11 = N (matrix dimension)
#   x12 = accumulator for dot product
#   x13 = k loop counter
#   x14 = A element address
#   x15 = B element address
#   x16 = A element value
#   x17 = B element value
#   x18 = temp for address calculation
#   x19 = C element address
#
# Memory layout (4x4 matrices, 16 elements each):
#   0x0000-0x003F: Matrix A (row-major)
#   0x0040-0x007F: Matrix B (row-major)
#   0x0080-0x00BF: Matrix C (output, row-major)
#
# Matrix storage (row-major):
#   A[row][col] at address: base_A + (row * N + col) * 4

.kernel matrix_mul

# Matrix dimension
ADDI    x11, x0, 4          # N = 4

# Calculate thread position within block
# For 4x4 block: tx = threadIdx % 4, ty = threadIdx / 4
ANDI    x7, x1, 0x3         # tx = threadIdx & 3
SRLI    x8, x1, 2           # ty = threadIdx >> 2

# For single-block execution, global position = local position
# col = tx, row = ty
ADD     x9, x0, x7          # col = tx
ADD     x10, x0, x8         # row = ty

# Initialize accumulator
ADDI    x12, x0, 0          # acc = 0

# Initialize k loop counter
ADDI    x13, x0, 0          # k = 0

# Dot product loop: C[row][col] = sum(A[row][k] * B[k][col]) for k=0..N-1
dot_loop:
    # Calculate A[row][k] address
    # addr_A = base_A + (row * N + k) * 4
    MUL     x14, x10, x11       # row * N
    ADD     x14, x14, x13       # row * N + k
    SLLI    x14, x14, 2         # (row * N + k) * 4
    # x14 now has offset from base_A (0x0000)

    # Calculate B[k][col] address
    # addr_B = base_B + (k * N + col) * 4
    MUL     x15, x13, x11       # k * N
    ADD     x15, x15, x9        # k * N + col
    SLLI    x15, x15, 2         # (k * N + col) * 4
    ADDI    x18, x0, 0x40       # base_B = 0x0040
    ADD     x15, x15, x18       # addr_B = base_B + offset

    # Load A[row][k] and B[k][col]
    LW      x16, 0(x14)         # x16 = A[row][k]
    LW      x17, 0(x15)         # x17 = B[k][col]

    # Multiply and accumulate
    MUL     x18, x16, x17       # temp = A[row][k] * B[k][col]
    ADD     x12, x12, x18       # acc += temp

    # Increment k and loop
    ADDI    x13, x13, 1         # k++
    BLT     x13, x11, dot_loop  # if k < N, continue

# Calculate C[row][col] address and store result
# addr_C = base_C + (row * N + col) * 4
MUL     x19, x10, x11       # row * N
ADD     x19, x19, x9        # row * N + col
SLLI    x19, x19, 2         # (row * N + col) * 4
ADDI    x18, x0, 0x80       # base_C = 0x0080
ADD     x19, x19, x18       # addr_C = base_C + offset

# Store result
SW      x12, 0(x19)         # C[row][col] = acc

RET
