"""
gives back the edges of G' = neutral edges + short edges.

"""
function gprime_edges(state::GameState)::Vector{Edge}
    filter(e -> e.state == :neutral || e.state == :short, state.graph.edges)
end

"""
BFS : gives back the nodes reachable from `src` using `edges`.

"""
function bfs_visited(edges::Vector{Edge}, src::Vertex)::Set{Int}
    visited = Set{Int}([src.id])
    queue = [src]
    while !isempty(queue)
        v = popfirst!(queue)
        for e in edges
            nbr = e.u.id == v.id ? e.v : e.v.id == v.id ? e.u : nothing
            if nbr !== nothing && !(nbr.id in visited)
                push!(visited, nbr.id)
                push!(queue, nbr)
            end
        end
    end
    return visited
end

"""
BFS : gives back a path from `s` to `t` using `edges`, or nothing if no path exists.

"""
function bfs_path(edges::Vector{Edge}, s::Vertex, t::Vertex)::Union{Vector{Edge}, Nothing}
    prev = Dict{Int, Union{Edge,Nothing}}(s.id => nothing)
    queue = [s]
    while !isempty(queue)
        v = popfirst!(queue)
        v.id == t.id && break
        for e in edges
            nbr = e.u.id == v.id ? e.v : e.v.id == v.id ? e.u : nothing
            if nbr !== nothing && !haskey(prev, nbr.id)
                prev[nbr.id] = e
                push!(queue, nbr)
            end
        end
    end
    !haskey(prev, t.id) && return nothing
    path, cur = Edge[], t.id
    while prev[cur] !== nothing
        e = prev[cur]
        push!(path, e)
        cur = e.u.id == cur ? e.v.id : e.u.id
    end
    return path
end

"""
Calculate a spanning tree (BFS) on `edges` starting from `src`.

"""
function spanning_tree(edges::Vector{Edge}, src::Vertex)::Vector{Edge}
    visited = Set{Int}([src.id])
    queue = [src]
    tree = Edge[]
    while !isempty(queue)
        v = popfirst!(queue)
        for e in edges
            nbr = e.u.id == v.id ? e.v : e.v.id == v.id ? e.u : nothing
            if nbr !== nothing && !(nbr.id in visited)
                push!(visited, nbr.id)
                push!(tree, e)
                push!(queue, nbr)
            end
        end
    end
    return tree
end

"""
Search for two spanning trees At, Bt in G' with disjoint neutral edges 

"""
function find_two_spanning_trees(state::GameState)
    gp  = gprime_edges(state)
    s, t = state.graph.s, state.graph.t

    bfs_visited(gp, s) |> v -> !(t.id in v) && return nothing

    At     = spanning_tree(gp, s)
    At_ids = Set(e.id for e in At)

    # Bt : arêtes Short (partagées) + arêtes neutres pas dans At
    bt_pool = filter(e -> e.state == :short || !(e.id in At_ids), gp)
    Bt      = spanning_tree(bt_pool, s)

    !(t.id in bfs_visited(Bt, s)) && return nothing
    return At, Bt
end

"""
Search for two cut sets At, Bt in G' with disjoint neutral edges.

"""
function find_two_cut_sets(state::GameState)
    gp  = gprime_edges(state)
    s, t = state.graph.s, state.graph.t

    p1 = bfs_path(gp, s, t)
    p1 === nothing && return nothing
    At = filter(e -> e.state == :neutral, p1)

    At_ids = Set(e.id for e in At)
    gp2 = filter(e -> !(e.id in At_ids), gp)  # removes neutral edges of At

    p2 = bfs_path(gp2, s, t)
    p2 === nothing && return nothing
    Bt = filter(e -> e.state == :neutral, p2)

    isempty(Bt) && return nothing
    return At, Bt
end



