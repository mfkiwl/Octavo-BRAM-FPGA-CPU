
`default_nettype none

`include "Global_Defines.vh"
`include "Triadic_ALU_Operations.vh"

module Generic_test_harness
#(
    // Data Path
    parameter   WORD_WIDTH                              = 36,
    parameter   READ_ADDR_WIDTH                         = 10,
    parameter   WRITE_ADDR_WIDTH                        = 12,
    // Data Memories (A/B)
    parameter   MEM_RAMSTYLE                            = "M10K, no_rw_check",
    parameter   MEM_READ_NEW_DATA                       = 0,
    parameter   MEM_INIT_FILE_A                         = "init_data_A.mem",
    parameter   MEM_INIT_FILE_B                         = "init_data_B.mem",
    parameter   MEM_READ_BASE_ADDR_A                    = 1,
    parameter   MEM_READ_BOUND_ADDR_A                   = 1023,
    parameter   MEM_WRITE_BASE_ADDR_A                   = 1,
    parameter   MEM_WRITE_BOUND_ADDR_A                  = 1023,
    parameter   MEM_READ_BASE_ADDR_B                    = 1,
    parameter   MEM_READ_BOUND_ADDR_B                   = 1023,
    parameter   MEM_WRITE_BASE_ADDR_B                   = 1025,
    parameter   MEM_WRITE_BOUND_ADDR_B                  = 2047,
    // S register in ALU
    parameter   S_WRITE_ADDR                            = 2048,
    parameter   S_RAMSTYLE                              = "logic, no_rw_check",
    parameter   S_READ_NEW_DATA                         = 0,
    // Same count and address for both A and B
    parameter   IO_PORT_COUNT                           = 8,
    parameter   IO_PORT_BASE_ADDR                       = 1,
    parameter   IO_PORT_ADDR_WIDTH                      = 3,
    // Addressing Module
    parameter   A_SHARED_ADDR_BASE                      = 1,
    parameter   A_SHARED_ADDR_BOUND                     = 12,
    parameter   B_SHARED_ADDR_BASE                      = 1,
    parameter   B_SHARED_ADDR_BOUND                     = 12,
    parameter   A_INDIRECT_ADDR_BASE                    = 13,
    parameter   B_INDIRECT_ADDR_BASE                    = 13,
    parameter   A_PO_ADDR_BASE                          = 2049,
    parameter   B_PO_ADDR_BASE                          = 2053,
    parameter   DA_PO_ADDR_BASE                         = 2057,
    parameter   DB_PO_ADDR_BASE                         = 2061,
    parameter   DO_ADDR                                 = 2065,
    parameter   PO_INCR_WIDTH                           = 4,
    parameter   PO_ENTRY_COUNT                          = 4,
    parameter   PO_ADDR_WIDTH                           = 2,
    parameter   PO_INIT_FILE                            = "init_po.mem",
    parameter   DO_INIT_FILE                            = "init_do.mem",
    parameter   AD_RAMSTYLE                             = "MLAB, no_rw_check",
    parameter   AD_READ_NEW_DATA                        = 0,
    // Control Path
    // Flow Control
    parameter   PC_WIDTH                                = 10,
    parameter   BRANCH_COUNT                            = 4,
    parameter   FC_RAMSTYLE                             = "MLAB, no_rw_check",
    parameter   FC_READ_NEW_DATA                        = 0,
    // Controller: initial PC values
    parameter   PC_INIT_FILE                            = "init_pc.mem",
    parameter   PC_PREV_INIT_FILE                       = "init_pc_prev.mem",
    // Instruction format
    parameter   OPCODE_WIDTH                            = `OPCODE_WIDTH,
    parameter   D_OPERAND_WIDTH                         = 12,
    parameter   A_OPERAND_WIDTH                         = 10,
    parameter   B_OPERAND_WIDTH                         = 10,
    // Instruction Memory (shared)
    parameter   IM_WORD_WIDTH                           = WORD_WIDTH,
    parameter   IM_ADDR_WIDTH                           = READ_ADDR_WIDTH,
    parameter   IM_READ_NEW                             = 0,
    parameter   IM_DEPTH                                = 1024,
    parameter   IM_RAMSTYLE                             = "M10K, no_rw_check",
    parameter   IM_INIT_FILE                            = "init_instr.mem",
    // Opcode Decoder Memory (multithreaded)
    parameter   OD_WORD_WIDTH                           = `TRIADIC_ALU_CTRL_WIDTH,
    parameter   OD_ADDR_WIDTH                           = 4,
    parameter   OD_READ_NEW                             = 0,
    parameter   OD_THREAD_DEPTH                         = `OPCODE_COUNT,
    parameter   OD_RAMSTYLE                             = "MLAB, no_rw_check",
    parameter   OD_INIT_FILE                            = "init_decode.mem",
    parameter   OD_INITIAL_THREAD_READ                  = 0,
    parameter   OD_INITIAL_THREAD_WRITE                 = 0,
    // Memory-mapping
    parameter   DB_BASE_ADDR                            = 1024,
    parameter   FC_BASE_ADDR_WRITE                      = 2100,
    parameter   IM_BASE_ADDR_WRITE                      = 2200,
    parameter   OD_BASE_ADDR_WRITE                      = 2300,

    // Multithreading (common)
    parameter   THREAD_COUNT                            = `OCTAVO_THREAD_COUNT,
    parameter   THREAD_COUNT_WIDTH                      = `OCTAVO_THREAD_COUNT_WIDTH
)
(
    input   wire    clock,
    input   wire    test_in,
    output  wire    test_out
);

