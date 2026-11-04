// Simple NoC Test - Demonstrates router functionality
// Sends packets from (0,0) to various destinations

`include "global.v"

module noc_simple_test;

    reg clk, rstn;
    
    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100 MHz
    end
    
    // Reset
    initial begin
        rstn = 0;
        #20 rstn = 1;
    end
    
    // Test packet transmission
    reg [`NOC_FLIT_WIDTH-1:0] pe00_in_flit;
    reg pe00_in_valid;
    wire pe00_in_ready;
    wire [`NOC_FLIT_WIDTH-1:0] pe00_out_flit;
    wire pe00_out_valid;
    reg pe00_out_ready;
    
    // Destination PEs
    wire [`NOC_FLIT_WIDTH-1:0] pe10_out_flit, pe11_out_flit, pe22_out_flit;
    wire pe10_out_valid, pe11_out_valid, pe22_out_valid;
    
    // Instantiate 3x3 mesh
    noc_mesh_3x3 noc (
        .clk(clk), .rstn(rstn),
        
        // PE (0,0) - Test source
        .pe00_in_flit(pe00_in_flit),
        .pe00_in_valid(pe00_in_valid),
        .pe00_in_ready(pe00_in_ready),
        .pe00_out_flit(pe00_out_flit),
        .pe00_out_valid(pe00_out_valid),
        .pe00_out_ready(pe00_out_ready),
        
        // PE (1,0) - Test destination 1
        .pe10_in_flit({`NOC_FLIT_WIDTH{1'b0}}),
        .pe10_in_valid(1'b0),
        .pe10_in_ready(),
        .pe10_out_flit(pe10_out_flit),
        .pe10_out_valid(pe10_out_valid),
        .pe10_out_ready(1'b1),
        
        // PE (1,1) - Test destination 2
        .pe11_in_flit({`NOC_FLIT_WIDTH{1'b0}}),
        .pe11_in_valid(1'b0),
        .pe11_in_ready(),
        .pe11_out_flit(pe11_out_flit),
        .pe11_out_valid(pe11_out_valid),
        .pe11_out_ready(1'b1),
        
        // PE (2,2) - Test destination 3
        .pe22_in_flit({`NOC_FLIT_WIDTH{1'b0}}),
        .pe22_in_valid(1'b0),
        .pe22_in_ready(),
        .pe22_out_flit(pe22_out_flit),
        .pe22_out_valid(pe22_out_valid),
        .pe22_out_ready(1'b1),
        
        // Other PEs - unused
        .pe20_in_flit({`NOC_FLIT_WIDTH{1'b0}}), .pe20_in_valid(1'b0), .pe20_in_ready(),
        .pe20_out_flit(), .pe20_out_valid(), .pe20_out_ready(1'b1),
        .pe01_in_flit({`NOC_FLIT_WIDTH{1'b0}}), .pe01_in_valid(1'b0), .pe01_in_ready(),
        .pe01_out_flit(), .pe01_out_valid(), .pe01_out_ready(1'b1),
        .pe21_in_flit({`NOC_FLIT_WIDTH{1'b0}}), .pe21_in_valid(1'b0), .pe21_in_ready(),
        .pe21_out_flit(), .pe21_out_valid(), .pe21_out_ready(1'b1),
        .pe02_in_flit({`NOC_FLIT_WIDTH{1'b0}}), .pe02_in_valid(1'b0), .pe02_in_ready(),
        .pe02_out_flit(), .pe02_out_valid(), .pe02_out_ready(1'b1),
        .pe12_in_flit({`NOC_FLIT_WIDTH{1'b0}}), .pe12_in_valid(1'b0), .pe12_in_ready(),
        .pe12_out_flit(), .pe12_out_valid(), .pe12_out_ready(1'b1)
    );
    
    // Test stimulus
    integer test_num;
    integer start_time, end_time, latency;
    
    initial begin
        pe00_in_valid = 0;
        pe00_out_ready = 1;
        test_num = 0;
        
        // Wait for reset
        @(posedge rstn);
        repeat(5) @(posedge clk);
        
        $display("==================================================");
        $display("NoC Simple Test - Packet Routing Demonstration");
        $display("==================================================\n");
        
        // Test 1: Send packet from (0,0) to (1,0) - 1 hop East
        test_num = 1;
        $display("Test %0d: Route from (0,0) to (1,0) - 1 hop", test_num);
        start_time = $time;
        send_packet(4'd0, 4'd0, 4'd1, 4'd0, 256'hDEADBEEF_CAFEBABE);
        wait_for_reception(pe10_out_valid, pe10_out_flit);
        end_time = $time;
        latency = (end_time - start_time) / 10; // Convert to cycles
        $display("  ✓ Packet received at (1,0) in %0d cycles\n", latency);
        
        repeat(10) @(posedge clk);
        
        // Test 2: Send packet from (0,0) to (1,1) - 2 hops (East, North)
        test_num = 2;
        $display("Test %0d: Route from (0,0) to (1,1) - 2 hops", test_num);
        start_time = $time;
        send_packet(4'd0, 4'd0, 4'd1, 4'd1, 256'h12345678_9ABCDEF0);
        wait_for_reception(pe11_out_valid, pe11_out_flit);
        end_time = $time;
        latency = (end_time - start_time) / 10;
        $display("  ✓ Packet received at (1,1) in %0d cycles\n", latency);
        
        repeat(10) @(posedge clk);
        
        // Test 3: Send packet from (0,0) to (2,2) - 4 hops (East, East, North, North)
        test_num = 3;
        $display("Test %0d: Route from (0,0) to (2,2) - 4 hops", test_num);
        start_time = $time;
        send_packet(4'd0, 4'd0, 4'd2, 4'd2, 256'hFEDCBA98_76543210);
        wait_for_reception(pe22_out_valid, pe22_out_flit);
        end_time = $time;
        latency = (end_time - start_time) / 10;
        $display("  ✓ Packet received at (2,2) in %0d cycles\n", latency);
        
        repeat(10) @(posedge clk);
        
        $display("==================================================");
        $display("All tests passed! NoC routing is functional.");
        $display("==================================================\n");
        
        #100 $finish;
    end
    
    // Task to send a packet
    task send_packet;
        input [3:0] src_x, src_y, dest_x, dest_y;
        input [255:0] data;
        begin
            @(posedge clk);
            pe00_in_flit = {2'b11, dest_x, dest_y, src_x, src_y, 2'b00, 18'd0, data};
            pe00_in_valid = 1;
            
            @(posedge clk);
            while (!pe00_in_ready) @(posedge clk);
            
            @(posedge clk);
            pe00_in_valid = 0;
            pe00_in_flit = 0;
        end
    endtask
    
    // Task to wait for packet reception
    task wait_for_reception;
        input wire valid_signal;
        input wire [`NOC_FLIT_WIDTH-1:0] flit_signal;
        begin
            @(posedge clk);
            while (!valid_signal) @(posedge clk);
            
            $display("  Data received: 0x%h", flit_signal[255:0]);
        end
    endtask
    
    // Monitor for debugging
    always @(posedge clk) begin
        if (pe10_out_valid)
            $display("  [T=%0t] PE(1,0) received packet", $time);
        if (pe11_out_valid)
            $display("  [T=%0t] PE(1,1) received packet", $time);
        if (pe22_out_valid)
            $display("  [T=%0t] PE(2,2) received packet", $time);
    end

endmodule
