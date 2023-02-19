//====================================================================================
//                        ------->  Revision History  <------
//====================================================================================
//
//   Date     Who   Ver  Changes
//====================================================================================
// 18-Feb-23  DWW  1000  Initial creation
//====================================================================================

`define S_AXI_DATA_WIDTH 512
`define S_AXI_ADDR_WIDTH 64

module fake_pcie_bridge
(
    input clk, resetn,

    //======================  An AXI Slave Interface  ==========================

    // "Specify write address"         -- Master --    -- Slave --
    input[`S_AXI_ADDR_WIDTH-1:0]       S_AXI_AWADDR,
    input                              S_AXI_AWVALID,
    input[2:0]                         S_AXI_AWPROT,
    input[3:0]                         S_AXI_AWID,
    input[7:0]                         S_AXI_AWLEN,
    input[2:0]                         S_AXI_AWSIZE,
    input[1:0]                         S_AXI_AWBURST,
    input                              S_AXI_AWLOCK,
    input[3:0]                         S_AXI_AWCACHE,
    input[3:0]                         S_AXI_AWQOS,
    output                                             S_AXI_AWREADY,


    // "Write Data"                    -- Master --    -- Slave --
    input[`S_AXI_DATA_WIDTH-1:0]       S_AXI_WDATA,
    input                              S_AXI_WVALID,
    input[(`S_AXI_DATA_WIDTH/8)-1:0]   S_AXI_WSTRB,
    input                              S_AXI_WLAST,
    output                                             S_AXI_WREADY,


    // "Send Write Response"           -- Master --    -- Slave --
    output[1:0]                                        S_AXI_BRESP,
    output                                             S_AXI_BVALID,
    input                              S_AXI_BREADY,



    // "Specify read address"          -- Master --    -- Slave --
    input [`S_AXI_ADDR_WIDTH-1:0]      S_AXI_ARADDR,
    input                              S_AXI_ARVALID,
    input [2:0]                        S_AXI_ARPROT,
    input                              S_AXI_ARLOCK,
    input [3:0]                        S_AXI_ARID,
    input [7:0]                        S_AXI_ARLEN,
    input [2:0]                        S_AXI_ARSIZE,
    input [1:0]                        S_AXI_ARBURST,
    input [3:0]                        S_AXI_ARCACHE,
    input [3:0]                        S_AXI_ARQOS,
    output                                             S_AXI_ARREADY,

    // "Read data back to master"      -- Master --    -- Slave --
    output[`S_AXI_DATA_WIDTH-1:0]                      S_AXI_RDATA,
    output reg                                         S_AXI_RVALID,
    output[1:0]                                        S_AXI_RRESP,
    output reg                                         S_AXI_RLAST,
    input                              S_AXI_RREADY,
    //==========================================================================


    //==================  AXI Stream output to the FIFO  =======================
    output[`S_AXI_ADDR_WIDTH-1:0]  AXIS_TF_TDATA,
    output                         AXIS_TF_TVALID,
    input                          AXIS_TF_TREADY,
    //==========================================================================


    //==================  AXI Stream input from the FIFO  ======================
    input[`S_AXI_ADDR_WIDTH-1:0]  AXIS_FF_TDATA,
    input                         AXIS_FF_TVALID,
    output reg                    AXIS_FF_TREADY
    //==========================================================================

 );

    // Some convenience declarations
    localparam S_AXI_ADDR_WIDTH = `S_AXI_ADDR_WIDTH;
    localparam S_AXI_DATA_WIDTH = `S_AXI_DATA_WIDTH;
    localparam S_AXI_DATA_BYTES = S_AXI_DATA_WIDTH / 8;

    // Wire the AR channel of the AXI4 interface to the input side of the FIFO
    assign AXIS_TF_TDATA  = S_AXI_ARADDR;
    assign AXIS_TF_TVALID = S_AXI_ARVALID;
    assign S_AXI_ARREADY  = AXIS_TF_TREADY;


    // This will store the address that is written into S_AXI_RDATA
    reg[S_AXI_ADDR_WIDTH-1:0] addr;

    // The top 64 bits of the AXI4 RDATA bus is the address of the data
    assign S_AXI_RDATA[511:448] = addr;

    //==========================================================================
    // State machine that writes data to the S_AXI R channel
    //==========================================================================
    reg[1:0]                  fsm_state;
    reg[7:0]                  countdown;

    always @(posedge clk) begin

        if (resetn == 0) begin
            
            fsm_state      <= 0;
            AXIS_FF_TREADY <= 0;
            S_AXI_RVALID   <= 0;

        end else case(fsm_state)

            0:  begin
                    AXIS_FF_TREADY <= 1;
                    fsm_state      <= 1;
                end

            1:  if (AXIS_FF_TREADY && AXIS_FF_TVALID) begin
                    AXIS_FF_TREADY <= 0;
                    addr           <= AXIS_FF_TDATA;
                    S_AXI_RVALID   <= 1;
                    countdown      <= 32 - 1;
                    fsm_state      <= 2;
                end
            
            2:  if (S_AXI_RVALID & S_AXI_RREADY) begin
                    if (countdown == 0) begin
                        AXIS_FF_TREADY <= 1;
                        S_AXI_RVALID   <= 0;
                        S_AXI_RLAST    <= 0;
                        fsm_state      <= 1;
                    end else begin
                        addr           <= addr + S_AXI_DATA_BYTES;
                        S_AXI_RLAST    <= (countdown == 1);
                        countdown      <= countdown - 1;
                    end
                end

        endcase

    end
    //==========================================================================

endmodule






