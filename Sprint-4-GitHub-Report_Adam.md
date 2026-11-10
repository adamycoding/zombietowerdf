# Sprint 4 GitHub Report — Adam

- **Repository:** https://github.com/adamycoding/zombietowerdf
- **Branch:** Adam-Sprint4
- **Pull request:** #18, merged into `main` on 2026-11-03 at 9:54 PM Central
- **Tickets:** MH2D-14, MH2D-15, MH2D-20, MH2D-30

## Commit

| Item | Detail |
|---|---|
| Commit | d10bdc8 (1 commit on the branch) |
| Committed and merged by | jonathynrusso (no reviews) |
| Size | 6 files changed, +376 / −162 |

Adam's branch was not working through git and Xcode, so the files were sent over manually and committed from Jon's account (this is also the PR title on GitHub).

| File | Lines |
|---|---|
| Combat/DamageType.swift | +13 / −0 |
| Game/GameScene.swift | +76 / −48 |
| Towers/TowerManager.swift | +16 / −14 |
| Towers/TowerUpgrade.swift | +116 / −64 |
| Zombies/WaveDefinition.swift | +71 / −1 |
| Zombies/ZombieManager.swift | +84 / −35 |

## Work by Jira ticket

- **MH2D-14 Round-based difficulty curve:** wave sizes and spawn speed scale up each round (WaveDefinition.swift, ZombieManager.swift).
- **MH2D-15 Wave complete / next wave UI:** waves no longer start by themselves; the player starts each one (GameScene.swift, ZombieManager.swift).
- **MH2D-20 Enemy type variety:** runner and brute zombies with their own stats, damage resistances and wave mix (WaveDefinition.swift, ZombieManager.swift, DamageType.swift).
- **MH2D-30 Branching upgrade paths:** towers upgrade down branching paths, and sell value equals the money spent on upgrades (TowerUpgrade.swift, TowerManager.swift, GameScene.swift).
