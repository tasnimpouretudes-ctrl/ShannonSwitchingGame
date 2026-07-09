# ==============================================================================
# Graphaufbau
# ==============================================================================

"""
    build_gprime(state)

Konstruiert den Teilgraphen G′, der für die optimale Strategie verwendet wird.

Rolle
-----
G' ist der "aktive" Graph: er enthält alle Kanten, die noch relevant sind,
d.h. neutrale Kanten (noch nicht gespielt) und Short-beanspruchte Kanten
(bereits gesichert). Von Cut entfernte Kanten werden ausgeschlossen,
da sie dauerhaft aus dem Spiel sind.

Argumente
---------
- `state` : aktueller Spielzustand.

Rückgabe
--------
Ein Vector{Edge} mit allen Kanten, deren Zustand nicht :cut ist.

Beispiel
--------
Angenommen der Graph hat 3 Kanten:
  e1 (state = :neutral), e2 (state = :short), e3 (state = :cut)
→ build_gprime gibt [e1, e2] zurück.
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
# Breitensuche
# ==============================================================================

"""
    bfs_path(s, t, edges)

Berechnet einen Weg zwischen den Knoten `s` und `t`
unter Verwendung nur der angegebenen Kanten.

Rolle
-----
Wird an zwei Stellen verwendet:
  1. In `fundamental_cycle`: um den eindeutigen Weg zwischen den
     Endpunkten einer Sehne innerhalb eines Spannbaums zu finden.
  2. In `short_strategy`: um im Fallback-Fall eine neutrale Kante
     auf einem s-t-Weg in G' zu wählen.

Argumente
---------
- `s`     : ID des Startknotens.
- `t`     : ID des Zielknotens.
- `edges` : Kantenmenge, die den Graphen definiert.

Rückgabe
--------
Ein Vector{Edge} mit den Kanten des gefundenen Weges (in Reihenfolge).
Falls kein Weg existiert, wird ein leerer Vektor zurückgegeben.

Beispiel
--------
Graph: s --e1-- a --e2-- t
bfs_path(s.id, t.id, [e1, e2]) → [e1, e2]
bfs_path(s.id, t.id, [e1])     → []   (t nicht erreichbar)
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
# Zusammenhangskomponenten
# ==============================================================================

"""
    reachable_vertices(start, edges)

Berechnet alle Knoten, die von `start` aus über die gegebenen Kanten
erreichbar sind.

Rolle
-----
Wird in `cut_partition` verwendet: nachdem eine Kante `a` aus einem
Spannbaum At entfernt wurde, zerfällt At in zwei Teilbäume. Diese
Funktion bestimmt durch BFS, welche Knoten noch mit s verbunden sind
(Komponente Cs) bzw. mit t (Komponente Ct).

Argumente
---------
- `start` : ID des Startknotens.
- `edges` : Kantenmenge, die den Graphen definiert.

Rückgabe
--------
Eine Set{Int} mit den IDs aller erreichbaren Knoten.

Beispiel
--------
Baum: s --e1-- a --e2-- t, Kante e1 entfernt.
reachable_vertices(s.id, [e2]) → {a.id, t.id}
reachable_vertices(s.id, [])   → {s.id}
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

Berechnet einen Spannbaum des durch `edges` induzierten Graphen
mittels Kruskal-Algorithmus.

Rolle
-----
Liefert einen der beiden Ausgangsspannbäume At und Bt für den
Kishi-Kajitani-Algorithmus. Wird zweimal aufgerufen: einmal mit
`gprime` und einmal mit `reverse(gprime)`, um zwei verschiedene
Startbäume zu erhalten.

Argumente
---------
- `edges`    : Kanten von G', aus denen der Spannbaum gebaut wird.
- `vertices` : alle Knoten des Graphen (für den Union-Find-Index).

Rückgabe
--------
Ein Vector{Edge} mit genau n-1 Kanten, der einen Spannbaum bildet.
Wirft einen Fehler, falls der Graph nicht zusammenhängend ist.

Beispiel
--------
Graph mit 3 Knoten und Kanten e1=(1,2), e2=(2,3), e3=(1,3):
spanning_tree([e1,e2,e3], vertices) → [e1, e2]  (oder ähnlich, n-1=2 Kanten)
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
    fundamental_cycle(chord, T)

Berechnet FC(chord, T): die Menge der Kanten, die den eindeutigen Kreis
in T ∪ {chord} bilden.

Rolle
-----
Kernfunktion des Kishi-Kajitani-Algorithmus. Da T ein Spannbaum ist,
gibt es zwischen chord.u und chord.v genau einen Weg in T. Fügt man
chord hinzu, entsteht genau ein Kreis. Diese Funktion findet diesen
Kreis durch BFS und gibt alle beteiligten Kanten zurück.

Argumente
---------
- `chord` : eine Sehne (Kante, die nicht in T liegt).
- `T`     : ein Spannbaum als Vector{Edge}.

Rückgabe
--------
Eine Set{Edge} mit den Kanten des Fundamentalkreises
(inklusive chord selbst).

Beispiel
--------
Baum T: s --e1-- a --e2-- t
Sehne chord = e3 = (s, t)
→ fundamental_cycle(e3, T) = {e1, e2, e3}
"""
function fundamental_cycle(chord::Edge, T::Vector{Edge})::Set{Edge}
    path = bfs_path(chord.u.id, chord.v.id, T)
    cycle = Set(path)
    push!(cycle, chord)
    cycle
