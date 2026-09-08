`timescale 1ns/1ps

module tb_smart_parking;

    logic clk;
    logic reset;
    logic car_in;
    logic car_out;
    logic ticket_valid;
    logic payment_done;

    logic gate_in;
    logic gate_out;
    logic parking_full;
    logic available_led;
    logic alarm;
    logic display_update;

    localparam logic [3:0] ST_IDLE            = 4'd0;
    localparam logic [3:0] ST_CHECK_ENTRY     = 4'd1;
    localparam logic [3:0] ST_OPEN_ENTRY_GATE = 4'd2;
    localparam logic [3:0] ST_UPDATE_ENTRY    = 4'd3;
    localparam logic [3:0] ST_CHECK_EXIT      = 4'd4;
    localparam logic [3:0] ST_OPEN_EXIT_GATE  = 4'd5;
    localparam logic [3:0] ST_UPDATE_EXIT     = 4'd6;
    localparam logic [3:0] ST_PARKING_FULL    = 4'd7;
    localparam logic [3:0] ST_ERROR           = 4'd8;

    integer pass_count;
    integer fail_count;
    integer monitor_count;
    logic [11:0] completed_cases;

    smart_parking_top dut (
        .clk            (clk),
        .reset          (reset),
        .car_in         (car_in),
        .car_out        (car_out),
        .ticket_valid   (ticket_valid),
        .payment_done   (payment_done),
        .gate_in        (gate_in),
        .gate_out       (gate_out),
        .parking_full   (parking_full),
        .available_led  (available_led),
        .alarm          (alarm),
        .display_update (display_update)
    );

    // 10 ns clock period.
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic check(input logic condition, input string message);
        begin
            if (condition === 1'b1) begin
                pass_count = pass_count + 1;
                $display("[PASS] %s", message);
            end else begin
                fail_count = fail_count + 1;
                $error("[FAIL] %s at time %0t", message, $time);
            end
        end
    endtask

    // Check all externally visible controls after each rising edge settles.
    // A violation fails even if the directed test does not sample that output.
    always @(posedge clk) begin
        #2;
        if (!reset) begin
            monitor_count = monitor_count + 1;
            if ($isunknown({dut.state_debug, dut.occupancy_count,
                            gate_in, gate_out, parking_full, available_led,
                            alarm, display_update}) ||
                dut.state_debug > ST_ERROR || dut.occupancy_count > 10 ||
                gate_in !== (dut.state_debug == ST_OPEN_ENTRY_GATE) ||
                gate_out !== (dut.state_debug == ST_OPEN_EXIT_GATE) ||
                alarm !== (dut.state_debug == ST_ERROR ||
                           dut.state_debug == ST_PARKING_FULL) ||
                display_update !== (dut.state_debug == ST_UPDATE_ENTRY ||
                                    dut.state_debug == ST_UPDATE_EXIT) ||
                parking_full !== (dut.occupancy_count == 10) ||
                available_led !== (dut.occupancy_count < 10))
                check(1'b0, "continuous control/indicator/range invariant");
        end
    end

    // Prevent a stalled stimulus or missing clock from appearing to pass.
    initial begin
        #100000;
        $fatal(1, "TESTBENCH TIMEOUT");
    end

    task automatic apply_reset;
        begin
            reset = 1'b1;
            #1;
            check(dut.state_debug == ST_IDLE, "reset places FSM in IDLE");
            check(dut.occupancy_count == 0, "reset clears occupancy counter");
            check(!gate_in && !gate_out, "reset closes both gates");
            check(!alarm && !display_update && !parking_full && available_led,
                  "reset clears control strobes and restores availability");
            @(negedge clk);
            reset = 1'b0;
            @(posedge clk);
            #1;
        end
    endtask

    task automatic do_valid_entry;
        logic [3:0] count_before;
        begin
            count_before = dut.occupancy_count;

            @(negedge clk);
            car_in       = 1'b1;
            ticket_valid = 1'b1;

            @(posedge clk);
            #1;
            check(dut.state_debug == ST_CHECK_ENTRY, "entry request reaches CHECK_ENTRY");

            @(negedge clk);
            car_in = 1'b0;

            @(posedge clk);
            #1;
            check(dut.state_debug == ST_OPEN_ENTRY_GATE && gate_in,
                  "valid ticket opens entrance gate");

            @(posedge clk);
            #1;
            check(dut.state_debug == ST_UPDATE_ENTRY && display_update,
                  "accepted entry requests a display update");
            check(dut.occupancy_count == count_before && !gate_in && !gate_out,
                  "entry update enable precedes counter write, with gates closed");

            @(posedge clk);
            #1;
            check(dut.state_debug == ST_IDLE, "entry sequence returns to IDLE");
            check(dut.occupancy_count == count_before + 1'b1,
                  "accepted entry increments occupancy once");
            check(!display_update && !alarm && !gate_in && !gate_out,
                  "entry controls return inactive after one-cycle pulses");

            ticket_valid = 1'b0;
        end
    endtask

    task automatic do_valid_exit;
        logic [3:0] count_before;
        begin
            count_before = dut.occupancy_count;

            @(negedge clk);
            car_out      = 1'b1;
            payment_done = 1'b1;

            @(posedge clk);
            #1;
            check(dut.state_debug == ST_CHECK_EXIT, "exit request reaches CHECK_EXIT");

            @(negedge clk);
            car_out = 1'b0;

            @(posedge clk);
            #1;
            check(dut.state_debug == ST_OPEN_EXIT_GATE && gate_out,
                  "completed payment opens exit gate");

            @(posedge clk);
            #1;
            check(dut.state_debug == ST_UPDATE_EXIT && display_update,
                  "accepted exit requests a display update");
            check(dut.occupancy_count == count_before && !gate_in && !gate_out,
                  "exit update enable precedes counter write, with gates closed");

            @(posedge clk);
            #1;
            check(dut.state_debug == ST_IDLE, "exit sequence returns to IDLE");
            check(dut.occupancy_count == count_before - 1'b1,
                  "accepted exit decrements occupancy once");
            check(!display_update && !alarm && !gate_in && !gate_out,
                  "exit controls return inactive after one-cycle pulses");

            payment_done = 1'b0;
        end
    endtask

    task automatic do_invalid_ticket;
        logic [3:0] count_before;
        begin
            count_before = dut.occupancy_count;

            @(negedge clk);
            car_in       = 1'b1;
            ticket_valid = 1'b0;

            @(posedge clk);
            #1;
            check(dut.state_debug == ST_CHECK_ENTRY, "invalid-ticket request is checked");

            @(negedge clk);
            car_in = 1'b0;

            @(posedge clk);
            #1;
            check(dut.state_debug == ST_ERROR && alarm,
                  "invalid ticket raises alarm in ERROR state");
            check(!gate_in, "invalid ticket keeps entrance gate closed");

            @(posedge clk);
            #1;
            check(dut.state_debug == ST_IDLE, "ERROR state recovers to IDLE");
            check(dut.occupancy_count == count_before,
                  "invalid ticket does not change occupancy");
        end
    endtask

    task automatic do_entry_when_full;
        begin
            @(negedge clk);
            car_in       = 1'b1;
            ticket_valid = 1'b1;

            @(posedge clk);
            #1;
            check(dut.state_debug == ST_CHECK_ENTRY, "full-lot entry request is checked");

            @(negedge clk);
            car_in = 1'b0;

            @(posedge clk);
            #1;
            check(dut.state_debug == ST_PARKING_FULL && alarm,
                  "full lot rejects entry and raises alarm");
            check(!gate_in, "full lot keeps entrance gate closed");

            @(posedge clk);
            #1;
            check(dut.state_debug == ST_IDLE, "PARKING_FULL state recovers to IDLE");
            check(dut.occupancy_count == 10, "full-lot rejection preserves count at 10");

            ticket_valid = 1'b0;
        end
    endtask

    task automatic do_exit_when_empty;
        begin
            @(negedge clk);
            car_out      = 1'b1;
            payment_done = 1'b1;

            @(posedge clk);
            #1;
            check(dut.state_debug == ST_CHECK_EXIT, "empty-lot exit request is checked");

            @(negedge clk);
            car_out = 1'b0;

            @(posedge clk);
            #1;
            check(dut.state_debug == ST_ERROR && alarm,
                  "exit from empty lot raises alarm");
            check(!gate_out, "empty-lot request keeps exit gate closed");

            @(posedge clk);
            #1;
            check(dut.occupancy_count == 0, "empty-lot request prevents underflow");

            payment_done = 1'b0;
        end
    endtask

    task automatic do_simultaneous_request;
        logic [3:0] count_before;
        begin
            count_before = dut.occupancy_count;

            @(negedge clk);
            car_in       = 1'b1;
            car_out      = 1'b1;
            ticket_valid = 1'b1;
            payment_done = 1'b1;

            @(posedge clk);
            #1;
            check(dut.state_debug == ST_CHECK_EXIT,
                  "simultaneous request applies documented exit priority");

            @(negedge clk);
            car_in  = 1'b0;
            car_out = 1'b0;

            @(posedge clk);
            #1;
            check(gate_out && !gate_in,
                  "simultaneous request opens only the priority exit gate");

            @(posedge clk);
            #1;
            check(dut.state_debug == ST_UPDATE_EXIT, "priority exit reaches UPDATE_EXIT");

            @(posedge clk);
            #1;
            check(dut.occupancy_count == count_before - 1'b1,
                  "simultaneous request processes exactly one exit");

            ticket_valid = 1'b0;
            payment_done = 1'b0;
        end
    endtask

    task automatic do_unpaid_exit;
        logic [3:0] count_before;
        begin
            count_before = dut.occupancy_count;
            check(count_before > 0, "unpaid-exit test starts with an occupied lot");
            @(negedge clk);
            car_out = 1'b1;
            payment_done = 1'b0;
            @(posedge clk);
            #1;
            check(dut.state_debug == ST_CHECK_EXIT, "unpaid exit reaches CHECK_EXIT");
            @(negedge clk);
            car_out = 1'b0;
            @(posedge clk);
            #1;
            check(dut.state_debug == ST_ERROR && alarm,
                  "incomplete payment raises alarm");
            check(!gate_in && !gate_out && !display_update,
                  "unpaid exit opens no gate and requests no display update");
            @(posedge clk);
            #1;
            check(dut.state_debug == ST_IDLE && !alarm &&
                  dut.occupancy_count == count_before,
                  "unpaid exit recovers without changing occupancy");
        end
    endtask

    initial begin
        pass_count    = 0;
        fail_count    = 0;
        monitor_count = 0;
        completed_cases = '0;
        reset         = 1'b0;
        car_in        = 1'b0;
        car_out       = 1'b0;
        ticket_valid  = 1'b0;
        payment_done  = 1'b0;

        $dumpfile("smart_parking.vcd");
        $dumpvars(0, tb_smart_parking);

        $display("\nTC1 - Reset system");
        apply_reset();
        check(available_led && !parking_full, "empty parking lot indicates availability");
        completed_cases[0] = 1'b1;

        $display("\nTC2 - Single vehicle enters");
        do_valid_entry();
        check(dut.occupancy_count == 1, "single-entry count is 1");
        completed_cases[1] = 1'b1;

        $display("\nTC3 - Multiple vehicles enter");
        repeat (3) do_valid_entry();
        check(dut.occupancy_count == 4, "multiple-entry count is 4");
        completed_cases[2] = 1'b1;

        $display("\nTC4 - Parking reaches maximum capacity");
        repeat (6) do_valid_entry();
        check(dut.occupancy_count == 10, "occupancy reaches maximum of 10");
        check(parking_full && !available_led, "full and available indicators are complementary");
        completed_cases[3] = 1'b1;

        $display("\nTC5 - Vehicle denied when full");
        do_entry_when_full();
        completed_cases[4] = 1'b1;

        $display("\nTC6 - Vehicle exits");
        do_valid_exit();
        check(dut.occupancy_count == 9, "single exit changes count from 10 to 9");
        check(!parking_full && available_led, "one exit clears the full indication");
        completed_cases[5] = 1'b1;

        $display("\nTC7 - Multiple vehicles exit");
        repeat (3) do_valid_exit();
        check(dut.occupancy_count == 6, "three more exits leave six vehicles");
        completed_cases[6] = 1'b1;

        $display("\nTC8 - Vehicle exits when parking is empty");
        repeat (6) do_valid_exit();
        check(dut.occupancy_count == 0, "valid exits can empty the parking lot");
        do_exit_when_empty();
        completed_cases[7] = 1'b1;

        $display("\nTC9 - Simultaneous entry and exit");
        do_valid_entry();
        do_simultaneous_request();
        check(dut.occupancy_count == 0, "exit-priority scenario leaves count at zero");
        completed_cases[8] = 1'b1;

        $display("\nTC10 - Invalid ticket");
        do_invalid_ticket();
        completed_cases[9] = 1'b1;

        $display("\nTC11 - Reset during operation");
        repeat (2) do_valid_entry();
        check(dut.occupancy_count == 2, "mid-operation reset starts with nonzero occupancy");
        @(negedge clk);
        car_in       = 1'b1;
        ticket_valid = 1'b1;
        @(posedge clk);
        #1;
        @(negedge clk);
        car_in = 1'b0;
        @(posedge clk);
        #1;
        check(gate_in, "entrance gate is open before mid-operation reset");
        #2;
        reset = 1'b1;
        #1;
        check(dut.state_debug == ST_IDLE, "asynchronous reset immediately returns to IDLE");
        check(dut.occupancy_count == 0, "mid-operation reset clears occupancy");
        check(!gate_in && !gate_out, "mid-operation reset closes both gates");
        check(!alarm && !display_update && !parking_full && available_led,
              "mid-operation reset clears controls and restores availability");
        @(negedge clk);
        reset        = 1'b0;
        ticket_valid = 1'b0;
        @(posedge clk);
        #1;
        check(dut.occupancy_count == 0 && dut.state_debug == ST_IDLE,
              "reset release does not commit the interrupted entry");
        completed_cases[10] = 1'b1;

        $display("\nTC12 - Continuous traffic scenario");
        repeat (3) do_valid_entry();
        do_valid_exit();
        do_valid_entry();
        repeat (2) do_valid_exit();
        check(dut.occupancy_count == 1, "continuous traffic finishes with expected count of 1");
        check(!parking_full && available_led, "continuous traffic leaves parking available");
        check(!alarm, "continuous valid traffic finishes without alarm");
        completed_cases[11] = 1'b1;

        $display("\nEXTRA - Incomplete payment and recovery");
        do_unpaid_exit();
        do_valid_exit();
        check(dut.occupancy_count == 0, "paid retry succeeds after unpaid rejection");

        $display("\nEXTRA - Reset while an exit update is pending");
        do_valid_entry();
        @(negedge clk);
        car_out = 1'b1;
        payment_done = 1'b1;
        @(posedge clk);
        @(negedge clk);
        car_out = 1'b0;
        repeat (2) @(posedge clk);
        #1;
        check(dut.state_debug == ST_UPDATE_EXIT && display_update &&
              dut.occupancy_count == 1, "exit update is pending before reset");
        #2;
        apply_reset();
        payment_done = 1'b0;
        repeat (2) @(posedge clk);
        #3;
        check(dut.state_debug == ST_IDLE && dut.occupancy_count == 0 &&
              !display_update, "reset cancels pending exit without underflow");

        // Finish after the continuous monitor has sampled the final edge.
        check(completed_cases == 12'hfff, "all 12 required scenarios completed");
        check(monitor_count > 0, "continuous monitor sampled the simulation");

        $display("\n============================================================");
        $display("TEST SUMMARY: %0d passed, %0d failed", pass_count, fail_count);
        $display("CONTINUOUS MONITOR: %0d clock samples", monitor_count);
        $display("============================================================");

        if (fail_count == 0) begin
            $display("ALL 12 REQUIRED FUNCTIONAL TEST CASES PASSED");
            $display("ADDITIONAL PAYMENT AND RESET CHECKS PASSED");
        end else
            $fatal(1, "TESTBENCH FAILED");

        $finish;
    end

endmodule
