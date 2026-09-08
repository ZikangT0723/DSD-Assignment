# Smart Car Parking Controller Assignment Guide

## 1. Assignment requirements

Requirements checked against the lecturer's **UGEA2353 DSD Assignment 2026June.pdf** (three pages):

- Language: Verilog or SystemVerilog; this solution uses SystemVerilog.
- Parking capacity: maximum 10 vehicles.
- Required inputs: `clk`, `reset`, `car_in`, `car_out`, `ticket_valid`, and `payment_done`.
- Required outputs: `gate_in`, `gate_out`, `parking_full`, `available_led`, `alarm`, and `display_update`.
- Required FSM states: `IDLE`, `CHECK_ENTRY`, `OPEN_ENTRY_GATE`, `UPDATE_ENTRY`, `CHECK_EXIT`, `OPEN_EXIT_GATE`, `UPDATE_EXIT`, `PARKING_FULL`, and `ERROR`.
- Required synthesizable modules: Parking FSM Controller, Vehicle Counter, Display Controller, and Top Module.
- Verification: all 12 functional test cases listed in Section 5 are included in the self-checking testbench.

## 2. Design architecture

The design uses a hierarchical implementation with separate FSM logic:

1. `parking_fsm_controller` contains a state register, combinational next-state logic, and Moore output logic.
2. `vehicle_counter` maintains a saturating occupancy count from 0 through 10 and produces the full/empty flags.
3. `display_controller` turns on `available_led` whenever the parking lot is not full.
4. `smart_parking_top` structurally instantiates and connects the three component modules.

Sequential blocks use `always_ff` with nonblocking assignments. Combinational blocks use `always_comb` with blocking assignments and safe default values, preventing unintended latches.

## 3. Operational assumptions

- The assignment requires an asynchronous reset; active-high polarity is a design choice.
- A ticket is sampled in `CHECK_ENTRY`; payment is sampled in `CHECK_EXIT`.
- Sensors are synchronous request levels and may be deasserted after the controller enters the corresponding check state. Requests asserted only while the FSM is busy are not queued. A sensor held high on a later visit to `IDLE` is treated as another request. Physical sensor synchronization, debounce, and one-request-per-vehicle conditioning are outside this assignment model.
- Entrance and exit gates open for one FSM state/cycle.
- In `UPDATE_ENTRY` or `UPDATE_EXIT`, the FSM asserts the counter enable and `display_update`. Occupancy changes once at the rising edge **leaving** that state, when the FSM returns to `IDLE`. The full/available indicators then follow the new count.
- An invalid ticket, incomplete payment, or an exit request while empty enters `ERROR` for one cycle and raises `alarm`.
- An entry request while full enters `PARKING_FULL` for one cycle, keeps the entrance gate closed, and raises `alarm`.
- If `car_in` and `car_out` are asserted simultaneously, exit has priority. This arbitration choice avoids opening both barriers together and is tested in TC9. The entry request is not queued: it must remain asserted or be retried when the controller returns to `IDLE`. An empty-lot or unpaid exit still takes priority and produces `ERROR`; there is no automatic fallback to entry.
- The counter saturates at 0 and 10, so invalid requests cannot cause underflow or overflow.

The PDF does not prescribe reset polarity, arbitration, request queuing, gate-open duration, or exact display-update timing. These are implementation assumptions, not additional lecturer requirements. Here `display_update` is an update-request strobe, not a registered indication that the updated count is already available. A future clocked display register would need to account for that timing.

## 4. FSM state/transition summary

| Current state | Condition | Next state | Main output/action |
|---|---|---|---|
| `IDLE` | `car_out=1` | `CHECK_EXIT` | Exit priority |
| `IDLE` | `car_out=0`, `car_in=1` | `CHECK_ENTRY` | Begin entry check |
| `IDLE` | No request | `IDLE` | Gates closed |
| `CHECK_ENTRY` | Lot full | `PARKING_FULL` | Reject entry |
| `CHECK_ENTRY` | Space available, invalid ticket | `ERROR` | Raise alarm |
| `CHECK_ENTRY` | Space available, valid ticket | `OPEN_ENTRY_GATE` | Accept entry |
| `OPEN_ENTRY_GATE` | Always | `UPDATE_ENTRY` | `gate_in=1` |
| `UPDATE_ENTRY` | Always | `IDLE` | Increment and update display |
| `CHECK_EXIT` | Empty or payment incomplete | `ERROR` | Raise alarm |
| `CHECK_EXIT` | Occupied and payment complete | `OPEN_EXIT_GATE` | Accept exit |
| `OPEN_EXIT_GATE` | Always | `UPDATE_EXIT` | `gate_out=1` |
| `UPDATE_EXIT` | Always | `IDLE` | Decrement and update display |
| `PARKING_FULL` | Always | `IDLE` | `alarm=1` |
| `ERROR` | Always | `IDLE` | `alarm=1` |

State encoding for waveform analysis:

| Value | State |
|---:|---|
| 0 | `IDLE` |
| 1 | `CHECK_ENTRY` |
| 2 | `OPEN_ENTRY_GATE` |
| 3 | `UPDATE_ENTRY` |
| 4 | `CHECK_EXIT` |
| 5 | `OPEN_EXIT_GATE` |
| 6 | `UPDATE_EXIT` |
| 7 | `PARKING_FULL` |
| 8 | `ERROR` |

## 5. Testbench coverage

The self-checking `tb_smart_parking.sv` verifies:

