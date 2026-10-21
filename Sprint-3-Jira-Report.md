# Sprint 3 Jira Report

- **Jira project:** MH2D (2D Defense / ZombieTD) — https://russojonathyn.atlassian.net/jira/software/projects/MH2D/boards/4
- **Sprint:** Course Sprint 3 = Jira sprint "MH2D Sprint 2" (Oct 8 – Oct 20, 2026)
- **Sprint goal:** Core combat loop: tower targeting/attack, zombie death, base health, currency, wave spawner, in-game HUD, game over

## Sprint Commitment vs Delivery

| Metric | Count |
|---|---|
| Issues committed at sprint start | 7 |
| Issues completed | 7 |
| Issues not completed | 0 |
| Issues added mid-sprint | 0 stories (2 subtasks added Oct 18: MH2D-126, MH2D-127) |

Counts are top-level stories. The stories also have 20 subtasks, all Done.

## Issue Breakdown by Type

| Type | To Do | In Progress | Done |
|---|---|---|---|
| Story | 0 | 0 | 7 |
| Task | 0 | 0 | 0 |
| Bug | 0 | 0 | 0 |

Stories: MH2D-9 Tower targeting and attack; MH2D-10 Zombie health and death; MH2D-11 Base health and lose condition; MH2D-13 Wave spawner; MH2D-16 Currency system; MH2D-23 In-game HUD; MH2D-25 Game Over screen.

## Per-Student Work Allocation

| Student | Issues Assigned | Issues Completed |
|---|---|---|
| Jonathyn Russo | 4 (MH2D-9, 10, 11, 25) | 4 |
| Adam | 3 (MH2D-13, 16, 23) | 3 |

## Estimation & Accuracy

| Metric | Value |
|---|---|
| Total story points committed | Not estimated (no story points set in Jira) |
| Total story points completed | Not estimated |
| Completion % | 100% of issues (7 of 7 stories) |

## Workflow Discipline

- [x] Issues moved through workflow states (To Do → In Progress → Done)
- [ ] Issues closed only after acceptance criteria met (see notes)
- [x] Sprint completed/closed in Jira (sprint end date Oct 20, 2026)

All 7 stories and all 20 subtasks are marked Done in Jira (checked Oct 20, 2026).

Note on the unchecked item:
- MH2D-25 (Game Over screen): the Retry button works, but the Main Menu button is wired and hidden until the main menu exists (MH2D-22, not in this sprint). The ticket also mentions a final score; the team decided to show waves survived only. The ticket is Done in Jira, but those two acceptance-criteria details are not fully met.

## Blockers & Scope Changes

- **Major blockers:** merge conflicts when merging the restructured project (GameScene.swift split into folders) with main; a stale local `main` caused a second "can't merge" on the pull request until the real main was merged in.
- **Scope changes:** two subtasks added mid-sprint (MH2D-126 base health hook for the HUD, MH2D-127 base health on the HUD) to connect the base health and HUD tickets. Final score on the Game Over screen was dropped; Main Menu button deferred to MH2D-22.
- **Why work spilled over:** nothing spilled over at story level; all seven stories are Done. The only carry-over is the Main Menu button (waits for MH2D-22).

## Jira Evidence Links

- Sprint report: https://russojonathyn.atlassian.net/jira/software/projects/MH2D/boards/4/reports/sprint-retrospective
- Backlog: https://russojonathyn.atlassian.net/jira/software/projects/MH2D/boards/4/backlog
- Board: https://russojonathyn.atlassian.net/jira/software/projects/MH2D/boards/4
