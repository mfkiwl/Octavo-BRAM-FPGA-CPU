
// IO_Write_Predication. Allows us to prevent a write to an I/O port if the
// port isn't ready.

// Same as IO_Read_Predication, except the IO_Active check, to generate all
// the write enables, is done after the ALU.

module IO_Write_Predication
#(
    parameter   WORD_WIDTH                      = 0,
    parameter   ADDR_WIDTH                      = 0,
    parameter   IO_WRITE_PORT_COUNT             = 0,
    parameter   IO_WRITE_PORT_BASE_ADDR         = 0,
    parameter   IO_WRITE_PORT_ADDR_WIDTH        = 0
)
(
    input   wire                                clock,
    input   wire                                IO_ready,
    input   wire    [ADDR_WIDTH-1:0]            addr,
    input   wire    [IO_WRITE_PORT_COUNT-1:0]   EmptyFull,
    output  wire                                EmptyFull_masked,
    output  wire                                wren_enable
);

// -----------------------------------------------------------

    wire addr_is_IO;

    IO_Check
    #(
        .READY_STATE        (1'b0),  // EMPTY
        .ADDR_WIDTH         (ADDR_WIDTH),
        .PORT_COUNT         (IO_WRITE_PORT_COUNT),
        .PORT_BASE_ADDR     (IO_WRITE_PORT_BASE_ADDR),
        .PORT_ADDR_WIDTH    (IO_WRITE_PORT_ADDR_WIDTH)
    )
    Write_IO_Check
    (
        .clock              (clock),
        .addr               (addr),
        .port_EF            (EmptyFull),
        .port_EF_masked     (EmptyFull_masked),
        .addr_is_IO         (addr_is_IO),
    );

// --------------------------------------------------------------------
// This is aligned to Stage 2 of the IO_Check

    reg addr_is_IO_stage_2 = 0;

    always @(posedge clock) begin
        addr_is_IO_stage_2 <= addr_is_IO;
    end

// --------------------------------------------------------------------

// Only output write enable if all accessed ports are ready.
// This prevents side-effects or lost data if an instruction is anulled.
// This happens in the stage *after* Stage 2 of IO_Check, since that's when
// the IO_ready signal is available.

    Annuller
    #(
        .WORD_WIDTH (1)
    )
    wren_enable
    (
        .annul      (~IO_ready),
        .in         (addr_is_IO_stage_2),
        .out        (wren_enable)
    );

endmodule