end

# ==============================================================================
# Kishi-Kajitani: zwei maximal distante Spannbäume
# ==============================================================================
# Ziel: zwei Spannbäume T1 und T2 von G' finden, deren NEUTRALE Kanten
# disjunkt sind. Dies erreichen wir, indem T1 und T2 "maximal distant"
# gemacht werden, d.h. kein Tausch kann |T1 \ T2| weiter erhöhen.
#
# Schlüsselbegriffe aus dem PDF:
#   - Eine "Sehne" von T ist eine Kante in G', die NICHT in T liegt.
#   - Eine "gemeinsame Sehne" liegt weder in T1 noch in T2.
#   - Der Fundamentalkreis FC(e, T) einer Sehne e bezüglich T ist
#     die Menge der Kanten, die den eindeutigen Kreis in T ∪ {e} bilden.
#
# Algorithmus 3 (Kishi-Kajitani):
#   Wiederholen bis keine gemeinsame Sehne die Distanz verbessern kann:
#     Für jede gemeinsame Sehne e, Augmentierung versuchen.
#
# Algorithmus 4 (Augment):
#   F = Front (nur neu erreichte Kanten der aktuellen Schicht)
#   V = alle bisher besuchten Kanten
#   Schichten F aufbauen, beginnend mit FC(e, T1).
#   Abwechselnd zwischen T1 und T2 wechseln.
#   Falls F eine Kante aus dem anderen Baum enthält → Tausch durchführen.

"""
    augment!(T1, T2, e)

Algorithmus 4 aus dem PDF: versucht d(T1, T2) = |T1 \\ T2| um 1 zu erhöhen,
indem die gemeinsame Sehne `e` (weder in T1 noch in T2) verwendet wird.

Rolle
-----
Kernstück des Kishi-Kajitani-Algorithmus. Baut schichtweise eine Front F auf,
beginnend mit FC(e, T1). Wechselt dabei abwechselnd zwischen T1 und T2.
Wichtig: nur die aktuelle Front F wird gegen den alternierenden Baum getestet,
nicht alle bisher besuchten Kanten V — sonst würden veraltete Kanten
fälschlicherweise einen Tausch auslösen (siehe PDF, Anhang A).
Falls F eine Kante f ∈ T1 ∩ T2 erreicht, wird die Tauschkette rekonstruiert
und der Tausch in-place durchgeführt.

Argumente
---------
- `T1`, `T2` : die zwei Spannbäume (werden bei Erfolg in-place verändert).
- `e`        : eine gemeinsame Sehne (in G', weder in T1 noch in T2).

Rückgabe
--------
`true` falls ein Tausch durchgeführt wurde, `false` sonst.

Beispiel
--------
T1 = {e1, e2}, T2 = {e1, e3}, gemeinsame Sehne e = e4
→ augment! findet eine Tauschkette und gibt true zurück.
→ T1 und T2 haben danach eine Kante mehr unterschiedlich.
"""
function augment!(T1::Vector{Edge}, T2::Vector{Edge}, e::Edge)::Bool
    par = Dict{Edge, Edge}()

    # F = Front (nur neu erreichte Kanten der aktuellen Schicht)
    # V = alle bisher besuchten Kanten
    F = fundamental_cycle(e, T1)
    delete!(F, e)
    V = copy(F)       #visited
    k = 1

    while !isempty(F)
        Talt = isodd(k) ? T2 : T1

        # Nur die aktuelle Front F gegen Talt testen, nicht alle von V
        inter = [x for x in F if x in Talt]

        if !isempty(inter)
            f = first(inter)
            chain = Edge[f]
            cur = f
            while haskey(par, cur)
                cur = par[cur]
                pushfirst!(chain, cur)
            end

            push!(T1, e)
            for (i, c) in enumerate(chain)
                if isodd(i)
                    filter!(x -> x.id != c.id, T1)
                    push!(T2, c)
                else
                    push!(T1, c)
                    filter!(x -> x.id != c.id, T2)
                end
            end
            return true
        end

        # Nächste Front F' aus Fundamentalkreisen der Kanten in F aufbauen,
        # nur Kanten hinzufügen, die noch nicht in V enthalten sind
        F_next = Set{Edge}()
        for g in F
            for f in fundamental_cycle(g, Talt)
                if f ∉ V
                    push!(F_next, f)
                    push!(V, f)
                    haskey(par, f) || (par[f] = g)
                end
            end
        end
        F = F_next
        k += 1
    end

    false
