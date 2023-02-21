
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
//              This module presents request ID's to the cores that receive requests
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

//===================================================================================================
//                            ------->  Revision History  <------
//===================================================================================================
//
//   Date     Who   Ver  Changes
//===================================================================================================
// 16-Feb-23  DWW  1000  Initial creation
//===================================================================================================


module req_presenter #
(
    parameter REQ_ID_WIDTH = 32
) 
(
    input clk,

    // If this is high, the incoming data-stream will be ignored
    input ignore_rx,

    //========================  AXI Stream interface for the input side  ============================
    input[REQ_ID_WIDTH-1:0] FIFO_TDATA,
    input                   FIFO_TVALID,
    output                  FIFO_TREADY,
    //===============================================================================================

    // The "ready for a request" signal from the two output channels
    input ch0_ready, ch1_ready,
    
    // The signal that tells the other cores "req_id is valid"
    output req_id_valid,

    // The request ID that is being presented
    output[REQ_ID_WIDTH-1:0] req_id
);

assign  req_id       = FIFO_TDATA;
assign  req_id_valid = FIFO_TVALID & ch0_ready & ch1_ready & ~ignore_rx;
assign  FIFO_TREADY  = ch0_ready & ch1_ready;

endmodule