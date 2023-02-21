
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

    // This will be active when test-packets are being sent
    output reg sending_testp,

    //===========  Lo order AXI Stream interface for the AXI request ===========
    output reg [511:0]  AXIS_OUT_LO_TDATA,
    output reg          AXIS_OUT_LO_TVALID,
    output reg          AXIS_OUT_LO_TLAST,
    input               AXIS_OUT_LO_TREADY,
    //==========================================================================

    //===========  Hi order AXI Stream interface for the AXI request ===========
    output reg [511:0]  AXIS_OUT_HI_TDATA,
    output reg          AXIS_OUT_HI_TVALID,
    output reg          AXIS_OUT_HI_TLAST,
    input               AXIS_OUT_HI_TREADY,
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

//==========================================================================
// Packet types that we can emit
//==========================================================================
localparam PKT_AXI_TRANSACT = 1;
localparam PKT_TEST_PATTERN = 2;
//==========================================================================


//===============================================================================================
// Define the various AXI4-Stream handshakes
//===============================================================================================
wire AXIS_OUT_LO_HS = AXIS_OUT_LO_TVALID & AXIS_OUT_LO_TREADY;
wire AXIS_OUT_HI_HS = AXIS_OUT_HI_TVALID & AXIS_OUT_HI_TREADY;
//===============================================================================================
    
//===============================================================================================
// Field definitions for the TDATA lines
//===============================================================================================

// Fields of the input stream
wire[31:0] axi_addr_in = AXIS_IN_TDATA[31:00];
wire[31:0] axi_data_in = AXIS_IN_TDATA[63:32];
wire[ 2:0] axi_resp_in = AXIS_IN_TDATA[66:64];

// Address and data registers for AXI4-Lite reads and writes
localparam AXI_ADDR_OFFS = 0;
localparam AXI_DATA_OFFS = 32;
localparam AXI_MODE_OFFS = 64;
localparam PKT_TYPE_OFFS = 504;

// These are the kind of AXI remote-transactions that can be performed
localparam AXI_MODE_WRITE = 0;
localparam AXI_MODE_READ  = 1;

// The state of our main state machine
reg[1:0] fsm_state;
localparam FSM_WAIT_FOR_AXI_CMD     = 0;
localparam FSM_WAIT_AXI_WRESP       = 1;
localparam FSM_WAIT_AXI_RRESP       = 2; 

// The ASHI state machines are idle when they're in state 0 when their "start" signals are low
assign ashi_widle = (ashi_write == 0) && (fsm_state == 0);
assign ashi_ridle = (ashi_read  == 0) && (fsm_state == 0);

// These are the valid values for ashi_rresp and ashi_wresp
localparam OKAY   = 0;
localparam SLVERR = 2;
localparam DECERR = 3;

// An AXI slave is gauranteed a minimum of 128 bytes of address space
// (128 bytes is 32 32-bit registers)
localparam ADDR_MASK = 7'h7F;


// The local AXI registers
reg[31:0] axi_reg[0:3];
localparam REG_REMOTE_ADDR  = 0;
localparam REG_REMOTE_RW    = 1;
localparam REG_TESTP_LENGTH = 2;
localparam REG_TESTP_COUNT  = 3;


//==========================================================================
// These state machine controls the AXI4-Stream outputs
//==========================================================================
// State machines both start when osm_cmd is non-zero.
// State machines are both done when osm_idle is 1
//
// For command OSM_CMD_AXI_TRANSACT:
//
//      On Entry:
//          osm_axi_addr  = The AXI address to read/write
//          osm_axi_wdata = The data to be written
//          osm_axi_mode  = AXI_MODE_READ or AXI_MODE_WRITE
//
//      On Exit:
//          osm_axi_tresp = AXI read-response
//          osm_axi_rdata = The data value that was read
//
// For command OSM_CMD_START_TESTP:
//
//      On Entry:
//          axi_reg[REG_TESTP_LENGTH] = Number of data-cycles in a packet
//          axi_reg[REG_TESTP_COUNT]  = THe number of packets to send
//
//      On Exit:
//          nothing
//
//==========================================================================
reg[1:0]   osm_cmd;
localparam OSM_CMD_AXI_TRANSACT = 1;
localparam OSM_CMD_START_TESTP  = 2;