end

"""
    maximally_distant_trees(gprime, vertices)

Algorithmus 3 aus dem PDF: berechnet zwei maximal distante Spannbäume
T1 und T2 von G' mittels Kishi-Kajitani.

Rolle
-----
Liefert At und Bt für short_strategy. Falls G' zwei kantendisjunkte
Spannbäume besitzt, sind At und Bt nach Abschluss kantendisjunkt —
insbesondere disjunkt in den neutralen Kanten, was Short's Invariante
garantiert. Startet mit zwei verschiedenen Anfangsbäumen (einmal
gprime vorwärts, einmal rückwärts), um Kishi-Kajitani einen besseren
Ausgangspunkt zu geben.

Argumente
---------
- `gprime`   : Kanten von G' (neutral + Short-beansprucht).
- `vertices` : alle Knoten des Spielgraphen.

Rückgabe
--------
Ein Tupel (T1, T2), jeweils ein Vector{Edge}.

Beispiel
--------
G' hat 5 Knoten und 8 Kanten (genug für 2 Spannbäume):
→ maximally_distant_trees gibt (At, Bt) zurück mit |At ∩ Bt neutralen Kanten| = 0,
  falls Short eine Gewinnstrategie hat.
"""
function maximally_distant_trees(gprime::Vector{Edge}, vertices::Vector{Vertex})
    T1 = spanning_tree(gprime, vertices)
    T2 = spanning_tree(reverse(gprime), vertices)

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
# Shorts Strategie
# =========================

"""
    last_cut_edge(state)

Gibt die zuletzt von Cut entfernte Kante zurück, oder `nothing`
falls Cut noch keinen Zug gemacht hat.

Rolle
-----
Wird in short_strategy verwendet, um die Kante `a` zu bestimmen,
auf die Short reagieren muss (Reparaturstrategie).

Argumente
---------
- `state` : aktueller Spielzustand.

Rückgabe
--------
Die letzte von Cut gespielte Edge, oder `nothing`.

Beispiel
--------
history = [(:short, e1), (:cut, e2), (:short, e3), (:cut, e4)]
→ last_cut_edge gibt e4 zurück.
"""
function last_cut_edge(state::GameState)
    for i = length(state.history):-1:1
        p, e = state.history[i]
        if p == :cut
            return e
        end
    end
    nothing
end

