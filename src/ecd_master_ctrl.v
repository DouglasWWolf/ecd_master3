`timescale 1ns / 1ps

//====================================================================================
//                        ------->  Revision History  <------
//====================================================================================
//
//   Date     Who   Ver  Changes
//====================================================================================
// 04-Oct-22  DWW  1000  Initial creation
//====================================================================================

`define AXIS_DATA_WIDTH  512
`define M_AXI_DATA_WIDTH 512
`define M_AXI_ADDR_WIDTH 64

module ecd_master_ctrl
(
    input clk, resetn,

    // Interrupt request signals that the PC's buffer has been fully read
    output reg IRQ_EOB,

    // This will strobe high the first time the output FIFO becomes full
    output reg PRELOAD_COMPLETE,

    // This is high when data is being received from the PCI bridge and thrown away
    // This is for debugging only, and is not normally connected to anythings
    output DRAINING,

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
    input                                   S_AXI_RREADY,
    //==========================================================================





    //===============  AXI Stream interface for outputting data ================
    output[`AXIS_DATA_WIDTH-1:0] AXIS_TX_TDATA,
    output                       AXIS_TX_TVALID,
    input                        AXIS_TX_TREADY,
    //==========================================================================





    //======================  An AXI Master Interface  =========================

    // "Specify write address"         -- Master --    -- Slave --
    output[`M_AXI_ADDR_WIDTH-1:0]      M_AXI_AWADDR,
    output                             M_AXI_AWVALID,
    output[2:0]                        M_AXI_AWPROT,
    output[3:0]                        M_AXI_AWID,
    output[7:0]                        M_AXI_AWLEN,
    output[2:0]                        M_AXI_AWSIZE,
    output[1:0]                        M_AXI_AWBURST,
    output                             M_AXI_AWLOCK,
    output[3:0]                        M_AXI_AWCACHE,
    output[3:0]                        M_AXI_AWQOS,
    input                                              M_AXI_AWREADY,


    // "Write Data"                    -- Master --    -- Slave --
    output[`M_AXI_DATA_WIDTH-1:0]      M_AXI_WDATA,
    output                             M_AXI_WVALID,
    output[(`M_AXI_DATA_WIDTH/8)-1:0]  M_AXI_WSTRB,
    output                             M_AXI_WLAST,
    input                                              M_AXI_WREADY,


    // "Send Write Response"           -- Master --    -- Slave --
    input [1:0]                                        M_AXI_BRESP,
    input                                              M_AXI_BVALID,
    output                             M_AXI_BREADY,

    // "Specify read address"          -- Master --    -- Slave --
    output reg[`M_AXI_ADDR_WIDTH-1:0]  M_AXI_ARADDR,
    output reg                         M_AXI_ARVALID,
    output[2:0]                        M_AXI_ARPROT,
    output                             M_AXI_ARLOCK,
    output[3:0]                        M_AXI_ARID,
    output[7:0]                        M_AXI_ARLEN,
    output[2:0]                        M_AXI_ARSIZE,
    output[1:0]                        M_AXI_ARBURST,
    output[3:0]                        M_AXI_ARCACHE,
    output[3:0]                        M_AXI_ARQOS,
    input                                              M_AXI_ARREADY,

    // "Read data back to master"      -- Master --    -- Slave --
    input[`M_AXI_DATA_WIDTH-1:0]                       M_AXI_RDATA,
    input                                              M_AXI_RVALID,
    input[1:0]                                         M_AXI_RRESP,
    input                                              M_AXI_RLAST,
    output                             M_AXI_RREADY
    //==========================================================================

 );

    // Some convenience declarations
    localparam M_AXI_ADDR_WIDTH = `M_AXI_ADDR_WIDTH;
    localparam M_AXI_DATA_WIDTH = `M_AXI_DATA_WIDTH;
    localparam M_AXI_DATA_BYTES = M_AXI_DATA_WIDTH / 8;

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

    // The state of our two state machines
    reg[2:0] ctrl_read_state, ctrl_write_state;

    // The state machines are idle when they're in state 0 and their "start" signals are low
    assign ashi_widle = (ashi_write == 0) && (ctrl_write_state == 0);
    assign ashi_ridle = (ashi_read  == 0) && (ctrl_read_state  == 0);

    // Data storage for the AXI registers
    reg[31:0] axi_register[0:4];

    // Some convenient human readable names for the AXI registers
    localparam REG_BUFFH     = 0;   // Hi 32-bits of start of the buffer on the PC
    localparam REG_BUFFL     = 1;   // Lo 32-bits of start of the buffer on the PC
    localparam REG_BUFF_SIZE = 2;   // PC buffer size in 2048-byte block
    localparam REG_START     = 3;   // A write to this register starts data transfer
    localparam REG_PAUSE     = 4;   // A non-zero value in this register pauses DMA transfers       
    
    // These are the valid values for ashi_rresp and ashi_wresp
    localparam OKAY   = 0;
    localparam SLVERR = 2;
    localparam DECERR = 3;

    // An AXI slave is gauranteed a minimum of 128 bytes of address space
    // (128 bytes is 32 32-bit registers)
    localparam ADDR_MASK = 7'h7F;

    // Every burst transfer will fetch us 32 AXI beats of data
    localparam BEATS_PER_BURST = 32;

    // This is the number of bytes fetched in a single burst read
    localparam BYTES_PER_BURST = M_AXI_DATA_BYTES * BEATS_PER_BURST;

    // This will strobe to 1 when it's time to start fetching data from the master interface
    reg start_fetching_data;
    
    // This is the state of the state machine that places read requests onto the AR channel
    reg[3:0] fsm_state;

    // This will be high when we are waiting to be told to start performing AXI reads 
    wire fsm_idle = (fsm_state == 0);

    // For debugging only: this goes high when data DMA'd from the PCI bridge is being thrown away
    assign DRAINING = fsm_idle & M_AXI_RVALID & M_AXI_RREADY;
    
    // The pause_dma signal will be high when DMA transfers are paused
    wire pause_dma = (axi_register[REG_PAUSE] != 0);

    // Burst parameters never change.  Burst type is INCR
    assign M_AXI_ARSIZE  = $clog2(M_AXI_DATA_BYTES);
    assign M_AXI_ARLEN   = BEATS_PER_BURST - 1;
    assign M_AXI_ARBURST = 1;

    // The AXI-Stream output is driven directly from the AXI Master interface    
    assign AXIS_TX_TVALID = M_AXI_RVALID && ~fsm_idle;
    
    // We're ready to receive data from the PCI bus if the FIFO is ready for data or
    // if we're idle.   If we're idle, the data is just thrown away
    assign M_AXI_RREADY = AXIS_TX_TREADY | fsm_idle;

    // We drive AXIS_TX_TDATA directly from M_AXI_RDATA, but we need to put the bytes
    // back in their original order (The PCI bridge delivers them to us in little-endian)
    wire[511:0] byte_swapped;
    genvar x;
    for (x=0; x<64; x=x+1) assign byte_swapped[x*8+7:x*8] = M_AXI_RDATA[(63-x)*8+7:(63-x)*8];
    assign AXIS_TX_TDATA[511:0] = byte_swapped[511:0];
   
    //==========================================================================
    // World's simplest state machine for handling write requests
    //==========================================================================
    always @(posedge clk) begin

        // When these goes high, they only stay high for once cycle
        start_fetching_data <= 0;

        // The PAUSE register always counts down to zero
        if (axi_register[REG_PAUSE]) begin
            axi_register[REG_PAUSE] <= axi_register[REG_PAUSE] - 1;
        end

        // If we're in reset, initialize important registers
        if (resetn == 0) begin
            ctrl_write_state <= 0;
            axi_register[REG_BUFFH    ] <= 0;
            axi_register[REG_BUFFL    ] <= 0;
            axi_register[REG_BUFF_SIZE] <= 0;
            axi_register[REG_PAUSE    ] <= 0;

        // If we're not in reset, and a write-request has occured...        
        end else if (ashi_write) begin
       
            // Assume for the moment that the result will be OKAY
            ashi_wresp <= OKAY;              
            
            // Convert the byte address into a register index
            case ((ashi_waddr & ADDR_MASK) >> 2)
                
                // Allow a write to any valid register
                REG_BUFFH:     axi_register[REG_BUFFH    ] <= ashi_wdata;
                REG_BUFFL:     axi_register[REG_BUFFL    ] <= ashi_wdata;
                REG_BUFF_SIZE: axi_register[REG_BUFF_SIZE] <= ashi_wdata;
                REG_PAUSE:     axi_register[REG_PAUSE    ] <= ashi_wdata;
                REG_START:     start_fetching_data         <= 1;

                // Writes to any other register are a decode-error
                default: ashi_wresp <= DECERR;
            endcase
        end
    end
    //==========================================================================



    //==========================================================================
    // World's simplest state machine for handling read requests
    //==========================================================================
    always @(posedge clk) begin

        // If we're in reset, initialize important registers
        if (resetn == 0) begin
            ctrl_read_state <= 0;
        
        // If we're not in reset, and a read-request has occured...        
        end else if (ashi_read) begin
       
            // Assume for the moment that the result will be OKAY
            ashi_rresp <= OKAY;              
            
            // Convert the byte address into a register index
            case ((ashi_raddr & ADDR_MASK) >> 2)

                // Allow a read from any valid register                
                REG_BUFFH:     ashi_rdata <= axi_register[REG_BUFFH    ];
                REG_BUFFL:     ashi_rdata <= axi_register[REG_BUFFL    ];
                REG_BUFF_SIZE: ashi_rdata <= axi_register[REG_BUFF_SIZE];
                REG_PAUSE:     ashi_rdata <= axi_register[REG_PAUSE    ];

                // Reads of any other register are a decode-error
                default: ashi_rresp <= DECERR;
            endcase
        end
    end
    //==========================================================================


    //==========================================================================
    // This state machine places read-requests on the AR channel of the AXI
    // Master bus
    //==========================================================================
    reg[31:0] blocks_remaining;
    //==========================================================================

    always @(posedge clk) begin

        if (resetn == 0) begin
            fsm_state     <= 0;
            M_AXI_ARVALID <= 0;
        end 

        else case(fsm_state)

        // Here we're idle, waiting to be told to start fetching data
        0:  if (start_fetching_data) begin
                fsm_state <= 1;
            end

        // Issue an AXI read-request for the first block of the PC's buffer
        1:  if (!pause_dma) begin
                
                // Determine the starting PCI address of the PC's buffer 
                M_AXI_ARADDR <= {axi_register[REG_BUFFH], axi_register[REG_BUFFL]};
            
                // Fetch the number of blocks remaining to be read-in from this buffer
                blocks_remaining <= axi_register[REG_BUFF_SIZE];

                // The AR channel now contains valid data
                M_AXI_ARVALID <= 1;

                // And go to the next state
                fsm_state <= 2;
            end


        // If our read-request was accepted...
        2:  if (M_AXI_ARREADY) begin
                
                // If we just issued the read-request for the last block in the PC buffer...
                if (blocks_remaining == 1) begin
                    M_AXI_ARVALID <= 0;
                    fsm_state     <= 1;
                
                // Otherwise, if we're pausing DMA, the ARADDR bus isn't valid
                end else if (pause_dma)
                    M_AXI_ARVALID <= 0;
                
                // Otherwise, generate a read-request for the next block in the PC buffer
                else begin
                    M_AXI_ARADDR     <= M_AXI_ARADDR + BYTES_PER_BURST;
                    M_AXI_ARVALID    <= 1;
                    blocks_remaining <= blocks_remaining - 1;
                end
            end

        endcase

    end
    //==========================================================================


    //==========================================================================
    // This state machine is responsible for raising an interrupt when the
    // last block in a buffer has been received.
    //==========================================================================
    reg [31:0] blocks_remaining_to_read;
    //==========================================================================
    always @(posedge clk) begin

        // When an interrupt-request line is raised, it should only strobe high for one cycle
        IRQ_EOB <= 0;

        // If we've just been told that "data fetching" (i.e., DMA transfers) has begun,
        // initialize our variables 
        if (start_fetching_data) begin
            blocks_remaining_to_read <= axi_register[REG_BUFF_SIZE];
        end

        // If we're fetching data, and this is a valid data cycle from the PCI bridge, and 
        // this is the last cycle of a block...
        else if (~fsm_idle & M_AXI_RREADY & M_AXI_RVALID & M_AXI_RLAST) begin
            
            // If this was the last block that was available in the buffer...
            if (blocks_remaining_to_read == 1) begin
                
                // Reload our counter of blocks remaining to be read
                blocks_remaining_to_read <= axi_register[REG_BUFF_SIZE];
                
                // Raise the interrupt that says "the buffer is empty"
                IRQ_EOB <= 1;
            end

            // Otherwise, if this was not the last block available in the buffer,
            // just keep track of how many blocks are left in this buffer
            else blocks_remaining_to_read <= blocks_remaining_to_read - 1;
        end
    end
    //==========================================================================


    //==========================================================================
    // This is the "preload-complete" state machine.  After a signal to start
    // fetching data, this detects the first occurence of the output FIFO being
    // full.  When this first "output FIFO is full" condition is detected, the 
    // PRELOAD_COMPLETE signal is strobed high for one cycle.
    //==========================================================================
    reg pcsm;
    always @(posedge clk) begin
        
        // When this signal is raised, it strobed high for exactly 1 cycle
        PRELOAD_COMPLETE <= 0;

        if (resetn == 0)
            pcsm <= 0;
        else case (pcsm)

        // Here we're waiting to be told that data-fetching has started
        0:  if (start_fetching_data) pcsm <= 1;

        // Here we're waiting for the output FIFO to become full
        1:  if (~AXIS_TX_TREADY) begin
                PRELOAD_COMPLETE <= 1;
                pcsm             <= 0;
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






