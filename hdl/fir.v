module fir 
#(  parameter pADDR_WIDTH = 12,
    parameter pDATA_WIDTH = 32,
    parameter Tape_Num    = 32
)
(
    output  reg                     awready,
    output  reg                     wready,
    input   wire                     awvalid,
    input   wire [(pADDR_WIDTH-1):0] awaddr,
    input   wire                     wvalid,
    input   wire [(pDATA_WIDTH-1):0] wdata,
    output  reg                     arready,
    input   wire                     rready,
    input   wire                     arvalid,
    input   wire [(pADDR_WIDTH-1):0] araddr,
    output  reg                     rvalid,
    output  reg [(pDATA_WIDTH-1):0] rdata,  

    input   wire                     ss_tvalid, 
    input   wire [(pDATA_WIDTH-1):0] ss_tdata, 
    input   wire                     ss_tlast, 
    output  reg                     ss_tready, 
    input   wire                     sm_tready, 
    output  reg                     sm_tvalid, 
    output  wire [(pDATA_WIDTH-1):0] sm_tdata, 
    output  reg                     sm_tlast, 
    
    // bram for tap RAM
    output  reg [3:0]               tap_WE,
    output  reg                     tap_EN,
    output  reg [(pDATA_WIDTH-1):0] tap_Di,
    output  reg [(pADDR_WIDTH-1):0] tap_A,
    input   wire [(pDATA_WIDTH-1):0] tap_Do,

    // bram for data RAM
    output  reg [3:0]               data_WE,
    output  reg                     data_EN,
    output  reg  [(pDATA_WIDTH-1):0] data_Di,
    output  reg  [(pADDR_WIDTH-1):0] data_A,
    input   wire [(pDATA_WIDTH-1):0] data_Do,

    input   wire                     axis_clk,
    input   wire                     axis_rst_n
);


// Main FSM
///////////////////////////////////////////////////////////////////////////////////// deal with ap_ctrl
    reg [2:0] state_engine;
    reg [2:0] next_state_engine;
    
    reg flag_addr_or_tap; // to judge now is waiting tap or addr, 0 is waiting addr, 1 is waiting tag
    reg next_flag_addr_or_tap;
    reg flag_addr_or_rdata;//0 is waiting data
    reg next_flag_addr_or_rdata;
    
    reg [2:0] ap_ctrl; // [ap_idle, ap_done, ap_start]
    reg [2:0] next_ap_ctrl;

    //when initial, put 0 to data_ram, and here is used to calculate data_A
    reg [11:0] initial_counter;
    wire [11:0] next_initial_counter;
    
    // deal with data_x_length
    reg [31:0] data_x_length;
    wire [31:0] next_data_x_length;
    reg flag_data_length_receive; // if it's 1 => data_x_length can be received => to hold 1 if there is space between awvalid and wvalid
    reg next_flag_data_length_receive;
    
    reg [31:0] tap_num;
    wire [31:0] next_tap_num;
    reg flag_tap_num_receive; // if it's 1 => tap_num can be received => to hold 1 if there is space between awvalid and wvalid
    reg next_flag_tap_num_receive;
    
