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
- **Tron Neon Aesthetic** — dark sci-fi look with glowing neon accents
- Surface: near-black with procedural cellular noise normal map (ice-rink texture relief)
- Rails: cyan neon emission (1.8x) with ridged brushed-metal normal map
- Puck: hot orange neon (2.5x), beveled profile, glowing core inlay disc, neon edge ring, surface normal map
- Paddles: red/cyan neon (2.0x), chamfered base, neon glow ring, detailed knob, glowing top cap, cellular grip normal map
- Markings: cyan unshaded emission, center circle + center line + Tron grid
- Goal inserts: recessed orange neon strips in rails + floor
- 3D depth: recessed surface, raised outer lip, bevel step, rail caps, under-table neon glow (desktop)
- Lighting: dim key + cyan spot + fill + rim (reduced on web)
- Glow, contrast 1.15, saturation 1.3

**Sound Design:**
- Procedural WAV synthesis, 44100 Hz stereo, 16-bit
- Multi-harmonic waveforms (sine + sawtooth + square), detuned harmonics for shimmer
- Comb filter reverb (dual taps) on hit, wall, goal, and game_over sounds
- Hit: sharp metallic impact (800Hz base, 4 harmonics, click transient, reverb)
- Wall bounce: pitch-dropping thud (200→80Hz) + crack + noise burst
- Goal: triumphant rising fanfare (523→1760Hz) + sub bass drop + shimmer
- Countdown: clean digital beep with 5ms attack, perfect fifth + octave
- Game over: major 7th chord (C-E-G-B) with octave doubling + sparkle shimmer + reverb
- Menu click: snappy two-tone pop (1200+1800Hz)

**Known Constraints:**
- Web export: SharedArrayBuffer headers needed → use itch.io or Cloudflare Pages
- Web runtime: conditional quality reduction (_is_web flag) for MSAA, shadows, particles, etc.
- Godot 4.6 API gaps: NO TONE_MAP_ACES/FILMIC/LINEAR, NO glow_bloom, NO ssao_enabled/ssr_enabled, NO TorusMesh.sections
- Use absf()/absi() instead of abs() on typed floats/ints

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
| 2026-02-22 | ✅ Procedural textures & normal maps: ice-rink surface, brushed-metal rails, grip paddles |
| 2026-02-22 | ✅ Upgraded puck geometry: beveled profile, glowing core inlay, neon edge ring |
| 2026-02-22 | ✅ Upgraded paddle geometry: chamfered base, neon glow ring, detailed knob, glowing cap |
| 2026-02-22 | ✅ Sound overhaul: 44100Hz stereo, multi-harmonic synthesis, sawtooth/square, comb reverb |

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