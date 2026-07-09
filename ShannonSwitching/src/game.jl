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
"""
new_game(g::GameGraph)::GameState:

Erstellt einen neuen Spielzustand für den Graphen g. 
Alle Kanten sind neutral, Short beginnt, kein Gewinner.
# Beispiel
```julia 
julia>

````
"""
function new_game(g::GameGraph)::GameState
    for i in g.edges 
        i.state = :neutral
    end 
    return GameState( g ,:short ,Vector{Tuple{Symbol, Edge}}(), nothing  )
end 
"""

# Beispiel
valid_moves(state::GameState)::Vector{Edge}: 
Gibt alle neutralen Kanten zurück, die der aktuelle Spieler wählen dar
```julia 
julia>

````
"""

function valid_moves(state::GameState)::Vector{Edge}
    v = []
    for i in state.graph.edges 
        if i.state=== :neutral
            push!(v,i)
        end 
    end 
    return v 
end 
"""
check_winner(state::GameState)::Union{Symbol, Nothing}: 
Gibt:shortzurück,fallsShorts beanspruchte Kanten einen s-t-Weg umfassen; 
gibt :cut zurück, falls im verbleibenden Graphen kein s-t-Weg mehr existiert; sonst nothing.


# Beispiel
```julia 
julia>

````
"""
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
"""
make_move!(state::GameState, e::Edge)::Nothing: Führt den Zug des aktuellen Spielers auf Kante e 
aus: Short setzt e.state = :short, Cut setzt e.state = :cut. Aktualisiert history,
wechselt den aktiven Spieler und prüft die Gewinnbedingung

# Beispiel
```julia 
julia>

````
"""
function make_move!(state::GameState, e::Edge)::Nothing
if e.state === :neutral
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
end 
   
    return nothing 
end
"""
random_graph(n::Int, m::Int; weighted=false)::GameGraph: 
Erzeugt einen zufälligen zu- sammenhängenden Graphen mit n Knoten und m Kanten. 
Knoten 1 ist die Quelle s, Kno- ten n ist das Ziel t. 
Im gewichteten Fall werden Kantengewichte gleichmäßig aus [1,10] gezogen.
# Beispiel

```julia 
julia>

````
"""
function random_graph(n::Int, m::Int; weighted=false)::GameGraph

    
    n = rand(4:10)

    
    max_extra = div(n*(n-1),2) - (n-1)

    possible_m = collect(n-1:n-1+max_extra)

    m = rand(possible_m)


    ve = Vertex[]
    e = Edge[]

    
    for i in 1:n
        push!(ve, Vertex(i))
    end


   
    for i in 2:n

        a = ve[i]
        b = ve[rand(1:i-1)]

        w = weighted ? rand(1:10) : 1

        push!(e,Edge(length(e)+1, a, b, w, :neutral))
    end



    
    if m > n-1

        existing = Set{Tuple{Int,Int}}()

        for edge in e
            push!(existing,(min(edge.u.id, edge.v.id),max(edge.u.id, edge.v.id)))
        end


        while length(e) < m

            a, b = rand(ve,2)

           
            if a.id == b.id
                continue
            end


            pair = (min(a.id,b.id),max(a.id,b.id))


           
            if pair ∉ existing

                push!(existing,pair)

                w = weighted ? rand(1:10) : 1

                push!(e,Edge(length(e)+1, a, b, w, :neutral))
            end
        end
    end


    return GameGraph(ve,e,ve[1],ve[end])
end
