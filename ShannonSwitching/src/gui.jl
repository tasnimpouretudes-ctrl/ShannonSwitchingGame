using Gtk4
using Cairo
using GtkObservables
using Random

const CANVAS_SIZE = 400
const NODE_RADIUS = 20

"""
    draw_vertex(ctx, x, y, label, color=:gray)

Zeichnet einen Knoten als Kreis.
- Farbe: Grün für s, Orange für t, Grau für alle anderen.
- arc: Zuerst füllen wir den Kreis (fill).
- Dann zeichnen wir den schwarzen Rand (stroke).
- Zum Schluss schreiben wir den Text in die Mitte.
"""
function draw_vertex(ctx, x, y, label, color=:gray)
    if color == :green
        set_source_rgb(ctx, 0.0, 0.8, 0.0)
    elseif color == :orange
        set_source_rgb(ctx, 1.0, 0.5, 0.0)
    else
        set_source_rgb(ctx, 0.85, 0.85, 0.85)
    end
    arc(ctx, x, y, NODE_RADIUS, 0, 2pi)
    fill(ctx)
    set_source_rgb(ctx, 0.0, 0.0, 0.0)
    set_line_width(ctx, 2.0)
    arc(ctx, x, y, NODE_RADIUS, 0, 2pi)
    stroke(ctx)
    set_source_rgb(ctx, 1.0, 1.0, 1.0)
    set_font_size(ctx, 16.0)
    move_to(ctx, x - 5, y + 6)
    show_text(ctx, label)
end

"""
    draw_edge(ctx, x1, y1, x2, y2, state)

Zeichnet eine Kante als Linie zwischen zwei Knoten.
- :neutral → Grau
- :short   → Blau (Short hat diese Kante beansprucht)
- :cut     → Rot  (Cut hat diese Kante entfernt)
- Linienbreite: 3 Pixel.
- move_to = Startpunkt, line_to = Endpunkt, stroke = zeichnen.
"""
function draw_edge(ctx, x1, y1, x2, y2, state)
    if state == :neutral
        set_source_rgb(ctx, 0.6, 0.6, 0.6)
    elseif state == :short
        set_source_rgb(ctx, 0.0, 0.0, 1.0)
    elseif state == :cut
        set_source_rgb(ctx, 1.0, 0.0, 0.0)
    end
    set_line_width(ctx, 3.0)
    move_to(ctx, x1, y1)
    line_to(ctx, x2, y2)
    stroke(ctx)
end

"""
    compute_positions(graph)

Berechnet die Positionen aller Knoten auf dem Canvas.
- n = Anzahl der Knoten.
- Dictionary: Knoten-ID → (x, y) Koordinaten.
- shuffle() mischt die Winkel → Knoten stehen bei jeder Partie anders.
- 2π / n verteilt die Knoten gleichmäßig auf einem Kreis.
- cos() und sin() berechnen die x- und y-Koordinaten.
"""
function compute_positions(graph::GameGraph)
    n = length(graph.vertices)
    positions = Dict{Int, Tuple{Float64,Float64}}()
    center_x, center_y = CANVAS_SIZE / 2, CANVAS_SIZE / 2
    radius = CANVAS_SIZE / 2 - 50
    angles = shuffle(collect(0:n-1)) .* (2π / n)
    for (i, v) in enumerate(graph.vertices)
        angle = angles[i]
        x = center_x + radius * cos(angle)
        y = center_y + radius * sin(angle)
        positions[v.id] = (x, y)
    end
    return positions
end

"""
    draw_graph(ctx, state, positions)

Hauptfunktion zum Zeichnen des Graphen.
- Zuerst Canvas weiß färben → alte Zeichnung löschen.
- Dann alle Kanten zeichnen (draw_edge).
- Dann alle Knoten darüber zeichnen (draw_vertex).
- Kanten zuerst → Knoten liegen darüber und bleiben sichtbar.
- s → grün, t → orange, andere → grau.
"""
function draw_graph(ctx, state::GameState, positions::Dict)
    set_source_rgb(ctx, 1.0, 1.0, 1.0)
    paint(ctx)
    for e in state.graph.edges
        x1, y1 = positions[e.u.id]
        x2, y2 = positions[e.v.id]
        draw_edge(ctx, x1, y1, x2, y2, e.state)
    end
    for v in state.graph.vertices
        x, y = positions[v.id]
        if v === state.graph.s
            draw_vertex(ctx, x, y, "s", :green)
        elseif v === state.graph.t
            draw_vertex(ctx, x, y, "t", :orange)
        else
            draw_vertex(ctx, x, y, string(v.id))
        end
    end
end

