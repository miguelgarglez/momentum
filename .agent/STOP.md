# STOP conditions

Stop the loop immediately if any of these occur:
- Missing or ambiguous verify commands in `.agent/commands.md`
- Verification fails twice in a row
- Scope grows beyond a single PRD item
- You are asked to add dependencies/tooling without PRD approval
- Secrets or credentials would be required
