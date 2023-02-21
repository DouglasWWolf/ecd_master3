//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// This module waits for incoming event messages and dispatches them appropriately
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

//===================================================================================================
//                            ------->  Revision History  <------
//===================================================================================================
//
//   Date     Who   Ver  Changes
//===================================================================================================
// 26-Dec-22  DWW  1000  Initial creation
//===================================================================================================


module event_broker # 
(
    parameter DATA_WIDTH  = 256
) 
(
    input clk, resetn,

    // If this is high, the input data-stream will be ignored
    input ignore_rx,

    // This will strobe high for one cycle when an "overflow" event message arrives
    output reg event_underflow,

    // This will strobe high for one cycle when the ECD detects "sequencing job complete"
    output reg event_jobcomplete,

    //========================  AXI Stream interface for the input side  ============================
    input[DATA_WIDTH-1:0]   AXIS_IN_TDATA,
    input                   AXIS_IN_TVALID,
    output reg              AXIS_IN_TREADY,
    //===============================================================================================
    
    //===================  AXI4-Lite transaction responses are reported here  =======================
    output reg[DATA_WIDTH-1:0] AXIS_OUT_TDATA,
    output reg                 AXIS_OUT_TVALID,
    input                      AXIS_OUT_TREADY
    //===============================================================================================
);

localparam EVENT_UNDERFLOW   = 1;
localparam EVENT_JOBCOMPLETE = 2;

wire[7:0] message_type = AXIS_IN_TDATA[255:248];
wire[7:0] event_type   = AXIS_IN_TDATA[7:0];

reg[1:0] fsm_state;

//===============================================================================================
// The "fsm_state" state machine waits for incoming event message to arrive, and dispatches
// each message according to its message type.
//===============================================================================================
always @(posedge clk) begin
    
    // When these are raised, they strobe high for exactly one clock cycle
    event_underflow   <= 0;
    event_jobcomplete <= 0;

    // When we're in reset...
    if (resetn == 0) begin
        fsm_state       <= 0;    
        AXIS_IN_TREADY  <= 0;
        AXIS_OUT_TVALID <= 0;

    // Otherwise, if we're not in reset, run our state machine    
    end else case (fsm_state)

        // When we come out of reset, make ready to accept incoming event messages
        0:  begin
                AXIS_IN_TREADY <= 1;
                fsm_state      <= 1;
            end

        // If we've received an event message...
        1:  if (AXIS_IN_TVALID & AXIS_IN_TREADY & ~ignore_rx) begin
                if (message_type == 0) begin
                    AXIS_OUT_TDATA  <= AXIS_IN_TDATA;
                    AXIS_OUT_TVALID <= 1;
                    AXIS_IN_TREADY  <= 0;
                    fsm_state       <= 2;
                end
                
                else if (message_type == 1) begin
                    if (event_type == EVENT_UNDERFLOW)   event_underflow   <= 1;
                    if (event_type == EVENT_JOBCOMPLETE) event_jobcomplete <= 1;
                end
            end

        // If the axi4lite response message was accepted...
        2:  if (AXIS_OUT_TREADY & AXIS_OUT_TVALID) begin
                AXIS_OUT_TVALID <= 0;
                AXIS_IN_TREADY  <= 1;
                fsm_state       <= 1;
            end

    endcase

end

endmodule
