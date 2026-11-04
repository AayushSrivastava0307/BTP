// Copyright (c) 2024 - NoC Mesh Network for CNN Accelerator
// 3x3 Mesh topology connecting Conv1, Pool1, Conv2, Pool2, FC layers

`include "global.v"

// NoC Mesh Network - 3x3 Topology
// Router locations:
// (0,2) -- (1,2) -- (2,2)
//   |        |        |
// (0,1) -- (1,1) -- (2,1)  
//   |        |        |
// (0,0) -- (1,0) -- (2,0)
//
// PE Mapping:
// (0,0) = Input/Conv1
// (1,0) = Pool1/Conv2
// (2,0) = Pool2/FC1
// (0,1) = FC2
// (1,1) = FC3/Output
// Others = Reserved for future expansion

module noc_mesh_3x3 (
    input clk,
    input rstn,
    
    // Local ports for 9 PEs
    // PE (0,0) - Input/Conv1
    input  [`NOC_FLIT_WIDTH-1:0] pe00_in_flit,
    input                        pe00_in_valid,
    output                       pe00_in_ready,
    output [`NOC_FLIT_WIDTH-1:0] pe00_out_flit,
    output                       pe00_out_valid,
    input                        pe00_out_ready,
    
    // PE (1,0) - Pool1/Conv2
    input  [`NOC_FLIT_WIDTH-1:0] pe10_in_flit,
    input                        pe10_in_valid,
    output                       pe10_in_ready,
    output [`NOC_FLIT_WIDTH-1:0] pe10_out_flit,
    output                       pe10_out_valid,
    input                        pe10_out_ready,
    
    // PE (2,0) - Pool2/FC1
    input  [`NOC_FLIT_WIDTH-1:0] pe20_in_flit,
    input                        pe20_in_valid,
    output                       pe20_in_ready,
    output [`NOC_FLIT_WIDTH-1:0] pe20_out_flit,
    output                       pe20_out_valid,
    input                        pe20_out_ready,
    
    // PE (0,1) - FC2
    input  [`NOC_FLIT_WIDTH-1:0] pe01_in_flit,
    input                        pe01_in_valid,
    output                       pe01_in_ready,
    output [`NOC_FLIT_WIDTH-1:0] pe01_out_flit,
    output                       pe01_out_valid,
    input                        pe01_out_ready,
    
    // PE (1,1) - FC3/Output
    input  [`NOC_FLIT_WIDTH-1:0] pe11_in_flit,
    input                        pe11_in_valid,
    output                       pe11_in_ready,
    output [`NOC_FLIT_WIDTH-1:0] pe11_out_flit,
    output                       pe11_out_valid,
    input                        pe11_out_ready,
    
    // Remaining PEs for expansion
    input  [`NOC_FLIT_WIDTH-1:0] pe21_in_flit,
    input                        pe21_in_valid,
    output                       pe21_in_ready,
    output [`NOC_FLIT_WIDTH-1:0] pe21_out_flit,
    output                       pe21_out_valid,
    input                        pe21_out_ready,
    
    input  [`NOC_FLIT_WIDTH-1:0] pe02_in_flit,
    input                        pe02_in_valid,
    output                       pe02_in_ready,
    output [`NOC_FLIT_WIDTH-1:0] pe02_out_flit,
    output                       pe02_out_valid,
    input                        pe02_out_ready,
    
    input  [`NOC_FLIT_WIDTH-1:0] pe12_in_flit,
    input                        pe12_in_valid,
    output                       pe12_in_ready,
    output [`NOC_FLIT_WIDTH-1:0] pe12_out_flit,
    output                       pe12_out_valid,
    input                        pe12_out_ready,
    
    input  [`NOC_FLIT_WIDTH-1:0] pe22_in_flit,
    input                        pe22_in_valid,
    output                       pe22_in_ready,
    output [`NOC_FLIT_WIDTH-1:0] pe22_out_flit,
    output                       pe22_out_valid,
    input                        pe22_out_ready
);

    // Inter-router connections
    wire [`NOC_FLIT_WIDTH-1:0] r00_e_out, r00_n_out, r01_e_out, r01_s_out, r01_n_out;
    wire [`NOC_FLIT_WIDTH-1:0] r02_e_out, r02_s_out, r10_e_out, r10_w_out, r10_n_out;
    wire [`NOC_FLIT_WIDTH-1:0] r11_e_out, r11_w_out, r11_s_out, r11_n_out;
    wire [`NOC_FLIT_WIDTH-1:0] r12_e_out, r12_w_out, r12_s_out;
    wire [`NOC_FLIT_WIDTH-1:0] r20_w_out, r20_n_out, r21_w_out, r21_s_out, r21_n_out;
    wire [`NOC_FLIT_WIDTH-1:0] r22_w_out, r22_s_out;
    
    wire r00_e_valid, r00_n_valid, r01_e_valid, r01_s_valid, r01_n_valid;
    wire r02_e_valid, r02_s_valid, r10_e_valid, r10_w_valid, r10_n_valid;
    wire r11_e_valid, r11_w_valid, r11_s_valid, r11_n_valid;
    wire r12_e_valid, r12_w_valid, r12_s_valid;
    wire r20_w_valid, r20_n_valid, r21_w_valid, r21_s_valid, r21_n_valid;
    wire r22_w_valid, r22_s_valid;
    
    wire r00_e_ready, r00_n_ready, r01_e_ready, r01_s_ready, r01_n_ready;
    wire r02_e_ready, r02_s_ready, r10_e_ready, r10_w_ready, r10_n_ready;
    wire r11_e_ready, r11_w_ready, r11_s_ready, r11_n_ready;
    wire r12_e_ready, r12_w_ready, r12_s_ready;
    wire r20_w_ready, r20_n_ready, r21_w_ready, r21_s_ready, r21_n_ready;
    wire r22_w_ready, r22_s_ready;
    
    // Router (0,0)
    noc_router #(.ROUTER_X(0), .ROUTER_Y(0)) router_00 (
        .clk(clk), .rstn(rstn),
        .local_in_flit(pe00_in_flit), .local_in_valid(pe00_in_valid), .local_in_ready(pe00_in_ready),
        .local_out_flit(pe00_out_flit), .local_out_valid(pe00_out_valid), .local_out_ready(pe00_out_ready),
        .north_in_flit(r01_s_out), .north_in_valid(r01_s_valid), .north_in_ready(r01_s_ready),
        .north_out_flit(r00_n_out), .north_out_valid(r00_n_valid), .north_out_ready(r00_n_ready),
        .south_in_flit({`NOC_FLIT_WIDTH{1'b0}}), .south_in_valid(1'b0), .south_in_ready(),
        .south_out_flit(), .south_out_valid(), .south_out_ready(1'b1),
        .east_in_flit(r10_w_out), .east_in_valid(r10_w_valid), .east_in_ready(r10_w_ready),
        .east_out_flit(r00_e_out), .east_out_valid(r00_e_valid), .east_out_ready(r00_e_ready),
        .west_in_flit({`NOC_FLIT_WIDTH{1'b0}}), .west_in_valid(1'b0), .west_in_ready(),
        .west_out_flit(), .west_out_valid(), .west_out_ready(1'b1)
    );
    
    // Router (1,0)
    noc_router #(.ROUTER_X(1), .ROUTER_Y(0)) router_10 (
        .clk(clk), .rstn(rstn),
        .local_in_flit(pe10_in_flit), .local_in_valid(pe10_in_valid), .local_in_ready(pe10_in_ready),
        .local_out_flit(pe10_out_flit), .local_out_valid(pe10_out_valid), .local_out_ready(pe10_out_ready),
        .north_in_flit(r11_s_out), .north_in_valid(r11_s_valid), .north_in_ready(r11_s_ready),
        .north_out_flit(r10_n_out), .north_out_valid(r10_n_valid), .north_out_ready(r10_n_ready),
        .south_in_flit({`NOC_FLIT_WIDTH{1'b0}}), .south_in_valid(1'b0), .south_in_ready(),
        .south_out_flit(), .south_out_valid(), .south_out_ready(1'b1),
        .east_in_flit(r20_w_out), .east_in_valid(r20_w_valid), .east_in_ready(r20_w_ready),
        .east_out_flit(r10_e_out), .east_out_valid(r10_e_valid), .east_out_ready(r10_e_ready),
        .west_in_flit(r00_e_out), .west_in_valid(r00_e_valid), .west_in_ready(r00_e_ready),
        .west_out_flit(r10_w_out), .west_out_valid(r10_w_valid), .west_out_ready(r10_w_ready)
    );
    
    // Router (2,0)
    noc_router #(.ROUTER_X(2), .ROUTER_Y(0)) router_20 (
        .clk(clk), .rstn(rstn),
        .local_in_flit(pe20_in_flit), .local_in_valid(pe20_in_valid), .local_in_ready(pe20_in_ready),
        .local_out_flit(pe20_out_flit), .local_out_valid(pe20_out_valid), .local_out_ready(pe20_out_ready),
        .north_in_flit(r21_s_out), .north_in_valid(r21_s_valid), .north_in_ready(r21_s_ready),
        .north_out_flit(r20_n_out), .north_out_valid(r20_n_valid), .north_out_ready(r20_n_ready),
        .south_in_flit({`NOC_FLIT_WIDTH{1'b0}}), .south_in_valid(1'b0), .south_in_ready(),
        .south_out_flit(), .south_out_valid(), .south_out_ready(1'b1),
        .east_in_flit({`NOC_FLIT_WIDTH{1'b0}}), .east_in_valid(1'b0), .east_in_ready(),
        .east_out_flit(), .east_out_valid(), .east_out_ready(1'b1),
        .west_in_flit(r10_e_out), .west_in_valid(r10_e_valid), .west_in_ready(r10_e_ready),
        .west_out_flit(r20_w_out), .west_out_valid(r20_w_valid), .west_out_ready(r20_w_ready)
    );
    
    // Router (0,1)
    noc_router #(.ROUTER_X(0), .ROUTER_Y(1)) router_01 (
        .clk(clk), .rstn(rstn),
        .local_in_flit(pe01_in_flit), .local_in_valid(pe01_in_valid), .local_in_ready(pe01_in_ready),
        .local_out_flit(pe01_out_flit), .local_out_valid(pe01_out_valid), .local_out_ready(pe01_out_ready),
        .north_in_flit(r02_s_out), .north_in_valid(r02_s_valid), .north_in_ready(r02_s_ready),
        .north_out_flit(r01_n_out), .north_out_valid(r01_n_valid), .north_out_ready(r01_n_ready),
        .south_in_flit(r00_n_out), .south_in_valid(r00_n_valid), .south_in_ready(r00_n_ready),
        .south_out_flit(r01_s_out), .south_out_valid(r01_s_valid), .south_out_ready(r01_s_ready),
        .east_in_flit(r11_w_out), .east_in_valid(r11_w_valid), .east_in_ready(r11_w_ready),
        .east_out_flit(r01_e_out), .east_out_valid(r01_e_valid), .east_out_ready(r01_e_ready),
        .west_in_flit({`NOC_FLIT_WIDTH{1'b0}}), .west_in_valid(1'b0), .west_in_ready(),
        .west_out_flit(), .west_out_valid(), .west_out_ready(1'b1)
    );
    
    // Router (1,1) - Central hub
    noc_router #(.ROUTER_X(1), .ROUTER_Y(1)) router_11 (
        .clk(clk), .rstn(rstn),
        .local_in_flit(pe11_in_flit), .local_in_valid(pe11_in_valid), .local_in_ready(pe11_in_ready),
        .local_out_flit(pe11_out_flit), .local_out_valid(pe11_out_valid), .local_out_ready(pe11_out_ready),
        .north_in_flit(r12_s_out), .north_in_valid(r12_s_valid), .north_in_ready(r12_s_ready),
        .north_out_flit(r11_n_out), .north_out_valid(r11_n_valid), .north_out_ready(r11_n_ready),
        .south_in_flit(r10_n_out), .south_in_valid(r10_n_valid), .south_in_ready(r10_n_ready),
        .south_out_flit(r11_s_out), .south_out_valid(r11_s_valid), .south_out_ready(r11_s_ready),
        .east_in_flit(r21_w_out), .east_in_valid(r21_w_valid), .east_in_ready(r21_w_ready),
        .east_out_flit(r11_e_out), .east_out_valid(r11_e_valid), .east_out_ready(r11_e_ready),
        .west_in_flit(r01_e_out), .west_in_valid(r01_e_valid), .west_in_ready(r01_e_ready),
        .west_out_flit(r11_w_out), .west_out_valid(r11_w_valid), .west_out_ready(r11_w_ready)
    );
    
    // Router (2,1)
    noc_router #(.ROUTER_X(2), .ROUTER_Y(1)) router_21 (
        .clk(clk), .rstn(rstn),
        .local_in_flit(pe21_in_flit), .local_in_valid(pe21_in_valid), .local_in_ready(pe21_in_ready),
        .local_out_flit(pe21_out_flit), .local_out_valid(pe21_out_valid), .local_out_ready(pe21_out_ready),
        .north_in_flit(r22_s_out), .north_in_valid(r22_s_valid), .north_in_ready(r22_s_ready),
        .north_out_flit(r21_n_out), .north_out_valid(r21_n_valid), .north_out_ready(r21_n_ready),
        .south_in_flit(r20_n_out), .south_in_valid(r20_n_valid), .south_in_ready(r20_n_ready),
        .south_out_flit(r21_s_out), .south_out_valid(r21_s_valid), .south_out_ready(r21_s_ready),
        .east_in_flit({`NOC_FLIT_WIDTH{1'b0}}), .east_in_valid(1'b0), .east_in_ready(),
        .east_out_flit(), .east_out_valid(), .east_out_ready(1'b1),
        .west_in_flit(r11_e_out), .west_in_valid(r11_e_valid), .west_in_ready(r11_e_ready),
        .west_out_flit(r21_w_out), .west_out_valid(r21_w_valid), .west_out_ready(r21_w_ready)
    );
    
    // Router (0,2)
    noc_router #(.ROUTER_X(0), .ROUTER_Y(2)) router_02 (
        .clk(clk), .rstn(rstn),
        .local_in_flit(pe02_in_flit), .local_in_valid(pe02_in_valid), .local_in_ready(pe02_in_ready),
        .local_out_flit(pe02_out_flit), .local_out_valid(pe02_out_valid), .local_out_ready(pe02_out_ready),
        .north_in_flit({`NOC_FLIT_WIDTH{1'b0}}), .north_in_valid(1'b0), .north_in_ready(),
        .north_out_flit(), .north_out_valid(), .north_out_ready(1'b1),
        .south_in_flit(r01_n_out), .south_in_valid(r01_n_valid), .south_in_ready(r01_n_ready),
        .south_out_flit(r02_s_out), .south_out_valid(r02_s_valid), .south_out_ready(r02_s_ready),
        .east_in_flit(r12_w_out), .east_in_valid(r12_w_valid), .east_in_ready(r12_w_ready),
        .east_out_flit(r02_e_out), .east_out_valid(r02_e_valid), .east_out_ready(r02_e_ready),
        .west_in_flit({`NOC_FLIT_WIDTH{1'b0}}), .west_in_valid(1'b0), .west_in_ready(),
        .west_out_flit(), .west_out_valid(), .west_out_ready(1'b1)
    );
    
    // Router (1,2)
    noc_router #(.ROUTER_X(1), .ROUTER_Y(2)) router_12 (
        .clk(clk), .rstn(rstn),
        .local_in_flit(pe12_in_flit), .local_in_valid(pe12_in_valid), .local_in_ready(pe12_in_ready),
        .local_out_flit(pe12_out_flit), .local_out_valid(pe12_out_valid), .local_out_ready(pe12_out_ready),
        .north_in_flit({`NOC_FLIT_WIDTH{1'b0}}), .north_in_valid(1'b0), .north_in_ready(),
        .north_out_flit(), .north_out_valid(), .north_out_ready(1'b1),
        .south_in_flit(r11_n_out), .south_in_valid(r11_n_valid), .south_in_ready(r11_n_ready),
        .south_out_flit(r12_s_out), .south_out_valid(r12_s_valid), .south_out_ready(r12_s_ready),
        .east_in_flit(r22_w_out), .east_in_valid(r22_w_valid), .east_in_ready(r22_w_ready),
        .east_out_flit(r12_e_out), .east_out_valid(r12_e_valid), .east_out_ready(r12_e_ready),
        .west_in_flit(r02_e_out), .west_in_valid(r02_e_valid), .west_in_ready(r02_e_ready),
        .west_out_flit(r12_w_out), .west_out_valid(r12_w_valid), .west_out_ready(r12_w_ready)
    );
    
    // Router (2,2)
    noc_router #(.ROUTER_X(2), .ROUTER_Y(2)) router_22 (
        .clk(clk), .rstn(rstn),
        .local_in_flit(pe22_in_flit), .local_in_valid(pe22_in_valid), .local_in_ready(pe22_in_ready),
        .local_out_flit(pe22_out_flit), .local_out_valid(pe22_out_valid), .local_out_ready(pe22_out_ready),
        .north_in_flit({`NOC_FLIT_WIDTH{1'b0}}), .north_in_valid(1'b0), .north_in_ready(),
        .north_out_flit(), .north_out_valid(), .north_out_ready(1'b1),
        .south_in_flit(r21_n_out), .south_in_valid(r21_n_valid), .south_in_ready(r21_n_ready),
        .south_out_flit(r22_s_out), .south_out_valid(r22_s_valid), .south_out_ready(r22_s_ready),
        .east_in_flit({`NOC_FLIT_WIDTH{1'b0}}), .east_in_valid(1'b0), .east_in_ready(),
        .east_out_flit(), .east_out_valid(), .east_out_ready(1'b1),
        .west_in_flit(r12_e_out), .west_in_valid(r12_e_valid), .west_in_ready(r12_e_ready),
        .west_out_flit(r22_w_out), .west_out_valid(r22_w_valid), .west_out_ready(r22_w_ready)
    );

endmodule
