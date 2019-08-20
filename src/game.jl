using UUIDs

export Game, GameHeaders, GameNode, SimpleGame

export board, addcomment!, adddata!, addmove!, addnag!, addprecomment!, back!,
    comment, domove!, forward!, headervalue, isatbeginning, isatend, isleaf,
    precomment, printtree, removeallchildren!, removenode!, replacemove!,
    setheadervalue!, tobeginning!, tobeginningofvariation!, toend!, undomove!


"""
    GameHeader

Type representing a PGN header tag.

Contains `name` and `value` slots, both of which are strings.
"""
mutable struct GameHeader
    name::String
    value::String
end


"""
    GameHeaders

Type representing the PGN header tags for a game.

Contains a slot for each the seven required PGN tags `event`, `site`, `date`,
`round`, `white`, `black` and `result`, all of which are strings. Remaining
tags are included in the `othertags` slot, which contains a vector of
`GameHeader`s.
"""
mutable struct GameHeaders
    event::String
    site::String
    date::String
    round::String
    white::String
    black::String
    result::String
    fen::Union{String, Nothing}
    othertags::Vector{GameHeader}
end


function GameHeaders()
    GameHeaders("?", "?", "?", "?", "?", "?", "*", nothing, GameHeader[])
end


mutable struct GameHistoryEntry
    move::Union{Move, Nothing}
    undo::Union{UndoInfo, Nothing}
    key::UInt64
end


"""
    SimpleGame

A type representing a simple game, with no support for comments or variations.
"""
mutable struct SimpleGame
    headers::GameHeaders
    startboard::Board
    board::Board
    history::Vector{GameHistoryEntry}
    ply::Int
end


"""
    SimpleGame(startboard::Board=startboard())

Constructor that creates a `SimpleGame` from the provided starting position.
"""
function SimpleGame(startboard::Board=startboard())
    result = SimpleGame(GameHeaders(),
                        deepcopy(startboard),
                        deepcopy(startboard),
                        GameHistoryEntry[GameHistoryEntry(nothing, nothing,
                                                          startboard.key)],
                        1)
    if fen(startboard) ≠ START_FEN
        setheadervalue!(result, "FEN", fen(startboard))
    end
    result
end


"""
    SimpleGame(startfen::String)

Constructor that creates a `SimpleGame` from the position given by the provided
FEN string.
"""
function SimpleGame(startfen::String)
    SimpleGame(fromfen(startfen))
end


"""
    GameNode

Type representing a node in a `Game`.

Games can contain variations, so this type actually represents a node in a
tree-like structure.

A `GameNode` is a mutable struct with the following slots:

- `parent`: The parent `GameNode`, or `nothing` if this node is the root of the
  game.
- `board`: The board position at this node.
- `children`: A vector of `GameNode`s, the children of the current node. The
  first entry is the main continuation, the remaining entries are alternative
  variations.
- `data`: A `Dict{String, Any}` used to store information about this node. This
  is used for comments and numeric annotation glyphs, but can also be used to
  store other data.
- `id`: A UUID, used to look up this node in a `Game`, which contains a
  dictionary mapping ids to `GameNode`s.
"""
mutable struct GameNode
    parent::Union{GameNode, Nothing}
    board::Board
    children::Vector{GameNode}
    data::Dict{String, Any}
    id::UUID
end


function Base.show(io::IO, n::GameNode)
    print("GameNode($(fen(n.board)))")
end


function GameNode(parent::Union{GameNode, Nothing},
                  board::Board,
                  children::Vector{GameNode},
                  data::Dict{String, Any})
    GameNode(parent, board, children, data, uuid1())
end


"""
    GameNode(parent::GameNode, move::Move)

Constructor that creates a `GameNode` from a parent node and a move.

The move must be a legal move from the board at the parent node.
"""
function GameNode(parent::GameNode, move::Move)
    GameNode(parent,
             domove(parent.board, move),
             GameNode[],
             Dict{String, Any}())
end


"""
    GameNode(board::Board)

Constructor that creates a root `GameNode` with the given board.

The resulting `GameNode` has no parent. This constructor is used to create the
root node of a game.
"""
function GameNode(board::Board)
    GameNode(nothing, deepcopy(board), GameNode[], Dict{String, Any}())
end


"""
    Game

Type representing a chess game, with support for comments and variations.
"""
mutable struct Game
    headers::GameHeaders
    root::GameNode
    node::GameNode
    nodemap::Dict{UUID, GameNode}
end