reg[2:0]   osm0_state, osm1_state;
localparam OSM_IDLE           = 0;
localparam OSM_AXI_RW         = 1;
localparam OSM_AXI_WAIT_HS    = 2;
localparam OSM_AXI_WAIT_RESP  = 3;
localparam OSM_START_TESTP    = 4;
localparam OSM_NEXT_TESTP     = 5;
localparam OSM_SEND_ONE_TESTP = 6;
localparam OSM_FINISH_TESTP   = 7;

reg[31:0]  osm_axi_addr;
reg[31:0]  osm_axi_wdata;
reg        osm_axi_mode;

reg[ 1:0]  osm_axi_tresp;
reg[31:0]  osm_axi_rdata;

reg[31:0]  osm0_testp_count,  osm1_testp_count;
reg[ 7:0]  osm0_testp_length, osm1_testp_length;
reg[ 7:0]  osm0_cycle,        osm1_cycle;

wire osm_idle = (osm_cmd == 0 & osm0_state == OSM_IDLE & osm1_state == OSM_IDLE);
//==========================================================================
always @(posedge clk) begin
    if (resetn == 0) begin
        osm0_state         <= OSM_IDLE;
        sending_testp      <= 0;
        AXIS_OUT_LO_TVALID <= 0;
        AXIS_IN_TREADY     <= 0;

    end else case (osm0_state)

        OSM_IDLE:
            
            begin
                if (osm_cmd == OSM_CMD_AXI_TRANSACT) osm0_state <= OSM_AXI_RW;
                if (osm_cmd == OSM_CMD_START_TESTP ) osm0_state <= OSM_START_TESTP;
            end

        OSM_AXI_RW:
            
            begin
                AXIS_OUT_LO_TDATA                      <= 0;
                AXIS_OUT_LO_TDATA[PKT_TYPE_OFFS +:  8] <= PKT_AXI_TRANSACT;
                AXIS_OUT_LO_TDATA[AXI_ADDR_OFFS +: 32] <= osm_axi_addr;
                AXIS_OUT_LO_TDATA[AXI_DATA_OFFS +: 32] <= osm_axi_wdata;
                AXIS_OUT_LO_TDATA[AXI_MODE_OFFS +:  1] <= osm_axi_mode;
                AXIS_OUT_LO_TLAST                      <= 1;
                AXIS_OUT_LO_TVALID                     <= 1;
                osm0_state                             <= OSM_AXI_WAIT_HS;
            end

        OSM_AXI_WAIT_HS:
            
            if (AXIS_OUT_LO_TVALID & AXIS_OUT_LO_TREADY) begin
                AXIS_OUT_LO_TVALID <= 0;
                AXIS_OUT_LO_TLAST  <= 0;
                AXIS_IN_TREADY     <= 1;
                osm0_state         <= OSM_AXI_WAIT_RESP;
            end

        OSM_AXI_WAIT_RESP:
            
            if (AXIS_IN_TVALID & AXIS_IN_TREADY) begin
                osm_axi_rdata   <= axi_data_in;
                osm_axi_tresp   <= axi_resp_in;
                AXIS_IN_TREADY  <= 0;
                osm0_state      <= OSM_IDLE;
            end

        OSM_START_TESTP:
            
            if (axi_reg[REG_TESTP_COUNT]) begin
                osm0_testp_count  <= axi_reg[REG_TESTP_COUNT];
                osm0_testp_length <= axi_reg[REG_TESTP_LENGTH] ? axi_reg[REG_TESTP_LENGTH] : 18;
                sending_testp     <= 1;
                osm0_state        <= OSM_NEXT_TESTP;
            end else begin
                osm0_state        <= OSM_IDLE;
            end
    
        OSM_NEXT_TESTP:

            if (osm0_testp_count) begin
                AXIS_OUT_LO_TDATA  <= {64{8'hAA}};
                AXIS_OUT_LO_TLAST  <= (osm0_testp_length == 1);
                AXIS_OUT_LO_TVALID <= 1;
                osm0_cycle         <= osm0_testp_length - 1;
                osm0_state         <= OSM_SEND_ONE_TESTP;
                osm0_testp_count   <= osm0_testp_count - 1;
            end else begin
                osm0_cycle         <= 10000;
                osm0_state         <= OSM_FINISH_TESTP;
            end

        OSM_SEND_ONE_TESTP:
            
            if (AXIS_OUT_LO_TREADY) begin
                AXIS_OUT_LO_TLAST  <= (osm0_cycle == 1);
                AXIS_OUT_LO_TVALID <= (osm0_cycle != 0);
                if (osm0_cycle == 0) begin
                    osm0_state <= OSM_NEXT_TESTP;
                end
                osm0_cycle <= osm0_cycle - 1;
            end

        // We're assuming we have a physical loopback connector installed 
        // and we need to wait for all the packets we just sent to arrive
        // before lowering the "sending_testp" line
        OSM_FINISH_TESTP:
            if (osm0_cycle)
                osm0_cycle <= osm0_cycle -1;
            else begin
                sending_testp <= 0;
                osm0_state    <= OSM_IDLE;
            end

   endcase
end


// This is the same as the state machine above, but for the high-order bits 
always @(posedge clk) begin
    if (resetn == 0) begin
        osm1_state         <= OSM_IDLE;
        AXIS_OUT_HI_TVALID <= 0;

    end else case (osm1_state)

        OSM_IDLE:
            begin
                if (osm_cmd == OSM_CMD_AXI_TRANSACT) osm1_state <= OSM_AXI_RW;
                if (osm_cmd == OSM_CMD_START_TESTP ) osm1_state <= OSM_START_TESTP;                
            end

        OSM_AXI_RW:
            begin
                AXIS_OUT_HI_TDATA                      <= 0;
                AXIS_OUT_HI_TDATA[AXI_ADDR_OFFS +: 32] <= osm_axi_addr;
                AXIS_OUT_HI_TDATA[AXI_DATA_OFFS +: 32] <= osm_axi_wdata;
                AXIS_OUT_HI_TDATA[AXI_MODE_OFFS +:  1] <= osm_axi_mode;
                AXIS_OUT_HI_TLAST                      <= 1;
                AXIS_OUT_HI_TVALID                     <= 1;
                osm1_state         <= OSM_AXI_WAIT_HS;
            end

        OSM_AXI_WAIT_HS:

            if (AXIS_OUT_HI_TVALID & AXIS_OUT_HI_TREADY) begin
                AXIS_OUT_HI_TVALID <= 0;
                AXIS_OUT_HI_TLAST  <= 0;
                osm1_state         <= OSM_AXI_WAIT_RESP;
            end

        OSM_AXI_WAIT_RESP:

            if (osm0_state == OSM_IDLE) begin
                osm1_state <= OSM_IDLE;
            end

        OSM_START_TESTP:
            
            if (axi_reg[REG_TESTP_COUNT]) begin
                osm1_testp_count  <= axi_reg[REG_TESTP_COUNT];
                osm1_testp_length <= axi_reg[REG_TESTP_LENGTH] ? axi_reg[REG_TESTP_LENGTH] : 18;
                osm1_state        <= OSM_NEXT_TESTP;
            end else begin
                osm1_state        <= OSM_IDLE;
            end
    
        OSM_NEXT_TESTP:

            if (osm1_testp_count) begin
                AXIS_OUT_HI_TDATA  <= {64{8'hAA}};
                AXIS_OUT_HI_TLAST  <= (osm1_testp_length == 1);
                AXIS_OUT_HI_TVALID <= 1;
                osm1_cycle         <= osm1_testp_length - 1;
                osm1_state         <= OSM_SEND_ONE_TESTP;
                osm1_testp_count   <= osm1_testp_count - 1;
            end else begin
                osm1_state         <= OSM_IDLE;
            end

        OSM_SEND_ONE_TESTP:
            
            if (AXIS_OUT_HI_TREADY) begin
                AXIS_OUT_HI_TLAST  <= (osm1_cycle == 1);
                AXIS_OUT_HI_TVALID <= (osm1_cycle != 0);
                if (osm1_cycle == 0) begin
                    osm1_state <= OSM_NEXT_TESTP;
                end
                osm1_cycle <= osm1_cycle - 1;
            end
 
   endcase
end
//==========================================================================



//==========================================================================
// This state machine handles both AXI-write and AXI-read requests
//==========================================================================
always @(posedge clk) begin

    // When this value is changed, the change lasts for exactly 1 cycle
    osm_cmd <= 0;

    // If we're in reset, initialize important registers
    if (resetn == 0) begin
        fsm_state  <= 0;

    // If we're not in reset...
    end else case(fsm_state)

        // If a write-request has come in...
        FSM_WAIT_FOR_AXI_CMD:
                
            // If the AXI master wants us to perform an AXI4-Lite write...
            if (ashi_write) begin

                case((ashi_waddr & ADDR_MASK) >> 2)

                    // Does the user want to store an AXI register remote-address.
                    REG_REMOTE_ADDR:
                        
                        begin
                            axi_reg[REG_REMOTE_ADDR] <= ashi_wdata;
                            ashi_wresp               <= OKAY;
                        end

                    // Does the user want to write a value to the remote AXI register?
                    REG_REMOTE_RW:
                        
                        if (osm_idle) begin
                            osm_axi_addr  <= axi_reg[REG_REMOTE_ADDR];  // Fill in the remote address to write to
                            osm_axi_wdata <= ashi_wdata;                // Fill in the data to write
                            osm_axi_mode  <= AXI_MODE_WRITE;            // This will be an AXI write
                            osm_cmd       <= OSM_CMD_AXI_TRANSACT;      // Tell the OSM to start an AXI transaction
                            fsm_state     <= FSM_WAIT_AXI_WRESP;        // And wait for the remote AXI write-response
                        end else begin
                            ashi_wresp <= SLVERR;
                        end


                    // If the user wants to store a length for test packets
                    REG_TESTP_LENGTH:

                        begin
                            axi_reg[REG_TESTP_LENGTH] <= ashi_wdata;
                            ashi_wresp                <= OKAY;
                        end

                    // If the user wants to start sending test packets
                    REG_TESTP_COUNT:
                        
                        if (osm_idle) begin
                            axi_reg[REG_TESTP_COUNT] <= ashi_wdata;
                            osm_cmd                  <= OSM_CMD_START_TESTP;
                            ashi_wresp               <= OKAY;
                        end else begin
                            ashi_wresp               <= SLVERR;
                        end


                    // A write to any other address is a slave-error
                    default: ashi_wresp <= SLVERR;

                endcase
            end

            // If the AXI master wants us to perform an AXI4-Lite read...
            else if (ashi_read) begin

                case((ashi_raddr & ADDR_MASK) >> 2)

                    // If the user wants to read the AXI remote-address register....
                    REG_REMOTE_ADDR:
                        
                        begin
                            ashi_rdata <= axi_reg[REG_REMOTE_ADDR];
                            ashi_rresp <= OKAY;
                        end

                    // If the user wants to read a value from remote AXI register...
                    REG_REMOTE_RW:
                        
                        if (osm_idle) begin
                            osm_axi_addr  <= axi_reg[REG_REMOTE_ADDR]; // Fill in the remote address to read from
                            osm_axi_wdata <= 32'hDEAD_BEEF;                 // Doesn't matter what we stuff here
                            osm_axi_mode  <= AXI_MODE_READ;                 // This will be an AXI read
                            osm_cmd       <= OSM_CMD_AXI_TRANSACT;          // Tell the OSM to start an AXI transaction       
                            fsm_state     <= FSM_WAIT_AXI_RRESP;            // And go wait for the remote AXI read-response
                        end else begin
                            ashi_rresp    <= SLVERR;
                        end

                    // Does the user want to fetch the test-pattern length?
                    REG_TESTP_LENGTH:

                        begin
                            ashi_rdata <= axi_reg[REG_TESTP_LENGTH];
                            ashi_rresp <= OKAY;
                        end

                    // Does the user want to fetch the number of packets in a test pattern?
                    REG_TESTP_COUNT:

                        begin
                            ashi_rdata <= axi_reg[REG_TESTP_COUNT];
                            ashi_rresp <= OKAY;
                        end

                    // A write to any other address is a slave-error
                    default: ashi_rresp <= SLVERR;
                
                endcase
            end
 
            // If we're being told to write to the "preload-complete" AXI remote-register...
            else if (preload_complete) begin
                osm_axi_addr  <= ECD_PRELOAD_ADDR;      // Fill in the AXI address of the remote register
                osm_axi_wdata <= ECD_PRELOAD_VALU;      // Fill in the data to write to that address
                osm_axi_mode  <= AXI_MODE_WRITE;        // This will be an AXI write
                osm_cmd       <= OSM_CMD_AXI_TRANSACT;  // Tell the OSM to begin an AXI transaction         
                fsm_state     <= FSM_WAIT_AXI_WRESP;    // And go wait for the remote AXI write-response
            end


        // Now we wait for the response to an AXI write
        FSM_WAIT_AXI_WRESP:
                
            if (osm_idle) begin
                ashi_wresp     <= osm_axi_tresp;
                fsm_state      <= FSM_WAIT_FOR_AXI_CMD;
            end 

        // Now we wait for the response to an AXI read
        FSM_WAIT_AXI_RRESP:

            if (osm_idle) begin
                ashi_rresp     <= osm_axi_tresp;
                ashi_rdata     <= osm_axi_rdata;
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