1. TC1 - Reset system.
2. TC2 - Single vehicle enters.
3. TC3 - Multiple vehicles enter.
4. TC4 - Parking reaches maximum capacity.
5. TC5 - Vehicle is denied when full.
6. TC6 - One vehicle exits.
7. TC7 - Multiple vehicles exit.
8. TC8 - A vehicle attempts to exit while the parking lot is empty.
9. TC9 - Simultaneous entry and exit, using the documented exit-priority policy.
10. TC10 - Invalid ticket.
11. TC11 - Asynchronous reset while the entry gate is open, starting with two vehicles; verifies immediate counter clearing and no delayed entry after release.
12. TC12 - Continuous valid entry/exit traffic.

Additional checks cover an unpaid exit from an occupied lot, a successful paid retry, and asynchronous reset while an exit update is pending. A continuous monitor checks state/count range, unknown values, gate exclusivity and state decoding, alarm/display strobes, and full/available indications after each rising edge. Directed checks verify count and one-cycle control timing. These are simulation checks, not exhaustive formal verification; a two-state simulator cannot establish four-state X/Z behavior.

The testbench generates `smart_parking.vcd`, tracks completion of all 12 required scenarios, prints a pass/fail summary, and calls `$fatal` if any check fails. A watchdog aborts a stalled run. The pass count counts individual assertions, not test cases.

## 6. Running in EDA Playground

1. Select **SystemVerilog/Verilog**.
2. Select a SystemVerilog simulator such as **Synopsys VCS** or **Aldec Riviera Pro**.
3. Put `smart_parking_design.sv` in the Design pane.
4. Put `tb_smart_parking.sv` in the Testbench pane.
5. Enable **Open EPWave after run**.
6. Run the simulation and confirm the console reports `ALL 12 REQUIRED FUNCTIONAL TEST CASES PASSED`.
7. Add all six inputs, all six outputs, `dut.state_debug`, and `dut.occupancy_count` to EPWave. The six inputs already include `clk` and `reset`.

Local regression with Verilator (C++ compiler and make required):

```sh
verilator --binary --timing --trace --top-module tb_smart_parking \
  --Mdir /tmp/dsd-build -Wno-fatal smart_parking_design.sv tb_smart_parking.sv
/tmp/dsd-build/Vtb_smart_parking
```

Review compiler warnings as well as the simulation summary. Local simulation supplements the PDF's required **EDA Playground** run; include EDA Playground/EPWave evidence in the submitted report.

## 7. Waveform discussion checklist

For each test case, discuss:

- the current FSM state and state transition;
- the input change that caused the transition;
- the gate and alarm response;
- the occupancy counter before and after the request;
- `parking_full` and `available_led` behavior;
- the one-cycle `display_update` pulse; and
- the timing relationship between clock edges, state changes, gate operation, and counter updates.

For an accepted entry with initial occupancy `N`, values after successive rising edges are:

| Edge | State | `gate_in` | `display_update` | Occupancy |
|---|---|---:|---:|---:|
| Request sampled | `CHECK_ENTRY` | 0 | 0 | N |
| Ticket accepted | `OPEN_ENTRY_GATE` | 1 | 0 | N |
| Gate cycle ends | `UPDATE_ENTRY` | 0 | 1 | N |
| Update committed | `IDLE` | 0 | 0 | N + 1 |

An accepted exit follows the same timing using exit states and `N - 1`. Reset can interrupt either sequence between clock edges.

## 8. Report requirements still to complete

The PDF also requires simulation in EDA Playground, waveform explanations, and evaluation of **testability and sustainable design considerations**. The code and a passing console summary alone do not complete the report.

- System specification/problem analysis (10 marks): describe the campus-parking problem, interfaces, capacity, and the assumptions above.
- FSM design (30 marks): provide a state diagram, transition/output table, arbitration rationale, and error/reset behavior.
- RTL design (30 marks): explain the four synthesizable modules and their connections.
- Testbench development (20 marks): map TC1-TC12 to stimulus and expected results, and discuss controllability through inputs/reset and observability through outputs, occupancy, and state debug signals.
- Simulation/waveform analysis (10 marks): provide EDA Playground results and annotated waveforms with the seven explanations listed on page 3 of the PDF.
- Discuss sustainable design qualitatively: the small counter, event-driven occupancy updates, and simple control logic limit hardware needs. Do not claim measured power or energy savings without synthesis/activity-based measurements. Gate motors and physical sensor power are outside this RTL simulation.

The stated submission deadline is **5:00 pm, Friday, 18 September 2026**, by email to the lecturer. No report submission is performed by this repository workflow.

## 9. Files

- `smart_parking_design.sv`: all four synthesizable modules.
- `tb_smart_parking.sv`: self-checking testbench for the 12 required cases.
- `assignment_guideline.md`: requirements, assumptions, FSM summary, and simulation instructions.

## 10. Review and local verification record (8 September 2026)

Baseline reviewed: commit `edb529987a6199b4a1a0a6b4abf907e96295f79c`.

| Check | Result |
|---|---|
| Required interfaces, four modules, nine states, capacity and asynchronous reset | Present in RTL; no functional RTL change identified by this review |
| Original testbench, local Verilator simulation | 178 individual checks passed, 0 failed |
| Strengthened testbench, local Verilator simulation | 280 individual checks passed, 0 failed; all TC1-TC12 completed |
| Continuous control/indicator/range monitor | 154 clock samples, no violations |
| Compiler diagnostics | Two existing `WIDTHEXPAND` warnings: the unsigned 4-bit count is extended for comparison with the 32-bit capacity parameter; correct for the configured capacity of 10 |
| EDA Playground simulation and report waveforms | Still required; not executed as part of this local review |
| Synthesis, physical timing and power measurements | Not performed |

The RTL is unchanged. Changes strengthen verification and distinguish lecturer requirements from implementation assumptions. Simulation success establishes the exercised cases, not exhaustive correctness or a guaranteed assignment mark.
