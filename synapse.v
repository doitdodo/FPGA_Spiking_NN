`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Research Lab of Ultra Low-Power and Intelligent Integrated Circuits, HUST, China
// Engineer: Jiajun Wu
// 
// Create Date: 2020/02/05 13:24:01
// Design Name: CORDIC-SNN, followed with "Unsupervised Learning SNN..." published in 2015, frontiers
// Module Name: synapse
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
// 
// Dependencies: 1- Xilinx multiplier IP
//               2- CORDIC (16-bits) source code, which is coded by my co-workers.
//               3- Multiplier IP details: mult_betaw is used for computing beta * w in this learning rule.
//                                         mult_gen_0 is used for computing trace * [diff(beta * w)]
//                                         mult_gen_1 is used for computing learning_rate * results
// 
// Revision:
// Revision 0.01 - File Created
//          0.1  - Firstly code
//          0.2  - Behavior simulation passed
//          0.3  - Cancel handshake
// Additional Comments: Maybe we should find some ways to save LUT because of the huge weights.
//                      In the future, we will also try to find some ways to simplify the parameters changing.
// 
//////////////////////////////////////////////////////////////////////////////////


module synapse #(
    // DW: CORDIC width, T_DW: trace width
    parameter DW = 16, T_DW = 4
)(
    // Clock, reset and enable
    input wire clk,
    input wire rst,
    input wire en,
    
    // Write or read weights in synapses
    input wire [DW - 1 : 0] weights_w,
    input wire write_enable,
    output reg [DW - 1 : 0] weights_r,
    input wire read_enable,
    
    // Input spiking and output value
    input wire pre_spiking,
    output reg signed [DW - 1 : 0] spking_value,
    output reg post_en,
    
    // Update weights control. Update_lock is used for locking the pre neurons to avoid write & read weights simultaneously
    input wire update_en,
    input wire signed [DW - 1 : 0] learning_rate
    );
    
    // FSM
    localparam IDLE = 3'b000;
    localparam FORWARD = 3'b001;
    localparam COMPUTE = 3'b010;
    localparam UPDATE = 3'b011;
    reg [2 : 0] fsm_state;
    reg [2 : 0] fsm_next_state;
    reg compute_finish;
    
    always@(posedge clk) begin
        if(rst) begin
            fsm_state <= IDLE;
        end
        else if(en) fsm_state <= fsm_next_state;
    end
    
    always@(*) begin
        case(fsm_state)
            IDLE: begin
                if(en) begin
                    fsm_next_state = FORWARD;
                end
                else fsm_next_state = fsm_state;
            end
            FORWARD: begin
                if(en) begin
                    if(update_en) fsm_next_state = COMPUTE;
                    else fsm_next_state = fsm_state;
                end
                else fsm_next_state = fsm_state;
            end
            COMPUTE: begin
                if(en) begin
                   if(compute_finish) fsm_next_state = UPDATE;
                   else fsm_next_state = fsm_state;
                end
                else fsm_next_state = fsm_state;                
            end
            UPDATE: begin
                if(en) fsm_next_state = FORWARD;
                else fsm_next_state = fsm_state;                
            end
            default: fsm_next_state = IDLE;
        endcase
    end

    // Trace, including pre-synapses and post-synapses
    // In 2015's paper, we only use pre-synapses trace
    reg [T_DW - 1 : 0] pre_trace;
    reg [T_DW - 1 : 0] post_trace;
    always@(posedge clk) begin
        if (rst) begin
            pre_trace <= 0;
        end
        else begin
            if (en) begin
                if(pre_spiking) pre_trace <= pre_trace + 1;
            end
        end
    end
    
    // Synapse weight and update weight control
    reg signed [DW - 1 : 0] weights;
        
    // Forward
    always@(posedge clk) begin
        if(rst) begin 
            spking_value <= 0;
            post_en <= 0;
        end
        else if(en) begin
            if(pre_spiking)begin
                spking_value <= weights;
                post_en <= 1'b1;
            end
            else post_en <= 1'b0;
        end
    end
    
    // Beta * w and beta * (wmax - w)
    wire signed [DW - 1 : 0] beta = 16'he667; // -beta, signed, default beta = 0.2
    wire signed [DW : 0] betaw;
    mult_betaw beta_w (clk,beta,weights,1'b1,betaw);
    
    wire signed [DW - 1 : 0] wmax = 16'h7fff; // wmax, default value is 1.0
    wire signed [DW - 1 : 0] wmax_w;
    assign wmax_w = wmax - weights;
    wire signed [DW : 0] betawmaxw;
    mult_betaw beta_wmax_w (clk,beta,wmax_w,1'b1,betawmaxw);
    
    // CORDIC
    wire cordic_opa; // 1- CORDIC stops, 0- CORDIC oparates
    wire signed [DW + 1 : 0] expbetaw;
    wire signed [DW + 1 : 0] expbetawmax_w;
    wire cordic_betaw_finish;
    wire cordic_betawmax_w_finish;
    assign cordic_opa = ~(fsm_state == COMPUTE);
    reg cordic_temp;
    reg cordic_init;
    always@(posedge clk) begin
        if(rst) cordic_temp <= 1'b0;
        else cordic_temp <= cordic_opa;
    end
    always@(posedge clk) begin
        if(rst) cordic_init <= 1'b0;
        else if (~cordic_opa) cordic_init <= cordic_opa ^ cordic_temp;
    end
    cordic cordic_betaw (
    .clk(clk),.rst(cordic_opa),.init(cordic_init),.x_i(18'd39567),.y_i(0),.theta_i(betaw),.exp_o(expbetaw),.done(cordic_betaw_finish)
    );
    
    cordic cordic_betawmax_w (
    .clk(clk),.rst(cordic_opa),.init(cordic_init),.x_i(18'd39567),.y_i(0),.theta_i(betawmaxw),.exp_o(expbetawmax_w),.done(cordic_betawmax_w_finish)
    );
    
    // Final result for updating
    reg delay_for_mul1, delay_for_mul2; // Delay for 3 cycles
    always@(posedge clk) begin
        if(rst) delay_for_mul1 <= 0;
        else if(en) delay_for_mul1 <= cordic_betaw_finish & cordic_betawmax_w_finish;
    end
       
    always@(posedge clk) begin
        if(rst) delay_for_mul2 <= 0;
        else if(en) delay_for_mul2 <= delay_for_mul1;
    end       
    
    always@(posedge clk) begin
        if(rst) compute_finish <= 0;
        else if(en) compute_finish <= delay_for_mul2;
    end 
    
    reg [T_DW - 1 : 0] pre_trace_temp;
    always@(posedge clk) begin
        if(rst) begin
            pre_trace_temp <= 0;
        end
        else if(en) begin
            if(update_en) pre_trace_temp <= pre_trace;
        end
    end
//    wire signed [DW - 1 : 0] trace_w;
//    wire signed [DW - 1 : 0] trace_wmaxw;
    wire signed [DW + 1 : 0] diff;
//    mult_gen_0 trace_beta_w (clk,{1'b0,pre_trace,15'h0000},{2'b00,expbetaw},cordic_betaw_finish,trace_w);
//    mult_gen_0 trace_beta_wmaxw (clk,{1'b0,pre_trace,15'h0000},{2'b00,expbetawmax_w},cordic_betawmax_w_finish,trace_wmaxw);
    assign diff = expbetaw - expbetawmax_w;
    wire signed [DW + T_DW + 2 : 0] diff_trace;
//    assign diff_trace = {1'b0,pre_trace}*diff;
    mult_gen_0 difftrace (clk, {1'b0,pre_trace_temp}, diff, 1'b1, diff_trace);
    
    wire signed [DW - 1 : 0] derta_w;
    mult_gen_1 dertaw (clk,diff_trace[DW + T_DW + 1 : T_DW + 2],learning_rate,derta_w);
    
    // Update weights or initialize weights
    always@(posedge clk) begin
        if(rst) begin
            weights <= 0;
        end
        else if(en) begin
            if(fsm_state == UPDATE) begin 
                weights <= weights + derta_w;
            end
            else if(read_enable) weights_r <= weights;
        end
        else if(write_enable) weights <= weights_w;
    end
    
endmodule
