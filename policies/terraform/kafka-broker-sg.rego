package torque.terraform_plan

import future.keywords.in

# Blocks any security-group INGRESS rule that exposes a protected port to the
# open internet. An over-broad rule (0.0.0.0/0 on 9098) is denied; a rule scoped
# to the VPC CIDR passes.
#
# Configurable data (admin-set in Torque; defaults below):
#   data.protected_ports  — list(number) of ports that must never be world-open. Default: [9098]
#   data.forbidden_cidr   — the CIDR treated as "the whole internet".          Default: "0.0.0.0/0"

protected_ports = data.protected_ports {
    data.protected_ports
}

protected_ports = [9098] {
    not data.protected_ports
}

forbidden_cidr = data.forbidden_cidr {
    data.forbidden_cidr
}

forbidden_cidr = "0.0.0.0/0" {
    not data.forbidden_cidr
}

port_in_range(from_port, to_port, p) {
    from_port <= p
    p <= to_port
}

# Standalone aws_security_group_rule (this is what the MSK module uses).
deny[reason] {
    rc := input.resource_changes[_]
    rc.type == "aws_security_group_rule"
    rc.change.actions[_] in {"create", "update"}
    rc.change.after.type == "ingress"
    rc.change.after.cidr_blocks[_] == forbidden_cidr
    port_in_range(rc.change.after.from_port, rc.change.after.to_port, protected_ports[_])
    reason := sprintf("Security group rule '%v' opens a protected broker port (%v-%v) to %v. Scope ingress to the VPC CIDR instead.", [rc.address, rc.change.after.from_port, rc.change.after.to_port, forbidden_cidr])
}

# Inline ingress blocks on an aws_security_group (defense in depth).
deny[reason] {
    rc := input.resource_changes[_]
    rc.type == "aws_security_group"
    rc.change.actions[_] in {"create", "update"}
    ing := rc.change.after.ingress[_]
    ing.cidr_blocks[_] == forbidden_cidr
    port_in_range(ing.from_port, ing.to_port, protected_ports[_])
    reason := sprintf("Security group '%v' has an inline ingress opening a protected broker port (%v-%v) to %v. Scope ingress to the VPC CIDR instead.", [rc.address, ing.from_port, ing.to_port, forbidden_cidr])
}
