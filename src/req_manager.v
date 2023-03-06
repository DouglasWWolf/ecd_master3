
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// This module reads data requests, and transmits the correspond row of data
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

//===================================================================================================
//                            ------->  Revision History  <------
//===================================================================================================
//
//   Date     Who   Ver  Changes
//===================================================================================================
// 06-Oct-22  DWW  1000  Initial creation
//===================================================================================================

module req_manager #
(
    parameter REQ_ID_WIDTH = 32
)
(
    input clk, resetn, 

    //============================  Interface for fetching row-requests  ============================
    input[REQ_ID_WIDTH-1:0] REQ_ID_IN,
    input                   REQ_ID_VALID,
    output                  READY_FOR_REQ,
    //===============================================================================================

    //===========================  AXI Stream interface for data input #0 ===========================
    input[511:0]        AXIS_RX0_TDATA,
    input               AXIS_RX0_TVALID,
    output              AXIS_RX0_TREADY,
    //===============================================================================================

    //===========================  AXI Stream interface for data input #1 ===========================
    input[511:0]        AXIS_RX1_TDATA,
    input               AXIS_RX1_TVALID,
    output              AXIS_RX1_TREADY,
    //===============================================================================================

    //========================  AXI Stream interface for data_output  ===============================
    output reg[511:0]  AXIS_TX_TDATA,
    output reg         AXIS_TX_TVALID,
    output reg         AXIS_TX_TLAST,
    input              AXIS_TX_TREADY,
    //===============================================================================================

    //======================  AXI Stream interface to the row buffering FIFO  =======================
    output reg[511:0]  AXIS_RBF_TDATA,
    output reg         AXIS_RBF_TVALID,
    input              AXIS_RBF_TREADY
    //===============================================================================================

);
// Set this to zero to 1 to assert TLAST on every cycle, 0 to only assert it on the row-footer
localparam TLAST_DEFAULT = 0;

// This is how many beats of the RX data stream are in a single outgoing packet
localparam RX_BEATS_PER_PACKET = 16;

localparam PKT_TYPE_OFFS = 0;
localparam ROW_ID_OFFS   = 8;

//===================================================================================================
// Define a virtual AXI stream interface that maps to either RX0 or RX1
//===================================================================================================
reg         input_sel;
reg         AXIS_RX_TREADY;
wire[511:0] AXIS_RX_TDATA   = (input_sel == 0) ? AXIS_RX0_TDATA  : AXIS_RX1_TDATA;
wire        AXIS_RX_TVALID  = (input_sel == 0) ? AXIS_RX0_TVALID : AXIS_RX1_TVALID;
assign      AXIS_RX0_TREADY = (input_sel == 0) & AXIS_RX_TREADY;
assign      AXIS_RX1_TREADY = (input_sel == 1) & AXIS_RX_TREADY;
//===================================================================================================


// Define the AXIS handshake for each stream
wire RQ_HANDSHAKE = REQ_ID_VALID & READY_FOR_REQ;


//===================================================================================================
// State machine that allows incoming data-requests to flow in
//===================================================================================================

// This will be driven high for one cycle when we're ready for a new data-request to arrive
reg get_new_rq;

// The most recently arrived data-request
reg[REQ_ID_WIDTH-1:0] rq_data;

// This is '1' if rq_data holds a valid data-request
reg rq_data_valid;

// READY_FOR_REQ stays high as long as this is high
reg ready_for_req;      

// READY_FOR_REQ goes high as soon as get_new_rq goes high
assign READY_FOR_REQ = (resetn == 1) && (get_new_rq || ready_for_req);
 