"""
Optimal short strategy
Short maintains two spanning trees At, Bt with disjoint neutral edges that connect s to t in G'.
After each Cut move, it repairs the threatened tree by replacing the removed edge with a neutral edge from the other tree if possible.
"""
function short_strategy(state::GameState)::Edge
    gp   = gprime_edges(state)
    s, t = state.graph.s, state.graph.t

    result = find_two_spanning_trees(state)

    # Fallback : no structure → neutral edge on an s-t path, else any neutral edge

    if result === nothing
        path = bfs_path(gp, s, t)
        if path !== nothing
            neu = filter(e -> e.state == :neutral, path)
            !isempty(neu) && return first(neu)
        end
        return first(filter(e -> e.state == :neutral, state.graph.edges))
    end

    At, Bt = result
    At_ids = Set(e.id for e in At)
    Bt_ids = Set(e.id for e in Bt)

    #   Last removed edge by Cut (a = virtual e* at first move)
    a = nothing
    for (player, edge) in reverse(state.history)
        player == :cut && (a = edge; break)
    end

    function repair(tree, pool_ids, removed)
        # Cs = component of s in tree \ {removed}, Ct = component of t
        remaining = filter(e -> e.id != removed.id, tree)
        cs = bfs_visited(remaining, s)
        ct = bfs_visited(remaining, t)
        for e in gp
            e.state == :neutral || continue
            e.id in pool_ids || continue
            if (e.u.id in cs && e.v.id in ct) || (e.u.id in ct && e.v.id in cs)
                return e
            end
        end
        return nothing
    end

    b = nothing
    if a === nothing
        # first move: simulate e* → repair At with a neutral edge from Bt
        # we choose the first neutral edge of Bt
        b = findfirst(e -> e.state == :neutral, Bt)
        b !== nothing && return Bt[b]
    elseif a.id in At_ids
        b = repair(At, Bt_ids, a)
    elseif a.id in Bt_ids
        b = repair(Bt, At_ids, a)
    else
        # a ∉ At ∪ Bt → neutral edge on an s-t path in G'
        path = bfs_path(gp, s, t)
        if path !== nothing
            neu = filter(e -> e.state == :neutral, path)
            !isempty(neu) && return first(neu)
        end
    end

    b !== nothing && return b

    # Fallback global
    path = bfs_path(gp, s, t)
    if path !== nothing
        neu = filter(e -> e.state == :neutral, path)
        !isempty(neu) && return first(neu)
    end
    return first(filter(e -> e.state == :neutral, state.graph.edges))
end


"""
Optimal cut strategy.
Cut maintains two sets At, Bt that cut all s-t paths.
After each Short move, it removes an edge from the other set on the threatened path.
"""
function cut_strategy(state::GameState)::Edge
    gp   = gprime_edges(state)
    s, t = state.graph.s, state.graph.t

    result = find_two_cut_sets(state)

    if result === nothing
        neu = filter(e -> e.state == :neutral, state.graph.edges)
        !isempty(neu) && return first(neu)
        return first(valid_moves(state))
    end

    At, Bt = result
    At_ids = Set(e.id for e in At)
    Bt_ids = Set(e.id for e in Bt)

    # Dernière arête prise par Short
    a = nothing
    for (player, edge) in reverse(state.history)
        player == :short && (a = edge; break)
    end

    function threatened_path(taken_set_ids, other_ids)
        # path s-t that has a but doesnt contain another neutral edge from the same set
        path = bfs_path(gp, s, t)
        path === nothing && return nothing
        # search for a neutral edge of the other set on this path
        for e in path
            e.state == :neutral && e.id in other_ids && return e
        end
        return nothing
    end

    b = nothing
    if a !== nothing && a.id in At_ids
        b = threatened_path(At_ids, Bt_ids)
        if b === nothing
            idx = findfirst(e -> e.state == :neutral, Bt)
            b = idx !== nothing ? Bt[idx] : nothing
        end
    elseif a !== nothing && a.id in Bt_ids
        b = threatened_path(Bt_ids, At_ids)
        if b === nothing
            idx = findfirst(e -> e.state == :neutral, At)
            b = idx !== nothing ? At[idx] : nothing
        end
    else
        # a ∉ At ∪ Bt → remove a neutral edge from At ∪ Bt
        for e in vcat(At, Bt)
            e.state == :neutral && return e
        end
    end

    b !== nothing && return b

    # Fallback global
    neu = filter(e -> e.state == :neutral, state.graph.edges)
    !isempty(neu) && return first(neu)
    return first(valid_moves(state))
end











function weighted_short(state)
    error("Weighted short strategy not implemented yet")
end

function weighted_cut(state)
    error("Weighted cut strategy not implemented yet")
end