// --------------------------------------------------------------------

    localparam INPUT_WIDTH  = (IO_PORT_COUNT * 4) + (IO_PORT_COUNT * WORD_WIDTH * 2) + 2;
    localparam OUTPUT_WIDTH = (IO_PORT_COUNT * 4) + (IO_PORT_COUNT * WORD_WIDTH * 2);

    wire    [INPUT_WIDTH-1:0]   test_input;
    reg     [OUTPUT_WIDTH-1:0]  test_output;

// --------------------------------------------------------------------

    reg                                     A_external      = 0;
    reg                                     B_external      = 0;
    reg  [IO_PORT_COUNT-1:0]                io_read_EF_A    = 0;
    reg  [IO_PORT_COUNT-1:0]                io_read_EF_B    = 0;
    reg  [IO_PORT_COUNT-1:0]                io_write_EF_A   = 0;
    reg  [IO_PORT_COUNT-1:0]                io_write_EF_B   = 0;
    reg  [(IO_PORT_COUNT*WORD_WIDTH)-1:0]   io_read_data_A  = 0;
    reg  [(IO_PORT_COUNT*WORD_WIDTH)-1:0]   io_read_data_B  = 0;

    wire [(IO_PORT_COUNT*WORD_WIDTH)-1:0]   io_write_data_A;
    wire [(IO_PORT_COUNT*WORD_WIDTH)-1:0]   io_write_data_B;

    wire [IO_PORT_COUNT-1:0]                io_rden_A;
    wire [IO_PORT_COUNT-1:0]                io_rden_B;
    wire [IO_PORT_COUNT-1:0]                io_wren_A;
    wire [IO_PORT_COUNT-1:0]                io_wren_B;

    always @(*) begin
        {A_external, B_external, io_read_EF_A, io_read_EF_B, io_write_EF_A, io_write_EF_B, io_read_data_A, io_read_data_B} <= test_input;
        test_output <= {io_write_data_A, io_write_data_B, io_rden_A, io_rden_B, io_wren_A, io_wren_B};
    end