//===================================================================================================
always @(posedge clk) begin
   
    // If we're in reset, by definition rq_data isn't valid.
    // When we come out of reset, we want to instantly drive READY_FOR_REQ 
    // high so that a data-request flows in as soon as one is available
    if (resetn == 0) begin
        rq_data_valid <= 0;
        ready_for_req <= 1;
    end else begin

        // If the other state machine asked for a new data-request, READY_FOR_REQ is 
        // already high.   Here we keep track of the fact that we want it to stay high
        // and we declare that the rq_data register no longer holds a valid data-request.
        if (get_new_rq) begin
            ready_for_req <= 1;
            rq_data_valid <= 0;
        end

        // If a new data-request has arrived...
        if (RQ_HANDSHAKE) begin
            
            // Lower the READY_FOR_REQ signal
            ready_for_req <= 0;
            
            // Store the data-request that just arrived
            rq_data <= REQ_ID_IN;

            // And indicate that rq_data holds a valid data-request
            rq_data_valid <= 1;
        end
    end

end
//===================================================================================================




//===================================================================================================
// flow state machine: main state machine that waits for a data-request to arrive, then transmits
// a 1 cycle packet header, 16 cycles of packet data, and 1 cycle of packet footer
//
// The sources of the received row data alternates between AXIS_RX0 and AXIS_RX1
//===================================================================================================
reg[2:0]               fsm_state;
reg[REQ_ID_WIDTH-1:0]  req_id;
reg[7:0]               beat_countdown;
reg[511:0]             skid_buffer;
reg                    skid_buffer_full;
//===================================================================================================

localparam FSM_WAIT_FOR_REQ    = 0;
localparam FSM_WAIT_FOR_DATA   = 1;
localparam FSM_SEND_DATA       = 2;
localparam FSM_WAIT_FOR_FINISH = 3;

