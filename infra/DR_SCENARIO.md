# DR rationale — preparedness, not narrative

Short version: cross-region DR here is framed as **preparedness for a
regional infrastructure disruption**, cost-weighed like everything else
in this stack — not a storytelling centerpiece. The one fact worth
keeping from the research: in February 2021, Texas's grid (ERCOT) is
deliberately isolated from the national interconnections, so when its
own generation failed in a severe winter storm, it had no interconnected
neighbor to import emergency power from — millions lost power for days,
and the grid came within minutes of a total collapse that would have
taken weeks to recover from.

The actual architectural lesson: a system with no independent fallback
has no fallback when it matters. That's why `us-east-2` (primary) is
paired with `us-west-2` (DR) — separate power grids, separate weather
systems — rather than picked for geography alone. AWS has no region in
Texas, so this is preparedness reasoning applied to region selection,
not a claim that a specific AWS region failed.

Design stays pilot-light (cheap, mostly idle) for the same reason
everything else here is cost-conscious. The planned implementation is
an RDS cross-region read replica, a DynamoDB Global Table, an idle
standby ASG and Route 53 failover, targeting an RTO of ~10-20 min and an
RPO of seconds to minutes (see `SECURITY.md` and the main README).
Still design-only, not built.

Sources: [EBSCO Research Starters](https://www.ebsco.com/research-starters/power-and-energy/2021-texas-power-crisis), [CHDS timeline](https://www.chds.us/c/timeline/2021-texas-power-crisis/)
