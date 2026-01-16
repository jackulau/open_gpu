// Unified memory model for simulation - separate I/D ports, byte-addressable

module memory_model
  import pkg_opengpu::*;
#(
  parameter int MEM_SIZE_BYTES = 65536,
  parameter int LATENCY_CYCLES = 0
)(
  input  logic                       clk,
  input  logic                       rst_n,

  // Instruction port (read-only)
  input  logic                       imem_req,
  input  logic [ADDR_WIDTH-1:0]      imem_addr,
  output logic [INSTR_WIDTH-1:0]     imem_rdata,
  output logic                       imem_valid,

  // Data port (read/write)
  input  logic                       dmem_req,
  input  logic                       dmem_we,
  input  logic [ADDR_WIDTH-1:0]      dmem_addr,
  input  logic [DATA_WIDTH-1:0]      dmem_wdata,
  input  logic [3:0]                 dmem_be,
  output logic [DATA_WIDTH-1:0]      dmem_rdata,
  output logic                       dmem_valid
);

  logic [7:0] mem [MEM_SIZE_BYTES];

  logic [31:0] imem_word_addr;
  logic [31:0] dmem_word_addr;

  assign imem_word_addr = imem_addr & (MEM_SIZE_BYTES - 1);
  assign dmem_word_addr = dmem_addr & (MEM_SIZE_BYTES - 1);

  // Instruction read (little-endian)
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      imem_rdata <= 32'h0;
      imem_valid <= 1'b0;
    end else begin
      imem_valid <= imem_req;
      if (imem_req)
        imem_rdata <= {mem[imem_word_addr+3], mem[imem_word_addr+2],
                       mem[imem_word_addr+1], mem[imem_word_addr]};
    end
  end

  // Data read/write
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      dmem_rdata <= 32'h0;
      dmem_valid <= 1'b0;
    end else begin
      dmem_valid <= dmem_req;
      if (dmem_req) begin
        if (dmem_we) begin
          if (dmem_be[0]) mem[dmem_word_addr]   <= dmem_wdata[7:0];
          if (dmem_be[1]) mem[dmem_word_addr+1] <= dmem_wdata[15:8];
          if (dmem_be[2]) mem[dmem_word_addr+2] <= dmem_wdata[23:16];
          if (dmem_be[3]) mem[dmem_word_addr+3] <= dmem_wdata[31:24];
        end
        dmem_rdata <= {mem[dmem_word_addr+3], mem[dmem_word_addr+2],
                       mem[dmem_word_addr+1], mem[dmem_word_addr]};
      end
    end
  end

  initial begin
    for (int i = 0; i < MEM_SIZE_BYTES; i++)
      mem[i] = 8'h00;
  end

  task load_program(input string filename);
    int fd, status;
    logic [31:0] word;
    int addr;
    $display("Loading program from %s", filename);
    fd = $fopen(filename, "r");
    if (fd == 0) begin
      $display("ERROR: Cannot open file %s", filename);
      return;
    end
    addr = 0;
    while (!$feof(fd)) begin
      status = $fscanf(fd, "%h", word);
      if (status == 1) begin
        mem[addr]   = word[7:0];
        mem[addr+1] = word[15:8];
        mem[addr+2] = word[23:16];
        mem[addr+3] = word[31:24];
        addr = addr + 4;
      end
    end
    $fclose(fd);
    $display("Loaded %0d bytes (%0d instructions)", addr, addr/4);
  endtask

  task dump_memory(input int start_addr, input int num_words);
    $display("\n=== Memory Dump ===");
    for (int i = 0; i < num_words; i++) begin
      int a = start_addr + i * 4;
      logic [31:0] word = {mem[a+3], mem[a+2], mem[a+1], mem[a]};
      $display("  [0x%04x]: 0x%08x (%0d)", a, word, $signed(word));
    end
    $display("==================\n");
  endtask

  function logic [31:0] read_word(input int addr);
    return {mem[addr+3], mem[addr+2], mem[addr+1], mem[addr]};
  endfunction

endmodule
