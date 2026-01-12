`timescale 1ns /1 ns
/************************** Control path **************************************************/
module control_path(
    input logic clk,
    input logic reset, 
    input logic run, 
    input logic [15:0] INSTRin,
    output logic R0in, R1in, Ain, Rin, IRin, 
    output logic [1:0] select, ALUOP,
    output logic done
); 

/* OPCODE format: II M X DDDDDDDDDDDD, where 
    *     II = instruction, M = Immediate, X = rX; X = (rX==0) ? r0:r1
    *     If M = 0, DDDDDDDDDDDD = 00000000000Y = rY; Y = (rY==0) r0:r1
    *     If M = 1, DDDDDDDDDDDD = #D is the immediate operand 
    *
    *  II M  Instruction   Description
    *  -- -  -----------   -----------
    *  00 0: mv    rX,rY    rX <- rY
    *  00 1: mv    rX,#D    rX <- D (sign extended)
    *  01 0: add   rX,rY    rX <- rX + rY
    *  01 1: add   rX,#D    rX <- rX + D
    *  10 0: sub   rX,rY    rX <- rX - rY
    *  10 1: sub   rX,#D    rX <- rX - D
    *  11 0: mult  rX,rY    rX <- rX * rY
    *  11 1: mult  rX,#D    rX <- rX * D 
*/

parameter mv = 2'b00, add = 2'b01, sub = 2'b10, mult = 2'b11;

logic [1:0] II;
logic M, rX, rY;

assign II = INSTRin[15:14];
assign M =  INSTRin[13];
assign rX = INSTRin[12];
assign rY = INSTRin[0];

// control FSM states
typedef enum logic[1:0]
{
    C0 = 'd0,
    C1 = 'd1, 
    C2 = 'd2, 
    C3 = 'd3
} statetype;

statetype current_state, next_state;


// control FSM state table
always_comb begin
    case(current_state)
	C0: next_state = run? C1:C0;
        C1: next_state = done? C0:C2;
        C2: next_state = C3;
        C3: next_state = C0;
    endcase
end

// output logic i.e: datapath control signals
always_comb begin
    // by default, make all our signals 0
    R0in = 1'b0; R1in = 1'b0;
    Ain = 1'b0; Rin = 1'b0; IRin = 1'b0;
    select = 2'bxx; 
    ALUOP = 2'bxx;
    done = 1'b0;

    case(current_state)
        C0: IRin = 1;
        C1: 
        begin 
            case(II)
                mv: 
                    begin 
                        if (M == 1)
                            select = 2'b11;
                        else
                            select = rY ? 2'b10 : 2'b01;
                    R0in = !rX;
                    R1in = rX;
                    done = 1;
                    end
                add:
                    begin
                    select = rX ? 2'b10 : 2'b01;
                    Ain = 1;
                    end
                sub:
                    begin
                    select = rX ? 2'b10 : 2'b01;
                    Ain = 1;
                    end
                mult:
                    begin
                    select = rX ? 2'b10 : 2'b01;
                    Ain = 1;
                    end
                default: done = 1;
            endcase
        end
        C2: 
        begin
            case(II)
                add:
                    begin
                    Rin = 1;
                    if (M == 1)
                        select = 2'b11;
                    else
                        select = rY ? 2'b10 : 2'b01;
                    ALUOP = 2'b00;
                    end
                sub:
                    begin
                    Rin = 1;
                    if (M == 1)
                        select = 2'b11;
                    else
                        select = rY ? 2'b10 : 2'b01;
                    ALUOP = 2'b01;
                    end
                mult:
                    begin
                    Rin = 1;
                    if (M == 1)
                        select = 2'b11;
                    else
                        select = rY ? 2'b10 : 2'b01;
                    ALUOP = 2'b10;
                    end
                default: done = 1;
            endcase
        end
        C3: 
        begin
            case(II)
                add:
                    begin
                    select = 0;
                    R0in = !rX;
                    R1in = rX;
                    done = 1;
                    end
                sub:
                    begin
                    select = 0;
                    R0in = !rX;
                    R1in = rX;
                    done = 1;
                    end
                mult:
                    begin
                    select = 0;
                    R0in = !rX;
                    R1in = rX;
                    done = 1;
                    end
            endcase
        end
    endcase 
end


// control FSM FlipFlop
always_ff @(posedge clk) begin
    if(reset)
        current_state <= C0;
    else
       current_state <= next_state;
end

endmodule




/************************** Datapath **************************************************/
module datapath(
    input logic clk, 
    input logic reset,
    input logic [15:0] INSTRin,
    input logic IRin, R0in, R1in, Ain, Rin,
    input logic [1:0] select, ALUOP,
    output logic [15:0] r0, r1, a, r // for testing purposes these are outputs
);

    logic [15:0] ir, MUXout, ALUout;

    FF IR (clk, reset, IRin, INSTRin, ir); 
    FF R0 (clk, reset, R0in, MUXout, r0);
    FF R1 (clk, reset, R1in, MUXout, r1);

    logic [15:0] ir1;
    assign ir1 = {ir[11], ir[11], ir[11], ir[11], ir[11:0]};

    mux MUX (r, r0, r1, ir1, select, MUXout);

    FF A (clk, reset, Ain, MUXout, a);

    ALU ALU (a, MUXout, ALUOP, ALUout);

    FF R (clk, reset, Rin, ALUout, r);

endmodule


// ALU
module ALU(input logic [15:0] A, B, input logic [1:0] choose, output logic [15:0] out);

    always_comb
        begin
            case(choose)
                0: out = A + B;
                1: out = A - B;
                2: out = A * B;
                default: out = 16'b0000000000000000;
            endcase
        end

endmodule

// FF
module FF(input logic clk, reset, enable, input logic [15:0] D, output logic [15:0] Q);
    always_ff @ (posedge clk)
        begin
        if (reset == 1)
            Q <= 16'b0;
        if (enable == 1)
            Q <= D;
        end
endmodule


// MUX
module mux(input logic [15:0] a, b, c, d, input logic [1:0] choose, output logic [15:0] out);
    
    always_comb
    begin
        case(choose)
            0: out = a;
            1: out = b;
            2: out = c;
            3: out = d;
            default: out = 16'b0000000000000000;
        endcase
    end

endmodule


/************************** processor  **************************************************/
module processor(
    input logic [15:0] INSTRin,
    input logic reset, 
    input logic clk,
    input logic run,
    output logic done,
    output logic[15:0] r0_out,r1_out, a_out, r_out
);

// intermediate logic 
logic r0in, r1in, ain, rin, irin;
logic[1:0] select, aluop;

control_path control(
   .clk(clk),
   .reset(reset), 
   .run(run), 
   .INSTRin(INSTRin),
   .R0in(r0in), 
   .R1in(r1in), 
   .Ain(ain), 
   .Rin(rin), 
   .IRin(irin), 
   .select(select), 
   .ALUOP(aluop),
   .done(done)
);

datapath data(
    .clk(clk), 
    .reset(reset),
    .INSTRin(INSTRin),
    .IRin(irin), 
    .R0in(r0in),
    .R1in(r1in), 
    .Ain(ain),
    .Rin(rin),
    .select(select), 
    .ALUOP(aluop),
    .r0(r0_out), 
    .r1(r1_out),
    .a(a_out),
    .r(r_out)
);

endmodule
