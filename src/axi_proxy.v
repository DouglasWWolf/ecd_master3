
//====================================================================================
//                        ------->  Revision History  <------
//====================================================================================
//
//   Date     Who   Ver  Changes
//====================================================================================
// 12-Dec-22  DWW  1000  Initial creation
//====================================================================================

/*

Usage:
    In register 0 (offset 0x00), store a 32 bit AXI address
    A write to register 1 (offset 0x04) will perform the AXI write to the EECD
    A read of register 1 (offset 0x04) will perform the AXI read from the EECD
*/


module axi_proxy
(
    // Clock and reset
    input clk, resetn,

    // This signal strobes high when the master data-FIFO first fills up
    input preload_complete,

    //===========  Channel 0 AXI Stream interface for the AXI request ==========
    output[511:0]  AXIS_OUT0_TDATA,
    output reg     AXIS_OUT0_TVALID,
    output         AXIS_OUT0_TLAST,
    input          AXIS_OUT0_TREADY,
    //==========================================================================

    //===========  Channel 1 AXI Stream interface for the AXI request ==========
    output[511:0]  AXIS_OUT1_TDATA,
    output reg     AXIS_OUT1_TVALID,
    output         AXIS_OUT1_TLAST,
    input          AXIS_OUT1_TREADY,
    //==========================================================================


    //===============  AXI Stream interface for the AXI response ===============
    input[255:0]  AXIS_IN_TDATA,
    input         AXIS_IN_TVALID,
    output reg    AXIS_IN_TREADY,
    //==========================================================================


    //================== This is an AXI4-Lite slave interface ==================
        
    // "Specify write address"              -- Master --    -- Slave --
    input[31:0]                             S_AXI_AWADDR,   
    input                                   S_AXI_AWVALID,  
    output                                                  S_AXI_AWREADY,
    input[2:0]                              S_AXI_AWPROT,

    // "Write Data"                         -- Master --    -- Slave --
    input[31:0]                             S_AXI_WDATA,      
    input                                   S_AXI_WVALID,
    input[3:0]                              S_AXI_WSTRB,
    output                                                  S_AXI_WREADY,

    // "Send Write Response"                -- Master --    -- Slave --
    output[1:0]                                             S_AXI_BRESP,
    output                                                  S_AXI_BVALID,
    input                                   S_AXI_BREADY,

    // "Specify read address"               -- Master --    -- Slave --
    input[31:0]                             S_AXI_ARADDR,     
    input                                   S_AXI_ARVALID,
    input[2:0]                              S_AXI_ARPROT,     
    output                                                  S_AXI_ARREADY,

    // "Read data back to master"           -- Master --    -- Slave --
    output[31:0]                                            S_AXI_RDATA,
    output                                                  S_AXI_RVALID,
    output[1:0]                                             S_AXI_RRESP,
    input                                   S_AXI_RREADY
    //==========================================================================
 );

    //==========================================================================
    // These describe the ECD AXI register that we use to inform the ECD that
    // a job is about to start and it should pre-load its data FIFO
    //==========================================================================
    localparam ECD_PRELOAD_ADDR = 32'h0000_1000;
    localparam ECD_PRELOAD_VALU = 32'h0000_000F;

    //==========================================================================
    // We'll communicate with the AXI4-Lite Slave core with these signals.
    //==========================================================================
    // AXI Slave Handler Interface for write requests
    wire[31:0]  ashi_waddr;     // Input:  Write-address
    wire[31:0]  ashi_wdata;     // Input:  Write-data
    wire        ashi_write;     // Input:  1 = Handle a write request
    reg[1:0]    ashi_wresp;     // Output: Write-response (OKAY, DECERR, SLVERR)
    wire        ashi_widle;     // Output: 1 = Write state machine is idle

    // AXI Slave Handler Interface for read requests
    wire[31:0]  ashi_raddr;     // Input:  Read-address
    wire        ashi_read;      // Input:  1 = Handle a read request
    reg[31:0]   ashi_rdata;     // Output: Read data
    reg[1:0]    ashi_rresp;     // Output: Read-response (OKAY, DECERR, SLVERR);
    wire        ashi_ridle;     // Output: 1 = Read state machine is idle
    //==========================================================================

    //===============================================================================================
    // Outgoing AXI stream packets are always exactly 1 data-cycle long
    //===============================================================================================
    assign AXIS_OUT0_TLAST = 1;
    assign AXIS_OUT1_TLAST = 1;
    //===============================================================================================
    
    //===============================================================================================
    // Field definitions for the TDATA lines
    //===============================================================================================

    // Fields of the input stream
    wire[31:0] axi_addr_in = AXIS_IN_TDATA[31:00];
    wire[31:0] axi_data_in = AXIS_IN_TDATA[63:32];
    wire[ 2:0] axi_resp_in = AXIS_IN_TDATA[66:64];

    // Address and data registers for AXI4-Lite reads and writes
    reg[31:0] axi_addr_out; assign AXIS_OUT0_TDATA[31:00] = axi_addr_out;
    reg[31:0] axi_data_out; assign AXIS_OUT0_TDATA[63:32] = axi_data_out;
    reg       axi_mode_out; assign AXIS_OUT0_TDATA[64   ] = axi_mode_out;

    // Set the packet-type to 1
    assign AXIS_OUT0_TDATA[511:504] = 1;

    // Channel 1 output data is always 0
    assign AXIS_OUT1_TDATA = 0;

    //===============================================================================================

    localparam AXI_MODE_WRITE = 0;
    localparam AXI_MODE_READ  = 1;

    // The state of our state machines
    reg[1:0] fsm_state, next_state;

    // The state machines are idle when they're in state 0 when their "start" signals are low
    assign ashi_widle = (ashi_write == 0) && (fsm_state == 0);
    assign ashi_ridle = (ashi_read  == 0) && (fsm_state == 0);

    // These are the valid values for ashi_rresp and ashi_wresp
    localparam OKAY   = 0;
    localparam SLVERR = 2;
    localparam DECERR = 3;

    // An AXI slave is gauranteed a minimum of 128 bytes of address space
    // (128 bytes is 32 32-bit registers)
    localparam ADDR_MASK = 7'h7F;

    // This will hold the values that get written to the AXI registers
    reg[31:0] axi_register[0:0];

    // The possible states of our state machine
    localparam FSM_WAIT_FOR_AXI_CMD     = 0;
    localparam FSM_AXI_STREAM_HANDSHAKE = 1;
    localparam FSM_WAIT_FOR_WRESP       = 2;
    localparam FSM_WAIT_FOR_RRESP       = 3; 

    //==========================================================================
    // This state machine handles both AXI-write and AXI-read requests
    //==========================================================================
    always @(posedge clk) begin

        // If we're in reset, initialize important registers
        if (resetn == 0) begin
            fsm_state        <= 0;
            AXIS_OUT0_TVALID <= 0;
            AXIS_OUT1_TVALID <= 0;
            AXIS_IN_TREADY   <= 0;
        
        // If we're not in reset...
        end else case(fsm_state)

            // If a write-request has come in...
            FSM_WAIT_FOR_AXI_CMD:
                
                // If the AXI master wants us to perform an AXI4-Lite write...
                if (ashi_write) begin

                    // Assume for a moment that we will be reporting "OKAY" as a write-response
                    ashi_wresp <= OKAY;

                    case((ashi_waddr & ADDR_MASK) >> 2)

                        // If the user wants to store an AXI register address.
                        0:  axi_register[0] <= ashi_wdata;

                        // If the user wants to write a value to the stored AXI register address...
                        1:  begin
                                axi_addr_out    <= axi_register[0]; // Stuff the AXI address into TDATA
                                axi_data_out    <= ashi_wdata;      // Stuff the data value into TDATA 
                                axi_mode_out    <= AXI_MODE_WRITE;  // This will be an AXI write
                                AXIS_OUT0_TVALID <= 1;              // And declare TDATA valid for 1 cycle
                                AXIS_OUT1_TVALID <= 1;
                                fsm_state       <= FSM_AXI_STREAM_HANDSHAKE;
                                next_state      <= FSM_WAIT_FOR_WRESP;
                            end

                        // A write to any other address is a slave-error
                        default: ashi_wresp <= SLVERR;
                    endcase
                end

                // If the AXI master wants us to perform an AXI4-Lite read...
                else if (ashi_read) begin

                    // Assume for a moment that we will be reporting "OKAY" as a read-response
                    ashi_rresp <= OKAY;

                    case((ashi_raddr & ADDR_MASK) >> 2)

                        // If the user wants to read the AXI address register.
                        0:  ashi_rdata <= axi_register[0];

                        // If the user wants to write a value to the stored AXI register address...
                        1:  begin
                                axi_addr_out    <= axi_register[0]; // Stuff the AXI address into TDATA
                                axi_data_out    <= 32'hDEAD_BEEF;   // Doesn't matter what we stuff here
                                axi_mode_out    <= AXI_MODE_READ;   // This will be an AXI read
                                AXIS_OUT0_TVALID <= 1;               // And declare TDATA valid for 1 cycle
                                AXIS_OUT1_TVALID <= 1;
                                fsm_state       <= FSM_AXI_STREAM_HANDSHAKE;
                                next_state      <= FSM_WAIT_FOR_RRESP;
                            end

                        // A write to any other address is a slave-error
                        default: ashi_rresp <= SLVERR;
                    endcase
                end
 
                // If we're being told to write to the "preload-complete" AXI register...
                else if (preload_complete) begin
                    axi_addr_out    <= ECD_PRELOAD_ADDR; // Stuff the AXI address into TDATA
                    axi_data_out    <= ECD_PRELOAD_VALU; // Stuff the data value into TDATA 
                    axi_mode_out    <= AXI_MODE_WRITE;   // This will be an AXI write
                    AXIS_OUT0_TVALID <= 1;               // And declare TDATA valid for 1 cycle
                    AXIS_OUT1_TVALID <= 1;
                    fsm_state       <= FSM_AXI_STREAM_HANDSHAKE;
                    next_state      <= FSM_WAIT_FOR_WRESP;
                 end


            // Here we wait for the AXI-Stream write to be accepted
            FSM_AXI_STREAM_HANDSHAKE:
                begin
            
                    // If handshake has occured on ch0, lower TVALID
                    if (AXIS_OUT0_TVALID && AXIS_OUT0_TREADY) AXIS_OUT0_TVALID <= 0;
                    
                    // If handshake has occured on ch1, lower TVALID
                    if (AXIS_OUT1_TVALID && AXIS_OUT1_TREADY) AXIS_OUT1_TVALID <= 0;                

                    // If both handshakes have occured, we're ready to accept a response packed
                    if (AXIS_OUT0_TVALID == 0 && AXIS_OUT1_TVALID == 0) begin
                        AXIS_IN_TREADY <= 1;
                        fsm_state      <= next_state;
                    end
                end

            // Now we wait for the response to an AXI write
            FSM_WAIT_FOR_WRESP:

                if (AXIS_IN_TREADY && AXIS_IN_TVALID) begin
                    AXIS_IN_TREADY <= 0;
                    ashi_wresp     <= axi_resp_in;
                    fsm_state      <= FSM_WAIT_FOR_AXI_CMD;
                end 

            // Now we wait for the response to an AXI read
            FSM_WAIT_FOR_RRESP:

                if (AXIS_IN_TREADY && AXIS_IN_TVALID) begin
                    AXIS_IN_TREADY <= 0;
                    ashi_rresp     <= axi_resp_in;
                    ashi_rdata     <= axi_data_in;
                    fsm_state      <= FSM_WAIT_FOR_AXI_CMD;
                end 
        endcase
    end
    //==========================================================================




    //==========================================================================
    // This connects us to an AXI4-Lite slave core
    //==========================================================================
    axi4_lite_slave axi_slave
    (
        .clk            (clk),
        .resetn         (resetn),
        
        // AXI AW channel
        .AXI_AWADDR     (S_AXI_AWADDR),
        .AXI_AWVALID    (S_AXI_AWVALID),   
        .AXI_AWPROT     (S_AXI_AWPROT),
        .AXI_AWREADY    (S_AXI_AWREADY),
        
        // AXI W channel
        .AXI_WDATA      (S_AXI_WDATA),
        .AXI_WVALID     (S_AXI_WVALID),
        .AXI_WSTRB      (S_AXI_WSTRB),
        .AXI_WREADY     (S_AXI_WREADY),

        // AXI B channel
        .AXI_BRESP      (S_AXI_BRESP),
        .AXI_BVALID     (S_AXI_BVALID),
        .AXI_BREADY     (S_AXI_BREADY),

        // AXI AR channel
        .AXI_ARADDR     (S_AXI_ARADDR), 
        .AXI_ARVALID    (S_AXI_ARVALID),
        .AXI_ARPROT     (S_AXI_ARPROT),
        .AXI_ARREADY    (S_AXI_ARREADY),

        // AXI R channel
        .AXI_RDATA      (S_AXI_RDATA),
        .AXI_RVALID     (S_AXI_RVALID),
        .AXI_RRESP      (S_AXI_RRESP),
        .AXI_RREADY     (S_AXI_RREADY),

        // ASHI write-request registers
        .ASHI_WADDR     (ashi_waddr),
        .ASHI_WDATA     (ashi_wdata),
        .ASHI_WRITE     (ashi_write),
        .ASHI_WRESP     (ashi_wresp),
        .ASHI_WIDLE     (ashi_widle),

        // AMCI-read registers
        .ASHI_RADDR     (ashi_raddr),
        .ASHI_RDATA     (ashi_rdata),
        .ASHI_READ      (ashi_read ),
        .ASHI_RRESP     (ashi_rresp),
        .ASHI_RIDLE     (ashi_ridle)
    );
    //==========================================================================

endmodule






