# Run make FRAMES=90 for the first 90 images; default is 900, ModelSim only.
# Requires GNU Make, Bash, Python 3, and ModelSim vlib/vlog/vsim on PATH.
# The instrumented simulation testbench is embedded in this Makefile.
SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := simulate
FRAMES ?= 900
SOURCES := lenet_roms.v cnn.v bhv_1w1r_sram.v bhvsrams.v systolic_array.v streaming_pool.v activation_noc.v lenet_noc.v
MS_DEFINE := +define+REPORT_HIERARCHY +define+COMPARISON_NOC

# Escape dollar signs for GNU Make; generated Verilog uses single dollars.
define TESTBENCH
`include "global.v"
// One design per simulation; comparison is performed from completed transcripts.
module comparison_tb;
    reg clk=0;
    always #(`CLK_PERIOD_DIV2) clk=~clk;
    reg rstn=0, go=0;
    reg [15:0] pixels [0:1023];
    reg [15:0] pixel;
    wire [9:0] addr;
    wire cena, ready;
    wire [3:0] digit;
`ifdef COMPARISON_NOC
    localparam MODEL="noc";
    lenet_noc dut(.clk(clk),.rstn(rstn),.go(go),.cena_src(cena),
        .aa_src(addr),.qa_src(pixel),.digit(digit),.ready(ready));
`else
    localparam MODEL="baseline";
    lenet dut(.clk(clk),.rstn(rstn),.go(go),.cena_src(cena),
        .aa_src(addr),.qa_src(pixel),.digit(digit),.ready(ready));
`endif
    integer cycles=0, started, elapsed, total=0;
    integer fd, f, j, value, logit_count=0;
    integer frames=900;
    reg [15:0] logits [0:9];
    always @(posedge clk) begin
        cycles<=cycles+1;
        if(!cena) pixel<=pixels[addr];
        if(rstn && dut.q_fc3_en) begin
            if(logit_count>=10) $$fatal(1,"Extra logits");
            logits[logit_count]=dut.q_fc3;
            logit_count=logit_count+1;
        end
    end

    // Simulation-only instrumentation: observe the actual memory enable edges.
    // Indices: conv1, pool1, conv2, pool2, fc1, fc2.
    reg traffic_active=0;
    longint unsigned reads[0:5], writes[0:5];
    longint unsigned total_reads[0:5], total_writes[0:5];
    longint unsigned row_writes[0:1], total_row_writes[0:1];
    longint unsigned injected[0:5], delivered[0:5];
    longint unsigned total_injected[0:5], total_delivered[0:5];
    wire [5:0] read_events, write_events;
    integer m;
    function automatic integer word_bytes(input integer bank);
        case(bank)
            0,1: word_bytes=12;
            2,3: word_bytes=32;
            default: word_bytes=2;
        endcase
    endfunction
    function automatic string bank_name(input integer bank);
        case(bank)
            0: bank_name="conv1";
            1: bank_name="pool1";
            2: bank_name="conv2";
            3: bank_name="pool2";
            4: bank_name="fc1";
            5: bank_name="fc2";
        endcase
    endfunction
`ifdef COMPARISON_NOC
    assign read_events=dut.read_enable;
    assign write_events=dut.delivered_valid & 6'b111010;
`else
    assign read_events={ !dut.cena_relu_fc2_buf, !dut.cena_relu_fc1_buf,
        !dut.cena_relu2_buf, !dut.cena_conv2_buf,
        !dut.cena_relu1_buf, !dut.cena_conv1_buf };
    assign write_events={ !dut.cenb_relu_fc2_buf, !dut.cenb_relu_fc1_buf,
        !dut.cenb_relu2_buf, !dut.cenb_conv2_buf,
        !dut.cenb_relu1_buf, !dut.cenb_conv1_buf };
`endif
    always @(posedge clk) if(rstn && traffic_active) begin
        if ((^read_events === 1'bx) || (^write_events === 1'bx))
            $$fatal(1,"Unknown SRAM enable");
        for(integer b=0;b<6;b=b+1) begin
            if(read_events[b]) reads[b]=reads[b]+1;
            if(write_events[b]) writes[b]=writes[b]+1;