"""
    Game(startboard::Board)

Constructor that creates a `Game` from the provided starting position.
"""
function Game(startboard::Board)
    root = GameNode(startboard)
    result = Game(GameHeaders(), root, root, Dict(root.id => root))
    if fen(startboard) ≠ START_FEN
        setheadervalue!(result, "FEN", fen(startboard))
    end
    result
end


"""
    Game(startboard::Board)

Constructor that creates a `Game` from the position given by the provided FEN
string.
"""
function Game(startfen::String)
    Game(fromfen(startfen))
end


"""
    Game()

Constructor that creates a new `Game` from the regular starting position.
"""
function Game()
    Game(startboard())
end


"""
    headervalue(ghs::GameHeaders, name::String)
    headervalue(g::SimpleGame, name::String)
    headervalue(g::Game, name::String)

Looks up the value for the header with the given name.

Returns the value as a `String`, or `nothing` if no header with the provided
name exists.
"""
function headervalue(ghs::GameHeaders, name::String)::Union{String, Nothing}
    if name == "Event"
        ghs.event
    elseif name == "Site"
        ghs.site
    elseif name == "Date"
        ghs.date
    elseif name == "Round"
        ghs.round
    elseif name == "White"
        ghs.white
    elseif name == "Black"
        ghs.black
    elseif name == "Result"
        ghs.result
    elseif name == "FEN" || name == "Fen"
        ghs.fen
    else
        for gh in ghs
            if gh.name == name
                return gh.value
            end
        end
        nothing
    end
end

function headervalue(g::SimpleGame, name::String)::Union{String, Nothing}
    headervalue(g.headers, name)
end

function headervalue(g::Game, name::String)::Union{String, Nothing}
    headervalue(g.headers, name)
end



"""
    setheadervalue!(ghs::GameHeaders, name::String, value::String)
    setheadervalue!(g::SimpleGame, name::String, value::String)
    setheadervalue!(g::Game, name::String, value::String)

Sets a header value, creating the header if it doesn't exist.
"""
function setheadervalue!(ghs::GameHeaders, name::String, value::String)
    if name == "Event"
        ghs.event = value
    elseif name == "Site"
        ghs.site = value
    elseif name == "Date"
        ghs.date = value
    elseif name == "Round"
        ghs.round = value
    elseif name == "White"
        ghs.white = value
    elseif name == "Black"
        ghs.black = value
    elseif name == "Result"
        ghs.result = value
    elseif name == "FEN" || name == "Fen"
        ghs.fen = value
    else
        for t in ghs.othertags
            if t.name == name
                t.value = value
                return
            end
        end
        push!(ghs.othertags, GameHeader(name, value))
    end
end

function setheadervalue!(g::SimpleGame, name::String, value::String)
    setheadervalue!(g.headers, name, value)
end

function setheadervalue!(g::Game, name::String, value::String)
    setheadervalue!(g.headers, name, value)
end


"""
    board(g::SimpleGame)
    board(g::Game)

The board position at the current node in a game.
"""
function board(g::SimpleGame)::Board
    g.board
end

function board(g::Game)::Board
    g.node.board
end



"""
    domove!(g::SimpleGame, m::Move)
    domove!(g::SimpleGame, m::String)
    domove!(g::Game, m::Move)
    domove!(g::Game, m::String)

Adds a new move at the current location in the game move list.

If the supplied move is a string, this function tries to parse the move as a UCI
move first, then as a SAN move.

If we are at the end of the game, all previous moves are kept, and the new move
is added at the end. If we are at any earlier point in the game (because we
have taken back one or more moves), the existing game continuation will be
deleted and replaced by the new move. All variations starting at this point in
the game will also be deleted. If you want to add the new move as a variation
instead, make sure you use the `Game` type instead of `SimpleGame`, and use
`addmove!` instead of `domove!`.

The move `m` is assumed to be a legal move. It's the caller's responsibility
to ensure that this is the case.
"""
function domove!(g::SimpleGame, m::Move)
    g.history[g.ply].move = m
    g.ply += 1
    deleteat!(g.history, g.ply:length(g.history))
    u = domove!(g.board, m)
    push!(g.history, GameHistoryEntry(nothing, u, g.board.key))
end

function domove!(g::SimpleGame, m::String)
    mv = movefromstring(m)
    if mv == nothing
        mv = movefromsan(board(g), m)
    end
    domove!(g, mv)
end

function domove!(g::Game, m::Move)
    removeallchildren!(g)
    addmove!(g, m)
end

function domove!(g::Game, m::String)
    removeallchildren!(g)
    addmove!(g, m)
end


