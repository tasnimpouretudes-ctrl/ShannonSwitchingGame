# ==============================================================================
# Graph Construction
# ==============================================================================

"""
    build_gprime(state)

Constructs the graph G′ used throughout the optimal strategy.
G' contains:
-neutral edges
-short owned 
Cut edges are excluded.
"""

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

# ==============================================================================
# Breadth-First Search
# ==============================================================================

"""
    bfs_path(start, goal, edges)

Computes a path between the vertices `start` and `goal`
using only the given edges.

Arguments
---------
- `start` : source vertex id.
- `goal`  : destination vertex id.
- `edges` : edge set defining the graph.

Returns
-------
A vector of edges representing the path from `start`
to `goal`.

If no path exists, an empty vector is returned.
"""
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

# ==============================================================================
# Connected Components
# ==============================================================================

"""
    reachable_vertices(start, edges)

Computes the connected component containing the vertex `start`
using only the supplied edges.

Arguments
---------
- `start` : starting vertex id.
- `edges` : edge set defining the graph.

Returns
-------
A set containing the ids of all reachable vertices.

This function is used in Algorithm 1 after removing one edge
from a spanning tree in order to obtain the two connected
components Cₛ and Cₜ.
"""
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

"""
    spanning_tree(edges, vertices)

Computes a spanning tree of the graph induced by `edges`
using Kruskal's algorithm.

Arguments
---------
- `edges`    : edges of G'
- `vertices` : graph vertices

Returns
-------
A set of edges forming a spanning tree.

Throws an error if the graph is disconnected.
"""

function spanning_tree(edges::Vector{Edge}, vertices::Vector{Vertex})::Vector{Edge}
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

"""
    fundamental_cycle(chord, tree)
 
Computes FC(chord, tree): the set of edges forming the unique cycle
in tree u {chord}.
 
This is found by running BFS from chord.u to chord.v inside `tree`,
then adding `chord` itself to close the cycle.
 
Arguments
---------
- `chord` : the chord edge (not in `tree`).
- `tree`  : a spanning tree as a Set{Edge}.
 
Returns
-------
A Set{Edge} containing the edges of the fundamental cycle.
"""

function fundamental_cycle(chord::Edge, T::Vector{Edge})::Set{Edge}
    path = bfs_path(chord.u.id, chord.v.id, T)
    cycle = Set(path)
    push!(cycle, chord)
    cycle
end

# ==============================================================================
# Kishi-Kajitani: two maximally distant spanning trees
# ==============================================================================
# Goal: find two spanning trees T1 and T2 of G' such that their NEUTRAL
# edges are disjoint. We do this by making T1 and T2 "maximally distant",
# meaning no swap can increase |T1 \ T2| any further.
#
# Key definitions from PDF
#   - A "chord" of tree T is an edge in G' that is NOT in T.
#   - A "common chord" is an edge that is a chord of BOTH T1 and T2
#     (i.e. it belongs to neither tree).
#   - The "fundamental cycle" FC(e, T) of a chord e w.r.t. tree T is
#     the set of edges forming the unique cycle in T u {e}.
#     In practice: it is the path from e.u to e.v inside T, plus e itself.
#
# Algorithm 3 (Kishi-Kajitani):
#   Repeat until no common chord can improve the distance:
#     For each common chord e, try to augment (swap edges to increase distance).
#
# Algorithm 4 (Augment):
#   Build layers L starting from FC(e, T1).
#   Alternate between T1 and T2 to extend the layers.
#   If a layer intersects the "other" tree → perform the swap (chain exchange).
 
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

function cut_partition(tree::Vector{Edge}, a::Edge, all_vertices::Vector{Vertex}, s::Int)
    tree_wo = [e for e in tree if e.id != a.id]
    Cs = reachable_vertices(s, tree_wo)
    Ct = setdiff(Set(v.id for v in all_vertices), Cs)
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
    isempty(moves) && return state.graph.edges[1]

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
        Cs, Ct = cut_partition(At, a, g.vertices, g.s.id)
        b = crossing_edge(Bt, Cs, Ct)
        return b === nothing ? first(moves) : b
    elseif a in Bt
        Cs, Ct = cut_partition(Bt, a, g.vertices, g.s.id)
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
