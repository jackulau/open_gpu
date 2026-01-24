// OpenGPU global parameters, types, and interfaces

package pkg_opengpu;

  // Data widths
  parameter int DATA_WIDTH     = 32;
  parameter int ADDR_WIDTH     = 32;
  parameter int INSTR_WIDTH    = 32;

  // Register file
  parameter int NUM_REGS       = 32;
  parameter int REG_ADDR_WIDTH = 5;

  // Memory (64KB for sim)
  parameter int MEM_SIZE       = 65536;
  parameter int MEM_ADDR_WIDTH = 16;

  // SIMT config
  parameter int WARP_SIZE      = 32;
  parameter int WARPS_PER_CORE = 4;
  parameter int CORES_PER_SM   = 4;
  parameter int NUM_SMS        = 8;

  // Instruction formats:
  // R-Type: [31:26] opcode | [25:21] rd | [20:16] rs1 | [15:11] rs2 | [10:0] func
  // I-Type: [31:26] opcode | [25:21] rd | [20:16] rs1 | [15:0] imm16
  // S-Type: [31:26] opcode | [25:21] rs2 | [20:16] rs1 | [15:0] offset
  // B-Type: [31:26] opcode | [25:21] cond | [20:16] rs1 | [15:0] offset
  // U-Type: [31:26] opcode | [25:21] rd | [20:0] imm21

  parameter int OPCODE_WIDTH   = 6;
  parameter int REG_FIELD_WIDTH = 5;
  parameter int FUNC_WIDTH     = 11;
  parameter int IMM16_WIDTH    = 16;
  parameter int IMM21_WIDTH    = 21;

  // Field positions
  parameter int OPCODE_MSB     = 31;
  parameter int OPCODE_LSB     = 26;
  parameter int RD_MSB         = 25;
  parameter int RD_LSB         = 21;
  parameter int RS1_MSB        = 20;
  parameter int RS1_LSB        = 16;
  parameter int RS2_MSB        = 15;
  parameter int RS2_LSB        = 11;
  parameter int FUNC_MSB       = 10;
  parameter int FUNC_LSB       = 0;
  parameter int IMM16_MSB      = 15;
  parameter int IMM16_LSB      = 0;
  parameter int IMM21_MSB      = 20;
  parameter int IMM21_LSB      = 0;

  typedef logic [OPCODE_WIDTH-1:0] opcode_t;

  // Integer arithmetic
  parameter opcode_t OP_ADD    = 6'h00;
  parameter opcode_t OP_ADDI   = 6'h01;
  parameter opcode_t OP_SUB    = 6'h02;
  parameter opcode_t OP_MUL    = 6'h03;
  parameter opcode_t OP_MULH   = 6'h04;
  parameter opcode_t OP_DIV    = 6'h05;
  parameter opcode_t OP_DIVU   = 6'h06;
  parameter opcode_t OP_REM    = 6'h07;
  parameter opcode_t OP_REMU   = 6'h08;

  // Logical & shift
  parameter opcode_t OP_AND    = 6'h10;
  parameter opcode_t OP_ANDI   = 6'h11;
  parameter opcode_t OP_OR     = 6'h12;
  parameter opcode_t OP_ORI    = 6'h13;
  parameter opcode_t OP_XOR    = 6'h14;
  parameter opcode_t OP_XORI   = 6'h15;
  parameter opcode_t OP_NOT    = 6'h16;
  parameter opcode_t OP_SLL    = 6'h17;
  parameter opcode_t OP_SLLI   = 6'h18;
  parameter opcode_t OP_SRL    = 6'h19;
  parameter opcode_t OP_SRLI   = 6'h1A;
  parameter opcode_t OP_SRA    = 6'h1B;
  parameter opcode_t OP_SRAI   = 6'h1C;

  // Floating-point
  parameter opcode_t OP_FADD   = 6'h20;
  parameter opcode_t OP_FSUB   = 6'h21;
  parameter opcode_t OP_FMUL   = 6'h22;
  parameter opcode_t OP_FDIV   = 6'h23;
  parameter opcode_t OP_FMADD  = 6'h24;
  parameter opcode_t OP_FMSUB  = 6'h25;
  parameter opcode_t OP_FSQRT  = 6'h26;
  parameter opcode_t OP_FABS   = 6'h27;
  parameter opcode_t OP_FNEG   = 6'h28;
  parameter opcode_t OP_FMIN   = 6'h29;
  parameter opcode_t OP_FMAX   = 6'h2A;
  parameter opcode_t OP_FCVTWS = 6'h2B;
  parameter opcode_t OP_FCVTSW = 6'h2C;
  parameter opcode_t OP_FCMPEQ = 6'h2D;
  parameter opcode_t OP_FCMPLT = 6'h2E;
  parameter opcode_t OP_FCMPLE = 6'h2F;

  // Memory
  parameter opcode_t OP_LW     = 6'h30;
  parameter opcode_t OP_LH     = 6'h31;
  parameter opcode_t OP_LHU    = 6'h32;
  parameter opcode_t OP_LB     = 6'h33;
  parameter opcode_t OP_LBU    = 6'h34;
  parameter opcode_t OP_SW     = 6'h35;
  parameter opcode_t OP_SH     = 6'h36;
  parameter opcode_t OP_SB     = 6'h37;
  parameter opcode_t OP_LDSLW  = 6'h38;
  parameter opcode_t OP_LDSSW  = 6'h39;
  parameter opcode_t OP_ATOMADD = 6'h3A;
  parameter opcode_t OP_ATOMCAS = 6'h3B;

  // Comparison
  parameter opcode_t OP_SLT    = 6'h40;
  parameter opcode_t OP_SLTI   = 6'h41;
  parameter opcode_t OP_SLTU   = 6'h42;
  parameter opcode_t OP_SLTIU  = 6'h43;
  parameter opcode_t OP_SEQ    = 6'h44;
  parameter opcode_t OP_SNE    = 6'h45;
  parameter opcode_t OP_SGE    = 6'h46;
  parameter opcode_t OP_SGEU   = 6'h47;

  // Control flow
  parameter opcode_t OP_BEQ    = 6'h50;
  parameter opcode_t OP_BNE    = 6'h51;
  parameter opcode_t OP_BLT    = 6'h52;
  parameter opcode_t OP_BGE    = 6'h53;
  parameter opcode_t OP_BLTU   = 6'h54;
  parameter opcode_t OP_BGEU   = 6'h55;
  parameter opcode_t OP_JAL    = 6'h56;
  parameter opcode_t OP_JALR   = 6'h57;
  parameter opcode_t OP_RET    = 6'h58;
  parameter opcode_t OP_SYNC   = 6'h59;
  parameter opcode_t OP_WSYNC  = 6'h5A;

  // GPU special ops
  parameter opcode_t OP_VOTEALL = 6'h60;
  parameter opcode_t OP_VOTEANY = 6'h61;
  parameter opcode_t OP_VOTEBAL = 6'h62;
  parameter opcode_t OP_SHFLIDX = 6'h63;
  parameter opcode_t OP_SHFLUP  = 6'h64;
  parameter opcode_t OP_SHFLDN  = 6'h65;
  parameter opcode_t OP_SHFLXOR = 6'h66;
  parameter opcode_t OP_POPC   = 6'h67;
  parameter opcode_t OP_CLZ    = 6'h68;
  parameter opcode_t OP_LUI    = 6'h69;
  parameter opcode_t OP_AUIPC  = 6'h6A;

  // NOP = ADDI x0, x0, 0
  parameter logic [INSTR_WIDTH-1:0] INSTR_NOP = {OP_ADDI, 5'd0, 5'd0, 16'd0};

  // ALU ops
  typedef enum logic [4:0] {
    ALU_ADD   = 5'd0,
    ALU_SUB   = 5'd1,
    ALU_MUL   = 5'd2,
    ALU_MULH  = 5'd3,
    ALU_DIV   = 5'd4,
    ALU_DIVU  = 5'd5,
    ALU_REM   = 5'd6,
    ALU_REMU  = 5'd7,
    ALU_AND   = 5'd8,
    ALU_OR    = 5'd9,
    ALU_XOR   = 5'd10,
    ALU_NOT   = 5'd11,
    ALU_SLL   = 5'd12,
    ALU_SRL   = 5'd13,
    ALU_SRA   = 5'd14,
    ALU_SLT   = 5'd15,
    ALU_SLTU  = 5'd16,
    ALU_SEQ   = 5'd17,
    ALU_SNE   = 5'd18,
    ALU_SGE   = 5'd19,
    ALU_SGEU  = 5'd20,
    ALU_PASS_A = 5'd21,
    ALU_PASS_B = 5'd22,
    ALU_NOP   = 5'd31
  } alu_op_t;

  // FPU operation enum
  typedef enum logic [3:0] {
    FPU_ADD   = 4'd0,
    FPU_SUB   = 4'd1,
    FPU_MUL   = 4'd2,
    FPU_DIV   = 4'd3,
    FPU_MADD  = 4'd4,
    FPU_MSUB  = 4'd5,
    FPU_SQRT  = 4'd6,
    FPU_ABS   = 4'd7,
    FPU_NEG   = 4'd8,
    FPU_MIN   = 4'd9,
    FPU_MAX   = 4'd10,
    FPU_CVTWS = 4'd11,
    FPU_CVTSW = 4'd12,
    FPU_CMPEQ = 4'd13,
    FPU_CMPLT = 4'd14,
    FPU_CMPLE = 4'd15
  } fpu_op_t;

  // IEEE 754 single precision constants
  parameter int FP_EXP_WIDTH  = 8;
  parameter int FP_MANT_WIDTH = 23;
  parameter int FP_EXP_BIAS   = 127;

  // FP classification
  typedef enum logic [2:0] {
    FP_ZERO     = 3'd0,
    FP_DENORMAL = 3'd1,
    FP_NORMAL   = 3'd2,
    FP_INF      = 3'd3,
    FP_SNAN     = 3'd4,
    FP_QNAN     = 3'd5
  } fp_class_t;

  typedef enum logic [2:0] {
    ITYPE_R    = 3'd0,
    ITYPE_I    = 3'd1,
    ITYPE_S    = 3'd2,
    ITYPE_B    = 3'd3,
    ITYPE_U    = 3'd4,
    ITYPE_CTRL = 3'd5,
    ITYPE_MEM  = 3'd6,
    ITYPE_INV  = 3'd7
  } instr_type_t;

  typedef struct packed {
    opcode_t      opcode;
    instr_type_t  itype;
    alu_op_t      alu_op;
    fpu_op_t      fpu_op;
    logic [REG_ADDR_WIDTH-1:0] rd;
    logic [REG_ADDR_WIDTH-1:0] rs1;
    logic [REG_ADDR_WIDTH-1:0] rs2;
    logic [REG_ADDR_WIDTH-1:0] rs3;  // For FMADD/FMSUB
    logic [DATA_WIDTH-1:0] imm;
    logic         reg_write;
    logic         mem_read;
    logic         mem_write;
    logic         branch;
    logic         jump;
    logic         is_ret;
    logic         use_imm;
    logic         is_fpu_op;
  } decoded_instr_t;

  typedef enum logic [1:0] {
    MEM_NONE  = 2'd0,
    MEM_LOAD  = 2'd1,
    MEM_STORE = 2'd2,
    MEM_ATOMIC = 2'd3
  } mem_op_t;

  typedef enum logic [1:0] {
    MEM_BYTE  = 2'd0,
    MEM_HALF  = 2'd1,
    MEM_WORD  = 2'd2
  } mem_size_t;

  typedef struct packed {
    logic                   valid;
    mem_op_t                op;
    mem_size_t              size;
    logic                   sign_extend;
    logic [ADDR_WIDTH-1:0]  addr;
    logic [DATA_WIDTH-1:0]  wdata;
  } mem_request_t;

  typedef struct packed {
    logic                   valid;
    logic                   ready;
    logic [DATA_WIDTH-1:0]  rdata;
  } mem_response_t;

  // Special registers (GPU context)
  parameter int REG_ZERO      = 0;
  parameter int REG_THREAD_ID = 1;
  parameter int REG_BLOCK_ID  = 2;
  parameter int REG_BLOCK_DIM = 3;
  parameter int REG_GRID_DIM  = 4;
  parameter int REG_WARP_ID   = 5;
  parameter int REG_LANE_ID   = 6;

  typedef enum logic [2:0] {
    CORE_IDLE      = 3'd0,
    CORE_FETCH     = 3'd1,
    CORE_DECODE    = 3'd2,
    CORE_EXECUTE   = 3'd3,
    CORE_FPU_WAIT  = 3'd4,
    CORE_MEMORY    = 3'd5,
    CORE_WRITEBACK = 3'd6,
    CORE_DONE      = 3'd7
  } core_state_t;

  // Utility functions
  function automatic logic [DATA_WIDTH-1:0] sign_extend_16(input logic [15:0] imm16);
    return {{16{imm16[15]}}, imm16};
  endfunction

  function automatic logic [DATA_WIDTH-1:0] sign_extend_21(input logic [20:0] imm21);
    return {{11{imm21[20]}}, imm21};
  endfunction

  function automatic logic [DATA_WIDTH-1:0] zero_extend(input logic [15:0] value);
    return {16'd0, value};
  endfunction

  function automatic logic is_branch_op(input opcode_t op);
    return (op >= OP_BEQ && op <= OP_BGEU);
  endfunction

  function automatic logic is_memory_op(input opcode_t op);
    return (op >= OP_LW && op <= OP_ATOMCAS);
  endfunction

  function automatic logic is_load_op(input opcode_t op);
    return (op >= OP_LW && op <= OP_LBU) || (op == OP_LDSLW);
  endfunction

  function automatic logic is_store_op(input opcode_t op);
    return (op >= OP_SW && op <= OP_SB) || (op == OP_LDSSW);
  endfunction

  function automatic logic is_fpu_op(input opcode_t op);
    return (op >= OP_FADD && op <= OP_FCMPLE);
  endfunction

  function automatic logic is_multicycle_fpu_op(input fpu_op_t op);
    return (op == FPU_DIV || op == FPU_SQRT);
  endfunction

  // ==========================================================================
  // SIMT Execution Types and Parameters
  // ==========================================================================

  // SIMT stack configuration
  parameter int SIMT_STACK_DEPTH = 32;  // Max nesting depth for divergence
  parameter int WARP_ID_WIDTH = 2;      // log2(WARPS_PER_CORE)
  parameter int LANE_ID_WIDTH = 5;      // log2(WARP_SIZE)

  // FPU SIMD configuration
  parameter int FPU_LANES = 8;          // Number of FPU lanes (32/8 = 4 cycles per warp)
  parameter int FPU_CYCLES_PER_WARP = WARP_SIZE / FPU_LANES;

  // Memory coalescing
  parameter int CACHE_LINE_SIZE = 64;   // Cache line size in bytes
  parameter int COALESCE_WIDTH = 128;   // Max coalesced transaction width in bits

  // Warp status enum
  typedef enum logic [2:0] {
    WARP_IDLE     = 3'd0,   // Not initialized
    WARP_READY    = 3'd1,   // Ready to execute
    WARP_RUNNING  = 3'd2,   // Currently executing
    WARP_WAITING  = 3'd3,   // Waiting on memory/sync
    WARP_BLOCKED  = 3'd4,   // Blocked on barrier
    WARP_DONE     = 3'd5    // Execution complete
  } warp_status_t;

  // Scheduler policy enum
  typedef enum logic [1:0] {
    SCHED_GTO     = 2'd0,   // Greedy-Then-Oldest
    SCHED_RR      = 2'd1,   // Round-Robin
    SCHED_LRR     = 2'd2    // Loose Round-Robin
  } sched_policy_t;

  // SIMT stack entry - stores divergence context
  typedef struct packed {
    logic [DATA_WIDTH-1:0]    reconvergence_pc;  // PC where paths reconverge
    logic [WARP_SIZE-1:0]     active_mask;       // Original active mask before divergence
    logic [WARP_SIZE-1:0]     taken_mask;        // Mask of threads that took the branch
  } simt_stack_entry_t;

  // Warp context - per-warp state
  typedef struct packed {
    logic [DATA_WIDTH-1:0]    pc;                // Program counter
    logic [WARP_SIZE-1:0]     active_mask;       // Current active thread mask
    warp_status_t             status;            // Warp execution status
    logic [7:0]               age;               // Age counter for GTO scheduling
    logic                     valid;             // Warp is valid/initialized
  } warp_context_t;

  // Branch divergence info
  typedef struct packed {
    logic                     is_divergent;      // Branch causes divergence
    logic [WARP_SIZE-1:0]     taken_mask;        // Threads taking the branch
    logic [WARP_SIZE-1:0]     not_taken_mask;    // Threads not taking the branch
    logic [DATA_WIDTH-1:0]    taken_pc;          // PC for taken path
    logic [DATA_WIDTH-1:0]    not_taken_pc;      // PC for not-taken path (reconvergence)
  } divergence_info_t;

  // Vote operation types
  typedef enum logic [1:0] {
    VOTE_ALL  = 2'd0,   // All active threads have predicate true
    VOTE_ANY  = 2'd1,   // Any active thread has predicate true
    VOTE_BAL  = 2'd2    // Ballot - return mask of threads with true predicate
  } vote_op_t;

  // Shuffle operation types
  typedef enum logic [1:0] {
    SHFL_IDX  = 2'd0,   // Indexed shuffle
    SHFL_UP   = 2'd1,   // Shuffle up (lower lanes)
    SHFL_DOWN = 2'd2,   // Shuffle down (higher lanes)
    SHFL_XOR  = 2'd3    // XOR shuffle (butterfly)
  } shuffle_op_t;

  // Memory coalescing request
  typedef struct packed {
    logic [WARP_SIZE-1:0]     lane_valid;        // Which lanes have valid requests
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] addr;  // Per-lane addresses
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] wdata; // Per-lane write data
    logic                     is_write;          // Write operation
    mem_size_t                size;              // Access size
  } coalesce_request_t;

  // Memory coalescing response
  typedef struct packed {
    logic                     valid;             // Response valid
    logic                     ready;             // All lanes serviced
    logic [WARP_SIZE-1:0][DATA_WIDTH-1:0] rdata; // Per-lane read data
  } coalesce_response_t;

  // SIMT decoded instruction extension
  typedef struct packed {
    decoded_instr_t           base;              // Base decoded instruction
    logic [WARP_ID_WIDTH-1:0] warp_id;           // Source warp ID
    logic [WARP_SIZE-1:0]     active_mask;       // Active thread mask
    logic                     is_vote_op;        // Vote operation
    logic                     is_shuffle_op;     // Shuffle operation
    vote_op_t                 vote_op;           // Vote operation type
    shuffle_op_t              shuffle_op;        // Shuffle operation type
  } simt_decoded_instr_t;

  // Utility functions for SIMT operations

  // Check if operation is a vote operation
  function automatic logic is_vote_op(input opcode_t op);
    return (op == OP_VOTEALL || op == OP_VOTEANY || op == OP_VOTEBAL);
  endfunction

  // Check if operation is a shuffle operation
  function automatic logic is_shuffle_op(input opcode_t op);
    return (op == OP_SHFLIDX || op == OP_SHFLUP || op == OP_SHFLDN || op == OP_SHFLXOR);
  endfunction

  // Check if warp is eligible for scheduling
  function automatic logic is_warp_eligible(input warp_context_t ctx);
    return (ctx.valid && ctx.status == WARP_READY);
  endfunction

  // Population count (number of set bits)
  function automatic logic [5:0] popcount32(input logic [31:0] mask);
    logic [5:0] count;
    count = '0;
    for (int i = 0; i < 32; i++) begin
      count = count + {5'b0, mask[i]};
    end
    return count;
  endfunction

  // Count leading zeros
  function automatic logic [5:0] clz32(input logic [31:0] value);
    logic [5:0] count;
    logic found;
    count = 6'd32;
    found = 1'b0;
    for (int i = 31; i >= 0; i--) begin
      if (value[i] && !found) begin
        count = 6'd31 - i[5:0];
        found = 1'b1;
      end
    end
    return count;
  endfunction

  // Find first set bit (returns lane index)
  function automatic logic [4:0] ffs32(input logic [31:0] mask);
    logic [4:0] idx;
    logic found;
    idx = '0;
    found = 1'b0;
    for (int i = 0; i < 32; i++) begin
      if (mask[i] && !found) begin
        idx = i[4:0];
        found = 1'b1;
      end
    end
    return idx;
  endfunction

endpackage
