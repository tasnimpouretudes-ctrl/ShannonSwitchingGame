using Gtk4
using Cairo
using GtkObservables
using Random

const CANVAS_SIZE = 400
const NODE_RADIUS = 20
const PANEL_WIDTH = 150

# ============================================
# FONCTIONS DE DESSIN
# ============================================

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

function draw_graph(ctx, state::GameState, positions::Dict)
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
        if v === state.graph.s
            draw_vertex(ctx, x, y, "s", :green)
        elseif v === state.graph.t
            draw_vertex(ctx, x, y, "t", :orange)
        else
            draw_vertex(ctx, x, y, string(v.id))
        end
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
    best_distance = 15.0

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

# ============================================
# AFFICHAGE DU STATUT ET DES POIDS
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

function weights_string(state::GameState)::String
    lines = ["Weights:"]
    for e in state.graph.edges
        push!(lines, "$(e.u.id) → $(e.v.id) : $(round(e.weight, digits=1))")
    end
    return join(lines, "\n")
end

# ============================================
# FENÊTRE PRINCIPALE
# ============================================

function run_game()
    # Les arguments n et m sont ignorés, random_graph les choisit aléatoirement
    function new_graph_and_positions(is_weighted::Bool)
        g = random_graph(0, 0, weighted=is_weighted)
        pos = compute_positions(g)
        return g, pos
    end

    graph_ref = Ref(random_graph(0, 0))
    positions_ref = Ref(compute_positions(graph_ref[]))
    state_obs = Observable(new_game(graph_ref[]))

    win = GtkWindow("Shannon-Switching Game", CANVAS_SIZE + PANEL_WIDTH, CANVAS_SIZE + 110)
    vbox = GtkBox(:v)
    hbox_main = GtkBox(:h)
    label = GtkLabel(status_string(state_obs[]))
    canvas = GtkCanvas(CANVAS_SIZE, CANVAS_SIZE)
    weights_label = GtkLabel("")
    weighted_check = GtkCheckButton("Weighted")
    btn = GtkButton("New Game")

    push!(win, vbox)
    push!(vbox, label)
    push!(hbox_main, canvas)
    push!(hbox_main, weights_label)
    push!(vbox, hbox_main)
    push!(vbox, weighted_check)
    push!(vbox, btn)

    show(win)

    @guarded draw(canvas) do widget
        ctx = getgc(widget)
        draw_graph(ctx, state_obs[], positions_ref[])
    end

    on(state_obs) do state
        @idle_add begin
            Gtk4.G_.set_label(label, status_string(state))
            is_weighted = Gtk4.G_.get_active(weighted_check)
            if is_weighted
                Gtk4.G_.set_label(weights_label, weights_string(state))
            else
                Gtk4.G_.set_label(weights_label, "")
            end
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
        is_weighted = Gtk4.G_.get_active(weighted_check)
        new_g, new_pos = new_graph_and_positions(is_weighted)
        graph_ref[] = new_g
        positions_ref[] = new_pos
        state_obs[] = new_game(new_g)
        notify(state_obs)
    end

    Gtk4.start_main_loop()
end
