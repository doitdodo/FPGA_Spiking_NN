`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Research Lab of Ultra Low-Power and Intelligent Integrated Circuits, HUST, China
// Engineer: Jiajun Wu
// 
// Create Date: 2020/02/07 11:03:17
// Design Name: CORDIC-SNN, followed with "Unsupervised Learning SNN..." published in 2015, frontiers
// Module Name: neuron
// Project Name: CORDIC_SNN
// Target Devices: Zynq-7020
// Tool Versions: Vivado 2018.3
// Description: 1- All spikes are under 100MHz clock domain synchronously.
//              2- Quantize CORDIC bits with one sign bit and two integer bits.
//              3- In our model, we don't use handshake.
//              4- In our model, we don't use voltage or trace decay.
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module exc_neuron #(
    parameter DW = 16, INT_DW = 8, REFRAC = 5, ENCODE_TIME = 23
)(
    // Clock, reset and enable
    input wire clk,
    input wire rst,
    input wire en,
    
    // Input spking values
    input wire signed [DW + INT_DW - 1 : 0] spiking_value,
    
    // Input inh
    input wire inh,
    
    // Output spikes and spike cnt
    output reg out_spike,
    output reg [31 : 0] spike_times
    );
    
    localparam inh_value = 24'h3c0000;
    localparam threshold = 24'h0d0000;
    localparam reset_v = 24'd0;
    
    reg signed [DW + INT_DW - 1 : 0] potential;
    reg [3 : 0] refractory_cnt;
    always@(posedge clk) begin
        if(rst) begin
            potential <= 0;
            out_spike <= 0;
            spike_times <= 0;
        end
        else if(en) begin
            if(refractory_cnt == 4'd0) begin
                potential <= potential + spiking_value;
                if(inh) begin
                    potential <= potential - inh_value;
                end
                if(potential >= threshold) begin
                    potential <= reset_v;
                    out_spike <= 1'b1;
                    spike_times <= spike_times + 1;
                end
                else out_spike <= 1'b0;
            end
            else begin
                potential <= potential;         
                out_spike <= 1'b0;
                spike_times <= spike_times;   
            end
        end
    end
   
   reg refractory_en;
    always@(posedge clk) begin
        if(rst) begin 
            refractory_cnt <= 0;
            refractory_en <= 0;
        end
        else if(en) begin
            if(refractory_cnt == REFRAC * ENCODE_TIME) begin
                refractory_cnt <= 0;
                refractory_en <= 1'b0;
            end
            if(potential >= threshold) begin
                refractory_en <= 1'b1;
            end
            else if (refractory_en) begin
                refractory_cnt <= refractory_cnt + 1;
            end
        end
    end
    
endmodule

module input_neuron #(
    parameter ENCODE_TIME = 23, T_WINDOW = 250
)(
    // Clock, reset and enable
    input wire clk,
    input wire rst,
    input wire en,
    
    // Original spikes and result bit
    input wire [T_WINDOW - 1 : 0] origin_spike,
    output wire spike_infor
);

    wire [ENCODE_TIME * (T_WINDOW - 1) + T_WINDOW : 0] dest_spike;
    reg [ENCODE_TIME * (T_WINDOW - 1) + T_WINDOW : 0] spikes;
    generate 
        genvar i;
        for(i = 0; i < T_WINDOW; i = i + 1) begin
            assign dest_spike[(ENCODE_TIME + 1) * (i + 1) - 1 : (ENCODE_TIME + 1) * i + 1] = 0;
            assign dest_spike[(ENCODE_TIME + 1) * i] = origin_spike[i];
        end
    endgenerate
    
    reg [32 : 0] cnt;
    always@(posedge clk) begin
        if(rst) cnt <= 0;
        else if(en) begin
            if(cnt < T_WINDOW * (ENCODE_TIME + 1)) cnt <= cnt + 1;
            else cnt <= cnt;
        end
    end
    
    wire shift_en;
    assign shift_en = (cnt <= T_WINDOW * (ENCODE_TIME + 1));
    always@(posedge clk) begin
        if(rst) begin 
            spikes <= dest_spike;
        end
        else if(en & shift_en) begin
            spikes <= spikes >> 1;
        end
    end
    
    assign spike_infor = spikes[0];

endmodule