"""
    distance_to_segment(px, py, x1, y1, x2, y2)

Berechnet die Distanz zwischen einem Mausklick und einer Kante.
- Findet den nächsten Punkt auf der Kante zum Klick.
- Berechnet dann die euklidische Distanz.
- Wird von find_closest_edge benutzt.
"""
function distance_to_segment(px, py, x1, y1, x2, y2)
    dx = x2 - x1
    dy = y2 - y1
    if dx == 0 && dy == 0
        return sqrt((px - x1)^2 + (py - y1)^2)
    end
    t = ((px - x1) * dx + (py - y1) * dy) / (dx^2 + dy^2)
    t = clamp(t, 0.0, 1.0)
    closest_x = x1 + t * dx
    closest_y = y1 + t * dy
    return sqrt((px - closest_x)^2 + (py - closest_y)^2)
end

"""
    find_closest_edge(state, positions, click_x, click_y)

Sucht die Kante, auf die der Benutzer geklickt hat.
- best_edge = nothing → noch keine Kante gefunden.
- Maximale Distanz: 20 Pixel.
- Nur neutrale Kanten werden geprüft (andere wurden schon gespielt).
- Für jede neutrale Kante: Distanz berechnen → beste Kante speichern.
- Gibt die nächste Kante zurück, oder nothing wenn zu weit.
"""
function find_closest_edge(state::GameState, positions::Dict, click_x, click_y)
    best_edge = nothing
    best_distance = 20.0
    for e in state.graph.edges
        e.state != :neutral && continue
        x1, y1 = positions[e.u.id]
        x2, y2 = positions[e.v.id]
        d = distance_to_segment(click_x, click_y, x1, y1, x2, y2)
        if d < best_distance
            best_distance = d
            best_edge = e
        end
    end
    return best_edge
end

"""
    status_string(state)

Gibt den Text zurück, der oben im Fenster angezeigt wird.
- Gewinner vorhanden → "Short wins!" oder "Cut wins!"
- Kein Gewinner → "Short's turn" oder "Cut's turn"
"""
function status_string(state::GameState)::String
    if !isnothing(state.winner)
        state.winner == :short ? "Short wins!" : "Cut wins!"
    elseif state.current_player == :short
        "Short's turn"
    else
        "Cut's turn"
    end
end

"""
    new_graph_and_positions(is_weighted)

Wird bei New Game aufgerufen.
- Erstellt einen neuen zufälligen Graphen mit random_graph.
- Berechnet die Positionen der Knoten mit compute_positions.
- Gibt den Graphen und die Positionen zurück.
"""
function new_graph_and_positions(is_weighted::Bool)
    g = random_graph(0, 0, weighted=is_weighted)
    pos = compute_positions(g)
    return g, pos
end

"""
    run_game()

Hauptfunktion der GUI. Startet das Spiel.
- Erstellt den Graphen, die Positionen und den Spielzustand.
- Ref() = veränderbare Box für Graph und Positionen (nötig für New Game).
- Observable = Box für den Spielzustand → automatische Aktualisierung.
- @guarded draw: zeichnet den Graphen bei jedem Neuzeichnen.
- on(state_obs): nach jedem Zug → Label und Canvas automatisch aktualisieren.
- @idle_add: verhindert Gtk4-Abstürze bei der Aktualisierung.
- Klick-Handler: findet die angeklickte Kante → make_move! → notify.
- New Game Button: neuer Graph, neue Positionen, neue Partie.
- start_main_loop: hält das Fenster offen und wartet auf Eingaben.
"""
function run_game()
    graph_ref = Ref(random_graph(0, 0))
    positions_ref = Ref(compute_positions(graph_ref[]))
    state_obs = Observable(new_game(graph_ref[]))

    win = GtkWindow("Shannon-Switching Game", CANVAS_SIZE, CANVAS_SIZE + 80)
    vbox = GtkBox(:v)
    label = GtkLabel(status_string(state_obs[]))
    canvas = GtkCanvas(CANVAS_SIZE, CANVAS_SIZE)
    btn = GtkButton("New Game")

    push!(win, vbox)
    push!(vbox, label)
    push!(vbox, canvas)
    push!(vbox, btn)

    show(win)

    @guarded draw(canvas) do widget
        ctx = getgc(widget)
        draw_graph(ctx, state_obs[], positions_ref[])
    end

    on(state_obs) do state
        @idle_add begin
            Gtk4.G_.set_label(label, status_string(state))
            draw(canvas)
            return false
        end
    end

    click = GtkGestureClick()
    push!(canvas, click)
    signal_connect(click, "pressed") do _ctrl, _n_press, x, y
        state = state_obs[]
        !isnothing(state.winner) && return
        clicked_edge = find_closest_edge(state, positions_ref[], x, y)
        isnothing(clicked_edge) && return
        make_move!(state, clicked_edge)
        notify(state_obs)
    end

    signal_connect(btn, "clicked") do _
        new_g, new_pos = new_graph_and_positions(false)
        graph_ref[] = new_g
        positions_ref[] = new_pos
        state_obs[] = new_game(new_g)
        notify(state_obs)
    end

    Gtk4.start_main_loop()
end