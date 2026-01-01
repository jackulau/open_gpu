# OpenGPU

A fully-featured GPU implementation in SystemVerilog, designed from the ground up to teach modern GPU architecture.

Built with comprehensive documentation, a complete 60+ instruction ISA, working compute kernels, and full simulation support with execution traces.

### Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
  - [GPU Top Level](#gpu-top-level)
  - [Streaming Multiprocessor](#streaming-multiprocessor)
  - [Compute Core](#compute-core)
- [Pipeline](#pipeline)
  - [Stages](#stages)
  - [Hazard Handling](#hazard-handling)
  - [Data Forwarding](#data-forwarding)
- [Memory System](#memory-system)
  - [Hierarchy](#hierarchy)
  - [Shared Memory](#shared-memory)
  - [Coalescing](#coalescing)
- [ISA](#isa)
  - [Instruction Formats](#instruction-formats)
  - [Instruction Set](#instruction-set)
  - [Register File](#register-file)
- [SIMT Execution](#simt-execution)
  - [Thread Hierarchy](#thread-hierarchy)
  - [Warp Scheduling](#warp-scheduling)
  - [Branch Divergence](#branch-divergence)
- [Kernels](#kernels)
  - [Vector Addition](#vector-addition)
  - [Sum Reduction](#sum-reduction)
  - [Matrix Multiplication](#matrix-multiplication)
- [Simulation](#simulation)
- [Implementation Roadmap](#implementation-roadmap)

---

# Overview

GPUs power everything from gaming to AI training, yet learning how they actually work at a hardware level is surprisingly difficult.

While CPU architecture is well-documented with countless tutorials and open-source implementations, GPU internals remain largely proprietary. The few open-source GPU projects that exist prioritize feature-completeness over educational clarity, making them challenging to learn from.

**OpenGPU changes this.**

## What is OpenGPU?

> [!IMPORTANT]
> **OpenGPU** is a complete GPU implementation optimized for understanding modern GPU architecture from first principles.
>
> Rather than focusing on graphics-specific hardware, OpenGPU emphasizes the general-purpose compute architecture shared by GPUs, ML accelerators, and tensor processors.

This project explores three fundamental aspects of GPU design:

1. **Parallel Architecture** — How do GPUs achieve massive parallelism with thousands of concurrent threads?
2. **SIMT Execution** — How does Single-Instruction Multiple-Thread execution work in hardware?
3. **Memory Hierarchy** — How do GPUs overcome the memory bandwidth wall?

## Specifications

| Component | Specification |
|-----------|--------------|
| Streaming Multiprocessors | 8 |
| Cores per SM | 4 |
| **Total Cores** | **32** |
| Threads per Warp | 32 |
| Max Concurrent Threads | 4,096 |
| Data Width | 32-bit |
| Instruction Width | 32-bit |
| Pipeline Depth | 5 stages |
| L1 I-Cache | 16 KB per SM |
| L1 D-Cache | 32 KB per SM |
| Shared Memory | 64 KB per SM |
| L2 Cache | 512 KB (shared) |
| Register File | 64 KB per SM |
| Instructions | 60+ |
| Floating Point | IEEE 754 FP32 |

---

# Architecture

## GPU Top Level

![GPU Architecture](doc/diagrams/gpu_top_level.svg)

OpenGPU is organized as a scalable array of Streaming Multiprocessors (SMs) connected through a crossbar to a shared L2 cache and memory controllers.

### Components

**Host Interface**
Receives kernel launch commands and parameters from the host CPU via an AXI-Lite interface. Stores kernel metadata including grid dimensions, block dimensions, and kernel entry point.

**Global Scheduler**
Manages the distribution of thread blocks across available SMs. Tracks block completion and signals kernel done when all blocks finish.

**Streaming Multiprocessors (SMs)**
The primary compute units. Each SM can execute multiple thread blocks concurrently, limited by available resources (registers, shared memory, warp slots).

**L2 Cache**
Shared cache between all SMs. Reduces memory bandwidth requirements by caching frequently accessed data. Split into multiple slices for parallel access.

**Memory Controllers**
Interface between the GPU and external GDDR memory. Handle request arbitration, address mapping, and data transfer scheduling.

---

## Streaming Multiprocessor

![SM Architecture](doc/diagrams/sm_internal.svg)

Each SM is a self-contained compute unit capable of executing hundreds of threads concurrently.

### SM Controller

Manages thread block assignment to the SM. Tracks resource allocation (registers, shared memory, warp slots) and signals the global scheduler when blocks complete.

### Warp Scheduler

Selects which warp to execute each cycle using the **Greedy-Then-Oldest (GTO)** scheduling policy:

1. If the currently executing warp is ready, continue with it (greedy)
2. Otherwise, select the oldest ready warp
3. If no warps are ready, stall

The scheduler maintains a scoreboard tracking pending register writes to detect Read-After-Write (RAW) hazards.

### Compute Cores

Each SM contains 4 compute cores. Every core has:
- **SIMT Stack** — 8-entry stack for handling branch divergence
- **Register File** — 32 registers × 32 threads × 32 bits = 4 KB
- **5-Stage Pipeline** — IF → ID → EX → MEM → WB
- **Integer ALU** — 32-wide for parallel thread execution
- **FP ALU** — 32-wide IEEE 754 single precision

### Shared Resources

| Resource | Size | Details |
|----------|------|---------|
| L1 I-Cache | 16 KB | 4-way associative, 64B lines |
| L1 D-Cache | 32 KB | 4-way associative, 128B lines |
| Shared Memory | 64 KB | 32 banks, 4 bytes each |
| Coalescing Unit | — | Combines memory requests |

---

## Compute Core

Each core executes one warp (32 threads) at a time. The core architecture resembles a traditional CPU, but with 32 parallel datapaths sharing a single instruction stream.

```
                    ┌─────────────────────────────────────┐
                    │           WARP STATE                │
                    │  ┌────────┐ ┌────────┐ ┌─────────┐  │
                    │  │   PC   │ │  Mask  │ │  Stack  │  │
                    │  │ 32-bit │ │ 32-bit │ │ 8-entry │  │
                    │  └────────┘ └────────┘ └─────────┘  │
                    └─────────────────────────────────────┘
                                     │
                    ┌────────────────▼────────────────────┐
                    │         THREAD LANES (×32)          │
                    │  ┌──────┐┌──────┐┌──────┐   ┌──────┐│
                    │  │Lane 0││Lane 1││Lane 2│...│Lane31││
                    │  ├──────┤├──────┤├──────┤   ├──────┤│
                    │  │32 reg││32 reg││32 reg│   │32 reg││
                    │  │ ALU  ││ ALU  ││ ALU  │   │ ALU  ││
                    │  └──────┘└──────┘└──────┘   └──────┘│
                    └─────────────────────────────────────┘
```

---

# Pipeline

![Pipeline Architecture](doc/diagrams/pipeline.svg)

## Stages

### IF — Instruction Fetch
- Access L1 instruction cache using warp program counter
- Handle cache misses by stalling and fetching from L2
- Predict branches (simple static prediction: not taken)

### ID — Instruction Decode
- Decode 32-bit instruction into control signals
- Read source operands from register file (32 parallel reads)
- Generate immediate values with sign/zero extension
- Check scoreboard for data hazards

### EX — Execute
- Perform ALU operations on all 32 threads in parallel
- Evaluate branch conditions
- Calculate memory addresses for load/store
- Handle multi-cycle operations (MUL, DIV, FP)

### MEM — Memory Access
- Access L1 data cache for loads and stores
- Coalesce memory requests from 32 threads
- Handle cache misses
- Sign/zero extend loaded data

### WB — Write Back
- Write results to register file (32 parallel writes)
- Update scoreboard to release pending registers
- Signal instruction completion

## Hazard Handling

| Hazard Type | Detection | Resolution |
|-------------|-----------|------------|
| RAW (Read-After-Write) | Scoreboard | Forwarding or stall |
| Control (Branch) | Branch unit | Flush + redirect |
| Structural | Resource tracking | Stall |

## Data Forwarding

Three forwarding paths minimize pipeline stalls:

```
EX → EX    ALU result available immediately for next instruction
MEM → EX   Load data available after 1 cycle delay
WB → ID    Through register file (if forwarding not possible)
```

---

# Memory System

## Hierarchy

```
┌─────────────────────────────────────────────────────────────┐
│                     MEMORY HIERARCHY                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  REGISTERS         4 KB/core     1 cycle      Per-thread    │
│       │                                                     │
│       ▼                                                     │
│  L1 CACHE          48 KB/SM      ~10 cycles   Per-SM        │
│  (I$ + D$)                                                  │
│       │                                                     │
│       ▼                                                     │
│  SHARED MEM        64 KB/SM      ~20 cycles   Per-SM        │
│  (Software managed)                                         │
│       │                                                     │
│       ▼                                                     │
│  L2 CACHE          512 KB        ~100 cycles  Shared        │
│       │                                                     │
│       ▼                                                     │
│  GLOBAL MEM        4 GB          ~400 cycles  Off-chip      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Address Space

| Range | Region | Size | Description |
|-------|--------|------|-------------|
| `0x00000000` | Global | 256 MB | Main GPU memory |
| `0x20000000` | Constant | 16 MB | Read-only, cached |
| `0x30000000` | Shared | 1 MB | Per-SM local view |
| `0x40000000` | Local | 256 MB | Per-thread stack |

## Shared Memory

Shared memory (Local Data Share) enables fast data sharing between threads in the same block.

**Organization:** 64 KB split into 32 banks of 2 KB each

**Bank Assignment:** `bank = (address >> 2) & 0x1F`

**Access Patterns:**

| Pattern | Example | Cycles |
|---------|---------|--------|
| No conflict | Stride-1 access | 1 |
| Broadcast | All threads same addr | 1 |
| 2-way conflict | Stride-16 | 2 |
| 32-way conflict | Stride-32 | 32 |

## Coalescing

The coalescing unit combines memory requests from 32 threads into minimal cache line transactions.

```
PERFECT COALESCING
Thread 0:  0x1000 ─┐
Thread 1:  0x1004  │
Thread 2:  0x1008  ├──▶  1 cache line request (128B)
   ...             │
Thread 31: 0x107C ─┘

SCATTERED ACCESS
Thread 0:  0x1000 ──▶  Request 1
Thread 1:  0x2000 ──▶  Request 2
Thread 2:  0x3000 ──▶  Request 3
   ...                    ...
```

---

# ISA

## Instruction Formats

![Instruction Formats](doc/diagrams/instruction_formats.svg)

All instructions are 32 bits with a 6-bit opcode:

| Format | Fields | Used By |
|--------|--------|---------|
| R-Type | opcode, rd, rs1, rs2, func | Arithmetic, logical |
| I-Type | opcode, rd, rs1, imm16 | Immediate ops, loads |
| S-Type | opcode, rs2, rs1, offset | Stores |
| B-Type | opcode, rs1, rs2, offset | Branches |
| U-Type | opcode, rd, imm21 | LUI, JAL |

## Instruction Set

### Integer Arithmetic
| Instruction | Operation | Description |
|-------------|-----------|-------------|
| `ADD rd, rs1, rs2` | rd = rs1 + rs2 | Add |
| `ADDI rd, rs1, imm` | rd = rs1 + imm | Add immediate |
| `SUB rd, rs1, rs2` | rd = rs1 - rs2 | Subtract |
| `MUL rd, rs1, rs2` | rd = rs1 × rs2 | Multiply (low 32 bits) |
| `DIV rd, rs1, rs2` | rd = rs1 ÷ rs2 | Divide (signed) |
| `REM rd, rs1, rs2` | rd = rs1 % rs2 | Remainder |

### Logical & Shift
| Instruction | Operation | Description |
|-------------|-----------|-------------|
| `AND rd, rs1, rs2` | rd = rs1 & rs2 | Bitwise AND |
| `OR rd, rs1, rs2` | rd = rs1 \| rs2 | Bitwise OR |
| `XOR rd, rs1, rs2` | rd = rs1 ^ rs2 | Bitwise XOR |
| `SLL rd, rs1, rs2` | rd = rs1 << rs2 | Shift left |
| `SRL rd, rs1, rs2` | rd = rs1 >> rs2 | Shift right logical |
| `SRA rd, rs1, rs2` | rd = rs1 >>> rs2 | Shift right arithmetic |

### Memory
| Instruction | Operation | Description |
|-------------|-----------|-------------|
| `LW rd, offset(rs1)` | rd = mem[rs1+offset] | Load word |
| `SW rs2, offset(rs1)` | mem[rs1+offset] = rs2 | Store word |
| `LB/LH` | Load byte/halfword | With sign extension |
| `LBU/LHU` | Load byte/halfword | Zero extended |

### Control Flow
| Instruction | Operation | Description |
|-------------|-----------|-------------|
| `BEQ rs1, rs2, offset` | if (rs1 == rs2) PC += offset | Branch equal |
| `BNE rs1, rs2, offset` | if (rs1 != rs2) PC += offset | Branch not equal |
| `BLT rs1, rs2, offset` | if (rs1 < rs2) PC += offset | Branch less than |
| `JAL rd, offset` | rd = PC+4; PC += offset | Jump and link |
| `RET` | — | End thread execution |

### Floating Point
| Instruction | Operation | Description |
|-------------|-----------|-------------|
| `FADD rd, rs1, rs2` | rd = rs1 + rs2 | FP add |
| `FMUL rd, rs1, rs2` | rd = rs1 × rs2 | FP multiply |
| `FMADD rd, rs1, rs2, rs3` | rd = rs1×rs2 + rs3 | Fused multiply-add |

### GPU Special
| Instruction | Description |
|-------------|-------------|
| `SYNC` | Block-level barrier synchronization |
| `VOTE.ALL/ANY/BAL` | Warp vote operations |
| `SHFL.*` | Warp shuffle (exchange data between lanes) |

## Register File

Each thread has 32 registers. Special registers provide execution context:

| Register | Name | Description |
|----------|------|-------------|
| x0 | zero | Hardwired to 0 |
| x1 | threadIdx | Thread index within block |
| x2 | blockIdx | Block index within grid |
| x3 | blockDim | Threads per block |
| x4 | gridDim | Blocks per grid |
| x5 | warpIdx | Warp index within block |
| x6 | laneIdx | Lane index within warp (0-31) |
| x7-x31 | — | General purpose |

---

# SIMT Execution

## Thread Hierarchy

```
                          GRID
            ┌──────────────┴──────────────┐
            │                             │
        ┌───┴───┐                     ┌───┴───┐
        │Block 0│                     │Block N│
        └───┬───┘                     └───────┘
            │
   ┌────────┼────────┬────────┐
   │        │        │        │
┌──┴──┐  ┌──┴──┐  ┌──┴──┐  ┌──┴──┐
│Warp0│  │Warp1│  │Warp2│  │Warp3│
└──┬──┘  └─────┘  └─────┘  └─────┘
   │
   ├── Thread 0
   ├── Thread 1
   ├── ...
   └── Thread 31
```

## Warp Scheduling

The warp scheduler selects a ready warp each cycle. Warps become not-ready when:
- Waiting for memory (cache miss)
- Data hazard (RAW dependency)
- Barrier synchronization
- Long-latency operation (DIV, SQRT)

**GTO Algorithm:**
```
if (current_warp.ready):
    return current_warp           # Greedy: stay on same warp
for warp in warps_by_age:
    if (warp.ready):
        return warp               # Oldest ready warp
return STALL
```

## Branch Divergence

When threads in a warp take different branch paths, the SIMT stack manages divergent execution:

```
                     ┌─────────────────────────────────┐
                     │         SIMT STACK              │
                     │  ┌─────────┬────────┬────────┐  │
                     │  │Reconv PC│  Mask  │Next PC │  │
                     │  ├─────────┼────────┼────────┤  │
                     │  │  0x120  │ 0xFFFF │ 0x108  │  │  Entry 0
                     │  │  0x140  │ 0x00FF │ 0x128  │  │  Entry 1
                     │  │   ...   │  ...   │  ...   │  │
                     │  └─────────┴────────┴────────┘  │
                     └─────────────────────────────────┘
```

**Divergence Handling:**
1. On divergent branch, push reconvergence point to stack
2. Execute taken-path with subset of threads (mask active threads)
3. At reconvergence point, pop stack and execute not-taken path
4. When stack empty, all threads reconverged

---

# Kernels

## Vector Addition

Adds two vectors element-wise: `C[i] = A[i] + B[i]`

```asm
# Vector Addition Kernel
# Grid: N/256 blocks, Block: 256 threads

MUL     x7, x2, x3          # global_id = blockIdx * blockDim
ADD     x7, x7, x1          # global_id += threadIdx

SLLI    x8, x7, 2           # byte_offset = global_id * 4

ADD     x9, x10, x8         # addr_A = base_A + offset
ADD     x10, x11, x8        # addr_B = base_B + offset
ADD     x11, x12, x8        # addr_C = base_C + offset

LW      x13, 0(x9)          # load A[i]
LW      x14, 0(x10)         # load B[i]

ADD     x15, x13, x14       # C[i] = A[i] + B[i]

SW      x15, 0(x11)         # store C[i]

RET
```

## Sum Reduction

Computes sum of 1 to N using parallel reduction pattern:

```asm
# Sum Reduction Kernel
# Computes: sum = 1 + 2 + 3 + ... + N

ADDI    x7, x0, 10          # N = 10
ADDI    x8, x0, 0           # sum = 0
ADDI    x9, x0, 1           # i = 1

loop:
    ADD     x8, x8, x9      # sum += i
    ADDI    x9, x9, 1       # i++
    BLT     x9, x7, loop    # while i < N
    BEQ     x9, x7, loop    # include i == N

SW      x8, 0(x0)           # store result (55)
RET
```

## Matrix Multiplication

Multiplies two NxN matrices using tiled algorithm with shared memory:

```asm
# Matrix Multiplication with Shared Memory Tiling
# C = A × B, using 16×16 tiles

# Calculate thread position
ANDI    x7, x1, 0xF         # tx = threadIdx & 15
SRLI    x8, x1, 4           # ty = threadIdx >> 4

# Calculate global position
SLLI    x9, x2, 4
ANDI    x10, x9, 0xF0       # col_base = (blockIdx & 0xF) * 16
SRLI    x11, x2, 4
SLLI    x11, x11, 4         # row_base = (blockIdx >> 4) * 16

ADD     x12, x10, x7        # col = col_base + tx
ADD     x13, x11, x8        # row = row_base + ty

# Initialize accumulator
ADDI    x20, x0, 0          # acc = 0

# Tile loop
ADDI    x14, x0, 0          # k = 0
tile_loop:
    # Load A tile to shared memory
    # ... (tile loading)

    SYNC                    # Barrier

    # Compute partial products
    # ... (16 multiply-adds)

    SYNC                    # Barrier

    ADDI    x14, x14, 16    # k += TILE_SIZE
    BLT     x14, x4, tile_loop

# Store result
# ... (store C[row][col])
RET
```

---

# Simulation

## Prerequisites

Install the required tools:

```bash
# macOS
brew install icarus-verilog

# Ubuntu/Debian
sudo apt install iverilog

# Python dependencies
pip3 install cocotb
```

## Running Tests

```bash
# Compile and run all tests
make sim

# Run specific test
make test

# Assemble a kernel
python3 sw/assembler/opengpu_asm.py sw/kernels/test_arithmetic.asm

# View waveforms (requires GTKWave)
make wave
```

## Execution Trace

The simulation produces detailed execution traces showing cycle-by-cycle state:

```
╔══════════════════════════════════════════════════════════════════╗
║ Cycle: 42  |  State: EXECUTE  |  PC: 0x0010                      ║
╠══════════════════════════════════════════════════════════════════╣
║ Instruction: ADD x9, x7, x8                                      ║
║ Opcode: 0x00  |  rd: 9  |  rs1: 7  |  rs2: 8                     ║
╠══════════════════════════════════════════════════════════════════╣
║ Registers:                                                       ║
║   x7 = 10  |  x8 = 20  |  x9 = 30 (written)                      ║
╠══════════════════════════════════════════════════════════════════╣
║ Memory: No access                                                ║
╚══════════════════════════════════════════════════════════════════╝
```

---

# Implementation Roadmap

## Completed

- [x] **Phase 1: Minimal Core** — Single-threaded FSM-based core
  - 60+ instruction ISA
  - Integer ALU with all operations
  - Register file with GPU context
  - Memory interface with byte/half/word access
  - Python assembler
  - Basic testbench

## In Progress

- [ ] **Phase 2: Pipelining**
  - 5-stage pipeline implementation
  - Scoreboard for hazard detection
  - Data forwarding paths
  - Branch prediction

## Planned

- [ ] **Phase 3: SIMT Execution**
  - 32 threads per warp
  - Warp scheduler with GTO policy
  - SIMT stack for branch divergence
  - Barrier synchronization

- [ ] **Phase 4: Memory Hierarchy**
  - L1 instruction cache
  - L1 data cache
  - L2 shared cache
  - Shared memory with bank conflict detection
  - Memory coalescing unit

- [ ] **Phase 5: Full System**
  - IEEE 754 FP32 unit
  - 8 SMs (32 total cores)
  - Global block scheduler
  - Host interface (AXI-Lite)

---

## Contributing

Contributions are welcome! Areas of interest:

- Pipeline hazard handling improvements
- Cache implementation
- SIMT stack and divergence handling
- FPU implementation
- Test kernels and verification

## License

MIT License — See LICENSE for details.
