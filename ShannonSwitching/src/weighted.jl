const TEAM_NAME::String = "Gruppe57"

# =========================================================================
#
# Idee: Beide Strategien basieren auf Dijkstra.
#
# - Kanten, die Short bereits beansprucht hat, bekommen virtuelles Gewicht 0.0
#   (sie sind schon "kostenlos" für Short, da er sie bereits besitzt).
# - Kanten, die Cut entfernt hat, sind nicht mehr in G' (entfernt).
# - weighted_short: nimmt die erste neutrale Kante auf dem aktuell günstigsten
#   s-t-Weg.
# - weighted_cut: testet für jede neutrale Kante auf dem aktuell günstigsten
#   Weg, wie teuer der NEUE günstigste Weg wird, wenn diese Kante entfernt
#   wird, und entfernt die Kante mit dem größten neuen Kostenanstieg.


# =========================================================================
# Dijkstra-Hilfsfunktion
# =========================================================================

"""
    dijkstra_path(s_id, t_id, edges)

Berechnet den günstigsten s-t-Weg in einem Graphen, der durch `edges`
gegeben ist. Jede Kante hat ein Feld `weight` (Float64), das als
Distanz benutzt wird.

Arguments
---------
- `s_id`  : ID des Startknotens.
- `t_id`  : ID des Zielknotens.
- `edges` : Vektor von Kanten, die den Graphen bilden. Das Feld
            `weight` jeder Kante wird als (virtuelles) Gewicht benutzt.

Returns
-------
Ein Tuple `(weg, gesamtkosten)`:
- `weg`            : Vector{Edge}, die Kanten des günstigsten Weges (in Reihenfolge).
- `gesamtkosten`   : Float64, Summe der Gewichte auf dem Weg.

Falls kein Weg existiert, wird `(Edge[], Inf)` zurückgegeben.
"""
function dijkstra_path(s_id::Int, t_id::Int, edges::Vector{Edge})::Tuple{Vector{Edge}, Float64}

    # Adjazenzliste: Knoten-ID -> Liste von (Nachbar-ID, Kante)
    adj = Dict{Int, Vector{Tuple{Int, Edge}}}()
    for e in edges
        push!(get!(adj, e.u.id, Tuple{Int,Edge}[]), (e.v.id, e))
        push!(get!(adj, e.v.id, Tuple{Int,Edge}[]), (e.u.id, e))
    end

    # dist[knoten] = aktuell bekannte kürzeste Distanz von s_id
    dist   = Dict{Int, Float64}(s_id => 0.0)
    # parent[knoten] = (vorheriger Knoten, benutzte Kante) für Pfadrekonstruktion
    parent = Dict{Int, Tuple{Int, Edge}}()
    besucht = Set{Int}()

    # Einfache Dijkstra-Implementierung ohne Priority Queue
    # (für die hier üblichen Graphengrößen ausreichend schnell)
    while true

        # Knoten mit kleinster bekannter Distanz suchen, der noch nicht besucht ist
        aktueller_knoten = -1
        kleinste_distanz  = Inf

        for (knoten, d) in dist
            if !(knoten in besucht) && d < kleinste_distanz
                kleinste_distanz = d
                aktueller_knoten = knoten
            end
        end

        # Kein erreichbarer unbesuchter Knoten mehr -> fertig
        aktueller_knoten == -1 && break

        push!(besucht, aktueller_knoten)

        # Ziel erreicht -> wir können abbrechen (Distanz ist final)
        aktueller_knoten == t_id && break

        # Nachbarn relaxieren
        for (nachbar, kante) in get(adj, aktueller_knoten, Tuple{Int,Edge}[])

            neue_distanz = dist[aktueller_knoten] + kante.weight

            if !haskey(dist, nachbar) || neue_distanz < dist[nachbar]
                dist[nachbar]   = neue_distanz
                parent[nachbar] = (aktueller_knoten, kante)
            end

        end

    end

    # Kein Weg gefunden
    !haskey(dist, t_id) && return (Edge[], Inf)

    # Weg rekonstruieren durch Rückverfolgen der parent-Einträge
    weg = Edge[]
    knoten = t_id
    while knoten != s_id
        (vorheriger_knoten, kante) = parent[knoten]
        push!(weg, kante)
        knoten = vorheriger_knoten
    end
    reverse!(weg)

    return (weg, dist[t_id])

end


# =========================================================================
# Hilfsfunktion: G' mit virtuellen Gewichten aufbauen
# =========================================================================

