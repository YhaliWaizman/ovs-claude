# Autonomous Task Queue

<!--
Format rules (the orchestrator parses this file):
- Each project block starts with: ## project: <name>
- path:    path to local repo (supports ~ for home dir, ${VAR} for env vars like ${PROJECTS_ROOT})
- context: one-line description injected into the agent prompt
- Tasks:   - [ ] <description> | priority: high|medium|low
- Done:    - [x] <description> | priority: ...   (orchestrator writes this automatically)

Example with environment variable:
  path: ${PROJECTS_ROOT}/biomarker-pipeline

Before running, set PROJECTS_ROOT env var:
  export PROJECTS_ROOT=/path/to/your/projects    # Linux
  set PROJECTS_ROOT=C:\path\to\your\projects     # Windows
  set PROJECTS_ROOT=~/repositories               # Using home dir shorthand
-->

## project: biomarkers
path: ${PROJECTS_ROOT}/biomarker-pipeline
context: Python bioinformatics pipeline for biomarker analysis

- [x] verify hydra migration is done | priority: high
- [x] commit changes to git | priority: medium


## project: claude automation
path: ${PROJECTS_ROOT}/claude-autonomous
context: node project to automate todo list with copilot or claude

- [x] make the code run at each hour at hh:05 instead of each 15 minutest from start | priority: high

