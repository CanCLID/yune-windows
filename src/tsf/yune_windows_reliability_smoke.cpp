#include <iostream>

#include "yune_windows_reliability_core.h"

namespace {

bool Require(bool condition, const char* message) {
    if (!condition) {
        std::cerr << message << "\n";
        return false;
    }
    return true;
}

}  // namespace

int main() {
    using yune_windows::reliability::ShiftClaimDisposition;
    using yune_windows::reliability::ShiftTokenArbiter;
    using yune_windows::reliability::ToggleParityIntent;
    using yune_windows::reliability::ToolbarEligibilityInput;
    using yune_windows::reliability::ToolbarEligibilityReason;

    ShiftTokenArbiter arbiter;
    arbiter.Reset(7);
    for (std::uint64_t token = 1; token <= 100; ++token) {
        if (!Require(arbiter.Claim(token, 7) ==
                         ShiftClaimDisposition::Accepted,
                     "paced Shift token was not accepted") ||
            !Require(arbiter.Claim(token, 7) ==
                         ShiftClaimDisposition::Duplicate,
                     "duplicate detector report was not rejected")) {
            return 1;
        }
    }
    if (!Require(arbiter.Claim(101, 6) ==
                     ShiftClaimDisposition::StaleGeneration,
                 "stale generation token was not rejected") ||
        !Require(arbiter.Claim(0, 7) ==
                     ShiftClaimDisposition::InvalidToken,
                 "zero token was not rejected")) {
        return 1;
    }
    arbiter.Reset(8);
    if (!Require(arbiter.Claim(20, 8) == ShiftClaimDisposition::Accepted &&
                     arbiter.Claim(10, 8) == ShiftClaimDisposition::Accepted,
                 "out-of-order distinct tokens were rejected") ||
        !Require(arbiter.Claim(20, 8) == ShiftClaimDisposition::Duplicate,
                 "out-of-order duplicate token was not rejected")) {
        return 1;
    }
    arbiter.Reset(9);
    for (std::uint64_t token = 1; token <= 300; ++token) {
        if (!Require(arbiter.Claim(token, 9) ==
                         ShiftClaimDisposition::Accepted,
                     "capacity-window token was not accepted")) {
            return 1;
        }
    }
    if (!Require(arbiter.Claim(1, 9) ==
                     ShiftClaimDisposition::ExpiredToken,
                 "evicted delayed token was not rejected explicitly")) {
        return 1;
    }

    ToggleParityIntent intent;
    intent.AcceptPress(7, true, false);
    if (!Require(intent.ResolveDesired(false) && intent.desired(),
                 "one fresh press did not toggle false to true")) {
        return 1;
    }
    intent.AcceptPress(7, true, false);
    if (!Require(!intent.desired() && intent.press_count() == 2,
                 "two in-flight presses did not preserve even parity")) {
        return 1;
    }
    intent.AcceptPress(7, true, false);
    if (!Require(intent.desired() && intent.press_count() == 3,
                 "three in-flight presses did not preserve odd parity")) {
        return 1;
    }

    intent.Reset();
    intent.AcceptPress(9, false, false);
    intent.AcceptPress(9, false, false);
    if (!Require(intent.ResolveDesired(true) && intent.desired(),
                 "two cold-state presses did not preserve the reconciled value")) {
        return 1;
    }
    intent.AcceptPress(9, true, true);
    if (!Require(!intent.desired(),
                 "post-timeout third press did not flip desired state")) {
        return 1;
    }
    intent.AcceptPress(10, true, false);
    if (!Require(intent.generation() == 10 && intent.press_count() == 1 &&
                     intent.desired(),
                 "generation replacement did not cancel stale parity")) {
        return 1;
    }

    ToolbarEligibilityInput eligibility = {
        true, true, true, true, true, true,
    };
    if (!Require(yune_windows::reliability::EvaluateToolbarEligibility(
                     eligibility) == ToolbarEligibilityReason::Eligible,
                 "foreground current service was not eligible")) {
        return 1;
    }
    eligibility.foreground_matches_owner = false;
    if (!Require(yune_windows::reliability::EvaluateToolbarEligibility(
                     eligibility) ==
                     ToolbarEligibilityReason::ForegroundMismatch,
                 "background owner was not rejected")) {
        return 1;
    }
    eligibility.foreground_matches_owner = true;
    eligibility.current_generation = false;
    if (!Require(yune_windows::reliability::EvaluateToolbarEligibility(
                     eligibility) ==
                     ToolbarEligibilityReason::NotCurrentGeneration,
                 "superseded service generation was not rejected")) {
        return 1;
    }

    std::cout << "M11D reliability core smoke passed.\n";
    return 0;
}
