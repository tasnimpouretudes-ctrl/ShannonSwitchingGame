module ShannonSwitching

include("game.jl")
include("shortstrategy.jl")
include("weighted.jl")
include("gui.jl")

export Vertex
export Edge
export GameGraph
export GameState

export new_game
export valid_moves
export make_move!
export check_winner

export short_strategy
export cut_strategy

export weighted_short
export weighted_cut

export run_game

end