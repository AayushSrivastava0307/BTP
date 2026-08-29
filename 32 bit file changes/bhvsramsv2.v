`define RFDP(dpeth, width)    \
module rfdp``dpeth``x``width (					\
	output 		[width-1:0]				QA,     \
	input 		[$clog2(dpeth)-1:0] 	AA,     \
	input 								CLKA,   \
	input 								CENA,   \
	input 		[$clog2(dpeth)-1:0] 	AB,     \
	input 		[width-1:0] 			DB,     \
	input 								CLKB,   \
	input 								CENB    \
	);                                          \
	bhv_1w1r_sram #(                            \
		.WWORD		(width),                    \
		.WADDR		($clog2(dpeth)),            \
		.DEPTH		(dpeth)                     \
		) u (                                   \
		.clka		(CLKA),                     \
		.aa			(AA),                       \
		.cena		(CENA),                     \
		.qa			(QA),                       \
                                                \
		.clkb		(CLKB),                     \
		.ab			(AB),                       \
		.cenb		(CENB),                     \
		.db			(DB));                      \
endmodule



`define RFDPWP(dpeth, width, wpwidth)    \
module rfdp``dpeth``x``width``_wp``wpwidth (		\
	output 		[width-1:0]				QA,     \
	input 		[$clog2(dpeth)-1:0] 	AA,     \
	input 								CLKA,   \
	input 								CENA,   \
	input 		[$clog2(dpeth)-1:0] 	AB,     \
	input 		[width-1:0] 			DB,     \
	input 								CLKB,   \
	input 		[width/wpwidth-1:0]		WENB,	\
	input 								CENB	\
	);                                          \
	bhv_1w1r_sram_wp #(                         \
		.WWORD		(width),                    \
		.WADDR		($clog2(dpeth)),            \
		.DEPTH		(dpeth),                    \
		.WP			(wpwidth)                   \
		) u (                                   \
		.clka		(CLKA),                     \
		.aa			(AA),                       \
		.cena		(CENA),                     \
		.qa			(QA),                       \
		.clkb		(CLKB),                     \
		.ab			(AB),                       \
		.wenb		(WENB),                     \
		.cenb		(CENB),                     \
		.db			(DB));                      \
endmodule


// 32bit datapath every activation buffer word holds (channels * 32) bits
//   conv1_buf     28x28x6   -> 6*32  = 192, depth 784 -> 1024 rounded to 2 nearest power
//   relu1_buf     14x14x6   -> 6*32  = 192, depth 196 ->  256
//   conv2_buf     10x10x16  -> 16*32 = 512, depth 100 ->  128
//   relu2_buf      5x5x16   -> 16*32 = 512, depth  25 ->   32
//   relu_fc1_buf  120x1     -> 1*32  =  32, depth 120 ->  128
//   relu_fc2_buf   84x1     -> 1*32  =  32, depth  84 ->  128
`RFDP(1024,192)
`RFDP(256,192)
`RFDP(128,512)
`RFDP(32,512)
`RFDP(128,32)
`RFDP(2048,8)
`RFDP(1024,8)

// `RFDPWP(2048,128,32)
// `RFDP(2048,128)
// `RFDP(256,32)
// `RFDP(512,32)
// `RFDP(1024,32)
// `RFDP(256,24)
// `RFDP(64,38)
// `RFDP(32,128)
// `RFDP(32,130)

// `RFDP(262144,8)
// `RFDP(143360,8)


