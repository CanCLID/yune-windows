#pragma once

#include <array>
#include <cstddef>
#include <cstdint>

namespace yune_windows::reliability {

enum class ShiftClaimDisposition {
    Accepted,
    InvalidToken,
    StaleGeneration,
    Duplicate,
    ExpiredToken,
};

class ShiftTokenArbiter {
public:
    void Reset(std::uint64_t generation) {
        generation_ = generation;
        claimed_tokens_.fill(0);
        next_claimed_token_ = 0;
        high_water_token_ = 0;
    }

    ShiftClaimDisposition Claim(std::uint64_t token,
                                std::uint64_t generation) {
        if (token == 0 || generation == 0) {
            return ShiftClaimDisposition::InvalidToken;
        }
        if (generation != generation_) {
            return ShiftClaimDisposition::StaleGeneration;
        }
        for (const std::uint64_t claimed : claimed_tokens_) {
            if (claimed == token) {
                return ShiftClaimDisposition::Duplicate;
            }
        }
        if (high_water_token_ >= claimed_tokens_.size() &&
            token <= high_water_token_ - claimed_tokens_.size()) {
            return ShiftClaimDisposition::ExpiredToken;
        }
        claimed_tokens_[next_claimed_token_] = token;
        next_claimed_token_ =
            (next_claimed_token_ + 1) % claimed_tokens_.size();
        if (token > high_water_token_) {
            high_water_token_ = token;
        }
        return ShiftClaimDisposition::Accepted;
    }

private:
    std::uint64_t generation_ = 0;
    std::array<std::uint64_t, 256> claimed_tokens_ = {};
    std::size_t next_claimed_token_ = 0;
    std::uint64_t high_water_token_ = 0;
};

class ToggleParityIntent {
public:
    void Reset() {
        active_ = false;
        has_desired_ = false;
        desired_ = false;
        parity_ = false;
        generation_ = 0;
        attempts_ = 0;
        press_count_ = 0;
    }

    void AcceptPress(std::uint64_t generation, bool state_fresh,
                     bool current_value) {
        if (!active_ || generation_ != generation) {
            Reset();
            active_ = true;
            generation_ = generation;
            press_count_ = 1;
            if (state_fresh) {
                has_desired_ = true;
                desired_ = !current_value;
            } else {
                parity_ = true;
            }
            return;
        }
        ++press_count_;
        if (has_desired_) {
            desired_ = !desired_;
        } else {
            parity_ = !parity_;
        }
    }

    bool ResolveDesired(bool current_value) {
        if (!active_) {
            return false;
        }
        if (!has_desired_) {
            desired_ = current_value ^ parity_;
            has_desired_ = true;
            parity_ = false;
        }
        return true;
    }

    bool active() const { return active_; }
    bool has_desired() const { return has_desired_; }
    bool desired() const { return desired_; }
    std::uint64_t generation() const { return generation_; }
    unsigned int attempts() const { return attempts_; }
    unsigned int press_count() const { return press_count_; }
    void RecordAttempt() { ++attempts_; }

private:
    bool active_ = false;
    bool has_desired_ = false;
    bool desired_ = false;
    bool parity_ = false;
    std::uint64_t generation_ = 0;
    unsigned int attempts_ = 0;
    unsigned int press_count_ = 0;
};

enum class ToolbarEligibilityReason {
    Eligible,
    ProfileInactive,
    NotCurrentGeneration,
    NotFocused,
    StateUnacknowledged,
    OwnerInvalid,
    ForegroundMismatch,
};

struct ToolbarEligibilityInput {
    bool profile_active = false;
    bool current_generation = false;
    bool focused = false;
    bool state_acknowledged = false;
    bool owner_valid = false;
    bool foreground_matches_owner = false;
};

inline ToolbarEligibilityReason EvaluateToolbarEligibility(
    const ToolbarEligibilityInput& input) {
    if (!input.profile_active) {
        return ToolbarEligibilityReason::ProfileInactive;
    }
    if (!input.current_generation) {
        return ToolbarEligibilityReason::NotCurrentGeneration;
    }
    if (!input.focused) {
        return ToolbarEligibilityReason::NotFocused;
    }
    if (!input.state_acknowledged) {
        return ToolbarEligibilityReason::StateUnacknowledged;
    }
    if (!input.owner_valid) {
        return ToolbarEligibilityReason::OwnerInvalid;
    }
    if (!input.foreground_matches_owner) {
        return ToolbarEligibilityReason::ForegroundMismatch;
    }
    return ToolbarEligibilityReason::Eligible;
}

inline const char* ToolbarEligibilityReasonName(
    ToolbarEligibilityReason reason) {
    switch (reason) {
        case ToolbarEligibilityReason::Eligible:
            return "eligible";
        case ToolbarEligibilityReason::ProfileInactive:
            return "profile_inactive";
        case ToolbarEligibilityReason::NotCurrentGeneration:
            return "not_current_generation";
        case ToolbarEligibilityReason::NotFocused:
            return "not_focused";
        case ToolbarEligibilityReason::StateUnacknowledged:
            return "state_unacknowledged";
        case ToolbarEligibilityReason::OwnerInvalid:
            return "owner_invalid";
        case ToolbarEligibilityReason::ForegroundMismatch:
            return "foreground_mismatch";
    }
    return "unknown";
}

}  // namespace yune_windows::reliability
