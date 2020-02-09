`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Research Lab of Ultra Low-Power and Intelligent Integrated Circuits, HUST, China
// Engineer: Jiajun Wu
// 
// Create Date: 2020/02/08 18:54:08
// Design Name: CORDIC-SNN, followed with "Unsupervised Learning SNN..." published in 2015, frontiers
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
//              9- DW: fractional part bits; INT_DW: integer part bits.
//              10- Default architecture: 8-2 SNN.
// 
// Dependencies: Based on synapses, neurons.
// 
// Revision:
// Revision 0.01 - File Created
//          0.1  - Synthesis failed because of limited LUTs. We will try to find a LUT-redundent board for snn.
// Additional Comments: This file is just a test file, which doesn't include true SNN for application.
// 
//////////////////////////////////////////////////////////////////////////////////


module simplified_snn #(
    parameter DW = 16, INPUTNUM = 8, EXCNUM = 2, INT_DW = 8
)(
    // Clock, reset and enable
    input wire clk,
    input wire rst,
    input wire en
    );
    
    wire signed [DW + INT_DW - 1 : 0] synapses_results [INPUTNUM - 1 : 0][EXCNUM - 1 : 0];
    wire signed [DW + INT_DW - 1 : 0] after_sum [EXCNUM - 1 : 0];
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
    
    generate
        genvar h;
        for(h = 0; h < EXCNUM; h = h + 1) begin
            assign after_sum[h] = 
            synapses_results[0][h]+
            synapses_results[1][h]+
            synapses_results[2][h]+
            synapses_results[3][h]+
            synapses_results[4][h]+
            synapses_results[5][h]+
            synapses_results[6][h]+
            synapses_results[7][h]+
            synapses_results[8][h]+
            synapses_results[9][h];
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