"""
    addmove!(g::Game, m::Move)
    addmove!(g::Game, m::String)

Adds the move `m` to the game `g` at the current node.

If the supplied move is a string, this function tries to parse the move as a UCI
move first, then as a SAN move.

The move `m` must be a legal move from the current node board position. A new
game node with the board position after the move has been made is added to the
end of the current node's children vector, and that node becomes the current
node of the game.

The move `m` is assumed to be a legal move. It's the caller's responsibility
to ensure that this is the case.
"""
function addmove!(g::Game, m::Move)
    node = GameNode(g.node, m)
    push!(g.node.children, node)
    g.nodemap[node.id] = node
    g.node = node
end

function addmove!(g::Game, m::String)
    mv = movefromstring(m)
    if mv == nothing
        mv = movefromsan(board(g), m)
    end
    addmove!(g, mv)
end


"""
    isatbeginning(g::SimpleGame)::Bool
    isatbeginning(g::Game)::Bool

Return `true` if we are at the beginning of the game, and `false` otherwise.

We can be at the beginning of the game either because we haven't yet added
any moves to the game, or because we have stepped back to the beginning.

# Examples

```julia-repl
julia> g = SimpleGame();

julia> isatbeginning(g)
true

julia> domove!(g, "e4");

julia> isatbeginning(g)
false

julia> back!(g);

julia> isatbeginning(g)
true
```
"""
function isatbeginning(g::SimpleGame)::Bool
    g.history[g.ply].undo == nothing
end

function isatbeginning(g::Game)::Bool
    g.node.parent == nothing
end


"""
    isatend(g::SimpleGame)::Bool
    isatend(g::Game)::Bool

Return `true` if we are at the end of the game, and `false` otherwise.

# Examples

```julia-repl
julia> g = SimpleGame();

julia> isatend(g)
true

julia> domove!(g, "Nf3");

julia> isatend(g)
true

julia> back!(g);

julia> isatend(g)
false
```
"""
function isatend(g::SimpleGame)::Bool
    g.history[g.ply].move == nothing
end

function isatend(g::Game)
    isleaf(g.node)
end


"""
    back!(g::SimpleGame)
    back!(g::Game)

Go one step back in the game by retracting a move.

If we're already at the beginning of the game, the game is unchanged.
"""
function back!(g::SimpleGame)
    if !isatbeginning(g)
        undomove!(g.board, g.history[g.ply].undo)
        g.ply -= 1
    end
end

function back!(g::Game)
    if !isatbeginning(g)
        g.node = g.node.parent
    end
end


"""
    forward!(g::SimpleGame)
    forward!(g::Game)

Go one step forward in the game by replaying a previously retracted move.

If we're already at the end of the game, the game is unchanged. If the current
node has multiple children, we always pick the first child (i.e. the main line).
"""
function forward!(g::SimpleGame)
    if !isatend(g)
        domove!(g.board, g.history[g.ply].move)
        g.ply += 1
    end
end

function forward!(g::Game)
    if !isatend(g)
        g.node = first(g.node.children)
    end
end


"""
    tobeginning!(g::SimpleGame)
    tobeginning!(g::Game)

Go back to the beginning of a game by taking back all moves.

If we're already at the beginning of the game, the game is unchanged.
"""
function tobeginning!(g::SimpleGame)
    while !isatbeginning(g)
        back!(g)
    end
end

function tobeginning!(g::Game)
    while !isatbeginning(g)
        back!(g)
    end
end



"""
    toend!(g::SimpleGame)
    toend!(g::Game)

Go forward to the end of a game by replaying all moves, following the main line.

If we're already at the end of the game, the game is unchanged.
"""
function toend!(g::SimpleGame)
    while !isatend(g)
        forward!(g)
    end
end

function toend!(g::Game)
    while !isatend(g)
        forward!(g)
    end
end


"""
    tobeginningofvariation!(g::Game)

Go to the beginning of the variation containing the current node of the game.

Steps back up the game tree until we reach the point where the first child node
(i.e. the main line) is not contained in the current variation.
"""
function tobeginningofvariation!(g::Game)
    while !isatbeginning(g)
        n = g.node
        back!(g)
        if n ≠ first(g.node.children)
            break
        end
    end
end


"""
    isleaf(n::GameNode)::Bool

Tests whether a `GameNode` is a leaf, i.e. that it has no children.
"""
function isleaf(n::GameNode)::Bool
    isempty(n.children)
end


"""
    comment(n::GameNode)

The comment after the move leading to this node, or `nothing`.
"""
function comment(n::GameNode)::Union{String, Nothing}
    get(n.data, "comment", nothing)
end


"""
    precomment(n::GameNode)

The comment before the move leading to this node, or `nothing`.
"""
function precomment(n::GameNode)::Union{String, Nothing}
    get(n.data, "precomment", nothing)
end


