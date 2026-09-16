# Network Connectivity and Security Validation

This validates the real 3-tier VPC in `infra/networking.tf` and
`infra/security_groups.tf` against the standard "public reaches
internet, private only reachable from a controlled path" test — using
live commands against the actual running instances, not a staged lab
environment.

## The architectural difference worth stating upfront

The typical version of this test provisions a standalone EC2 instance
in a public subnet, then SSHs into it and hops from there into a
private-subnet instance — transferring an SSH private key onto the
public instance to do it. This system doesn't have a public-subnet EC2
instance at all: both app instances sit in private subnets
(`appointments-private-app-0/1`, confirmed below, no public IP on
either), and the only public-facing component is the ALB — a managed
service, not a host. Nothing to SSH into even exists in a public
subnet.

Instance access uses AWS Systems Manager Session Manager instead of
SSH — no key pairs, no port 22 open anywhere, no private key ever
leaves Secrets Manager or gets copied between hosts. This isn't a
simplification of the standard test; it removes the exact risk (a
private key sitting on a public-facing host) the SSH-hop pattern
introduces.

## Instance placement (real, current)

| Instance | Subnet | Public IP |
|---|---|---|
| `i-00f06761feae7e15f` | `appointments-private-app-0` (10.20.10.0/24) | None |
| `i-0c30e15a0c9a01f53` | `appointments-private-app-1` (10.20.11.0/24) | None |

Both `appointments-public-0/1` subnets exist and hold the ALB and the
NAT gateway — no app compute in either.

## Test 1 — private instance can still reach the public internet

Run via `aws ssm send-command` against `i-00f06761feae7e15f` (no SSH,
no bastion):

```
--- ping ---
PING google.com (142.250.177.78) 56(84) bytes of data.
64 bytes from ...: icmp_seq=1 ttl=115 time=11.1 ms
64 bytes from ...: icmp_seq=2 ttl=115 time=10.6 ms
64 bytes from ...: icmp_seq=3 ttl=115 time=10.6 ms
64 bytes from ...: icmp_seq=4 ttl=115 time=10.7 ms
4 packets transmitted, 4 received, 0% packet loss

--- curl ---
HTTP/2 200
content-type: text/html;charset=utf-8
```

Egress path: private subnet → NAT gateway (`nat-0910afe4e083f3d47`, in
`appointments-public-0`) → internet gateway. Matches the `~$32/mo` NAT
line already in the README's Cost posture table — this isn't a
hypothetical cost, it's what's actually enabling this test to pass.

## Test 2 — no SSH path exists, anywhere

Real security group ingress rules, all four groups in the VPC:

| Security group | Port | Source |
|---|---|---|
| `appointments-alb-sg` | 80, 443 | `0.0.0.0/0` |
| `appointments-app-sg` | 8088 | `appointments-alb-sg` only |
| `appointments-rds-sg` | 3306 | `appointments-app-sg` only |
| `appointments-vpce-sg` | 443 | `appointments-app-sg` only |

Zero port-22 rules, on any group. The app tier doesn't accept traffic
from any CIDR block at all — only from the ALB's security group ID
specifically, which is a stronger scope than "from the VPC" or "from
the private subnet range." The chain is internet → ALB → app → RDS,
with no tier able to skip the one before it and no tier reachable by
raw IP/port from outside its specific upstream.

## What replaces "SSH from the public instance into the private one"

Running the two commands above *was* the access test — `aws ssm
send-command` reached a private-subnet instance with no public IP, no
open inbound port, and no key material anywhere, authenticated purely
through IAM (the operator's AWS credentials, scoped by IAM policy, not
a key file). Every such session is logged to CloudTrail automatically,
which an SSH session to a bastion is not, by default.

## Result

| Standard lab goal | Status | Evidence |
|---|---|---|
| Public instance reaches the internet | N/A — no public-subnet app instance exists | ALB is the only public component |
| Private instance reaches the internet | ✅ Confirmed | 0% packet loss, HTTP 200 |
| Private instance only reachable from a controlled path | ✅ Confirmed, and stronger than SSH-hop | SSM, IAM-authenticated, CloudTrail-logged, zero port-22 rules anywhere |
