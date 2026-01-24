// SIMT Register File - Multi-warp, multi-lane register file
// 4 warps x 32 registers x 32 lanes x 32 bits = 16KB total

module simt_regfile
  import pkg_opengpu::*;
#(
  parameter int NUM_WARPS = WARPS_PER_CORE,
  parameter int NUM_LANES = WARP_SIZE,
  parameter int NUM_REGS_PARAM = NUM_REGS
)(
  input  logic                          clk,
  input  logic                          rst_n,

  // Read port 1 (all lanes)
  input  logic [WARP_ID_WIDTH-1:0]      rs1_warp_id,
  input  logic [REG_ADDR_WIDTH-1:0]     rs1_addr,
  output logic [NUM_LANES-1:0][DATA_WIDTH-1:0] rs1_data,

  // Read port 2 (all lanes)
  input  logic [WARP_ID_WIDTH-1:0]      rs2_warp_id,
  input  logic [REG_ADDR_WIDTH-1:0]     rs2_addr,
  output logic [NUM_LANES-1:0][DATA_WIDTH-1:0] rs2_data,

  // Read port 3 (all lanes) - for FMA operations
  input  logic [WARP_ID_WIDTH-1:0]      rs3_warp_id,
  input  logic [REG_ADDR_WIDTH-1:0]     rs3_addr,
  output logic [NUM_LANES-1:0][DATA_WIDTH-1:0] rs3_data,

  // Write port (masked, all lanes)
  input  logic [WARP_ID_WIDTH-1:0]      rd_warp_id,
  input  logic [REG_ADDR_WIDTH-1:0]     rd_addr,
  input  logic [NUM_LANES-1:0][DATA_WIDTH-1:0] rd_data,
  input  logic [NUM_LANES-1:0]          rd_mask,   // Per-lane write enable
  input  logic                          rd_we,     // Global write enable

  // Context initialization
  input  logic                          init_context,
  input  logic [WARP_ID_WIDTH-1:0]      init_warp_id,
  input  logic [DATA_WIDTH-1:0]         thread_idx,
  input  logic [DATA_WIDTH-1:0]         block_idx,
  input  logic [DATA_WIDTH-1:0]         block_dim,
  input  logic [DATA_WIDTH-1:0]         grid_dim,
  input  logic [DATA_WIDTH-1:0]         warp_idx
);

  // Register storage: [warp][register][lane]
  logic [DATA_WIDTH-1:0] regfile [NUM_WARPS][NUM_REGS_PARAM][NUM_LANES];

  // Read logic (combinational, asynchronous read)
  always_comb begin
    for (int lane = 0; lane < NUM_LANES; lane++) begin
      // Read port 1
      if (rs1_addr == '0) begin
        rs1_data[lane] = '0;  // x0 is hardwired to zero
      end else begin
        rs1_data[lane] = regfile[rs1_warp_id][rs1_addr][lane];
      end

      // Read port 2
      if (rs2_addr == '0) begin
        rs2_data[lane] = '0;
      end else begin
        rs2_data[lane] = regfile[rs2_warp_id][rs2_addr][lane];
      end

      // Read port 3
      if (rs3_addr == '0) begin
        rs3_data[lane] = '0;
      end else begin
        rs3_data[lane] = regfile[rs3_warp_id][rs3_addr][lane];
      end
    end
  end

  // Write logic (synchronous, masked)
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      // Reset all registers to zero
      for (int w = 0; w < NUM_WARPS; w++) begin
        for (int r = 0; r < NUM_REGS_PARAM; r++) begin
          for (int l = 0; l < NUM_LANES; l++) begin
            regfile[w][r][l] <= '0;
          end
        end
      end
    end else begin
      // Context initialization - set up GPU thread context registers
      if (init_context) begin
        for (int lane = 0; lane < NUM_LANES; lane++) begin
          // x0 stays zero (handled by read logic)
          // x1 = thread_id (global thread index = warp_idx * WARP_SIZE + lane)
          regfile[init_warp_id][REG_THREAD_ID][lane] <= thread_idx + lane;
          // x2 = block_id
          regfile[init_warp_id][REG_BLOCK_ID][lane] <= block_idx;
          // x3 = block_dim
          regfile[init_warp_id][REG_BLOCK_DIM][lane] <= block_dim;
          // x4 = grid_dim
          regfile[init_warp_id][REG_GRID_DIM][lane] <= grid_dim;
          // x5 = warp_id
          regfile[init_warp_id][REG_WARP_ID][lane] <= warp_idx;
          // x6 = lane_id
          regfile[init_warp_id][REG_LANE_ID][lane] <= lane;
        end
      end

      // Masked write
      if (rd_we && rd_addr != '0) begin  // Never write to x0
        for (int lane = 0; lane < NUM_LANES; lane++) begin
          if (rd_mask[lane]) begin
            regfile[rd_warp_id][rd_addr][lane] <= rd_data[lane];
          end
        end
      end
    end
  end

endmodule
