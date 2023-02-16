//<><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><>
//   This core doesn't do anything at all except for provide an AXI4 master interace
//<><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><>

//====================================================================================
//                        ------->  Revision History  <------
//====================================================================================
//
//   Date     Who   Ver  Changes
//====================================================================================
// 10-May-22  DWW  1000  Initial creation
//====================================================================================


module axi4_master_plug #
( 
    parameter integer AXI_DATA_WIDTH = 32,
    parameter integer AXI_ADDR_WIDTH = 32
)
(

    input wire clk, 

    //======================  An AXI Master Interface  =========================

    // "Specify write address"          -- Master --    -- Slave --
    output     [AXI_ADDR_WIDTH-1:0]     AXI_AWADDR,   
    output                              AXI_AWVALID,  
    output     [2:0]                    AXI_AWPROT,
    output     [3:0]                    AXI_AWID,
    output     [7:0]                    AXI_AWLEN,
    output     [2:0]                    AXI_AWSIZE,
    output     [1:0]                    AXI_AWBURST,
    output                              AXI_AWLOCK,
    output     [3:0]                    AXI_AWCACHE,
    output     [3:0]                    AXI_AWQOS,
    input                                               AXI_AWREADY,


    // "Write Data"                     -- Master --    -- Slave --
    output     [AXI_DATA_WIDTH-1:0]     AXI_WDATA,      
    output                              AXI_WVALID,
    output     [(AXI_DATA_WIDTH/8)-1:0] AXI_WSTRB,
    output                              AXI_WLAST,
    input                                               AXI_WREADY,


    // "Send Write Response"            -- Master --    -- Slave --
    input      [1:0]                                    AXI_BRESP,
    input                                               AXI_BVALID,
    output                              AXI_BREADY,

    // "Specify read address"           -- Master --    -- Slave --
    output     [AXI_ADDR_WIDTH-1:0]     AXI_ARADDR,     
    output                              AXI_ARVALID,
    output     [2:0]                    AXI_ARPROT,     
    output                              AXI_ARLOCK,
    output     [3:0]                    AXI_ARID,
    output     [7:0]                    AXI_ARLEN,
    output     [2:0]                    AXI_ARSIZE,
    output     [1:0]                    AXI_ARBURST,
    output     [3:0]                    AXI_ARCACHE,
    output     [3:0]                    AXI_ARQOS,
    input                                               AXI_ARREADY,

    // "Read data back to master"       -- Master --    -- Slave --
    input [AXI_DATA_WIDTH-1:0]                          AXI_RDATA,
    input                                               AXI_RVALID,
    input [1:0]                                         AXI_RRESP,
    input                                               AXI_RLAST,
    output                              AXI_RREADY
    //==========================================================================
);


    assign AXI_WVALID  = 0;
    assign AXI_AWVALID = 0;
    assign AXI_ARVALID = 0;
    assign AXI_RREADY  = 0;
    assign AXI_BREADY  = 0;


endmodule
