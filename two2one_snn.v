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
//              10- This module includes a 2-1 SNN(simplest).
// 
// Dependencies: Based on synapses, neurons.
// 
// Revision:
// Revision 0.01 - File Created
//          0.1  - Synthesis failed because of limited LUTs. We will try to find a LUT-redundent board for snn.
// Additional Comments: This file is just a test file, which doesn't include true SNN for application.
// 
//////////////////////////////////////////////////////////////////////////////////


module two2one_snn(
    input clk,
    input rst,
    input en
    );
    
    wire output_spikes;
    wire [23 : 0] synapses_results1;
    wire [23 : 0] synapses_results2;
    wire [23 : 0] after_sum;
    
    reg weights_en;
    always@(posedge clk) begin
        if(rst) weights_en <= 1'b0;
        else if (en) weights_en <= en;
    end
    wire en_for_initweights;
    assign en_for_initweights = weights_en ^ en;
    
    synapse syn1 (
        .clk(clk), .rst(rst), .en(en),
        .weights_w(16'sd2000),.write_enable(en_for_initweights),.pre_spiking(1'b1), //input_spikes[j]
        .spking_value(synapses_results1),.update_en(output_spikes),
        .learning_rate(16'h0148)
    );
    
    synapse syn2 (
        .clk(clk), .rst(rst), .en(en),
        .weights_w(16'sd2000),.write_enable(en_for_initweights),.pre_spiking(1'b1), //input_spikes[j]
        .spking_value(synapses_results2),.update_en(output_spikes),
        .learning_rate(16'h0148)
    );
    
    assign after_sum = synapses_results1 + synapses_results2;
    exc_neuron exc (
        clk,rst,en,after_sum,1'b0,output_spikes
    );    
    
endmodule
