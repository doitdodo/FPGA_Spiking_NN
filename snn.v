`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Research Lab of Ultra Low-Power and Intelligent Integrated Circuits, HUST, China
// Engineer: Jiajun Wu
// 
// Create Date: 2020/02/08 18:54:08
// Design Name: CORDIC-SNN, followed with "Unsupervised learning of digital recognition using STDP" published in 2015, frontiers
// Module Name: snn
// Project Name: CORDIC_SNN
// Target Devices: Zynq-7020
// Tool Versions: Vivado 2018.3
// Description: 1- All spikes are under 100MHz clock domain synchronously.
//              2- Quantize CORDIC bits with one sign bit and two integer bits.
//              3- We only use pre-synapse traces and update the weights at post-synaptic neuron spiking.
//              4- Default values: beta(weight dependence param)- 0.2; wmax- 1.0.
//              5- Handshake: update_en and update_finish. Update_en port is emited by post-synaptic neuron, after that, synapse 
//              begins to compute and updates the weights. Then, synapse emits update_finish to inform the post-synaptic neuron to
//              invalidate the update_en signal.
//              6- We do not use handshake anymore.
//              7- For application, we use axistream protocol to initialize weights, spikes and return spikes information of output.
//              8- The parameter "ENCODE_TIME" is used for inserting 0 in original sequences.
//              9- ADDER_FIRST and ADDER_SECOND are parameters which indicate large scale adder's optimization.
//              10- DW: fractional part bits; INT_DW: integer part bits.
//              11- Default architecture: 784-100 SNN.
// 
// Dependencies: Based on synapses, neurons.
// 
// Revision:
// Revision 0.01 - File Created
//          0.1  - Synthesis failed because of limited LUTs. We will try to find a LUT-redundent board for snn.
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module snn #(
    parameter DW = 16, T_WINDOW = 250, INPUTNUM = 784, 
    ENCODE_TIME = 23, EXCNUM = 100, INT_DW = 8, ADDER_FIRST = 49, ADDER_SECOND = 3    
)(

/************************* These ports are usd for evaluation **************************/

    // Clock, reset and enable
    input wire clk,
    input wire rst,
    input wire en
    
/************************* These ports are usd for evaluation **************************/

/************************* These ports are usd for communicating with PS **************************/
/************************* For application, we use these ports **************************/
    // Handshake ports for weights initialization
//    input wire axis_tvalid_w,
//    output wire axis_tready_w,
//    input wire axis_tlast_w,
//    input wire [DW - 1 : 0] axis_tdata_w,

    // Handshake ports for spikes initialization
//    input wire axis_tvalid_s,
//    output wire axis_tready_s,
//    input wire axis_tlast_s,
//    input wire [T_WINDOW - 1 : 0] axis_tdata_s,
        
    // Callback to PS with each exc_neuron's spike counts
//    input wire axis_tvalid_c,
//    output wire axis_tready_c,
//    input wire axis_tlast_c,
//    input wire [31 : 0] axis_tdata_c       
    
/************************* These ports are usd for communicating with PS **************************/

    );
    
    wire signed [DW + INT_DW - 1 : 0] synapses_results [INPUTNUM - 1 : 0][EXCNUM - 1 : 0];
    wire signed [DW + INT_DW - 1 : 0] after_sum [EXCNUM - 1 : 0];
    wire input_spikes [INPUTNUM - 1 : 0];
    wire output_spikes [EXCNUM - 1 : 0];
    wire spike_inh;
    
    generate
        genvar a, b;
        for(a = 0; a < EXCNUM; a = a + 1) begin
            assign spike_inh = spike_inh | output_spikes[a];
        end
    endgenerate
    
    reg weights_en;
    always@(posedge clk) begin
        if(rst) weights_en <= 1'b0;
        else if (en) weights_en <= en;
    end
    wire en_for_initweights;
    assign en_for_initweights = weights_en ^ en;
    
//    generate
//        genvar i;
//        for(i = 0; i < INPUTNUM; i = i + 1) begin
//            input_neuron (clk, rst, en, 
//                          250'h044444444444444444444444444444444444444444444444444444444444444,input_spikes[i]);
//        end
//    endgenerate
    
    generate
        genvar j, k;
        for(j = 0; j < INPUTNUM; j = j + 1) begin
            for(k = 0; k < EXCNUM; k = k + 1) begin
                synapse syn (
                    .clk(clk), .rst(rst), .en(en),
                    .weights_w(16'sd2000),.pre_spiking(1'b1), //input_spikes[j]
                    .spking_value(synapses_results[j][k]),.update_en(output_spikes[k]),
                    .learning_rate(16'h0148)
                );
            end
        end
    endgenerate
    
    // 784-1 adder
    reg [31 : 0] adder_fst_stage [EXCNUM - 1 : 0][ADDER_FIRST - 1 : 0];
    reg [47 : 0] adder_snd_stage [EXCNUM - 1 : 0][ADDER_SECOND - 1 : 0];
    reg [50 : 0] adder_trd_stage [EXCNUM - 1 : 0];
    reg [3 : 0] cnt_for_adder;
    always@(posedge clk) begin
        if(rst) cnt_for_adder <= 0;
        else if(en) begin
            if(cnt_for_adder == 4'd2) cnt_for_adder <= 4'd0;
            else cnt_for_adder <= cnt_for_adder + 1;
        end
    end
    generate
        genvar c,d;
        for(c = 0; c < EXCNUM; c = c + 1) begin
            for(d = 0; d < ADDER_FIRST; d = d + 1) begin
                always@(posedge clk) begin
                    if(en) adder_fst_stage[c][d] <= 
                    synapses_results[d*16][c]+
                    synapses_results[d*16+1][c]+
                    synapses_results[d*16+2][c]+
                    synapses_results[d*16+3][c]+
                    synapses_results[d*16+4][c]+
                    synapses_results[d*16+5][c]+
                    synapses_results[d*16+6][c]+
                    synapses_results[d*16+7][c]+
                    synapses_results[d*16+8][c]+
                    synapses_results[d*16+9][c]+
                    synapses_results[d*16+10][c]+
                    synapses_results[d*16+11][c]+
                    synapses_results[d*16+12][c]+
                    synapses_results[d*16+13][c]+
                    synapses_results[d*16+14][c]+
                    synapses_results[d*16+15][c];
                end
            end
        end
    endgenerate
    
    generate
        genvar e,f;
        for(e = 0; e < EXCNUM; e = e + 1) begin
            for(f = 0; f < ADDER_SECOND; f = f + 1) begin
                always@(posedge clk) begin
                    if(en) adder_snd_stage[e][f] <= 
                    adder_fst_stage[e][f*16]+
                    adder_fst_stage[e][f*16+1]+
                    adder_fst_stage[e][f*16+2]+
                    adder_fst_stage[e][f*16+3]+
                    adder_fst_stage[e][f*16+4]+
                    adder_fst_stage[e][f*16+5]+
                    adder_fst_stage[e][f*16+6]+
                    adder_fst_stage[e][f*16+7]+
                    adder_fst_stage[e][f*16+8]+
                    adder_fst_stage[e][f*16+9]+
                    adder_fst_stage[e][f*16+10]+
                    adder_fst_stage[e][f*16+11]+
                    adder_fst_stage[e][f*16+12]+
                    adder_fst_stage[e][f*16+13]+
                    adder_fst_stage[e][f*16+14]+
                    adder_fst_stage[e][f*16+15];
                end
            end
        end
    endgenerate
    
    generate
        genvar g;
        for(g = 0; g < EXCNUM; g = g + 1) begin
            always@(posedge clk) begin
                adder_trd_stage[g] <= adder_snd_stage[g][0] + adder_snd_stage[g][1] + adder_snd_stage[g][2];
            end
        end
    endgenerate
    
    generate
        genvar h;
        for(h = 0; h < EXCNUM; h = h + 1) begin
            assign after_sum[h] = adder_trd_stage[h][50 : 50-(DW + INT_DW - 1)];
        end
    endgenerate
    
    generate 
        genvar m;
        for(m = 0; m < EXCNUM; m = m + 1) begin
            exc_neuron exc (
                clk,rst,en,after_sum[m],spike_inh,output_spikes[m]
            );
        end
    endgenerate
    
endmodule
