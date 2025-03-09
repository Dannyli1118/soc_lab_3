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
    input   wire                     axis_rst_n,
    
    output [4:0] shift_count,
    output [1:0] state_engine,
    output [11:0] aw_ctrl_addr,
    output [11:0] ar_ctrl_addr,
    output [31:0] tap_num,
    output [31:0] data_length,
    output [31:0] data_addr_used_table,
    output [5:0] data_num,
    output [31:0] x,
    output [31:0] h,
    output [31:0] y,
    output [4:0] data_addr_counter,
    output [1:0] state_data_ram
    //output [4:0] shift_count
    //output [4:0] shift_reg_data [31:0]
);


// Main FSM
///////////////////////////////////////////////////////////////////////////////////// deal with ap_ctrl
    reg [1:0] state_engine;
    reg [1:0] next_state_engine;
    
    reg start_cal, next_start_cal;
    
    reg [11:0] aw_ctrl_addr; // used in main FSM
    reg [11:0] next_aw_ctrl_addr; // judged in tap RAM
    reg [11:0] ar_ctrl_addr; // used in main FSM
    reg [11:0] next_ar_ctrl_addr; // judged in data RAM
    

    parameter engine_before_start = 2'd1;
    parameter engine_not_idle = 2'd2;
    parameter engine_done = 2'd3;

    always @(posedge axis_clk or negedge axis_rst_n) begin
        if (!axis_rst_n) begin
            aw_ctrl_addr <= 12'hfff;
            start_cal <= 1'b0;
            ar_ctrl_addr <= 12'hfff;
        end else begin
            aw_ctrl_addr <= next_aw_ctrl_addr;
            ar_ctrl_addr <= next_ar_ctrl_addr;
            start_cal <= next_start_cal;
        end        
    end
    
    // FSM
    always @(posedge axis_clk or negedge axis_rst_n) begin
        if (!axis_rst_n) begin
            state_engine <= engine_before_start; 
        end else begin
            state_engine <= next_state_engine;
        end
    end

    always @(*) begin
        case (state_engine)
            engine_before_start: begin
                if (start_cal == 1'b1) begin ///////////////// ap_start not yet be judged
                    next_state_engine = engine_not_idle;
                end else begin
                    next_state_engine = state_engine;
                end
            end
            engine_not_idle: begin
                next_state_engine = engine_not_idle;
            end
            engine_done: begin

            end
            default: begin
                next_state_engine = state_engine;
            end
        endcase
    end
    
    //start_cal
    always @(*) begin////////////////////////////////////////////////////////////////////////wrong
        if (data_A == 12'd0 * data_num && tap_A == 12'h038) begin
            next_start_cal = 1'b1;
        end else begin
            next_start_cal = 1'b0;
        end
    end
/////////////////////////////////////////////////////////////////////////////


    // deal with data_length
    reg [31:0] data_length;
    reg [31:0] next_data_length;
    wire[5:0] data_num;
    reg [5:0] next_data_num;
    
    always @(posedge axis_clk, negedge axis_rst_n) begin
        if (!axis_rst_n) begin
            data_length <= 32'd0;
        end else begin
            data_length <= next_data_length;
        end
    end
    
    always @(*) begin
        if (state_engine == engine_before_start) begin
            if (araddr < 12'h14 && araddr >= 12'h10) begin
                next_data_length = rdata;
            end else if ((awaddr < 12'h14 && awaddr >= 12'h10)) begin
                next_data_length = wdata;
            end else begin
                next_data_length = data_length;
            end
        end else if (state_engine == engine_not_idle) begin
            if (data_length > 32'd32) begin
                next_data_length = data_length - 32'd32;
            end else begin
                next_data_length = 32'd0;
            end
        end else begin
            next_data_length = data_length;   
        end
    end
    
    //deal with data_num
    
    assign data_num = 6'd32;//////////////////////////////////////////////////////////////////////////////////////////////////////////////
    
    
    // deal with tap_num
    reg [31:0] tap_num;
    reg [31:0] next_tap_num;
    
    always @(posedge axis_clk, negedge axis_rst_n) begin
        if (!axis_rst_n) begin
            tap_num <= 32'd0;
        end else begin
            tap_num <= next_tap_num;
        end
    end
    
    always @(*) begin
        if (state_engine == engine_before_start) begin
            if (araddr <= 12'h14 && araddr < 12'h18) begin
                next_tap_num = rdata;
            end else if ((awaddr < 12'h18 && awaddr >= 12'h14)) begin
                next_tap_num = wdata;
            end else begin
                next_tap_num = tap_num;
            end
        end else begin
            next_tap_num = tap_num;   
        end
    end


// tap RAM
/////////////////////////////////////////////////////////////////////////////////////// deal with tap_RAM axi-lite
    reg [4:0] tap_addr_counter;
    reg [4:0] next_tap_addr_counter;
    reg next_awready;
    reg next_wready;
    
    
    // control write process
    reg flag_addr_or_tap; // to judge now is waiting tap or addr, 0 is waiting addr, 1 is waiting tag
    reg next_flag_addr_or_tap;
    reg flag_tap_finish;
    
    // deal with flag_tap_finish to know whether tap is all written 
    always @(*) begin
        if (awaddr[6:2] == tap_num) begin
            flag_tap_finish = 1'b1;
        end else begin
            flag_tap_finish = 1'b0;
        end
    end
    
    always @(posedge axis_clk, negedge axis_rst_n) begin
        if (!axis_rst_n) begin
            flag_addr_or_tap <= 1'b0;
        end else begin
            flag_addr_or_tap <= next_flag_addr_or_tap;
        end
    end
    
    always @(*) begin
        if (awready == 1'b1 && awvalid == 1'b1) begin
            next_flag_addr_or_tap = 1'b1;
        end else if (wready == 1'b1 && wvalid == 1'b1) begin
            next_flag_addr_or_tap = 1'b0;
        end else begin
            next_flag_addr_or_tap = flag_addr_or_tap;
        end
    end
    
    // deal with aw_ctrl_addr used in main module
    always @(*) begin
        if (awvalid == 1'b1 && awready == 1'b0) begin
            next_aw_ctrl_addr = awaddr;
        end else begin
            next_aw_ctrl_addr = aw_ctrl_addr;
        end
    end

    
    // deal with addr counter-sequential
    always @(posedge axis_clk, negedge axis_rst_n) begin
        if (!axis_rst_n) begin
            tap_addr_counter <= 5'd0;
        end else begin
            tap_addr_counter <= next_tap_addr_counter; 
        end
    end 
    
    
    // deal with addr counter-combination
    always @(*) begin
        if (state_engine == engine_not_idle) begin
            if (tap_addr_counter == tap_num) begin
                next_tap_addr_counter = 5'd0;
            end else begin
                next_tap_addr_counter = tap_addr_counter + 5'd1;
            end  
        end else begin
            next_tap_addr_counter = tap_addr_counter;
        end
    end
    

    // deal with ''awready''
    always @(posedge axis_clk, negedge axis_rst_n) begin
        if (!axis_rst_n) begin
            awready <= 1'b0;
        end else begin
            awready <= next_awready;
        end
    end 
    
    always @(*) begin
        if (awvalid == 1'b1 && state_engine == engine_before_start && awready == 1'b0 && flag_addr_or_tap == 1'b0) begin
            next_awready = 1'b1;
        end else begin
            next_awready = 1'b0;
        end
    end
    
    
    // deal with ''wready''
    always @(posedge axis_clk, negedge axis_rst_n) begin
        if (!axis_rst_n) begin
            wready <= 1'b0;
        end else begin
            wready <= next_wready;
        end
    end 
    
    always @(*) begin
        if (wvalid == 1'b1 && state_engine == engine_before_start && wready == 1'b0 && flag_addr_or_tap == 1'b1) begin
            next_wready = 1'b1;
        end else begin
            next_wready = 1'b0;
        end
    end
    
    
    // deal with ''tap_Di''
    always @(*) begin
        tap_Di =  wdata;
    end
    
    
    // deal with ''tap_A''
    always @(*) begin
        if (state_engine == engine_before_start) begin
            if (tap_WE == 4'd15) begin
                tap_A = awaddr[6:0];
            end else begin
                tap_A = araddr[6:0];
            end 
        end else begin
            tap_A = tap_do_pointer * 12'd4;
        end
    end
    
    
    // deal with ''tap_EN''
    always @(*) begin
        if (state_engine == engine_before_start) begin
            if ((awaddr[11:8] == 4'd0 && awaddr[7] == 1'b1) || (araddr[11:8] == 0 && araddr[7] == 0)) begin
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
        if (wvalid == 1'b1 && awvalid == 1'b1 && awaddr[11:8] == 4'd0 && awaddr[7] == 1'b1) begin
            tap_WE = 4'b1111;        
        end else begin
            tap_WE = 4'b0000;
        end
    end
    
    ///////////////////
    ///////////////////
    ///////////////////deal with axi-lite reading part
    reg [4:0] read_tap_addr;
    reg [4:0] next_read_tap_addr;
    reg flag_addr_rdata;//0 is waiting data
    reg next_flag_addr_rdata;
    
    //deal with ''arready'', read_tap_addr;
    reg next_arready;
    always @(posedge axis_clk, negedge axis_rst_n) begin
        if (!axis_rst_n) begin
            arready <= 1'b0;
            read_tap_addr <= 5'd0;
        end else begin
            arready <= next_arready;
            read_tap_addr <= next_read_tap_addr;
        end
    end
    
    always @(*) begin
         if (arready == 1'b0 && arvalid == 1'b1 && flag_addr_rdata == 1'b0) begin
            if (araddr >= 12'h80 && araddr < 12'hff) begin
                next_arready = 1'b1;
                next_read_tap_addr = araddr[6:2];
            end else begin
                next_arready = 1'b0;
                next_read_tap_addr = read_tap_addr;
            end
         end else begin
            next_arready = 1'b0;
            next_read_tap_addr = read_tap_addr;
         end
    end
    
    //deal with next_ar_ctrl_addr used in main FSM
    always @(*) begin
        if (arready == 1'b0 && arvalid == 1'b1) begin
            next_ar_ctrl_addr = araddr;
        end else begin
            next_ar_ctrl_addr = ar_ctrl_addr;
        end
    end
    
    reg next_rvalid;

    always @(posedge axis_clk, negedge axis_rst_n) begin
        if (!axis_rst_n) begin
            rvalid <= 1'b0;
            flag_addr_rdata <= 1'b0;
        end else begin
            rvalid <= next_rvalid;
            flag_addr_rdata <= next_flag_addr_rdata;
        end
    end
    
    always @(*) begin
        if (rready == 1'b1 && rvalid == 1'b0 && flag_addr_rdata == 1'b1) begin
            next_rvalid = 1'b1;
        end else begin
            next_rvalid = 1'b0;
        end
    end
    
    always @(*) begin
        if (rready == 1'b1) begin
            rdata = tap_Do;
        end else begin
            rdata = 32'd0;
        end
    end
    
    // deal with
    always @(*) begin
        if (arready == 1'b0 && arvalid == 1'b1 && flag_addr_rdata == 1'b0) begin
            next_flag_addr_rdata = 1'b1;
        end else if(rready == 1'b1 && rvalid == 1'b0 && flag_addr_rdata == 1'b1) begin
            next_flag_addr_rdata = 1'b0;
        end else begin
            next_flag_addr_rdata = flag_addr_rdata;
        end
    end
    
    
////////////////////////////////////////////////////////////////////////////////////////////////////

// data RAM
//////////////////////////////////////////////////////////////////////////////////////////// deal with data_RAM axi-stream
    reg next_ss_tready;
    
    reg [4:0] data_addr_counter;
    reg [4:0] next_data_addr_counter;
    reg [11:0] next_data_A;
    
    reg [31:0] data_addr_used_table;
    reg [31:0] next_data_addr_used_table;

    reg [1:0] state_data_ram;
    reg [1:0] next_state_data_ram;
    
    parameter waiting_ap_start = 2'd0;
    parameter waiting_data = 2'd1;
    parameter waiting_cal = 2'd2;
    parameter rest = 2'd3;
    
    // data_ram_FSM
    always @(posedge axis_clk or negedge axis_rst_n) begin
        if (!axis_rst_n) begin
            state_data_ram <= waiting_ap_start;
        end else begin
            state_data_ram <= next_state_data_ram;    
        end
    end    
    
    always @(*) begin
        case(state_data_ram)
            waiting_ap_start: begin
                if (state_engine == engine_not_idle) begin
                    next_state_data_ram = waiting_data;
                end else begin
                    next_state_data_ram = state_data_ram;
                end
            end
            waiting_data: begin
                if (ss_tready == 1'b1 && ss_tvalid == 1'b1) begin
                    next_state_data_ram = waiting_cal;
                end else begin
                    next_state_data_ram = waiting_data;
                end
            end
            waiting_cal: begin
                if (sm_tvalid == 1'b1 && sm_tready) begin
                    next_state_data_ram = waiting_data;
                end else begin
                    next_state_data_ram = waiting_cal;
                end 
            end
            default: begin
                next_state_data_ram = state_data_ram;
            end             
        endcase
    end
    
    //////////////////////// waiting data
    // deal with ss_tready
    always @(posedge axis_clk or negedge axis_rst_n) begin
        if (!axis_rst_n) begin
            ss_tready <= 1'b0;
            data_addr_used_table <= 32'd0;
        end else begin
            ss_tready <= next_ss_tready;
            data_addr_used_table <= next_data_addr_used_table;
        end
    end

    always @(*) begin
        if (ss_tvalid == 1'b1 && ss_tready == 1'b0 && state_data_ram == waiting_data) begin
            next_ss_tready = 1'b1;
        end else begin
            next_ss_tready = 1'b0;
        end
    end
    
    // deal with data_EN and data_WE and data_Di
    always @(*) begin
        if (state_engine == engine_not_idle) begin
            data_EN = 1'b1;
        end else begin
            data_EN = ss_tvalid;
        end
        
        if (ss_tready == 1'b0) begin
            data_WE = 4'b0000;
        end else begin
            data_WE = 4'b1111;
        end
        
        data_Di = ss_tdata;
    end

    // deal with data_A, data_addr_counter;
    always @(posedge axis_clk, negedge axis_rst_n) begin
        if (!axis_rst_n) begin
            data_addr_counter <= 5'd0;
        end else begin
            data_addr_counter <= next_data_addr_counter;
        end
    end
    
    always @(*) begin
        if (ss_tready == 1'b1 && ss_tvalid == 1'b1) begin
            if (data_addr_counter == data_num - 1'd1) begin
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
        if (state_data_ram == waiting_ap_start) begin
            data_A = 12'd0;
        end else if (state_data_ram == waiting_data) begin
            data_A = 12'h4 * data_addr_counter; 
        end else begin
            data_A = 12'h4 * data_do_pointer;
        end     
    end    


/////////////////////////////////////////////////////////// control data_do and tap_do
    wire [7:0] output_num;
    
    wire [4:0] data_do_pointer; // to count which data_A should be read
    wire [4:0] tap_do_pointer; // to count which tap_A should be read
    
    reg [4:0] counter_reset_time; // the times counter has been reset, to know how many cycles core porecess should calculate
    reg [4:0] next_counter_reset_time;
    
    reg [5:0] shift_reg_data [31:0];
    reg [5:0] shift_in_data; // data that will maybe be shifted in
    reg [5:0] next_shift_in_data;
    wire [5:0] shift_size;
    integer i;
     
    wire flag_temporary_fininsh_cal;
    reg [5:0] counter_every_thirty_five_cycles;
    reg [5:0] next_counter_every_thirty_five_cycles;
     
    reg [4:0] shift_count; // when count to shift_size => return to 0    
    reg [4:0] next_shift_count;
    
    reg [31:0] done_times;
    wire [31:0] next_done_times;
    
    assign output_num = tap_num + data_num - 8'd2;
    assign shift_size = (tap_num < data_num) ? tap_num : data_num;
    
    // deal with shift register
    
    always @(posedge axis_clk, negedge axis_rst_n) begin
        if (next_state_data_ram == waiting_cal && state_data_ram == waiting_data) begin
            for (i = 31; i > 0; i = i - 1) begin
                shift_reg_data[i] <= shift_reg_data[i-1];
            end
            shift_reg_data[0] <= data_addr_counter;
        end else begin
            for (i = 0; i < 11; i = i + 1) begin
                shift_reg_data[i] <= shift_reg_data[i];
            end
        end
    end
    
    
    // deal with shift_count, done_times
    always @(posedge axis_clk, negedge axis_rst_n) begin
        if (!axis_rst_n) begin
            shift_count <= 5'd0;
            done_times <= 32'd0;
            counter_every_thirty_five_cycles <= 6'd0;
        end else begin
            shift_count <= next_shift_count;
            done_times <= next_done_times;
            counter_every_thirty_five_cycles <= next_counter_every_thirty_five_cycles;
        end
    end
    assign next_done_times = (shift_count == 5'd30 && next_shift_count == 5'd31) ? done_times + 32'd1 : done_times;
    
    
    //deal with next_shift_count
    always @(*) begin 
        if (state_data_ram == waiting_ap_start) begin
            next_shift_count = 5'd0;
        end else if (state_data_ram == waiting_data && next_state_data_ram == waiting_data) begin
            next_shift_count = 5'd0;
        end else if (next_state_data_ram == waiting_cal && state_data_ram == waiting_data) begin
            next_shift_count = 5'd1;
        end else if (state_data_ram == waiting_cal) begin
            if (shift_count == 5'd31) begin
                next_shift_count = 5'd31;
            end else begin
                next_shift_count = shift_count + 5'd1;
            end
        end else begin
            next_shift_count = shift_count;
        end
    end
    
    always @(*) begin
        
    end
        
    // assign data_do_pointer value
    assign data_do_pointer = shift_reg_data[shift_count];
    
    //ssign tap_do_pointer = shift_reg_data[shift_count];
    assign tap_do_pointer = shift_count;
    
    
    // deal with counter 35 cycles
    always @(*) begin
        if (state_data_ram == waiting_ap_start || state_data_ram == waiting_data) begin
            next_counter_every_thirty_five_cycles = 6'd0;
        end else begin
            if (counter_every_thirty_five_cycles == 6'd35) begin
                next_counter_every_thirty_five_cycles = 6'd0;
            end else begin
                next_counter_every_thirty_five_cycles = counter_every_thirty_five_cycles + 6'd1;
            end
        end
    end
    
    assign flag_temporary_fininsh_cal = (counter_every_thirty_five_cycles == 6'd35) ? 1 : 0;
/////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////
///////////////////////////////////////////////////////// core caculation
    wire [(pDATA_WIDTH-1):0] m_tmp;
    reg [(pDATA_WIDTH-1):0] h_tmp;
    reg [(pDATA_WIDTH-1):0] x_tmp;
    reg [(pDATA_WIDTH-1):0] y_tmp;

    reg [(pDATA_WIDTH-1):0] pre_x_tmp;

    reg [(pDATA_WIDTH-1):0] m;
    reg [(pDATA_WIDTH-1):0] y;
    reg [(pDATA_WIDTH-1):0] h;
    reg [(pDATA_WIDTH-1):0] x;

    assign m_tmp = h * x;       
    //assign h_tmp = tap_Do;

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
    
    
    // deal with x_tmp // wrong
    always @(*) begin
        //if (shift_count <= counter_reset_time + 1'b1) begin
        if (data_Do[0] == 1'b1 || data_Do[0] == 1'b0) begin
            x_tmp = data_Do;
        end  else begin
            x_tmp = 32'd0;
        end
    end
    
    // deal with y_tmp
    always @(*) begin
        if (state_data_ram == waiting_cal) begin
            y_tmp = y + m;
        end else begin
            y_tmp = 0;
        end
    end
    
    // wrong
    always @(*) begin ////////////////////////////////////////////////////////////////// wrong
        if (tap_Do[0] == 1'b1 || tap_Do[0] == 1'b0) begin
            h_tmp = tap_Do;
        end else begin
            h_tmp = 32'd0;
        end
    end
    
    // use sm_valid to transport data;
    always @(*) begin
        sm_tvalid = flag_temporary_fininsh_cal;
    end
    
    assign sm_tdata = y;
        
/////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////


endmodule


