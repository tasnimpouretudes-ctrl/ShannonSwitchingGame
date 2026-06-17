mutable struct Vertex
    id::Int
end
mutable struct Edge
    id::Int
    u::Vertex
    v::Vertex
    weight::Float64
    state::Symbol # :neutral, :short, :cut
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
    history::Vector{Tuple{Symbol, Edge}}
    winner::Union{Symbol, Nothing}
end

function new_game(g::GameGraph)::GameState
    for i in g.edges 
        i.state = :neutral
    end 
    return GameState(graph = g ,current_player = :short ,history=Vector{Tuple{Symbol, Edge}}(),winner = nothing  )
end 

function valid_moves(state::GameState)::Vector{Edge}
    v = []
    for i in state.graph.edges 
        if i.state=== :neutral
            push!(v,i)
        end 
    end 
    return v 
end 
function check_winner(state::GameState)::Union{Symbol, Nothing}
    
    s = state.graph.s 
    Q =[s]
    
    visited =[s]
    while !isempty(Q)
        l =popfirst!(Q)
        if l === state.graph.t 
            
            return  :short 
            
        end 
        for i in state.graph.edges 
            if i.u == l && i.state == :short && !(i.v in visited )
                push!(Q,i.v)
                push!(visited,i.v)
            end 
            if i.v == l && i.state == :short && !(i.u in visited)
                push!(Q,i.u)
                push!(visited,i.u)
            end 
        end 
    end
    
    s = state.graph.s 
    Q =[s]
    
    visited =[]
    a = false 
    while !isempty(Q)
        l =popfirst!(Q)
        if l === state.graph.t 
            a = true 
             
            break
        end 
        for i in state.graph.edges 
            if i.u == l && i.state !== :cut && !(i.v in visited )
                push!(Q,i.v)
                push!(visited,i.v)
            end 
            if i.v == l && i.state !== :cut && !(i.u in visited)  
                push!(Q,i.u)
                push!(visited,i.u)
            end 
        end 
    end
    if a ==false 
        return :cut 
    end 
    return nothing
     
end 
function make_move!(state::GameState, e::Edge)::Nothing
    if state.current_player === :short 
        e.state= :short 
        push!(state.history,(:short , e))
        state.current_player = :cut
        

        
     
    elseif state.current_player === :cut 
            e.state= :cut 
            push!(state.history,(:cut , e))
            state.current_player = :short 
            
    end 
    state.winner = check_winner(state)
    return nothing 
end

function  random_graph(n::Int, m::Int; weighted=false)::GameGraph
    if m < n-1 
        return error("Diese Graph ist nicht zusammenhanged ")
    else 
        ve = []
        e = []
        for i in 1:n
            push!(ve,Vertex(i))
        end 
         k = ve
        for s in 1:n-1
            if s == 1 
                k = shuffle(k)
                a = pop!(k)
                b = pop!(k)
                if weighted === false 
                    push!(e,Edge(s,a,b,1,:neutral))
                else 
                    push!(e,Edge(s,a,b,rand(1:10),:neutral))
                end
            else 
                a = e[s-1].v
                k= shuffle(k)
                b = pop!(k)
                if weighted === false 
                    push!(e,Edge(s,a,b,1,:neutral))
                else 
                    push!(e,Edge(s,a,b,rand(1:10),:neutral))
                end
            end 
        end 
        if m >n-1
            
            for s in n:m
                # Fix duplikats ohne selfloops und selfloops ohne duplikats 
                # slefloop : (4,4)  duplikat: kante (5,2) schone exitiert und wir werden 
                # (5,2) nochmal als kante erstellen  
                c = shuffle(e)
                c_1 = pop!(c)
                c_2 = pop!(c)
                if weighted === false 
                    push!(e,Edge(s,c_1.u,c_2.v,1,:neutral))
                else 
                    push!(e,Edge(s,c_1.u,c_2.v,rand(1:10),:neutral))
                end
            
            
            end 
            
        end 



        
    end 
    return GameGraph(ve,e,ve[1],ve[end])
end 