`ifdef COMPARISON_NOC
            if(dut.net_valid[b] && dut.net_ready[b]) injected[b]=injected[b]+1;
            if(dut.delivered_valid[b]) delivered[b]=delivered[b]+1;
`endif
        end
`ifdef COMPARISON_NOC
        if(dut.fused_pool1.valid && dut.fused_pool1.y%2==0) row_writes[0]=row_writes[0]+1;
        if(dut.fused_pool2.valid && dut.fused_pool2.y%2==0) row_writes[1]=row_writes[1]+1;
`endif
    end
    task automatic report_traffic(input integer frame_id);
        longint unsigned boundary_bytes, all_bytes;
        boundary_bytes=0; all_bytes=0;
        for(integer b=0;b<6;b=b+1) begin
            $$display("SRAM model=%0s frame=%0d bank=%0s reads=%0d writes=%0d word_bytes=%0d read_bytes=%0d write_bytes=%0d",
                MODEL,frame_id,bank_name(b),reads[b],writes[b],word_bytes(b),
                reads[b]*word_bytes(b),writes[b]*word_bytes(b));
            all_bytes=all_bytes+(reads[b]+writes[b])*word_bytes(b);
            if(b==0 || b==2) boundary_bytes=boundary_bytes+(reads[b]+writes[b])*word_bytes(b);
            if(b==1 || b==3) boundary_bytes=boundary_bytes+writes[b]*word_bytes(b);
            total_reads[b]=total_reads[b]+reads[b];
            total_writes[b]=total_writes[b]+writes[b];
`ifdef COMPARISON_NOC
            if(injected[b]!=delivered[b]) $$fatal(1,"Undrained network bank=%0d",b);
            $$display("NETWORK model=%0s frame=%0d bank=%0d injected=%0d delivered=%0d",MODEL,frame_id,b,injected[b],delivered[b]);
            total_injected[b]=total_injected[b]+injected[b];
            total_delivered[b]=total_delivered[b]+delivered[b];
`endif
        end
