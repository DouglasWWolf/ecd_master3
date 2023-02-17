

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// This module is a auto-matic switch to map multile AXIS input streams to a single output stream
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

//===================================================================================================
//                            ------->  Revision History  <------
//===================================================================================================
//
//   Date     Who   Ver  Changes
//===================================================================================================
// 12-Dec-22  DWW  1000  Initial creation
//===================================================================================================


module axis_switch #
(
    parameter DATA_WIDTH  = 512
) 
(
    input clk,

    //========================  AXI Stream interface for the input side  ============================
    input[DATA_WIDTH-1:0]   AXIS_IN1_TDATA,
    input                   AXIS_IN1_TVALID,
    input                   AXIS_IN1_TLAST,
    output                  AXIS_IN1_TREADY,
    //===============================================================================================

    //========================  AXI Stream interface for the input side  ============================
    input[DATA_WIDTH-1:0]   AXIS_IN2_TDATA,
    input                   AXIS_IN2_TVALID,
    input                   AXIS_IN2_TLAST,
    output                  AXIS_IN2_TREADY,
    //===============================================================================================


    //========================  AXI Stream interface for the output side  ===========================
    output[DATA_WIDTH-1:0]  AXIS_OUT_TDATA,
    output                  AXIS_OUT_TVALID,
    output                  AXIS_OUT_TLAST,
    input                   AXIS_OUT_TREADY
    //===============================================================================================
);


assign AXIS_OUT_TVALID = (AXIS_IN1_TVALID) ? 1 :
                         (AXIS_IN2_TVALID) ? 1 :
                        0;

assign AXIS_OUT_TLAST = (AXIS_IN1_TVALID) ? AXIS_IN1_TLAST :
                        (AXIS_IN2_TVALID) ? AXIS_IN2_TLAST :
                        0;

assign AXIS_OUT_TDATA = (AXIS_IN1_TVALID) ? AXIS_IN1_TDATA :
                        (AXIS_IN2_TVALID) ? AXIS_IN2_TDATA :
                        0;

assign AXIS_IN1_TREADY = (AXIS_IN1_TVALID) ? AXIS_OUT_TREADY : 0;
assign AXIS_IN2_TREADY = (AXIS_IN2_TVALID) ? AXIS_OUT_TREADY : 0;



endmodule
