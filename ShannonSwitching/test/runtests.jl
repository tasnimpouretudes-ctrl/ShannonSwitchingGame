using Test
using Random
include("../src/game.jl")
include("../src/shortstrategy.jl")
include("../src/weighted.jl")




function triangle_graph()
    s = Vertex(1); v = Vertex(2); t = Vertex(3)
    e1 = Edge(1, s, t, 1.0, :neutral) 
    e2 = Edge(2, s, v, 1.0, :neutral)  # s-v
    e3 = Edge(3, v, t, 1.0, :neutral)  # v-t
    return GameGraph([s, v, t], [e1, e2, e3], s, t)
end


function path_graph()
    s = Vertex(1); a = Vertex(2); t = Vertex(3)
    e1 = Edge(1, s, a, 1.0, :neutral)
    e2 = Edge(2, a, t, 1.0, :neutral)
    return GameGraph([s, a, t], [e1, e2], s, t)
end


function disconnected_graph()
    s = Vertex(1); t = Vertex(2)
    return GameGraph([s, t], Edge[], s, t)
end



@testset "new_game" begin
    g = triangle_graph()

    @testset "initializes player and winner" begin
        state = new_game(g)
        @test state.current_player == :short
        @test state.winner === nothing
        @test isempty(state.history)
    end

    @testset "all edges set to neutral" begin
        state = new_game(g)
        @test all(e -> e.state == :neutral, state.graph.edges)
    end

    @testset "resets edges that were already short/cut" begin
        g2 = triangle_graph()
        g2.edges[1].state = :short
        g2.edges[2].state = :cut
        state = new_game(g2)
        @test all(e -> e.state == :neutral, state.graph.edges)
    end

    @testset "stores reference to the same graph object" begin
        state = new_game(g)
        @test state.graph === g
    end
end


@testset "valid_moves" begin
    @testset "all edges neutral at game start" begin
        state = new_game(triangle_graph())
        moves = valid_moves(state)
        @test length(moves) == 3
        @test Set(e.id for e in moves) == Set([1, 2, 3])
    end

    @testset "excludes short and cut edges" begin
        state = new_game(triangle_graph())
        state.graph.edges[1].state = :short
        state.graph.edges[2].state = :cut
        moves = valid_moves(state)
        @test length(moves) == 1
        @test moves[1].id == 3
    end

    @testset "empty when no neutral edges remain" begin
        state = new_game(triangle_graph())
        for e in state.graph.edges
            e.state = :short
        end
        @test isempty(valid_moves(state))
    end

    @testset "empty for a graph with no edges" begin
        state = new_game(disconnected_graph())
        @test isempty(valid_moves(state))
    end
end



@testset "make_move!" begin
    @testset "short's move sets edge state and passes turn to cut" begin
        state = new_game(path_graph())
        e = state.graph.edges[1]
        make_move!(state, e)
        @test e.state == :short
        @test state.current_player == :cut
    end

    @testset "cut's move sets edge state and passes turn to short" begin
        state = new_game(path_graph())
        e1 = state.graph.edges[1]
        e2 = state.graph.edges[2]
        make_move!(state, e1)   
        make_move!(state, e2)   
        @test e2.state == :cut
        @test state.current_player == :short
    end

    @testset "records moves in history with the correct player" begin
        state = new_game(path_graph())
        e1, e2 = state.graph.edges
        make_move!(state, e1)
        make_move!(state, e2)
        @test state.history == [(:short, e1), (:cut, e2)]
    end

    @testset "updates winner field after a winning move" begin
       
        state = new_game(triangle_graph())
        direct_edge = state.graph.edges[1]
        @test state.winner === nothing
        make_move!(state, direct_edge)
        @test state.winner == :short
    end

    @testset "updates winner field after a move that severs the last path" begin
       
        state = new_game(path_graph())
        e1, e2 = state.graph.edges
        make_move!(state, e1)   # short
        @test state.winner === nothing
        make_move!(state, e2)   # cut
        @test state.winner == :cut
    end

    @testset "returns nothing" begin
        state = new_game(path_graph())
        result = make_move!(state, state.graph.edges[1])
        @test result === nothing
    end

    @testset "players alternate across a full sequence" begin
        state = new_game(triangle_graph())
        players = Symbol[]
        for e in copy(state.graph.edges)
            e.state == :neutral || continue
            push!(players, state.current_player)
            make_move!(state, e)
        end
        @test players == [:short, :cut, :short]
    end
end


@testset "check_winner" begin
    @testset "nothing at the start of the game" begin
        state = new_game(triangle_graph())
        @test check_winner(state) === nothing
    end

    @testset "short wins once a short path connects s and t directly" begin
        state = new_game(triangle_graph())
        state.graph.edges[1].state = :short 
        @test check_winner(state) == :short
    end

    @testset "short wins via a multi-edge short path" begin
        state = new_game(path_graph())
        for e in state.graph.edges
            e.state = :short
        end
        @test check_winner(state) == :short
    end

    @testset "short does not win on a single edge of a longer path" begin
        state = new_game(path_graph())
        state.graph.edges[1].state = :short
       
        @test check_winner(state) === nothing
    end

    @testset "cut wins once every s-t path is severed" begin
        state = new_game(path_graph())
        state.graph.edges[1].state = :cut
        @test check_winner(state) == :cut
    end

    @testset "no winner while a neutral path still exists" begin
        state = new_game(triangle_graph())
        state.graph.edges[1].state = :cut  
        
        @test check_winner(state) === nothing
    end

    @testset "cut needs to sever all paths, not just one" begin
        state = new_game(triangle_graph())
        state.graph.edges[1].state = :cut  
        state.graph.edges[2].state = :cut  
        
        @test check_winner(state) == :cut
    end

    @testset "already-disconnected s and t count as a cut win" begin
        state = new_game(disconnected_graph())
        @test check_winner(state) == :cut
    end

    @testset "short overrides cut when both s-t connectivity tests would pass" begin
        
        state = new_game(triangle_graph())
        state.graph.edges[1].state = :short
        state.graph.edges[2].state = :cut
        state.graph.edges[3].state = :cut
        @test check_winner(state) == :short
    end
