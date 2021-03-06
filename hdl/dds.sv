`timescale 1ns / 1ns

module dds
/*********************************************************************************************/
#(
    parameter PHASE_DW = 16,          // phase data width
    parameter OUT_DW = 16,            // output data width
    parameter USE_TAYLOR = 0,         // use taylor approximation
    parameter LUT_DW = 10,            // width of sine lut if taylor approximation is used
    parameter SIN_COS = 0,            // set to 1 if cos output in addition to sin output is desired
    parameter DECIMAL_SHIFT = 5
)
/*********************************************************************************************/
(
    input                                   clk,
    input                                   reset_n,
    input   wire  unsigned [PHASE_DW-1:0]   s_axis_phase_tdata,
    input                                   s_axis_phase_tvalid,
    output  wire    signed [OUT_DW-1:0]     m_axis_out_sin_tdata,
    output                                  m_axis_out_sin_tvalid,
    output  wire    signed [OUT_DW-1:0]     m_axis_out_cos_tdata,
    output                                  m_axis_out_cos_tvalid,
    output  wire    signed [2*OUT_DW-1:0]   m_axis_out_tdata,
    output                                  m_axis_out_tvalid
);
/*********************************************************************************************/

localparam EFFECTIVE_LUT_WIDTH = USE_TAYLOR ? LUT_DW : PHASE_DW - 2;
localparam PHASE_ERROR_WIDTH = USE_TAYLOR ? PHASE_DW - (LUT_DW - 2) : 1;

reg signed [OUT_DW - 1 : 0] lut [0 : 2**EFFECTIVE_LUT_WIDTH - 1];
// `include "sine_lut_10_16.vh"  // I dont know how to insert variable numbers into the include string
initial	begin
    string filename = $sformatf("../../hdl/sine_lut_%0d_%0d.hex",EFFECTIVE_LUT_WIDTH,OUT_DW);
    $readmemh(filename, lut);
    if (USE_TAYLOR) begin
        if (LUT_DW > PHASE_DW - 2) begin
            $display("LUT_DW > PHASE_DW - 2 does not make sense!");
        end
    end
end

// input buffer, stage 1
reg unsigned [PHASE_DW - 1 : 0] phase_buf;
reg in_valid_buf;
always_ff @(posedge clk) begin
    phase_buf <= !reset_n ? 0 : (s_axis_phase_tvalid ? s_axis_phase_tdata : phase_buf);
    in_valid_buf <= !reset_n ? 0 : s_axis_phase_tvalid;
end

// calculate lut index, stage 2
reg in_valid_buf2;
reg unsigned [EFFECTIVE_LUT_WIDTH-1:0] sin_lut_index, cos_lut_index;
reg unsigned [1:0] sin_quadrant_index;
always_ff @(posedge clk) begin
    in_valid_buf2 <= !reset_n ? 0 : in_valid_buf;
    sin_quadrant_index <= !reset_n ? 0 : phase_buf[PHASE_DW-1:PHASE_DW-2];
    // sin
    if (phase_buf[PHASE_DW - 2]) // if in 2nd or 4th quadrant
        sin_lut_index <= !reset_n ? 0 : ~phase_buf[PHASE_DW - 3 -: EFFECTIVE_LUT_WIDTH] + 1;
    else
        sin_lut_index <= !reset_n ? 0 : phase_buf[PHASE_DW - 3 -: EFFECTIVE_LUT_WIDTH];
    // cos
    if (SIN_COS || USE_TAYLOR) begin
        if (!phase_buf[PHASE_DW - 2]) // if in 1st or 3rd quadrant
            cos_lut_index <= !reset_n ? 0 : ~phase_buf[PHASE_DW - 3 -: EFFECTIVE_LUT_WIDTH] + 1;
        else
            cos_lut_index <= !reset_n ? 0 : phase_buf[PHASE_DW - 3 -: EFFECTIVE_LUT_WIDTH];
    end
end

// lut reading, stage 3
reg in_valid_buf3;
reg signed [OUT_DW-1:0] sin_lut_data, cos_lut_data;
reg unsigned [1:0] sin_quadrant_index2;
always_ff @(posedge clk) begin
    in_valid_buf3 <= !reset_n ? 0 : in_valid_buf2;
    // sin
    sin_quadrant_index2 <= !reset_n ? 0 : sin_quadrant_index;
    if (sin_quadrant_index[0] && sin_lut_index == 0)
        sin_lut_data <= !reset_n ? 0 : 2**(OUT_DW-1) - 1;
    else
        sin_lut_data <= !reset_n ? 0 : lut[sin_lut_index];
    // cos
    if (SIN_COS || USE_TAYLOR) begin
        if (!sin_quadrant_index[0] && cos_lut_index == 0)
            cos_lut_data <= !reset_n ? 0 : 2**(OUT_DW-1) - 1;
        else
            cos_lut_data <= !reset_n ? 0 :  lut[cos_lut_index];
    end
    // debug stuff
    if(in_valid_buf2) begin
        // $display("lut[%d] = %d",sin_lut_index, sin_lut_data);
        // $display("lut[%d] = %d",cos_lut_index, cos_lut_data);
    end
end