// --------------------------------------------------------------------
// Test Harness Registers

    harness_input_register
    #(
        .WIDTH  (INPUT_WIDTH)
    )
    i
    (
        .clock  (clock),    
        .in     (test_in),
        .rden   (1'b1),
        .out    (test_input)
    );

    harness_output_register 
    #(
        .WIDTH  (OUTPUT_WIDTH)
    )
    o
    (
        .clock  (clock),
        .in     (test_output),
        .wren   (1'b1),
        .out    (test_out)
    );

// --------------------------------------------------------------------

    Octavo
    #(
        .WORD_WIDTH                 (WORD_WIDTH),
        .READ_ADDR_WIDTH            (READ_ADDR_WIDTH),
        .WRITE_ADDR_WIDTH           (WRITE_ADDR_WIDTH),
        .MEM_RAMSTYLE               (MEM_RAMSTYLE),
        .MEM_READ_NEW_DATA          (MEM_READ_NEW_DATA),
        .MEM_INIT_FILE_A            (MEM_INIT_FILE_A),
        .MEM_INIT_FILE_B            (MEM_INIT_FILE_B),
        .MEM_READ_BASE_ADDR_A       (MEM_READ_BASE_ADDR_A),
        .MEM_READ_BOUND_ADDR_A      (MEM_READ_BOUND_ADDR_A),
        .MEM_WRITE_BASE_ADDR_A      (MEM_WRITE_BASE_ADDR_A),
        .MEM_WRITE_BOUND_ADDR_A     (MEM_WRITE_BOUND_ADDR_A),
        .MEM_READ_BASE_ADDR_B       (MEM_READ_BASE_ADDR_B),
        .MEM_READ_BOUND_ADDR_B      (MEM_READ_BOUND_ADDR_B),
        .MEM_WRITE_BASE_ADDR_B      (MEM_WRITE_BASE_ADDR_B),
        .MEM_WRITE_BOUND_ADDR_B     (MEM_WRITE_BOUND_ADDR_B),
        .S_WRITE_ADDR               (S_WRITE_ADDR),
        .S_RAMSTYLE                 (S_RAMSTYLE),
        .S_READ_NEW_DATA            (S_READ_NEW_DATA),
        .IO_PORT_COUNT              (IO_PORT_COUNT),
        .IO_PORT_BASE_ADDR          (IO_PORT_BASE_ADDR),
        .IO_PORT_ADDR_WIDTH         (IO_PORT_ADDR_WIDTH),
        .A_SHARED_ADDR_BASE         (A_SHARED_ADDR_BASE),
        .A_SHARED_ADDR_BOUND        (A_SHARED_ADDR_BOUND),
        .B_SHARED_ADDR_BASE         (B_SHARED_ADDR_BASE),
        .B_SHARED_ADDR_BOUND        (B_SHARED_ADDR_BOUND),
        .A_INDIRECT_ADDR_BASE       (A_INDIRECT_ADDR_BASE),
        .B_INDIRECT_ADDR_BASE       (B_INDIRECT_ADDR_BASE),
        .A_PO_ADDR_BASE             (A_PO_ADDR_BASE),
        .B_PO_ADDR_BASE             (B_PO_ADDR_BASE),
        .DA_PO_ADDR_BASE            (DA_PO_ADDR_BASE),
        .DB_PO_ADDR_BASE            (DB_PO_ADDR_BASE),
        .DO_ADDR                    (DO_ADDR),
        .PO_INCR_WIDTH              (PO_INCR_WIDTH),
        .PO_ENTRY_COUNT             (PO_ENTRY_COUNT),
        .PO_ADDR_WIDTH              (PO_ADDR_WIDTH),
        .PO_INIT_FILE               (PO_INIT_FILE),
        .DO_INIT_FILE               (DO_INIT_FILE),
        .AD_RAMSTYLE                (AD_RAMSTYLE),
        .AD_READ_NEW_DATA           (AD_READ_NEW_DATA),
        .PC_WIDTH                   (PC_WIDTH),
        .BRANCH_COUNT               (BRANCH_COUNT),
        .FC_RAMSTYLE                (FC_RAMSTYLE),
        .FC_READ_NEW_DATA           (FC_READ_NEW_DATA),
        .PC_INIT_FILE               (PC_INIT_FILE),
        .PC_PREV_INIT_FILE          (PC_PREV_INIT_FILE),
        .OPCODE_WIDTH               (OPCODE_WIDTH),
        .D_OPERAND_WIDTH            (D_OPERAND_WIDTH),
        .A_OPERAND_WIDTH            (A_OPERAND_WIDTH),
        .B_OPERAND_WIDTH            (B_OPERAND_WIDTH),
        .IM_WORD_WIDTH              (IM_WORD_WIDTH),
        .IM_ADDR_WIDTH              (IM_ADDR_WIDTH),
        .IM_READ_NEW                (IM_READ_NEW),
        .IM_DEPTH                   (IM_DEPTH),
        .IM_RAMSTYLE                (IM_RAMSTYLE),
        .IM_INIT_FILE               (IM_INIT_FILE),
        .OD_WORD_WIDTH              (OD_WORD_WIDTH),
        .OD_ADDR_WIDTH              (OD_ADDR_WIDTH),
        .OD_READ_NEW                (OD_READ_NEW),
        .OD_THREAD_DEPTH            (OD_THREAD_DEPTH),
        .OD_RAMSTYLE                (OD_RAMSTYLE),
        .OD_INIT_FILE               (OD_INIT_FILE),
        .OD_INITIAL_THREAD_READ     (OD_INITIAL_THREAD_READ),
        .OD_INITIAL_THREAD_WRITE    (OD_INITIAL_THREAD_WRITE),
        .FC_BASE_ADDR_WRITE         (FC_BASE_ADDR_WRITE),
        .DB_BASE_ADDR               (DB_BASE_ADDR),
        .IM_BASE_ADDR_WRITE         (IM_BASE_ADDR_WRITE),
        .OD_BASE_ADDR_WRITE         (OD_BASE_ADDR_WRITE),
        .THREAD_COUNT               (THREAD_COUNT),
        .THREAD_COUNT_WIDTH         (THREAD_COUNT_WIDTH)
    )
    CPU
    (
        .clock                      (clock),

        .A_external                 (A_external),
        .B_external                 (B_external),

        .io_read_EF_A               (io_read_EF_A),
        .io_read_EF_B               (io_read_EF_B),
        .io_write_EF_A              (io_write_EF_A),
        .io_write_EF_B              (io_write_EF_B),

        .io_read_data_A             (io_read_data_A),
        .io_read_data_B             (io_read_data_B),
        .io_write_data_A            (io_write_data_A),
        .io_write_data_B            (io_write_data_B),

        .io_rden_A                  (io_rden_A),
        .io_rden_B                  (io_rden_B),
        .io_wren_A                  (io_wren_A),
        .io_wren_B                  (io_wren_B)
    );

endmodule
