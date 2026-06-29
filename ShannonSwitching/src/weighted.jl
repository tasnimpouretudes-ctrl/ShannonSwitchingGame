const TEAM_NAME::String = "Gruppe57"

function weighted_short(state::GameState)::Edge
    path = find_best_virtual_path(state)
    
    # Extraire uniquement les arêtes encore neutres sur ce chemin idéal
    neutral_on_path = filter(e -> e.state == :neutral, path)
    
    if !isempty(neutral_on_path)
        # Stratégie : Sécuriser l'arête la moins chère du chemin pour verrouiller le gain
        return sort(neutral_on_path, by = e -> e.weight)[1]
    else
        # Fallback : Si aucun chemin complet n'est visible, prendre l'arête neutre globale la moins chère
        all_neutral = filter(e -> e.state == :neutral, state.graph.edges)
        return sort(all_neutral, by = e -> e.weight)[1]
    end
end

# --- STRATÉGIE DE CUT POUR LE CONCOURS ---
function weighted_cut(state::GameState)::Edge
    path = find_best_virtual_path(state)
    
    neutral_on_path = filter(e -> e.state == :neutral, path)
    
    if !isempty(neutral_on_path)
        # Stratégie : Saboter le plan de Short en lui coupant l'arête la moins chère de son chemin
        return sort(neutral_on_path, by = e -> e.weight)[1]
    else
        # Fallback : Si Short n'a déjà plus de chemin, couper n'importe quelle arête neutre restante
        all_neutral = filter(e -> e.state == :neutral, state.graph.edges)
        return sort(all_neutral, by = e -> e.weight)[1]
    end
end