//    reg [4:0] tap_addr_counter;
//   reg [4:0] next_tap_addr_counter;
    reg next_awready;
    reg next_wready;
    wire next_arready;
    reg next_rvalid;
    wire [31:0] next_rdata;
    reg [11:0] temporary_addr;
    reg [11:0] next_temporary_addr;
    
    reg next_sm_tvalid;

    wire [4:0] data_do_pointer; // to count which data_A should be read
    wire [4:0] tap_do_pointer; // to count which tap_A should be read
    
    reg [31:0] done_times; //how many times the convolution has been done
    reg [31:0] next_done_times;
    
    reg [4:0] data_ram_start_place_count; // to record the start place of data_ram   
    reg [4:0] next_data_ram_start_place_count;
    
    reg [4:0] tap_cursor_count; // to record the current addr to send to tap_RAM 
    reg [4:0] next_tap_cursor_count;
    
    reg [4:0] data_cursor_count; // to record the current addr to send ap_ctrl data_RAM
    reg [4:0] next_data_cursor_count;
    
    reg [5:0] cycle_count; // need to record how many cycle in state=engine_processing
    reg [5:0] next_cycle_count;
    
    wire next_ss_tready;
    
    reg [4:0] data_addr_counter;
    reg [4:0] next_data_addr_counter;
    
    wire [(pDATA_WIDTH-1):0] m_tmp;
    wire [(pDATA_WIDTH-1):0] h_tmp;
    reg [(pDATA_WIDTH-1):0] x_tmp;
    reg [(pDATA_WIDTH-1):0] y_tmp;

    reg [(pDATA_WIDTH-1):0] m;
    reg [(pDATA_WIDTH-1):0] y;
    reg [(pDATA_WIDTH-1):0] h;
    reg [(pDATA_WIDTH-1):0] x;
    
    parameter engine_initial = 3'd0;
    parameter engine_before_start = 3'd1;
    parameter engine_waiting_data = 3'd2;
    parameter engine_processing = 3'd3;
    parameter engine_done = 3'd4;

    always @(posedge axis_clk or negedge axis_rst_n) begin
        if (!axis_rst_n) begin
            state_engine <= engine_initial; 
            ap_ctrl <= 3'b100;
        end else begin
            state_engine <= next_state_engine;
            ap_ctrl <= next_ap_ctrl;
        end        
    end
    
    // FSM
    always @(*) begin
        case (state_engine)
            engine_initial: begin
                if (initial_counter == 12'd32) begin
                    next_state_engine = engine_before_start;
                end else begin
                    next_state_engine = state_engine;
                end
            end
            engine_before_start: begin
                if (wdata == 32'd1 && awaddr == 12'd0 && wvalid == 1'b1 && wready == 1'b1) begin
                    next_state_engine = engine_waiting_data;
                end else begin
                    next_state_engine = state_engine;
                end
            end
            engine_waiting_data: begin
                if (sm_tlast == 1'b1) begin
                    next_state_engine = engine_done;
                end else if (ss_tready == 1'b1 && ss_tvalid == 1'b1) begin 
                    next_state_engine = engine_processing;
                end else begin
                    next_state_engine = state_engine;
                end
            end
            engine_processing: begin
                if (sm_tlast == 1'b1) begin
                    next_state_engine = engine_done;
                end else if (sm_tvalid == 1'b1 && sm_tready == 1'b1) begin
                    next_state_engine = engine_waiting_data;
                end else begin
                    next_state_engine = state_engine;
                end
            end
            engine_done: begin/////////////////////////////////////////////////////////////////////////////////////
                if (rvalid && rready && rdata == 32'd2) begin
                    next_state_engine = engine_initial;
                end else begin
                    next_state_engine = state_engine;
                end
            end
            default: begin
                next_state_engine = engine_before_start;
            end
        endcase
    end

/////////////////////////////////////////////////////////////////////////////
//deal with ap_ctrl
    always @(*) begin
        case (state_engine)
            engine_initial: begin
                next_ap_ctrl = 3'b100;
            end
            engine_before_start: begin
                if (wdata == 32'd1 && awaddr == 12'd0 && awvalid == 1'b1) begin
                    next_ap_ctrl = 3'b101;
                end else begin
                    next_ap_ctrl = 3'b100;
                end
            end
            engine_waiting_data: begin
                if (sm_tlast == 1'b1) begin
                    next_ap_ctrl = 3'b010;
                end else if (ss_tready == 1'b1 && ss_tvalid == 1'b1) begin 
                    next_ap_ctrl = 3'b000;
                end else begin
                    next_ap_ctrl = 3'b000;
                end
            end
            engine_processing: begin
                if (sm_tlast == 1'b1) begin
                    next_ap_ctrl = 3'b010;
                end else if (sm_tvalid == 1'b1 && sm_tready == 1'b1) begin
                    next_ap_ctrl = 3'b000;
                end else begin
                    next_ap_ctrl = 3'b000;
                end
            end
            engine_done: begin/////////////////////////////////////////////////////////////////////////////////////
                if (rvalid && rready) begin
                    next_ap_ctrl = 3'b100;
                end else begin
                    next_ap_ctrl = 3'b010;
                end
            end
            default: begin
                next_ap_ctrl = ap_ctrl;
            end
        endcase
    end

/////////////////////////////////////////////////////////////////////////////

/////////////////////////////////////////////////////////////////////////////
//when initial, put 0 to data_ram, and here is used to calculate data_A
    always @(posedge axis_clk, negedge axis_rst_n) begin
        if (!axis_rst_n) begin
            initial_counter <= 12'd0;
        end else begin
            initial_counter <= next_initial_counter;
        end
    end
    
    assign next_initial_counter = (state_engine == engine_initial && initial_counter != 12'd32) ? initial_counter + 12'd1 : 12'd0;
/////////////////////////////////////////////////////////////////////////////

/////////////////////////////////////////////////////////////////////////////
// used to judge it's now to receive addr or tap. addr is 0, tap is 1, it can be used to hold the state of receive tap or addr
    always @(*) begin
        if (awready == 1'b1 && awvalid == 1'b1) begin
            next_flag_addr_or_tap = 1'b1;
        end else if (wready == 1'b1 && wvalid == 1'b1) begin
            next_flag_addr_or_tap = 1'b0;
        end else begin
            next_flag_addr_or_tap = flag_addr_or_tap;
        end
    end
    
    // deal with flag_addr_or_rdata
    always @(*) begin
        if (arvalid == 1'b1 && arready == 1'b1) begin
            next_flag_addr_or_rdata = 1'b1;
        end else if(rvalid == 1'b1 && rready == 1'b1) begin
            next_flag_addr_or_rdata = 1'b0;
        end else begin
            next_flag_addr_or_rdata = flag_addr_or_rdata;
        end
    end
/////////////////////////////////////////////////////////////////////////////

    // deal with data_x_length
    always @(posedge axis_clk, negedge axis_rst_n) begin
        if (!axis_rst_n) begin
            data_x_length <= 32'd0;
            flag_data_length_receive <= 1'b0;
        end else begin
            data_x_length <= next_data_x_length;
            flag_data_length_receive <= next_flag_data_length_receive;
        end
    end
    
    always @(*) begin
        if (state_engine == engine_initial) begin
            next_flag_data_length_receive = 1'b0;
        end
        else if (awaddr == 12'h10 && awvalid == 1'b1 && awready == 1'b1 && flag_addr_or_tap == 1'b0 && state_engine == engine_before_start) begin
            next_flag_data_length_receive = 1'b1;
        end else if (wvalid && wready && flag_addr_or_tap == 1'b1) begin
            next_flag_data_length_receive = 1'b0;
        end else begin
            next_flag_data_length_receive = flag_data_length_receive;
        end
    end
    
    assign next_data_x_length = (wvalid && wready && flag_data_length_receive && state_engine == engine_before_start) ? wdata : data_x_length;
    
    // deal with tap_num
    always @(posedge axis_clk, negedge axis_rst_n) begin
        if (!axis_rst_n) begin
            tap_num <= 32'd0;
            flag_tap_num_receive = 1'b0;
        end else begin
            tap_num <= next_tap_num;
            flag_tap_num_receive = next_flag_tap_num_receive;
        end
    end
    
    always @(*) begin
        if (state_engine == engine_initial) begin
            next_flag_tap_num_receive = 1'b0;
        end
        else if (awaddr == 12'h14 && awvalid == 1'b1 && awready == 1'b1 && flag_addr_or_tap == 1'b0 && state_engine == engine_before_start) begin
            next_flag_tap_num_receive = 1'b1;
        end else if (wvalid && wready && flag_addr_or_tap == 1'b1) begin
            next_flag_tap_num_receive = 1'b0;
        end else begin
            next_flag_tap_num_receive = flag_tap_num_receive;
        end
    end

    assign next_tap_num = (wvalid && wready && flag_tap_num_receive && state_engine == engine_before_start) ? wdata : tap_num;
    

// tap RAM
/////////////////////////////////////////////////////////////////////////////////////// deal with tap_RAM axi-lite
    
    
    always @(posedge axis_clk, negedge axis_rst_n) begin
        if (!axis_rst_n) begin
            flag_addr_or_tap <= 1'b0;
            flag_addr_or_rdata <= 1'b0;

            awready <= 1'b0;
            wready <= 1'b0;
            arready <= 1'b0;
            rvalid <= 1'b0;

            temporary_addr <= 12'd0;

        end else begin
            flag_addr_or_tap <= next_flag_addr_or_tap;
            flag_addr_or_rdata <= next_flag_addr_or_rdata;

            awready <= next_awready;
            wready <= next_wready;
            arready <= next_arready;
            rvalid <= next_rvalid;
            
            temporary_addr <= next_temporary_addr;

        end
    end 

    // deal with ''awready'', ''wready'' , ''arready'', ''rvalid'' 
    //assign next_flag_one_cycle = awvalid || arvalid;
    always @(*) begin
        if (awvalid == 1'b1 && (state_engine == engine_before_start || state_engine == engine_processing || state_engine == engine_waiting_data || state_engine == engine_done) && awready == 1'b0 && flag_addr_or_tap == 1'b0) begin
            next_awready = 1'b1;
        end else begin
            next_awready = 1'b0;
        end
    end
    always @(*) begin
        if (wvalid == 1'b1 && (state_engine == engine_before_start || state_engine == engine_processing || state_engine == engine_waiting_data || state_engine == engine_done) && wready == 1'b0 && flag_addr_or_tap == 1'b1) begin
            next_wready = 1'b1;
        end else begin
            next_wready = 1'b0;
        end
    end
    always @(*) begin
        if (rvalid == 1'b0 && flag_addr_or_rdata == 1'b1) begin
            next_rvalid = 1'b1;
        end else if (rvalid == 1'b1 && rready == 1'b1) begin
            next_rvalid = 1'b0;
        end else begin
            next_rvalid = rvalid;
        end
    end
    //assign next_awready = (awvalid == 1'b1 && state_engine == engine_before_start && awready == 1'b0 && flag_addr_or_tap == 1'b0);
    //assign next_wready = (wvalid == 1'b1 && state_engine == engine_before_start && wready == 1'b0 && flag_addr_or_tap == 1'b1);
    //assign next_rvalid = (arvalid == 1'b0 && rready == 1'b1 && rvalid == 1'b0 && flag_addr_or_rdata == 1'b1);
    assign next_arready = (arready == 1'b0 && arvalid == 1'b1 && flag_addr_or_rdata == 1'b0);
    
    always @(*) begin
        if (temporary_addr == 12'h00) begin
            rdata = ap_ctrl;
        end else begin
            rdata = tap_Do;
        end
    end
    
    always @(*) begin
        if (awvalid && state_engine == engine_before_start) begin
            next_temporary_addr[7:0] = awaddr[7:0];
        end else if (arvalid && state_engine == engine_before_start) begin
            next_temporary_addr[7:0] = araddr[7:0];
        end else begin
            next_temporary_addr = temporary_addr;
        end
    end
    
    // deal with ''tap_Di''
    always @(*) begin
        if (state_engine == engine_initial) begin
            tap_Di =  32'd0;
        end else begin
            tap_Di =  wdata;
        end
    end
    
    // deal with ''tap_A''
    always @(*) begin
        if (state_engine == engine_before_start) begin
            tap_A[6:0] = temporary_addr[6:0];
            tap_A[11:7] = 5'd0;
        end else if (state_engine == engine_processing) begin
            tap_A = tap_do_pointer * 12'd4;
        end else begin
            tap_A = araddr[6:0];
        end
    end
    
    
    // deal with ''tap_EN''
    always @(*) begin
        if (state_engine == engine_before_start) begin
            if (temporary_addr[11:8] == 4'd0 && temporary_addr[7] == 1'b1) begin
                tap_EN = 1'b1;
            end else begin
                tap_EN = 1'b0;
            end
        end else begin
            tap_EN = 1'b1;
        end
    end


    // deal with ''tap_WE''
    always @(*) begin
        if (state_engine == engine_before_start && wready == 1'b1 && temporary_addr[11:8] == 4'd0 && temporary_addr[7] == 1'b1) begin
            tap_WE = 4'b1111;        
        end else begin
            tap_WE = 4'b0000;
        end
    end
    
    
////////////////////////////////////////////////////////////////////////////////////////////////////

// data RAM
//////////////////////////////////////////////////////////////////////////////////////////// deal with data_RAM axi-stream
    
    
    //////////////////////// waiting data
    // deal with ss_tready
    // deal with data_A, data_addr_counter;
    always @(posedge axis_clk or negedge axis_rst_n) begin
        if (!axis_rst_n) begin
            ss_tready <= 1'b0;
            sm_tvalid <= 1'b0;
            data_addr_counter <= 5'd0;
        end else begin
            ss_tready <= next_ss_tready;
            sm_tvalid <= next_sm_tvalid;
            data_addr_counter <= next_data_addr_counter;
        end
    end
    
    assign next_ss_tready = (ss_tvalid == 1'b1 && ss_tready == 1'b0 && state_engine == engine_waiting_data);
    
    // deal with data_EN and data_WE and data_Di
    always @(*) begin
        if (state_engine == engine_initial || state_engine == engine_processing || state_engine == engine_waiting_data) begin
            data_EN = 1'b1;
        end else begin
            data_EN = ss_tvalid;
        end
        
        if (ss_tready == 1'b1 || state_engine == engine_initial) begin
            data_WE = 4'b1111;
        end else begin
            data_WE = 4'b0000;
        end
        
        if (state_engine == engine_initial) begin
            data_Di = 32'd0;
        end  else begin
            data_Di = ss_tdata;
        end
    end
    
    always @(*) begin
        if (state_engine == engine_initial) begin
            next_data_addr_counter = 1'b0;
        end else if (ss_tready == 1'b1 && ss_tvalid == 1'b1) begin
            if (data_addr_counter == 5'd31) begin
                next_data_addr_counter = 1'b0;
            end else begin
                next_data_addr_counter = data_addr_counter + 5'd1;
            end
        end else begin
            next_data_addr_counter = data_addr_counter;
        end
    end
    
    // data A
    always @(*) begin
        if (state_engine == engine_initial) begin
            data_A = 12'h4 * initial_counter;
        end else if (state_engine == engine_processing) begin
            data_A = 12'h4 * data_do_pointer;
        end else if (state_engine == engine_waiting_data) begin
            data_A = 12'h4 * data_addr_counter; 
        end else begin
            data_A = 5'd0;
        end     
    end    


/////////////////////////////////////////////////////////// control data_do and tap_do and sm value
    
    
    always @(posedge axis_clk, negedge axis_rst_n) begin
        if (!axis_rst_n) begin
            data_cursor_count <= 5'd0;
            tap_cursor_count <= 5'd0;
            done_times <= 32'd0;
            cycle_count <= 6'd0;
            data_ram_start_place_count <= 5'd0;
            //counter_every_thirty_five_cycles <= 6'd0;
        end else begin
            data_cursor_count <= next_data_cursor_count;
            tap_cursor_count <= next_tap_cursor_count;
            done_times <= next_done_times;
            cycle_count <= next_cycle_count;
            data_ram_start_place_count <= next_data_ram_start_place_count;
            //counter_every_thirty_five_cycles <= next_counter_every_thirty_five_cycles;
        end
    end
    
    always @(*) begin
        if (state_engine == engine_before_start) begin
            next_done_times = 32'd0;
        end else begin
            if (sm_tvalid && sm_tready) begin
                next_done_times = done_times + 32'd1;
            end else begin
                next_done_times = done_times;
            end
        end
    end
    
    always @(*) begin
        if (state_engine == engine_initial) begin
            next_data_ram_start_place_count = 5'd0;
        end else if (sm_tvalid && sm_tready) begin
            if (data_ram_start_place_count == 5'd31) begin
                next_data_ram_start_place_count = 5'd0;
            end else begin
                next_data_ram_start_place_count = data_ram_start_place_count + 5'd1;
            end
        end else begin
            next_data_ram_start_place_count = data_ram_start_place_count;
        end
    end
    
    always @(*) begin
        if (state_engine != engine_processing && next_state_engine != engine_processing) begin
            next_tap_cursor_count = 5'd0;
        end else if (next_state_engine == engine_processing && state_engine != engine_processing) begin
            next_tap_cursor_count = 5'd1;
        end else begin
            if (tap_num == 32'd32) begin
                if (tap_cursor_count == 5'd31) begin
                    next_tap_cursor_count = tap_cursor_count;
                end else begin
                    next_tap_cursor_count = tap_cursor_count + 5'd1;
                end
            end else begin
                if (tap_cursor_count == tap_num[4:0] - 5'd1) begin
                    next_tap_cursor_count = tap_cursor_count;
                end else begin
                    next_tap_cursor_count = tap_cursor_count + 5'd1;
                end
            end
        end
    end
    
    always @(*) begin
        if ((state_engine != engine_processing && next_state_engine != engine_processing) || state_engine == engine_initial) begin
            next_data_cursor_count = data_ram_start_place_count;
        end else if (next_state_engine == engine_processing && state_engine != engine_processing) begin
            if (data_cursor_count == 5'd0) begin
                next_data_cursor_count = 5'd31;
            end else begin
                next_data_cursor_count = data_cursor_count - 5'd1;
            end
        end else begin
            if (tap_num == 32'd32) begin
                if (tap_cursor_count == 5'd31) begin
                    next_data_cursor_count = data_cursor_count;
                end else begin
                    if (data_cursor_count == 5'd0) begin
                        next_data_cursor_count = 5'd31;
                    end else begin
                        next_data_cursor_count = data_cursor_count - 5'd1;
                    end
                end
            end else begin
                if (tap_cursor_count == tap_num[4:0] - 5'd1) begin
                    next_data_cursor_count = data_cursor_count;
                end else begin
                    if (data_cursor_count == 5'd0) begin
                        next_data_cursor_count = 5'd31;
                    end else begin
                        next_data_cursor_count = data_cursor_count - 5'd1;
                    end
                end
            end
        end
    end
    
    assign data_do_pointer = data_cursor_count; 
    assign tap_do_pointer = tap_cursor_count;
    
    assign sm_tdata = y;
    

    
    always @(*) begin
        if (state_engine != engine_processing) begin
            next_cycle_count = 6'd0;
        end else begin
            next_cycle_count = cycle_count + 6'd1;
        end
    end
    
    always @(*) begin
        if (tap_num == 32'd32) begin
            if (cycle_count == 6'd33) begin
                next_sm_tvalid = 1'b1;
            end else if (sm_tvalid && sm_tready) begin
                next_sm_tvalid = 1'b0;
            end else begin
                next_sm_tvalid = sm_tvalid;
            end
        end else begin
            if (cycle_count == tap_num[5:0] + 6'd1) begin
                next_sm_tvalid = 1'b1;
            end else if (sm_tvalid && sm_tready) begin
                next_sm_tvalid = 1'b0;
            end else begin
                next_sm_tvalid = sm_tvalid;
            end
        end
    end
    
    
/////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////
///////////////////////////////////////////////////////// core caculation
    

    assign m_tmp = h * x;       
    assign h_tmp = tap_Do;
    //assign x_tmp = data_Do;

    always @(posedge axis_clk or negedge axis_rst_n) begin
        if (!axis_rst_n) begin
            h <= 32'd0;
            x <= 32'd0;
            m <= 32'd0;
            y <= 32'd0;
        end else begin
            h <= h_tmp;
            x <= x_tmp;
            m <= m_tmp;
            y <= y_tmp;
        end
    end
    
    always @(*) begin
        if (cycle_count <= tap_num[5:0] + 6'd1 && state_engine == engine_processing) begin
            x_tmp = data_Do;
        end else begin
            x_tmp = 32'd0;
        end
    end
    
    // deal with y_tmp
    always @(*) begin
        if (state_engine == engine_processing) begin
            if (sm_tvalid == 1'd1) begin
                y_tmp = y;
            end else begin
                y_tmp = y + m;
            end
        end else begin
            y_tmp = 0;
        end
    end

    
/////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////
///////////////////////////////////////////////////////// output sm_tlast

    always @(*) begin
        if (done_times == data_x_length) begin
            sm_tlast = 1'b1;
        end else begin
            sm_tlast = 1'b0;
        end
    end

endmodule