// output buffer, stage 4
reg signed [OUT_DW - 1 : 0] out_sin_buf;
reg signed [OUT_DW - 1 : 0] out_cos_buf;
reg out_valid_buf;
always_ff @(posedge clk) begin
    if (sin_quadrant_index2[1]) // if in 3rd or 4th quadrant
        out_sin_buf <= !reset_n ? 0 : -sin_lut_data;
    else
        out_sin_buf <= !reset_n ? 0 : sin_lut_data;
    if (SIN_COS || USE_TAYLOR) begin
        if (sin_quadrant_index2 == 2'b10 || sin_quadrant_index2 == 2'b01) // if in 2nd or 3rd quadrant
            out_cos_buf <= !reset_n ? 0 : -cos_lut_data;
        else
            out_cos_buf <= !reset_n ? 0 : cos_lut_data;
    end
    out_valid_buf <= !reset_n ? 0 : in_valid_buf3;    
end

// taylor phase offset multiplication, stage 2-4
wire signed [PHASE_ERROR_WIDTH:0] phase_error_signed;
localparam      EXTENDED_WIDTH    = OUT_DW + PHASE_ERROR_WIDTH;
localparam real PHASE_FACTOR_REAL = (2 * 3.14159) / 2**LUT_DW * 2**DECIMAL_SHIFT;
typedef bit unsigned [DECIMAL_SHIFT - 1 : 0] t_PHASE_FACTOR;
localparam t_PHASE_FACTOR PHASE_FACTOR = t_PHASE_FACTOR'(PHASE_FACTOR_REAL);
localparam SIN_LUT_DELAY = 3;
reg unsigned [PHASE_ERROR_WIDTH-1:0]                    phase_error_buf [0:SIN_LUT_DELAY];
reg signed   [EXTENDED_WIDTH + DECIMAL_SHIFT - 1 : 0]   phase_error_multiplied;
assign phase_error_signed = {1'b0, phase_error_buf[SIN_LUT_DELAY]};
if (USE_TAYLOR) begin
    always_ff@(posedge clk) begin
        foreach(phase_error_buf[k]) begin
            if(k == 0)
                phase_error_buf[0] <= !reset_n ? 0 : phase_buf[PHASE_ERROR_WIDTH - 1: 0];
            else
                phase_error_buf[k] <= !reset_n ? 0 : phase_error_buf[k-1];
        end
        phase_error_multiplied <= !reset_n ? 0 : phase_error_signed * PHASE_FACTOR;
    end
end

// taylor correction, stage 5
reg signed [OUT_DW - 1 : 0] out_sin_buf2;
reg signed [OUT_DW - 1 : 0] out_cos_buf2;
reg out_valid_buf2;
wire signed [EXTENDED_WIDTH - 1 : 0] sin_extended, cos_extended;
wire signed [EXTENDED_WIDTH - 1 : 0] sin_corrected, cos_corrected;
assign sin_extended = {out_sin_buf, {(PHASE_ERROR_WIDTH){1'b0}}};
assign sin_corrected = sin_extended + out_cos_buf * phase_error_multiplied[EXTENDED_WIDTH + DECIMAL_SHIFT - 1 -: EXTENDED_WIDTH];
assign cos_extended = {out_cos_buf, {(PHASE_ERROR_WIDTH){1'b0}}};
assign cos_corrected = cos_extended - out_sin_buf * phase_error_multiplied[EXTENDED_WIDTH + DECIMAL_SHIFT - 1 -: EXTENDED_WIDTH];
if (USE_TAYLOR) begin
    always_ff @(posedge clk) begin
        if (out_valid_buf && USE_TAYLOR) begin
            // $display("sin_phase_error * cos = %d * %d = %d", phase_error_signed, out_cos_buf, out_cos_buf * phase_error_signed);
            // $display("corrected = %d  uncorrected = %d", sin_corrected, sin_extended);
            // $display("cos_phase_error * sin = %d * %d = %d", phase_error_signed, out_sin_buf, out_sin_buf * phase_error_signed);
            // $display("corrected = %d  uncorrected = %d", cos_corrected[EXTENDED_WIDTH - 1 -: OUT_DW], cos_extended[EXTENDED_WIDTH - 1 -: OUT_DW]);
        end
        out_sin_buf2 <= !reset_n ? 0 : sin_corrected[EXTENDED_WIDTH - 1 -: OUT_DW];
        out_cos_buf2 <= !reset_n ? 0 : cos_corrected[EXTENDED_WIDTH - 1 -: OUT_DW];
        out_valid_buf2 <= !reset_n ? 0 : out_valid_buf;    
    end
end

if (USE_TAYLOR) begin
    assign m_axis_out_sin_tdata = out_sin_buf2;
    assign m_axis_out_sin_tvalid = out_valid_buf2;
    assign m_axis_out_cos_tdata = out_cos_buf2;
    assign m_axis_out_cos_tvalid = out_valid_buf2;    
end
else begin
    assign m_axis_out_sin_tdata = out_sin_buf;
    assign m_axis_out_sin_tvalid = out_valid_buf;
    assign m_axis_out_cos_tdata = out_cos_buf;
    assign m_axis_out_cos_tvalid = out_valid_buf;
end
assign m_axis_out_tdata = {m_axis_out_sin_tdata, m_axis_out_cos_tdata};
assign m_axis_out_tvalid = m_axis_out_sin_tvalid;

endmodule