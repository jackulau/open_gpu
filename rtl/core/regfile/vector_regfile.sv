// Register file: 32 regs x 32 bits, x0 hardwired to zero
// 3 read ports (async), 1 write port (sync)

module vector_regfile
  import pkg_opengpu::*;
(
  input  logic                       clk,
  input  logic                       rst_n,

  // Read ports
  input  logic [REG_ADDR_WIDTH-1:0]  rs1_addr,
  input  logic [REG_ADDR_WIDTH-1:0]  rs2_addr,
  input  logic [REG_ADDR_WIDTH-1:0]  rs3_addr,  // For FMA operations
  output logic [DATA_WIDTH-1:0]      rs1_data,
  output logic [DATA_WIDTH-1:0]      rs2_data,
  output logic [DATA_WIDTH-1:0]      rs3_data,  // For FMA operations

  // Write port
  input  logic                       we,
  input  logic [REG_ADDR_WIDTH-1:0]  rd_addr,
  input  logic [DATA_WIDTH-1:0]      rd_data,

  // GPU context init
  input  logic                       init_context,
  input  logic [DATA_WIDTH-1:0]      thread_idx,
  input  logic [DATA_WIDTH-1:0]      block_idx,
  input  logic [DATA_WIDTH-1:0]      block_dim,
  input  logic [DATA_WIDTH-1:0]      grid_dim,
  input  logic [DATA_WIDTH-1:0]      warp_idx,
  input  logic [DATA_WIDTH-1:0]      lane_idx
);

  logic [DATA_WIDTH-1:0] registers [NUM_REGS];

  // Read (async)
  assign rs1_data = (rs1_addr == REG_ZERO) ? '0 : registers[rs1_addr];
  assign rs2_data = (rs2_addr == REG_ZERO) ? '0 : registers[rs2_addr];
  assign rs3_data = (rs3_addr == REG_ZERO) ? '0 : registers[rs3_addr];

  // Write (sync)
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < NUM_REGS; i++)
        registers[i] <= '0;
    end else if (init_context) begin
      registers[REG_ZERO]      <= '0;
      registers[REG_THREAD_ID] <= thread_idx;
      registers[REG_BLOCK_ID]  <= block_idx;
      registers[REG_BLOCK_DIM] <= block_dim;
      registers[REG_GRID_DIM]  <= grid_dim;
      registers[REG_WARP_ID]   <= warp_idx;
      registers[REG_LANE_ID]   <= lane_idx;
    end else if (we && rd_addr != REG_ZERO) begin
      registers[rd_addr] <= rd_data;
    end
  end

`ifdef SIMULATION
  wire [DATA_WIDTH-1:0] dbg_x0  = registers[0];
  wire [DATA_WIDTH-1:0] dbg_x1  = registers[1];
  wire [DATA_WIDTH-1:0] dbg_x2  = registers[2];
  wire [DATA_WIDTH-1:0] dbg_x3  = registers[3];
  wire [DATA_WIDTH-1:0] dbg_x4  = registers[4];
  wire [DATA_WIDTH-1:0] dbg_x5  = registers[5];
  wire [DATA_WIDTH-1:0] dbg_x6  = registers[6];
  wire [DATA_WIDTH-1:0] dbg_x7  = registers[7];
  wire [DATA_WIDTH-1:0] dbg_x8  = registers[8];
  wire [DATA_WIDTH-1:0] dbg_x9  = registers[9];
  wire [DATA_WIDTH-1:0] dbg_x10 = registers[10];
  wire [DATA_WIDTH-1:0] dbg_x11 = registers[11];
  wire [DATA_WIDTH-1:0] dbg_x12 = registers[12];
  wire [DATA_WIDTH-1:0] dbg_x13 = registers[13];
  wire [DATA_WIDTH-1:0] dbg_x14 = registers[14];
  wire [DATA_WIDTH-1:0] dbg_x15 = registers[15];
`endif

endmodule
