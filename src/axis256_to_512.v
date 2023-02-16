
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
//     This module is used to narrow the width of an AXI stream in order to trim-off unused bits
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

//===================================================================================================
//                            ------->  Revision History  <------
//===================================================================================================
//
//   Date     Who   Ver  Changes
//===================================================================================================
// 14-Feb-22  DWW  1000  Initial creation
//===================================================================================================


module axis256_to_512
(
    input clk,

    //========================  AXI Stream interface for the input side  ============================
    input[255:0]    AXIS_RX_TDATA,
    input           AXIS_RX_TVALID,
    output          AXIS_RX_TREADY,
    //===============================================================================================


    //========================  AXI Stream interface for the output side  ===========================
    output[511:0]  AXIS_TX_TDATA,
    output         AXIS_TX_TVALID,
    output         AXIS_TX_TLAST,
    input          AXIS_TX_TREADY
    //===============================================================================================

);

assign  AXIS_TX_TDATA[255:0]   = AXIS_RX_TDATA[255:0];
assign  AXIS_TX_TDATA[511:256] = 0;
assign  AXIS_TX_TVALID         = AXIS_RX_TVALID;
assign  AXIS_TX_TLAST          = 1;
assign  AXIS_RX_TREADY         = AXIS_TX_TREADY;

endmodule