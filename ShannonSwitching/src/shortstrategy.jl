# =========================
# Basic graph helpers
# =========================

other_vertex(e::Edge, vid::Int) = e.u.id == vid ? e.v.id : e.u.id

function build_gprime(state::GameState)::Vector{Edge}
    [e for e in state.graph.edges if e.state != :cut]
end

function edge_adj(edges::Vector{Edge})
    adj = Dict{Int, Vector{Edge}}()
    for e in edges
        push!(get!(adj, e.u.id, Edge[]), e)
        push!(get!(adj, e.v.id, Edge[]), e)
    end
    adj
end

function bfs_path(s::Int, t::Int, edges::Vector{Edge})::Vector{Edge}
    adj = edge_adj(edges)
    q = [s]
    seen = Set([s])
    parent = Dict{Int, Tuple{Int, Edge}}()
    while !isempty(q)
        x = popfirst!(q)
        x == t && break
        for e in get(adj, x, Edge[])
            y = other_vertex(e, x)
            if !(y in seen)
                push!(seen, y)
                parent[y] = (x, e)
                push!(q, y)
            end
        end
    end
    t in seen || return Edge[]
    path = Edge[]
    cur = t
    while cur != s
        prev, e = parent[cur]
        push!(path, e)
        cur = prev
    end
    reverse!(path)
    path
end

function reachable_vertices(start::Int, edges::Vector{Edge})::Set{Int}
    adj = Dict{Int, Vector{Int}}()
    for e in edges
        push!(get!(adj, e.u.id, Int[]), e.v.id)
        push!(get!(adj, e.v.id, Int[]), e.u.id)
    end
    q = [start]
    seen = Set([start])
    while !isempty(q)
        x = popfirst!(q)
        for y in get(adj, x, Int[])
            if !(y in seen)
                push!(seen, y)
                push!(q, y)
            end
        end
    end
    seen
end

# =========================
# Spanning tree utilities
# =========================

function spanning_tree_from_order(edges::Vector{Edge}, vertices::Vector{Vertex})::Vector{Edge}
    idx = Dict(v.id => i for (i, v) in enumerate(vertices))
    uf = UnionFind(length(vertices))
    T = Edge[]
    for e in edges
        if union!(uf, idx[e.u.id], idx[e.v.id])
            push!(T, e)
            length(T) == length(vertices) - 1 && break
        end
    end
    length(T) == length(vertices) - 1 || error("No spanning tree exists")
    T
end

function fundamental_cycle(chord::Edge, T::Vector{Edge})::Set{Edge}
    path = bfs_path(chord.u.id, chord.v.id, T)
    cycle = Set(path)
    push!(cycle, chord)
    cycle
end

# =========================
# Kishi–Kajitani
# =========================

function augment!(T1::Vector{Edge}, T2::Vector{Edge}, e::Edge)::Bool
    par = Dict{Int, Int}()

    L = fundamental_cycle(e, T1)
    delete!(L, e)
    Lprev = Set{Edge}()
    k = 1

    while L != Lprev
        Lprev = copy(L)
        Talt = isodd(k) ? T2 : T1

        inter = [x for x in L if x in Talt]
        if !isempty(inter)
            f = first(inter)
            chain = [f]
            x = f
            while haskey(par, x.id)
                pid = par[x.id]
                px = nothing
                for z in Lprev
                    if z.id == pid
                        px = z
                        break
                    end
                end
                px === nothing && break
                x = px
                pushfirst!(chain, x)
            end

            newT1 = copy(T1)
            newT2 = copy(T2)

            deleteat!(newT1, findall(x -> x.id == e.id, newT1))
            push!(newT1, e)

            for (i, c) in enumerate(chain)
                if isodd(i)
                    deleteat!(newT1, findall(x -> x.id == c.id, newT1))
                    push!(newT2, c)
                else
                    deleteat!(newT2, findall(x -> x.id == c.id, newT2))
                    push!(newT1, c)
                end
            end

            empty!(T1); append!(T1, newT1)
            empty!(T2); append!(T2, newT2)
            return true
        end

        newL = copy(L)
        for g in L
            for f in fundamental_cycle(g, Talt)
                if !(f in L)
                    push!(newL, f)
                    haskey(par, f.id) || (par[f.id] = g.id)
                end
            end
        end
        L = newL
        k += 1
    end

    false
end

function maximally_distant_trees(gprime::Vector{Edge}, vertices::Vector{Vertex})
    T1 = spanning_tree_from_order(gprime, vertices)
    T2 = spanning_tree_from_order(reverse(gprime), vertices)

    changed = true
    while changed
        changed = false
        for e in gprime
            (e in T1 || e in T2) && continue
            if augment!(T1, T2, e)
                changed = true
                break
            end
        end
    end

    T1, T2
end

# =========================
# Short strategy
# =========================

function last_cut_edge(state::GameState)
    for i = length(state.history):-1:1
        p, e = state.history[i]
        if p == :cut
            return e
        end
    end
    nothing
end

function cut_partition(tree::Vector{Edge}, a::Edge, s::Int)
    tree_wo = [e for e in tree if e.id != a.id]
    Cs = reachable_vertices(s, tree_wo)
    allv = Set{Int}()
    for e in tree_wo
        push!(allv, e.u.id)
        push!(allv, e.v.id)
    end
    Ct = setdiff(allv, Cs)
    Cs, Ct
end

function crossing_edge(tree::Vector{Edge}, Cs::Set{Int}, Ct::Set{Int})
    for e in tree
        if e.state == :neutral
            if (e.u.id in Cs && e.v.id in Ct) || (e.u.id in Ct && e.v.id in Cs)
                return e
            end
        end
    end
    nothing
end

function short_strategy(state::GameState)::Edge
    moves = valid_moves(state)
    isempty(moves) && error("No valid moves")

    g = state.graph
    gprime = build_gprime(state)
    n = length(g.vertices)

    if length(gprime) < 2 * (n - 1)
        return first(moves)
    end

    At, Bt = maximally_distant_trees(gprime, g.vertices)

    if length(At) != n - 1 || length(Bt) != n - 1
        return first(moves)
    end

    neutral_At = Set(e for e in At if e.state == :neutral)
    neutral_Bt = Set(e for e in Bt if e.state == :neutral)

    if !isempty(intersect(neutral_At, neutral_Bt))
        return first(moves)
    end

    a = last_cut_edge(state)
    if a === nothing
        a = Edge(-1, g.s, g.t, 0.0, :cut)  # virtual edge for first move
    end

    if a in At
        Cs, Ct = cut_partition(At, a, g.s.id)
        b = crossing_edge(Bt, Cs, Ct)
        return b === nothing ? first(moves) : b
    elseif a in Bt
        Cs, Ct = cut_partition(Bt, a, g.s.id)
        b = crossing_edge(At, Cs, Ct)
        return b === nothing ? first(moves) : b
    else
        path = bfs_path(g.s.id, g.t.id, gprime)
        for e in path
            if e.state == :neutral
                return e
            end
        end
        return first(moves)
    end
end