"""
    build_weighted_gprime(state)

Baut G' (neutrale + Short-beanspruchte Kanten) auf und gibt eine Kopie
zurück, in der die Kanten von Short virtuelles Gewicht 0.0 haben.

Dadurch behandelt Dijkstra Shorts bereits beanspruchte Kanten als
"kostenlos", da Short sie schon besitzt.

Wichtig: Es werden NEUE Edge-Objekte mit denselben IDs erzeugt
(nur das `weight`-Feld wird für Short-Kanten überschrieben),
damit der echte Spielzustand nicht verändert wird.
"""
function build_weighted_gprime(state::GameState)::Vector{Edge}

    gprime = Edge[]

    for e in state.graph.edges

        e.state == :cut && continue  # entfernte Kanten gehören nicht zu G'

        if e.state == :short
            # virtuelles Gewicht 0.0 für bereits beanspruchte Kanten
            push!(gprime, Edge(e.id, e.u, e.v, 0.0, e.state))
        else
            # neutrale Kante: Originalgewicht behalten
            push!(gprime, Edge(e.id, e.u, e.v, e.weight, e.state))
        end

    end

    return gprime

end


# =========================================================================
# weighted_short
# =========================================================================

"""
    weighted_short(state)

Wettbewerbsstrategie für Short im gewichteten Spiel.

Idee: Short berechnet den aktuell günstigsten s-t-Weg in G' (wobei
bereits beanspruchte Kanten virtuelles Gewicht 0.0 haben) und beansprucht
die erste neutrale Kante auf diesem Weg.

Da Dijkstra die bereits gesicherten (kostenlosen) Kanten berücksichtigt,
passt sich der gewählte Weg bei jedem Aufruf automatisch an Cuts
vorherige Züge an.

Arguments
---------
- `state` : aktueller Spielzustand.

Returns
-------
Die Edge, die Short als nächstes beanspruchen sollte.
"""
function weighted_short(state::GameState)::Edge

    moves = valid_moves(state)
    isempty(moves) && error("No valid moves available")

    g      = state.graph
    gprime = build_weighted_gprime(state)

    weg, kosten = dijkstra_path(g.s.id, g.t.id, gprime)

    # Kein Weg mehr möglich -> Short kann nicht mehr gewinnen, beliebiger Zug
    isinf(kosten) && return first(moves)

    # Erste neutrale Kante auf dem günstigsten Weg suchen
    for e in weg
        if e.state == :neutral
            # Wir müssen die ECHTE Kante aus dem Spielzustand zurückgeben
            # (nicht die Kopie mit virtuellem Gewicht aus build_weighted_gprime)
            echte_kante = first(filter(x -> x.id == e.id, g.edges))
            return echte_kante
        end
    end

    # Alle Kanten auf dem Weg sind schon Short -> Weg ist bereits komplett,
    # beliebiger gültiger Zug
    return first(moves)

end


# =========================================================================
# weighted_cut
# =========================================================================

"""
    weighted_cut(state)

Wettbewerbsstrategie für Cut im gewichteten Spiel.

Idee: Cut berechnet zuerst den aktuell günstigsten s-t-Weg für Short.
Für jede neutrale Kante auf diesem Weg simuliert Cut, was passieren würde,
wenn er genau diese Kante entfernt: er berechnet den NEUEN günstigsten
Weg ohne diese Kante und vergleicht dessen Kosten.

Cut wählt die Kante, deren Entfernung die höchsten neuen Kosten erzeugt
(oder den Weg komplett zerstört).

Dies ist aufwändiger als nur die billigste Kante des aktuellen Weges zu
entfernen, simuliert aber tatsächlich die Konsequenz jedes Kandidaten-Zugs.

Arguments
---------
- `state` : aktueller Spielzustand.

Returns
-------
Die Edge, die Cut als nächstes entfernen sollte.
"""
function weighted_cut(state::GameState)::Edge

    moves = valid_moves(state)
    isempty(moves) && error("No valid moves available")

    g      = state.graph
    gprime = build_weighted_gprime(state)

    weg, kosten = dijkstra_path(g.s.id, g.t.id, gprime)

    # Kein Weg vorhanden -> Cut hat schon strukturell gewonnen, beliebiger Zug
    isinf(kosten) && return first(moves)

    # Neutrale Kanten auf dem aktuellen günstigsten Weg sammeln
    neutrale_kanten_im_weg = filter(e -> e.state == :neutral, weg)

    isempty(neutrale_kanten_im_weg) && return first(moves)

    beste_kante = nothing
    bester_neuer_kosten = -Inf

    for kandidat in neutrale_kanten_im_weg

        # G' ohne diese Kandidaten-Kante aufbauen
        gprime_ohne_kandidat = filter(e -> e.id != kandidat.id, gprime)

        neuer_weg, neue_kosten = dijkstra_path(g.s.id, g.t.id, gprime_ohne_kandidat)

        # Wenn das Entfernen dieser Kante s und t komplett trennt,
        # ist das der bestmögliche Zug -> sofort zurückgeben
        if isinf(neue_kosten)
            echte_kante = first(filter(x -> x.id == kandidat.id, g.edges))
            return echte_kante
        end

        if neue_kosten > bester_neuer_kosten
            bester_neuer_kosten = neue_kosten
            beste_kante = kandidat
        end

    end

    # Echte Kante aus dem Spielzustand zurückgeben (nicht die Kopie mit
    # virtuellem Gewicht)
    echte_kante = first(filter(x -> x.id == beste_kante.id, g.edges))
    return echte_kante

end