"""
    removeallchildren!(g::Game, node::GameNode = g.node)

Recursively remove all children of the given node in the game.

If no node is supplied, removes the children of the current node.
"""
function removeallchildren!(g::Game, node::GameNode = g.node)
    while !isempty(node.children)
        c = popfirst!(node.children)
        removeallchildren!(g, c)
        delete!(g.nodemap, c.id)
    end
end


"""
    removenode!(g::Game, node::GameNode = g.node)

Remove a node (by default, the current node) in a `Game`, and go to the parent
node.

All children of the node are also recursively deleted.
"""
function removenode!(g::Game, node::GameNode = g.node)
    if node.parent ≠ nothing
        removeallchildren!(g, node)
        deleteat!(node.parent.children, ch .== node)
        delete!(g.nodemap, node.id)
        g.node = node.parent
    end
end


"""
    replacemove!(g::Game, m::Move)

Remove all children of the current node of the game, and add the new move.

The move `m` is alssumed to be a legal move. It's the callers responsibility to
ensure that this is the case.
"""
function replacemove!(g::Game, m::Move)
    removeallchildren!(g)
    addmove!(g, m)
end


"""
    adddata!(n::GameNode, key::String, value)

Add a piece of data to the given node's data dictionary.

This is a low-level function that is mainly used to add comments and NAGs, but
can also be used to add any type of custom annotation data to a game node.
"""
function adddata!(n::GameNode, key::String, value)
    n.data[key] = value
end


"""
    adddata!(g::Game, key::String, value)

Add a piece of data to the current game node's data dictionary.

This is a low-level function that is mainly used to add comments and NAGs, but
can also be used to add any type of custom annotation data to a game node.
"""
function adddata!(g::Game, key::String, value)
    adddata!(g.node, key, value)
end


"""
    removedata!(n::GameNode, key::String)

Remove a piece of data from the game node's data dictionary.

This is a low-level function that is mainly used to delete comments and NAGs.
"""
function removedata!(n::GameNode, key::String)
    delete!(n.data, key)
end


"""
    removedata!(n::GameNode, key::String)

Remove a piece of data from the current game node's data dictionary.

This is a low-level function that is mainly used to delete comments and NAGs.
"""
function removedata!(g::Game, key::String)
    removedata!(g.node, key)
end


"""
    addcomment!(g::Game, comment::String)

Adds a comment to the current game node.

In PGN and other text ouput formats, the comment is printed _after_ the move
leading to the node.
"""
function addcomment!(g::Game, comment::String)
    adddata!(g, "comment", comment)
end


"""
    addprecomment!(g::Game, comment::String)

Adds a pre-comment to the current game node.

In PGN and other text ouput formats, the comment is printed _before_ the move
leading to the node.
"""
function addprecomment!(g::Game, comment::String)
    adddata!(g, "precomment", comment)
end


"""
    addnag!(g::Game, nag::Int)

Adds a Numeric Annotation Glyph (NAG) to the current game node.
"""
function addnag!(g::Game, nag::Int)
    addata!(g, "nag", nag)
end


function isrepetitiondraw(g::SimpleGame)::Bool
    key = board(g).key
    rcount = 1
    for i in 2:2:board(g).r50
        if g.history[g.ply - i].key == key
            rcount += 1
            if rcount == 3
                return true
            end
        end
    end
    false
end

function isrepetitiondraw(g::Game)::Bool
    rcount = 1
    key = g.node.board.key
    n = g.node.parent
    while n != nothing
        if n.board.key == key
            rcount += 1
            if rcount == 3
                return true
            end
        end
        if n.board.r50 == 0
            break
        end
        n = n.parent
    end
    false
end


"""
    isdraw(g::SimpleGame)
    isdraw(g::Game)

Checks whether the current game position is drawn.
"""
function isdraw(g::SimpleGame)::Bool
    isdraw(board(g)) || isrepetitiondraw(g)
end

function isdraw(g::Game)::Bool
    isdraw(board(g)) || isrepetitiondraw(g)
end


"""
    ischeckmate(g::SimpleGame)
    ischeckmate(g::Game)

Checks whether the current game position is a checkmate.
"""
function ischeckmate(g::SimpleGame)::Bool
    ischeckmate(board(g))
end

function ischeckmate(g::Game)::Bool
    ischeckmate(board(g))
end


"""
    isterminal(g::SimpleGame)
    isterminal(g::Game)

Checks whether the current game position is terminal, i.e. mate or drawn.
"""
function isterminal(g::SimpleGame)
    isterminal(board(g)) || isrepetitiondraw(g)
end

function isterminal(g::Game)
    isterminal(board(g)) || isrepetitiondraw(g)
end