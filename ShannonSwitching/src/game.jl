const SHORT =:short 
const CUT =:cut

struct Vertex
    id::Int
end

mutable struct Edge 
    u::Vertex
    v::Vertex
    weight::Float64
    status::Symbol
end

mutable struct GameGraph
    vertices::Vector{Vertex}
    edges::Vector{Edge}
    s::Vertex
    t::Vertex
end

mutable struct GameState
    graph::GameGraph
    current_player::Symbol
    winner::Union{Symbol, Nothing}
    game_over::Bool
end

function new_game(graph::GameGraph)
    GameState(graph, SHORT, nothing, false)
end

function valid_moves(state::GameState)
    filter(e -> e.status == :unclaimed, state.graph.edges)
end

function make_move!(state::GameState, edge::Edge)
    @assert edge.status == :neutral

    if state.current_player == SHORT
        edge.status = :short
    else
        edge.status = :cut
    end

    state.winner = check_winner(state)
    
    if !isnothing(state.winner)
        state.game_over = true
    else
        state.current_player = 
            state.current_player == SHORT ? CUT : SHORT
    end
end

function check_winner(state::GameState)
    return nothing
end
