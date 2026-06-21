package torque.environment

import future.keywords.if

result = { "decision": "Manual", "reason": reason } if {
    input.duration_minutes > data.max_duration_minutes
    reason := sprintf("Requested duration of %v minutes exceeds 2 hours and requires approval", [input.duration_minutes])
}

result = { "decision": "Approved" } if {
    input.duration_minutes <= data.max_duration_minutes
}
