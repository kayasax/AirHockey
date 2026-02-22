# 🧠 AI Session Starter: airHockey

*Project memory file for AI assistant session continuity. Auto-referenced by custom instructions.*

---

## 📘 Project Context
**Project:** Air Hockey 3D
**Type:** Game Development (Godot 4 / GDScript)
**Purpose:** Professional-looking 3D air hockey game with AI opponent and local 2-player modes
**Status:** 🔄 MVP — core game built, needs Godot 4 install to test

**Core Technologies:**
- **Engine:** Godot 4.2+ (Forward Plus renderer)
- **Language:** GDScript
- **Rendering:** 3D PBR materials, ACES tonemapping, glow, SSAO, SSR
- **Physics:** Godot 3D physics (RigidBody3D, AnimatableBody3D, Area3D)

**Available AI Capabilities:**
- 🔧 MCP Servers: Standard set available
- 📚 Documentation: Microsoft docs MCP (not needed for this project type)
- 🔍 Tools: No game-engine-specific MCP servers

---

## 🎯 Current State
**Build Status:** 🔄 Code complete — awaiting Godot 4 installation for testing
**Key Achievement:** Full MVP codebase created from scratch
**Active Issue:** Godot 4 not installed on system — need to install before first run
**Game Modes:** VS AI (mouse control) + 2-Player Local (mouse + arrow keys)

**Architecture Highlights:**
- **Code-first approach:** Scene is built programmatically from `main.gd` (no complex .tscn editing needed)
- **Autoload singleton:** `GameManager` handles state, scores, game flow
- **Physics layers:** 4 layers (walls, puck, paddles, goals) with precise collision masks
- **Zero gravity:** Puck movement constrained to XZ plane via axis locking
- **AnimatableBody3D paddles:** Automatically push RigidBody3D puck on contact
- **AI with prediction:** Wall-bounce prediction, reaction-time simulation, difficulty scaling

---

## 🧠 Technical Memory

**Critical Discoveries:**
- Godot 4 .tscn files are text-based — can be created/edited outside the editor
- AnimatableBody3D is ideal for paddles (kinematic bodies that push rigid bodies)
- Zero gravity + axis_lock_linear_y keeps puck on the table without floor collider
- RigidBody3D continuous_cd enabled to prevent puck tunnelling at high speeds
- collision_layer uses bit-shifted values (layer 3 = `1 << 2` = 4)

**Physics Tuning:**
- Puck: mass=0.3, bounce=0.92, friction=0.02, linear_damp=0.25, max_speed=10
- Walls: bounce=1.0, friction=0.0 (perfect reflection)
- Paddles: LERP-based following (speed=18 for mouse, 3.2 for keyboard)
- AI: base_speed=2.8, max_speed=5.5, reaction_time=0.18s

**Visual Setup:**
- Table surface: dark teal (0, 0.12, 0.28), glossy (roughness=0.25)
- Rails: chrome (metallic=0.9, roughness=0.12)
- Puck: dark with orange emission glow (energy=1.8)
- Paddles: red/blue metallic with chrome ring detail
- Markings: white with subtle blue emission
- Lighting: directional + overhead spot + fill spot, ACES tonemapping, glow+SSAO+SSR

**Known Constraints:**
- Godot 4 must be installed before project can be run/tested
- No audio yet — sound effects are a future enhancement
- No particle effects yet — puck trail, goal celebrations planned
- AI wall-bounce prediction is simplified (may have edge cases)

---

## 🚀 Recent Achievements
| Date | Achievement |
|------|-------------|
| 2026-02-22 | ✅ Project initialized with session continuity infrastructure |
| 2026-02-22 | ✅ Chose Godot 4 as game engine (3D, professional quality) |
| 2026-02-22 | ✅ Created full project structure (project.godot, scenes, scripts) |
| 2026-02-22 | ✅ Built 3D table with PBR materials, rails, markings, goal slots |
| 2026-02-22 | ✅ Implemented puck physics (speed capping, axis locking, damping) |
| 2026-02-22 | ✅ Implemented mouse-controlled paddle (ray-plane intersection) |
| 2026-02-22 | ✅ Implemented AI opponent with prediction and difficulty scaling |
| 2026-02-22 | ✅ Built complete UI (main menu, score HUD, game over, countdown) |
| 2026-02-22 | ✅ Tron neon aesthetic: neon edge lines, grid surface, orange trail, boosted goal burst |

---

## 📋 Active Priorities
- [x] ✅ COMPLETED — Initial project setup & architecture
- [x] ✅ COMPLETED — Core gameplay (table, puck, paddles, goals)
- [x] ✅ COMPLETED — AI opponent
- [x] ✅ COMPLETED — UI system (menu, HUD, game over)
- [ ] 🔧 Install Godot 4 and test the game
- [ ] 🐛 Fix any runtime issues found during first test
- [ ] 🎵 Add sound effects (puck hits, goals, ambience)
- [ ] ✨ Add particle effects (puck trail, goal celebration)
- [ ] 🎮 Add difficulty selection in menu
- [ ] 📱 Add touch/gamepad support
- [ ] 🏆 Add win animations and polish

---

## 🔧 Development Environment
**Common Commands:**
- Open project: Launch Godot 4 → Import → select `project.godot` in `D:\WIP\airHockey`
- Run game: F5 in Godot editor (or Godot CLI: `godot --path . --main-scene scenes/main.tscn`)
- Install Godot: Download from https://godotengine.org/download/

**Key Files:**
- `project.godot` — Engine config, autoloads, physics, display settings
- `scenes/main.tscn` — Main scene (minimal, loads main.gd)
- `scripts/main.gd` — World builder, game flow, UI (central script)
- `scripts/game_manager.gd` — Autoload: state machine, scoring
- `scripts/puck.gd` — RigidBody3D puck behaviour
- `scripts/paddle.gd` — Human paddle control (mouse + keyboard)
- `scripts/ai_controller.gd` — AI opponent logic

**Setup Requirements:**
1. Install Godot 4.2+ (standard version, not .NET)
2. Open Godot → Import Project → browse to `D:\WIP\airHockey\project.godot`
3. Press F5 to run

---

*This file serves as persistent project memory for enhanced AI assistant session continuity.*