"""
    cut_partition(tree, a, all_vertices, s)

Entfernt Kante `a` aus `tree` und bestimmt die zwei entstehenden
Zusammenhangskomponenten Cs (enthält s) und Ct (enthält t).

Rolle
-----
Nach dem Entfernen einer Kante `a` aus einem Spannbaum zerfällt
dieser in genau zwei Teilbäume. Diese Funktion bestimmt, welche
Knoten auf der s-Seite und welche auf der t-Seite liegen.
Das Ergebnis wird in `crossing_edge` verwendet, um eine Brückenkante
im anderen Baum zu finden.

Argumente
---------
- `tree`         : der Spannbaum (At oder Bt).
- `a`            : die zu entfernende Kante.
- `all_vertices` : alle Knoten des Graphen (damit keine Knoten verloren gehen).
- `s`            : ID des Quellknotens.

Rückgabe
--------
Ein Tupel (Cs, Ct) mit je einer Set{Int} der Knoten-IDs.

Beispiel
--------
Baum At: s --e1-- a --e2-- t, Kante e1 entfernt.
cut_partition(At, e1, vertices, s.id) → ({s.id}, {a.id, t.id})
"""
function cut_partition(tree::Vector{Edge}, a::Edge, all_vertices::Vector{Vertex}, s::Int)
    tree_wo = [e for e in tree if e.id != a.id]
    Cs = reachable_vertices(s, tree_wo)
    Ct = setdiff(Set(v.id for v in all_vertices), Cs)
    Cs, Ct
end

"""
    crossing_edge(tree, Cs, Ct)

Sucht die erste neutrale Kante in `tree`, die den Cs-Ct-Schnitt überquert.

Rolle
-----
Nach der Aufteilung in Cs und Ct durch `cut_partition` sucht diese
Funktion im anderen Baum (Bt wenn At gerissen wurde, At wenn Bt gerissen)
eine neutrale Kante, die die zwei Komponenten wieder verbindet.
Diese Kante ist Short's nächster Zug (Reparatur der Invariante).

Argumente
---------
- `tree` : der andere Spannbaum (Bt oder At).
- `Cs`   : Knoten-IDs der s-Komponente.
- `Ct`   : Knoten-IDs der t-Komponente.

Rückgabe
--------
Die erste neutrale Kante, die Cs und Ct verbindet, oder `nothing`.

Beispiel
--------
Bt = {e3=(s,b), e4=(b,t)}, Cs={s}, Ct={a,t}
→ crossing_edge gibt e3 zurück (s ∈ Cs, b ∈ Ct).
"""
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

"""
    short_strategy(state)

Berechnet Shorts optimalen Zug im ungewichteten Shannon-Switching-Spiel.

Rolle
-----
Hauptfunktion der optimalen Strategie für Short. Short hält zwei Spannbäume
At und Bt aufrecht, deren neutrale Kanten disjunkt sind. Nach jedem Cut-Zug
wird einer der Bäume "repariert": die gerissene Kante wird durch eine
Kante aus dem anderen Baum ersetzt, die den entstandenen Schnitt überbrückt.
Solange diese Invariante aufrechterhalten werden kann, hat Short eine
Gewinnstrategie.

Implementiert Algorithmus 1 aus dem PDF:

  1. G' aufbauen (neutrale + Short-beanspruchte Kanten).
  2. At und Bt berechnen (Kishi-Kajitani): zwei Spannbäume mit
     disjunkten neutralen Kanten.
  3. Letzte von Cut entfernte Kante `a` bestimmen.
     Beim ersten Zug gibt es noch keinen Cut-Zug: das PDF sagt,
     eine virtuelle Kante a* = (s,t) zu simulieren, die weder in At
     noch in Bt liegt → Fallback (neutrale Kante auf einem s-t-Weg).
  4. Reparaturstrategie:
     - a ∈ At → At − {a} in Cs und Ct aufteilen, neutrale Kante in Bt
               suchen, die den Schnitt überquert.
     - a ∈ Bt → symmetrisch.
     - sonst  → beliebige neutrale Kante auf einem s-t-Weg in G'.

Falls Short keine Gewinnstrategie hat (z.B. zu wenig Kanten in G'),
wird ein beliebiger gültiger Zug zurückgegeben.

Argumente
---------
- `state` : aktueller Spielzustand.

Rückgabe
--------
Die Edge, die Short als nächstes beanspruchen soll.

Beispiel
--------
G' hat zwei disjunkte Spannbäume At und Bt.
Cut hat zuletzt e2 ∈ At entfernt.
→ short_strategy findet eine neutrale Kante in Bt, die At repariert,
  und gibt diese zurück.
"""
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
        # Erster Zug: virtuelle Kante a* = (s,t) simulieren (liegt in keinem Baum)
        a = Edge(-1, g.s, g.t, 0.0, :cut)
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