`ifdef COMPARISON_NOC
        for(integer b=0;b<2;b=b+1) begin
            $$display("LOCAL_ROW model=%0s frame=%0d pool=%0d writes=%0d word_bytes=%0d write_bytes=%0d",
                MODEL,frame_id,b+1,row_writes[b],b==0?12:32,row_writes[b]*(b==0?12:32));
            total_row_writes[b]=total_row_writes[b]+row_writes[b];
        end
`endif
        $$display("SRAM_SCOPE model=%0s frame=%0d boundary_bytes=%0d all_intermediate_bytes=%0d local_row_write_bytes=%0d",
            MODEL,frame_id,boundary_bytes,all_bytes,row_writes[0]*12+row_writes[1]*32);
    endtask
    initial begin
        if ($$value$$plusargs("FRAMES=%d",frames)) begin end
        if(frames<1 || frames>900) $$fatal(1,"Invalid frame count");
        for(m=0;m<6;m=m+1) begin
            total_reads[m]=0; total_writes[m]=0;
            total_injected[m]=0; total_delivered[m]=0;
        end
        total_row_writes[0]=0; total_row_writes[1]=0;
        fd=$$fopen("test_900.yuv","rb");
        if(!fd) $$fatal(1,"Cannot open input");
        $$display("RUN model=%0s frames=%0d first=0",MODEL,frames);
        repeat(10) @(negedge clk);
        rstn=1;
        for(f=0;f<frames;f=f+1) begin
            for(j=0;j<1024;j=j+1) begin
                value=$$fgetc(fd);
                if(value<0) $$fatal(1,"Truncated input frame=%0d pixel=%0d",f,j);
                pixels[j]=value;
            end
            @(negedge clk);
            logit_count=0;
            for(m=0;m<6;m=m+1) begin
                reads[m]=0; writes[m]=0; injected[m]=0; delivered[m]=0;
            end
            row_writes[0]=0; row_writes[1]=0;
            traffic_active=1;
            go=1; started=cycles;
            @(negedge clk); go=0;
            while(!ready) begin
                @(negedge clk);
                if(cycles-started>1000000) $$fatal(1,"Frame %0d watchdog timeout",f);
            end
            elapsed=cycles-started;
            if((^digit === 1'bx) || digit>9) $$fatal(1,"Invalid prediction frame=%0d",f);
            if(logit_count!=10) $$fatal(1,"Missing logits frame=%0d",f);
            for(j=0;j<10;j=j+1) begin
                if(^logits[j] === 1'bx) $$fatal(1,"Unknown logit frame=%0d class=%0d",f,j);
                $$display("LOGIT model=%0s frame=%0d class=%0d value=%04h",MODEL,f,j,logits[j]);
            end
            total=total+elapsed;
            $$display("RESULT model=%0s frame=%0d digit=%0d cycles=%0d",MODEL,f,digit,elapsed);
            // Include completion-edge events and verify a quiet drain interval.
            repeat(4) @(negedge clk);
`ifdef COMPARISON_NOC
            if(dut.activation_network.occupied!=0 || dut.net_valid!=0)
                $$fatal(1,"Network not drained");
`endif
            if(read_events!=0 || write_events!=0) $$fatal(1,"Memory still active after completion");
            traffic_active=0;
            report_traffic(f);
        end
        $$fclose(fd);
        for(m=0;m<6;m=m+1) begin
            $$display("SRAM_TOTAL model=%0s bank=%0s reads=%0d writes=%0d word_bytes=%0d read_bytes=%0d write_bytes=%0d",
                MODEL,bank_name(m),total_reads[m],total_writes[m],word_bytes(m),
                total_reads[m]*word_bytes(m),total_writes[m]*word_bytes(m));
`ifdef COMPARISON_NOC
            $$display("NETWORK_TOTAL model=%0s bank=%0d injected=%0d delivered=%0d",MODEL,m,total_injected[m],total_delivered[m]);
`endif
        end
`ifdef COMPARISON_NOC
        for(m=0;m<2;m=m+1)
            $$display("LOCAL_ROW_TOTAL model=%0s pool=%0d writes=%0d word_bytes=%0d write_bytes=%0d",
                MODEL,m+1,total_row_writes[m],m==0?12:32,total_row_writes[m]*(m==0?12:32));
`endif
        $$display("COMPLETE model=%0s frames=%0d cycles=%0d",MODEL,frames,total);
        $$finish;
    end
endmodule
endef
export TESTBENCH

.PHONY: simulate
simulate:
	@[[ "$(FRAMES)" =~ ^[1-9][0-9]{0,2}$$ ]] && [ "$(FRAMES)" -le 900 ] || { echo 'FRAMES must be an integer from 1 to 900.' >&2; exit 2; }
	rm -f build/measurements.json
	command -v python3 >/dev/null
	command -v vlib >/dev/null
	command -v vlog >/dev/null
	command -v vsim >/dev/null
	mkdir -p build
	printf '%s\n' "$$TESTBENCH" > build/comparison_tb.v
	rm -rf build/work
	vlib build/work
	vlog -sv +incdir+. $(MS_DEFINE) -work build/work $(SOURCES) build/comparison_tb.v > build/compile.log 2>&1
	vsim -c -onfinish stop -lib build/work comparison_tb "+FRAMES=$(FRAMES)" -do 'onerror {quit -code 1}; run -all; quit -f' 2>&1 | tee build/simulation.log
	grep -Eq 'COMPLETE model=noc frames=$(FRAMES) cycles=[0-9]+' build/simulation.log
	! grep -Eq 'FATAL|\*\* Error|\*\* Fatal' build/simulation.log
	python3 compare_designs.py --validate build/simulation.log --model noc --frames $(FRAMES) > build/measurements.json.tmp
	mv build/measurements.json.tmp build/measurements.json
	cat build/measurements.json
