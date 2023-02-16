//===================================================================================================
//                            ------->  Revision History  <------
//===================================================================================================
//
//   Date     Who   Ver  Changes
//===================================================================================================
// 25-Oct-22  DWW  1000  Initial creation
//===================================================================================================


module axis_consumer#
(
    parameter DATA_WIDTH  = 256
) 
(
    input clk,
    output reg[DATA_WIDTH-1:0] data,

    //========================  AXI Stream interface for the input side  ============================
    input[DATA_WIDTH-1:0]    AXIS_TDATA,
    input                    AXIS_TVALID,
    output reg               AXIS_TREADY
    //===============================================================================================

);

always @(posedge clk) begin
    AXIS_TREADY <= 1;
    if (AXIS_TVALID & AXIS_TREADY) data <= AXIS_TDATA;
end


endmodule