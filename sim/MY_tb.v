`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 08/20/2023 10:38:55 AM
// Design Name: 
// Module Name: fir_tb
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
`define Data_Num_1 400
`define Data_Num_2 300
`define Coef_Num_1 15
`define Coef_Num_2 31

module fir_tb
#(  parameter pADDR_WIDTH = 12,
    parameter pDATA_WIDTH = 32
)();
    wire                        awready;
    wire                        wready;
    reg                         awvalid;
    reg   [(pADDR_WIDTH-1): 0]  awaddr;
    reg                         wvalid;
    reg signed [(pDATA_WIDTH-1) : 0] wdata;
    wire                        arready;
    reg                         rready;
    reg                         arvalid;
    reg         [(pADDR_WIDTH-1): 0] araddr;
    wire                        rvalid;
    wire signed [(pDATA_WIDTH-1): 0] rdata;
    reg                         ss_tvalid;
    reg signed [(pDATA_WIDTH-1) : 0] ss_tdata;
    reg                         ss_tlast;
    wire                        ss_tready;
    reg                         sm_tready;
    wire                        sm_tvalid;
    wire signed [(pDATA_WIDTH-1) : 0] sm_tdata;
    wire                        sm_tlast;
    reg                         axis_clk;
    reg                         axis_rst_n;
    
    wire [2:0] state_engine;
    wire [5:0] cycle_count;

// ram for tap
    wire [3:0]               tap_WE;
    wire                     tap_EN;
    wire [(pDATA_WIDTH-1):0] tap_Di;
    wire [(pADDR_WIDTH-1):0] tap_A;
    wire [(pDATA_WIDTH-1):0] tap_Do;

// ram for data RAM
    wire [3:0]               data_WE;
    wire                     data_EN;
    wire [(pDATA_WIDTH-1):0] data_Di;
    wire [(pADDR_WIDTH-1):0] data_A;
    wire [(pDATA_WIDTH-1):0] data_Do;



    fir fir_DUT(
        .awready(awready),
        .wready(wready),
        .awvalid(awvalid),
        .awaddr(awaddr),
        .wvalid(wvalid),
        .wdata(wdata),
        .arready(arready),
        .rready(rready),
        .arvalid(arvalid),
        .araddr(araddr),
        .rvalid(rvalid),
        .rdata(rdata),
        .ss_tvalid(ss_tvalid),
        .ss_tdata(ss_tdata),
        .ss_tlast(ss_tlast),
        .ss_tready(ss_tready),
        .sm_tready(sm_tready),
        .sm_tvalid(sm_tvalid),
        .sm_tdata(sm_tdata),
        .sm_tlast(sm_tlast),

        // ram for tap
        .tap_WE(tap_WE),
        .tap_EN(tap_EN),
        .tap_Di(tap_Di),
        .tap_A(tap_A),
        .tap_Do(tap_Do),

        // ram for data
        .data_WE(data_WE),
        .data_EN(data_EN),
        .data_Di(data_Di),
        .data_A(data_A),
        .data_Do(data_Do),

        .axis_clk(axis_clk),
        .axis_rst_n(axis_rst_n),
        
        .state_engine(state_engine),
        .cycle_count(cycle_count)
        );
    
    // RAM for tap
    bram32 tap_RAM (
        .CLK(axis_clk),
        .WE(tap_WE),
        .EN(tap_EN),
        .Di(tap_Di),
        .A(tap_A),
        .Do(tap_Do)
    );

    // RAM for data: choose bram11 or bram12
    bram32 data_RAM(
        .CLK(axis_clk),
        .WE(data_WE),
        .EN(data_EN),
        .Di(data_Di),
        .A(data_A),
        .Do(data_Do)
    );
    reg signed [(pDATA_WIDTH-1):0] Din_list_1[0:(`Data_Num_1-1)];
    reg signed [(pDATA_WIDTH-1):0] golden_list_1[0:(`Data_Num_1-1)];
    reg signed [(pDATA_WIDTH-1):0] coef_1[0:(`Coef_Num_1-1)]; // fill in coef 
    
    reg signed [(pDATA_WIDTH-1):0] Din_list_2[0:(`Data_Num_2-1)];
    reg signed [(pDATA_WIDTH-1):0] golden_list_2[0:(`Data_Num_2-1)];
    reg signed [(pDATA_WIDTH-1):0] coef_2[0:(`Coef_Num_2-1)]; // fill in coef 
    
    reg done;
    // `ifdef FSDB
    //     initial begin
    //         $fsdbDumpfile("fir.fsdb");
    //         $fsdbDumpvars("+mda");
    //     end
    // `elsif
        initial begin
            $dumpfile("fir.vcd");
            $dumpvars();
        end
    // `endif

    initial begin
        axis_clk = 0;
        forever begin
            #5 axis_clk = (~axis_clk);
        end
    end

    initial begin
        axis_rst_n = 0;
        @(posedge axis_clk); 
        @(posedge axis_clk);
        axis_rst_n = 1;
    end

    reg [31:0]  data_length_1;
    reg [31:0] coef_length_1;
    reg [31:0]  data_length_2;
    reg [31:0] coef_length_2;
    integer Din1, golden1, coef_in1, input_data1, golden_data1, m1, n1, coef_data1;
    integer Din2, golden2, coef_in2, input_data2, golden_data2, m2, n2, coef_data2;
    initial begin
        data_length_1 = 0;
        coef_length_1 = 0;
        
        data_length_2 = 0;
        coef_length_2 = 0;
        
        Din1 = $fopen("x1.dat","r");
        golden1 = $fopen("y1.dat","r");
	    coef_data1 = $fopen("coef1.dat","r");
	    
	    Din2 = $fopen("x3.dat","r");
        golden2 = $fopen("y3.dat","r");
	    coef_data2 = $fopen("coef3.dat","r");

        for(m1=0;m1< `Data_Num_1 ;m1=m1+1) begin
            input_data1 = $fscanf(Din1,"%d", Din_list_1[m1]);
            golden_data1 = $fscanf(golden1,"%d", golden_list_1[m1]);
            data_length_1 = data_length_1 + 1;
        end
        for(n1=0;n1< `Coef_Num_1 ;n1=n1+1)  begin 
            coef_in1=$fscanf(coef_data1,"%d", coef_1[n1]);
            coef_length_1 = coef_length_1 + 1;
        end
        
        for(m2=0;m2< `Data_Num_2 ;m2=m2+1) begin
            input_data2 = $fscanf(Din2,"%d", Din_list_2[m2]);
            golden_data2 = $fscanf(golden2,"%d", golden_list_2[m2]);
            data_length_2 = data_length_2 + 1;
        end
        for(n2=0;n2< `Coef_Num_2 ;n2=n2+1)  begin 
            coef_in2=$fscanf(coef_data2,"%d", coef_2[n2]);
            coef_length_2 = coef_length_2 + 1;
        end
    end

    integer i, delay_data_input;
    initial begin
        $display("------------Start simulation-----------");
        ss_tvalid = 0;
        done = 0;
        delay_data_input = 0;
        $display("----Start the first data input(AXI-Stream)----");
        for(i=0;i<(data_length_1-1);i=i+1) begin
            ss_tlast = 0; axi_stream_master(Din_list_1[i]);
            for(d=0; d<delay_data_input; d=d+1) begin
                @(posedge axis_clk);
            end
            delay_data_input = {$random} % 10;
        end
	    config_read_check(12'h00, 32'h00, 32'h0000_0002); // check done= 0
        ss_tlast = 1; 
        axi_stream_master(Din_list_1[(`Data_Num_1 - 1)]);
        
        $display("----Start the second data input(AXI-Stream)----");
        for(i=0;i<(data_length_2-1);i=i+1) begin
            ss_tlast = 0; axi_stream_master(Din_list_2[i]);
            for(d=0; d<delay_data_input; d=d+1) begin
                @(posedge axis_clk);
            end
            delay_data_input = {$random} % 10;
        end
	    config_read_check(12'h00, 32'h00, 32'h0000_0002); // check done= 0
        ss_tlast = 1; axi_stream_master(Din_list_2[(`Data_Num_2 - 1)]);
        
        $display("------End the data input(AXI-Stream)------");
    end
    
    reg error_coef;
    integer k,l,d,delay_tap_input, delay_check_input;
    reg error;
    reg status_error;
    initial begin
        wait(axis_rst_n==0);
        wait(axis_rst_n==1);
        error = 0; status_error = 0;
        sm_tready = 0;
        delay_check_input = 0;
        for(l=0;l < data_length_1;l=l+1) begin
            sm(golden_list_1[l],l);
            for(d=0; d<delay_check_input; d=d+1) begin
                @(posedge axis_clk);
            end
            delay_check_input = {$random} % 10;
        end
        config_read_check(12'h00, 32'h02, 32'h0000_0002); // check ap_done = 1 (0x00 [bit 1])
        config_read_check(12'h00, 32'h04, 32'h0000_0004); // check ap_idle = 1 (0x00 [bit 2])
        
        done = 1;
        @(posedge axis_clk);
        done = 0;
                
        sm_tready = 0;
        for(l=0;l < data_length_2;l=l+1) begin
            sm(golden_list_2[l],l);
            for(d=0; d<delay_check_input; d=d+1) begin
                @(posedge axis_clk);
            end
            delay_check_input = {$random} % 10;
        end
        config_read_check(12'h00, 32'h02, 32'h0000_0002); // check ap_done = 1 (0x00 [bit 1])
        config_read_check(12'h00, 32'h04, 32'h0000_0004); // check ap_idle = 1 (0x00 [bit 2])
        
        done = 1;
        @(posedge axis_clk);
        done = 0;
        
        if (error == 0 & error_coef == 0) begin
            $display("---------------------------------------------");
            $display("-----------Congratulations! Pass-------------");
        end
        else begin
            $display("--------Simulation Failed---------");
        end
        $finish;
    end

    //Prevent hang
    // integer timeout = (1000000);
    // initial begin
    //     while(timeout > 0) begin
    //         @(posedge axis_clk);
    //         timeout = timeout - 1;
    //     end
    //     $display($time, "Simualtion Hang ....");
    //     $finish;
    // end

    initial begin
        arvalid=0;
        rready=0;
        error_coef = 0;
        delay_tap_input = 0;
        $display("----Start the coefficient input first time(AXI-lite)----");
        config_write(12'h10, data_length_1);
        config_write(12'h14, coef_length_1);
        for(k=0; k< `Coef_Num_1; k=k+1) begin
            config_write(12'h80+4*k, coef_1[k]);
            for(d=0; d<delay_tap_input; d=d+1) begin    //give random delay
                @(posedge axis_clk);
            end
            delay_tap_input = {$random} % 10;
        end
        awvalid <= 0; wvalid <= 0;
        // read-back and check
        $display(" Check Coefficient ...");
        for(k=0; k < `Coef_Num_1; k=k+1) begin
            config_read_check(12'h80+4*k, coef_1[k], 32'hffffffff);
            for(d=0; d<delay_tap_input; d=d+1) begin
                @(posedge axis_clk);
            end
            delay_tap_input = {$random} % 10;
        end
        arvalid <= 0;
        $display(" Tape programming done ...");
        $display(" Start FIR");
        @(posedge axis_clk) config_write(12'h00, 32'h0000_0001);    // ap_start = 1
        @(posedge axis_clk) config_write(12'h10, 32'd1);    //wrong time writing data_length
        config_read_check(12'h10, 32'd400, 32'hffffffff);   //check data_length
        @(posedge axis_clk) config_write(12'h14, 32'd1);    //wrong time writing tap_num
        config_read_check(12'h14, 32'd15, 32'hffffffff);   //check tap_num
        
        wait(done == 1)
        @(posedge axis_clk);
        
        $display("----Start the coefficient input second time(AXI-lite)----");
        config_write(12'h10, data_length_2);
        config_write(12'h14, coef_length_2);
        for(k=0; k< `Coef_Num_2; k=k+1) begin
            config_write(12'h80+4*k, coef_2[k]);
            for(d=0; d<delay_tap_input; d=d+1) begin
                @(posedge axis_clk);
            end
            delay_tap_input = {$random} % 10;
        end
        awvalid <= 0; wvalid <= 0;
        // read-back and check
        $display(" Check Coefficient ...");
        for(k=0; k < `Coef_Num_2; k=k+1) begin
            config_read_check(12'h80+4*k, coef_2[k], 32'hffffffff);
            for(d=0; d<delay_tap_input; d=d+1) begin
                @(posedge axis_clk);
            end
            delay_tap_input = {$random} % 10;
        end
        arvalid <= 0;
        $display(" Tape programming done ...");
        $display(" Start FIR");
        @(posedge axis_clk) config_write(12'h00, 32'h0000_0001);    // ap_start = 1
        @(posedge axis_clk) config_write(12'h10, 32'd1);    //wrong time writing data_length
        config_read_check(12'h10, 32'd300, 32'hffffffff);   //check data_length
        @(posedge axis_clk) config_write(12'h14, 32'd1);    //wrong time writing tap_num
        config_read_check(12'h14, 32'd31, 32'hffffffff);   //check tap_num
        
        $display("----End the coefficient input(AXI-lite)----");
        //$finish;
    end

    integer s, write_delay;
    task config_write;
        input [11:0]    addr;
        input [31:0]    data;
        begin
            @(posedge axis_clk);
            awvalid <= 1; awaddr <= addr;
            wvalid  <= 1; wdata <= data;
            fork
                begin
                    @(posedge axis_clk);
                    while (!awready) @(posedge axis_clk);
                    awvalid<=0;
                    awaddr<=0;
                end
                begin
                    @(posedge axis_clk);
                    while (!wready) @(posedge axis_clk);
                    wvalid<=0;   
                    wdata<=0;                 
                
                end
            join 
        end
    endtask
    
    integer check_delay;
    task config_read_check;
        input [11:0]        addr;
        input signed [31:0] exp_data;
        input [31:0]        mask;
        begin
            check_delay = {$random} %100;
            for(s=0; s<check_delay; s=s+1) begin
                @(posedge axis_clk); 
            end
            arvalid <= 1; araddr <= addr;
            rready <= 1;
            fork 
                begin
                    @(posedge axis_clk);
                    while (!arready) @(posedge axis_clk);
                    arvalid<=0;
                    araddr<=0;
                end
                begin
                    while (!rvalid) @(posedge axis_clk);
                    if( (rdata & mask) != (exp_data & mask)) begin
                        $display("ERROR: exp = %d, rdata = %d", exp_data, rdata);
                        error_coef <= 1;
                    end else begin
                        $display("OK: exp = %d, rdata = %d", exp_data, rdata);
                    end
                    rready<=0;                

                end
            join 
        end
    endtask


    integer axi_delay;
    task axi_stream_master;
        input  signed [31:0] in1;
        begin
            axi_delay = {$random} %100;
            for(s=0; s<axi_delay; s=s+1) begin
                @(posedge axis_clk); 
            end
            @(posedge axis_clk);
            ss_tvalid <= 1;
            ss_tdata  <= in1;
            @(posedge axis_clk);
            while (!ss_tready) @(posedge axis_clk);
            ss_tvalid <= 0;
            ss_tdata <=0;
        end
    endtask
    
    integer sm_delay;
    task sm;
        input   signed [31:0] in2; // golden data
        input         [31:0] pcnt; // pattern count
        begin
            sm_delay = {$random} %100;
            for(s=0; s<sm_delay; s=s+1) begin
                @(posedge axis_clk); 
            end
            @(posedge axis_clk);
            sm_tready <= 1;
            @(posedge axis_clk);
            while(!sm_tvalid) @(posedge axis_clk);
            sm_tready <=0;
            if (sm_tdata != in2) begin
                $display("[ERROR] [Pattern %d] Golden answer: %d, Your answer: %d", pcnt, in2, sm_tdata);
                error <= 1;
            end
            else begin
                $display("[PASS] [Pattern %d] Golden answer: %d, Your answer: %d", pcnt, in2, sm_tdata);
            end
        end
    endtask
endmodule