always @(posedge clk) begin
    
    // These signals strobe high for only a single cycle
    get_new_rq      <= 0;
    AXIS_RBF_TVALID <= 0;
    
    if (resetn == 0) begin
        AXIS_TX_TVALID   <= 0;
        AXIS_TX_TLAST    <= TLAST_DEFAULT;
        AXIS_RX_TREADY   <= 0;
        input_sel        <= 0;
        fsm_state        <= FSM_WAIT_FOR_REQ;
        skid_buffer_full <= 0;
    end else case(fsm_state)


    FSM_WAIT_FOR_REQ:

        // If a new request has arrived...
        if (rq_data_valid) begin
            
            // Keep track of the request ID for future use
            req_id <= rq_data;

            // Emit a packet-header which consists of the request ID
            AXIS_TX_TDATA[PKT_TYPE_OFFS +: 8] <= 0;         // This is the message type
            AXIS_TX_TDATA[ROW_ID_OFFS   +:32] <= rq_data;   // This is the request ID

            // We have valid data on the TX data bus
            AXIS_TX_TVALID <= 1;

            // We're ready to receive row data
            AXIS_RX_TREADY <= 1;

            // Allow another data-request to get buffered up
            get_new_rq <= 1;

            // This is how many beats of RX data we have left to send
            beat_countdown <= RX_BEATS_PER_PACKET;

            // And go to the next state
            fsm_state <= FSM_SEND_DATA;
        end


    FSM_WAIT_FOR_DATA:

        // If data arrives from the RX stream, transmit it
        if (AXIS_RX_TVALID & AXIS_RX_TREADY) begin
            AXIS_TX_TDATA   <= AXIS_RX_TDATA;              // Copy data from the RX bus to the TX bus
            AXIS_TX_TVALID  <= 1;                          // The TX bus now contains valid data
            AXIS_RBF_TDATA  <= AXIS_RX_TDATA;              // Copy data from the RX bus to the RBF bus
            AXIS_RBF_TVALID <= (input_sel == 0);           // We only write to the RBF when reading from RX0
            AXIS_RX_TREADY  <= (beat_countdown != 1);      // Do we still need to receive for data for this burst?
            fsm_state       <= FSM_SEND_DATA;              // And go wait for the TX handshake
        end    

    FSM_SEND_DATA:
        
        // If we've received the TX handshake signaling that the previous write is finished...
        if (AXIS_TX_TVALID & AXIS_TX_TREADY) begin
        
            // If that was the last beat of the burst, emit the row footer
            if (beat_countdown == 0) begin
                AXIS_RX_TREADY  <= 0;                      // Don't accept further any RX data for the moment
                AXIS_RBF_TVALID <= 0;                      // We're not writing data to the row-buffer FIFO
                AXIS_TX_TDATA   <= req_id;                 // This is the footer data-cycle that we write
                AXIS_TX_TLAST   <= 1;                      // The row-footer marks the end of the packet
                input_sel       <= ~input_sel;             // Switch the RX stream to the "other" RX stream
                fsm_state       <= FSM_WAIT_FOR_FINISH;    // And go wait for the footer-cycle to be accepted
            end

            // Otherwise, if there is data in the skid buffer, transmit it
            else if (skid_buffer_full) begin
                AXIS_TX_TDATA    <= skid_buffer;           // Copy the skid-buffer to the TX bus
                AXIS_TX_TVALID   <= 1;                     // The TX bus now contains valid data
                AXIS_RBF_TDATA   <= skid_buffer;           // Copy the skid-buffer to the RBF bus
                AXIS_RBF_TVALID  <= (input_sel == 0);      // We only write to the RBF when reading from RX0
                skid_buffer_full <= 0;                     // The skid-buffer is now empty
                AXIS_RX_TREADY   <= (beat_countdown != 1); // Do we still need to receive data for this burst?
            end

            // Otherwise, if data has arrived from the RX stream, transmit it
            else if (AXIS_RX_TVALID & AXIS_RX_TREADY) begin    
                AXIS_TX_TDATA   <= AXIS_RX_TDATA;          // Copy the data from the RX bus to the TX bus
                AXIS_TX_TVALID  <= 1;                      // The TX bus now has valid data
                AXIS_RBF_TDATA  <= AXIS_RX_TDATA;          // Copy the data from the RX bus to the RBF bus
                AXIS_RBF_TVALID <= (input_sel == 0);       // We only write to the RBF when reading from RX0
                AXIS_RX_TREADY  <= (beat_countdown != 1);  // Do we still need to receive data for this burst?
            end

            // If we get here, no RX data is waiting, so go wait for more data to arrive
            else begin
                AXIS_RBF_TVALID <= 0;                      
                AXIS_TX_TVALID  <= 0;
                fsm_state       <= FSM_WAIT_FOR_DATA;
            end

            // Keep track of how many data-beats are left in this burst
            beat_countdown <= beat_countdown - 1;

        end

        // If RX data has arrived but the transmit-bus is busy, stash the RX data
        // so we can send it later.
        else if (AXIS_RX_TVALID & AXIS_RX_TREADY) begin
            skid_buffer      <= AXIS_RX_TDATA;
            skid_buffer_full <= 1;
            AXIS_RX_TREADY   <= 0;
        end    

    FSM_WAIT_FOR_FINISH:

        // If the packet footer was accepted...
        if (AXIS_TX_TREADY) begin

            // The next data-cycle we write is the start of a new packet
            AXIS_TX_TLAST <= TLAST_DEFAULT;

            // If we have another data-request pending...
            if (rq_data_valid) begin
                  
                // Keep track of the data-request ID for future use
                req_id <= rq_data;

                // Emit a packet-header which consists of the data-request ID
                AXIS_TX_TDATA[PKT_TYPE_OFFS +: 8] <= 0;         // This is the message type
                AXIS_TX_TDATA[ROW_ID_OFFS   +:32] <= rq_data;   // This is the request ID

                // The TX_TDATA bus is valid (it contains the request-ID)
                AXIS_TX_TVALID <= 1;

                // We're ready to receive data to be retransmitted
                AXIS_RX_TREADY <= 1;

                // Allow another data-request to get buffered up
                get_new_rq <= 1;

                // This is how many beats of RX data we have left to send
                beat_countdown <= RX_BEATS_PER_PACKET;

                // Go start emitting packet data
                fsm_state <= FSM_SEND_DATA;
            end

            // Otherwise, we no longer have valid data on the TX data-bus
            // and we need to go wait for a request to arrive
            else begin
                AXIS_TX_TVALID <= 0;
                fsm_state      <= FSM_WAIT_FOR_REQ;
            end
        end

    endcase

end
//===================================================================================================


endmodule