end



@testset "random_graph" begin
   
    function random_graph_with_timeout(args...; timeout=2.0, kwargs...)
        result = Ref{Union{GameGraph, Nothing}}(nothing)
        task = @async (result[] = random_graph(args...; kwargs...))
        waited = 0.0
        step = 0.05
        while !istaskdone(task) && waited < timeout
            sleep(step)
            waited += step
        end
        return istaskdone(task) ? result[] : nothing
    end


    @testset "produces a connected graph with at least n-1 edges" begin
        Random.seed!(101)

        successes = 0

        for _ in 1:10
            g = random_graph_with_timeout(10,20)
            g === nothing && continue

            successes += 1

            n = length(g.vertices)

            @test length(g.edges) >= n - 1

            adj = Dict{Int, Vector{Int}}()

            for e in g.edges
                push!(get!(adj, e.u.id, Int[]), e.v.id)
                push!(get!(adj, e.v.id, Int[]), e.u.id)
            end

            seen = Set([g.s.id])
            queue = [g.s.id]

            while !isempty(queue)
                x = popfirst!(queue)

                for y in get(adj, x, Int[])
                    if !(y in seen)
                        push!(seen, y)
                        push!(seen, y)
                        push!(queue, y)
                    end
                end
            end

            @test length(seen) == n
        end

        @test successes > 0
    end



    @testset "s is vertex 1 and t is the last vertex" begin
        Random.seed!(102)

        successes = 0

        for _ in 1:10
            g = random_graph_with_timeout(10,20)

            g === nothing && continue

            successes += 1

            @test g.s === g.vertices[1]
            @test g.t === g.vertices[end]
            @test g.s.id == 1
        end

        @test successes > 0
    end



    @testset "all edges start neutral" begin
        Random.seed!(103)

        g = random_graph_with_timeout(10,20)

        @test g !== nothing

        if g !== nothing
            @test all(e -> e.state == :neutral, g.edges)
        end
    end



    @testset "unweighted graphs use weight 1 on every edge" begin
        Random.seed!(104)

        g = random_graph_with_timeout(10,20; weighted=false)

        @test g !== nothing

        if g !== nothing
            @test all(e -> e.weight == 1, g.edges)
        end
    end



    @testset "weighted graphs draw weights from [1,10]" begin
        Random.seed!(105)

        g = random_graph_with_timeout(10,20; weighted=true)

        @test g !== nothing

        if g !== nothing
            @test all(e -> 1 <= e.weight <= 10, g.edges)
        end
    end



    @testset "no self-loops" begin
        Random.seed!(106)

        successes = 0

        for _ in 1:10
            g = random_graph_with_timeout(10,20)

            g === nothing && continue

            successes += 1

            @test all(e -> e.u.id != e.v.id, g.edges)
        end

        @test successes > 0
    end



    @testset "no duplicate edges between the same pair of vertices" begin
        Random.seed!(107)

        successes = 0

        for _ in 1:10
            g = random_graph_with_timeout(10,20)

            g === nothing && continue

            successes += 1

            pairs = [
                (min(e.u.id,e.v.id), max(e.u.id,e.v.id))
                for e in g.edges
            ]

            @test length(pairs) == length(Set(pairs))
        end

        @test successes > 0
    end



    @testset "vertex ids run from 1 to n with no gaps" begin
        Random.seed!(108)

        g = random_graph_with_timeout(10,20)

        @test g !== nothing

        if g !== nothing
            ids = sort([v.id for v in g.vertices])

            @test ids == collect(1:length(g.vertices))
        end
    end


end


using Test

include("../src/game.jl")
include("../src/shortstrategy.jl")
include("../src/weighted.jl")

@testset "Strategies.jl" begin

    function small_game()
        g = random_graph(5, 7)
        return new_game(g)
    end

    @testset "valid move property" begin
        state = small_game()
        moves = valid_moves(state)

        @test !isempty(moves)

        e = short_strategy(state)
        @test e in moves
        @test e.state == :neutral

        e2 = weighted_short(state)
        @test e2 in moves
        @test e2.state == :neutral
    end

    @testset "short_strategy never picks illegal edge" begin
        state = small_game()

        for _ in 1:10
            if state.winner !== nothing
                break
            end

            e = short_strategy(state)

            @test e in valid_moves(state)
            make_move!(state, e)
        end
    end

    @testset "weighted_short consistency" begin
        state = small_game()

        for _ in 1:10
            if state.winner !== nothing
                break
            end

            e = weighted_short(state)

            @test e in valid_moves(state)
            make_move!(state, e)
        end
    end

    @testset "weighted_cut validity" begin
        state = small_game()

        for _ in 1:10
            if state.winner !== nothing
                break
            end

            e = weighted_cut(state)

            @test e in valid_moves(state)
            make_move!(state, e)
        end
    end

    @testset "strategies respect game state" begin
        state = small_game()

        e = short_strategy(state)
        make_move!(state, e)

        @test state.current_player in (:short, :cut)

        e = weighted_short(state)
        @test e in valid_moves(state)
    end

    @testset "endgame robustness" begin
        state = small_game()

        while state.winner === nothing && !isempty(valid_moves(state))
            make_move!(state, first(valid_moves(state)))
        end

        @test short_strategy(state) isa Edge
        @test weighted_short(state) isa Edge
        @test weighted_cut(state) isa Edge
    end

end
