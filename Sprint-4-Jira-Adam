# GitHub and Jira Report — Adam

- **Project:** 2D Zombie Tower Defense iOS Game
- **Repository:** [adamycoding/zombietowerdf](https://github.com/adamycoding/zombietowerdf)
- **Development date:** November 3, 2026
- **GitHub username:** adamycoding
- **Technology:** Swift, SpriteKit, and Xcode

## Summary

Today, I worked on the game’s round difficulty, wave completion screen, enemy variety, and branching tower upgrades. These features give players more control over wave progression and more choices when defending their base.

I implemented and manually tested the features locally in Xcode. Integration with the latest pulled changes still requires merge conflict resolution and another build.

## My Jira Tasks

| Issues | Task | Assignee | Implementation Status |
|---|---|---|---|
| MH2D-63, MH2D-64, MH2D-65 | Round-based difficulty curve | Adam | Implemented locally |
| MH2D-66, MH2D-67, MH2D-68 | Wave Complete / Next Wave UI | Adam | Implemented locally |
| MH2D-85, MH2D-86 | Enemy type variety | Adam | Implemented locally |
| MH2D-83, MH2D-84 | Branching upgrade paths | Adam | Implemented locally |

**Progress:** All four feature groups implemented locally. Verification of the merged project remains pending.

## Contributions

### Round-Based Difficulty Curve

I expanded the game to 15 rounds and moved the round definitions into `Rounds.json`. Each round defines its enemy groups, counts, and spawn interval.

I added easier breather rounds at rounds 5, 9, and 13 after harder rounds. The configuration lets me tune difficulty without changing the Swift spawning logic.

### Wave Complete / Next Wave UI

I added a Wave Complete screen showing the completed wave number and a $50 completion bonus. The reward is added once before the next wave starts.

I replaced automatic wave advancement with a Next Wave button. I also added Manage Towers so players can place and upgrade towers between waves.

### Enemy Type Variety

I added four zombie types with different health, speed, rewards, and appearances.

| Enemy Type | Health | Speed | Kill Reward |
|---|---:|---:|---:|
| Normal | 3 | 60 | $10 |
| Runner | 2 | 95 | $10 |
| Armored | 8 | 45 | $20 |
| Tank | 18 | 28 | $30 |

I added illustrated sprites based on the concept board, simple walking motion, hit flashes, and an ice tint. I also updated projectile aiming to account for different movement speeds.

### Branching Upgrade Paths

I added two upgrade paths for each tower, with two tiers per path.

| Tower | Path A | Path B |
|---|---|---|
| Soldier | Rapid Fire | Heavy Rounds |
| Sniper | Quick Reload | Longshot |
| Ice | Wide Freeze | Lasting Frost |

Purchasing the first tier locks that individual tower to its chosen path. The upgrade panel displays both paths, current tiers, prices, and stat changes. Purchases deduct currency and update the selected tower’s combat stats.

## Testing

I built and manually checked the features in Xcode, including round progression, wave rewards, enemy behavior, upgrade purchases, and path locking.

## Remaining Work

- Resolve conflicts from the latest pull.
- Build and test the combined project.
- Complete a full 15-round playthrough.
- Adjust difficulty and upgrade prices based on playtesting.
