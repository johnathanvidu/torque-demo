package torque.environment

import future.keywords.if

default result = { "decision": "Approved" }

result = { "decision": "Manual", "reason": reason } if {
    input.action_identifier.action_type == "Extend" 
    input.extend_duration_minutes > data.max_duration_minutes
    reason := sprintf("Requested extend duration of %v minutes exceeds the allowed %v minutes and requires approval", [input.duration_minutes, data.max_duration_minutes])
}

result = { "decision": "Approved" } if {
    input.action_identifier.action_type == "Extend" 
    input.extend_duration_minutes <= data.max_duration_minutes
}
