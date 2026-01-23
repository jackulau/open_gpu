# OpenGPU Test Kernel: Vector Addition
# =====================================
# Adds two vectors element-wise: C[i] = A[i] + B[i]
#
# Register usage:
#   x1  = threadIdx (built-in)
#   x2  = blockIdx (built-in)
#   x3  = blockDim (built-in)
#   x7  = global_id
#   x8  = byte_offset
#   x9  = addr_A
#   x10 = addr_B
#   x11 = addr_C
#   x12 = A[i] value
#   x13 = B[i] value
#   x14 = C[i] result
#
# Memory layout (for simulation with small vectors):
#   0x0000-0x003F: Vector A (16 elements)
#   0x0040-0x007F: Vector B (16 elements)
#   0x0080-0x00BF: Vector C (16 elements, output)
#
# Expected: C[i] = A[i] + B[i] for all i

.kernel vector_add

# Calculate global thread ID
# global_id = blockIdx * blockDim + threadIdx
MUL     x7, x2, x3          # x7 = blockIdx * blockDim
ADD     x7, x7, x1          # x7 = global_id

# Calculate byte offset (4 bytes per element)
SLLI    x8, x7, 2           # byte_offset = global_id * 4

# Calculate addresses for A, B, C
# Base addresses: A=0x0000, B=0x0040, C=0x0080
ADDI    x9, x8, 0           # addr_A = 0x0000 + offset
ADDI    x10, x0, 0x40       # base_B = 0x0040
ADD     x10, x10, x8        # addr_B = base_B + offset
ADDI    x11, x0, 0x80       # base_C = 0x0080
ADD     x11, x11, x8        # addr_C = base_C + offset

# Load values from A and B
LW      x12, 0(x9)          # x12 = A[i]
LW      x13, 0(x10)         # x13 = B[i]

# Compute C[i] = A[i] + B[i]
ADD     x14, x12, x13       # x14 = A[i] + B[i]

# Store result to C
SW      x14, 0(x11)         # C[i] = result

RET
