## Game Manager — Autoload singleton
## Manages game state, scores, modes, and round flow.
extends Node

# ── Enums ──────────────────────────────────────────────
enum GameMode  { VS_AI, VS_PLAYER }
enum GameState { MENU, PLAYING, GOAL_SCORED, GAME_OVER }

# ── State ──────────────────────────────────────────────
var game_mode  : GameMode  = GameMode.VS_AI
var game_state : GameState = GameState.MENU
var score      : Array[int] = [0, 0]   # [player1, player2]
var winning_score : int = 7
var ai_difficulty : float = 0.7        # 0 = easy, 1 = hard

# ── Signals ────────────────────────────────────────────
signal score_changed(scores: Array[int])
signal game_state_changed(state: GameState)
signal goal_scored(scoring_player: int)

# ── Public API ─────────────────────────────────────────

func start_game(mode: GameMode) -> void:
	game_mode  = mode
	score      = [0, 0]
	game_state = GameState.PLAYING
	score_changed.emit(score)
	game_state_changed.emit(game_state)


func register_goal(scoring_player: int) -> void:
	score[scoring_player] += 1
	score_changed.emit(score)
	goal_scored.emit(scoring_player)

	if score[scoring_player] >= winning_score:
		game_state = GameState.GAME_OVER
	else:
		game_state = GameState.GOAL_SCORED
	game_state_changed.emit(game_state)


func resume_play() -> void:
	game_state = GameState.PLAYING
	game_state_changed.emit(game_state)


func return_to_menu() -> void:
	score      = [0, 0]
	game_state = GameState.MENU
	score_changed.emit(score)
	game_state_changed.emit(game_state)
