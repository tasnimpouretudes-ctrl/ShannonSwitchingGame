using Gtk4
using Cairo
using GtkObservables
using Random
include("game.jl")
include("strategies.jl")
const CANVAS_SIZE = 400
const NODE_RADIUS = 20

# ============================================
# FONCTIONS DE DESSIN
# ============================================

function draw_vertex(ctx, x, y, label)
    # Cercle gris
    set_source_rgb(ctx, 0.85, 0.85, 0.85)
    arc(ctx, x, y, NODE_RADIUS, 0, 2pi)
    fill(ctx)

    # Contour noir
    set_source_rgb(ctx, 0.0, 0.0, 0.0)
    set_line_width(ctx, 2.0)
    arc(ctx, x, y, NODE_RADIUS, 0, 2pi)
    stroke(ctx)

    # Le nom du noeud (s, a, b, t...)
    move_to(ctx, x - 5, y + 5)
    show_text(ctx, label)
end

function draw_edge(ctx, x1, y1, x2, y2, state)
    if state == :neutral
        set_source_rgb(ctx, 0.6, 0.6, 0.6)   # gris
    elseif state == :short
        set_source_rgb(ctx, 0.0, 0.0, 1.0)   # bleu
    elseif state == :cut
        set_source_rgb(ctx, 1.0, 0.0, 0.0)   # rouge
    end

    set_line_width(ctx, 3.0)
    move_to(ctx, x1, y1)
    line_to(ctx, x2, y2)
    stroke(ctx)
end

function compute_positions(graph::GameGraph)
    n = length(graph.vertices)
    positions = Dict{Int, Tuple{Float64,Float64}}()
    
    center_x, center_y = CANVAS_SIZE / 2, CANVAS_SIZE / 2
    radius = CANVAS_SIZE / 2 - 50

    for (i, v) in enumerate(graph.vertices)
        angle = 2π * (i - 1) / n
        x = center_x + radius * cos(angle)
        y = center_y + radius * sin(angle)
        positions[v.id] = (x, y)
    end

    return positions
end

function draw_graph(ctx, state::GameState, positions::Dict)
    # Fond blanc
    set_source_rgb(ctx, 1.0, 1.0, 1.0)
    paint(ctx)

    # 1. Dessiner toutes les arêtes d'abord
    for e in state.graph.edges
        x1, y1 = positions[e.u.id]
        x2, y2 = positions[e.v.id]
        draw_edge(ctx, x1, y1, x2, y2, e.state)
    end

    # 2. Dessiner tous les noeuds par-dessus
    for v in state.graph.vertices
        x, y = positions[v.id]
        label = string(v.id)
        draw_vertex(ctx, x, y, label)
    end
end

# ============================================
# DÉTECTION DES CLICS
# ============================================

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

function find_closest_edge(state::GameState, positions::Dict, click_x, click_y)
    best_edge = nothing
    best_distance = 15.0  # tolérance en pixels

    for e in state.graph.edges
        e.state != :neutral && continue  # on ignore les arêtes déjà jouées

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

# ============================================
# AFFICHAGE DU STATUT
# ============================================

function status_string(state::GameState)::String
    if !isnothing(state.winner)
        state.winner == :short ? "Short wins!" : "Cut wins!"
    elseif state.current_player == :short
        "Short's turn"
    else
        "Cut's turn"
    end
end

# ============================================
# FENÊTRE PRINCIPALE
# ============================================

function run_game()
    # Graphe aléatoire (6 noeuds, 8 arêtes)
    graph = random_graph(6, 5)

    # Positions calculées automatiquement
    positions = compute_positions(graph)

    state_obs = Observable(new_game(graph))

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

    # Dessine le graphe quand l'état change
    @guarded draw(canvas) do widget
        ctx = getgc(widget)
        draw_graph(ctx, state_obs[], positions)
    end

    # Met à jour le label quand l'état change
    on(state_obs) do state
        Gtk4.G_.set_label(label, status_string(state))
        draw(canvas)
    end

    # Gère les clics sur le plateau
    click = GtkGestureClick()
    push!(canvas, click)
    signal_connect(click, "pressed") do _ctrl, _n_press, x, y
        state = state_obs[]
        !isnothing(state.winner) && return

        clicked_edge = find_closest_edge(state, positions, x, y)
        isnothing(clicked_edge) && return

        make_move!(state, clicked_edge)
        notify(state_obs)
    end

    # Gère le bouton New Game
    signal_connect(btn, "clicked") do _
        state_obs[] = new_game(graph)
    end

    Gtk4.start_main_loop()
end