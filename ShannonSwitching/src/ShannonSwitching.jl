module ShannonSwitching

include("game.jl")            #Datenstrukturen und Logik   
include("strategies.jl")      #Strategien für Short und Cut
include("gui.jl")             #Gtk4-Fenster + Cairo-Zeichnung

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

