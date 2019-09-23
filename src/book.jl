#=
        Chess.jl: A Julia chess programming library
        Copyright (C) 2019 Tord Romstad

        This program is free software: you can redistribute it and/or modify
        it under the terms of the GNU Affero General Public License as
        published by the Free Software Foundation, either version 3 of the
        License, or (at your option) any later version.

        This program is distributed in the hope that it will be useful,
        but WITHOUT ANY WARRANTY; without even the implied warranty of
        MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
        GNU Affero General Public License for more details.

        You should have received a copy of the GNU Affero General Public License
        along with this program.  If not, see <https://www.gnu.org/licenses/>.
=#

using Dates

export BookEntry

export createbook


mutable struct BookEntry
    key::UInt64
    move::Int32
    elo::Int16
    oppelo::Int16
    wins::Int32
    draws::Int32
    losses::Int32
    year::Int16
    score::Float32
end

function BookEntry()
    BookEntry(0, 0, 0, 0, 0, 0, 0, 0, 0)
end


function randomentry()::BookEntry
    r = rand(1:3)
    BookEntry(rand(1:20),
              rand(101:120),
              rand(1800:2800),
              rand(1800:2800),
              r == 1 ? 1 : 0,
              r == 2 ? 1 : 0,
              r == 3 ? 1 : 0,
              rand(2000:2019),
              rand())
end


const ENTRY_SIZE = 34
const COMPACT_ENTRY_SIZE = 16


function entrytobytes(entry::BookEntry, compact::Bool)::Vector{UInt8}
    io = IOBuffer(UInt8[], read = true, write = true,
                  maxsize = compact ? COMPACT_ENTRY_SIZE : ENTRY_SIZE)
    write(io, entry.key)
    write(io, entry.move)
    write(io, entry.score)
    if !compact
        write(io, entry.elo)
        write(io, entry.oppelo)
        write(io, entry.wins)
        write(io, entry.draws)
        write(io, entry.losses)
        write(io, entry.year)
    end
    take!(io)
end


function entryfrombytes(bytes::Vector{UInt8}, compact::Bool)::BookEntry
    io = IOBuffer(bytes)
    result = BookEntry()
    result.key = read(io, UInt64)
    result.move = read(io, Int32)
    result.score = read(io, Float32)
    if !compact
        result.elo = read(io, Int16)
        result.oppelo = read(io, Int16)
        result.wins = read(io, Int32)
        result.draws = read(io, Int32)
        result.losses = read(io, Int32)
        result.year = read(io, Int16)
    end
    result
end


const SCORE_WHITE_WIN = 8.0
const SCORE_WHITE_DRAW = 4.0
const SCORE_WHITE_LOSS = 1.0
const SCORE_BLACK_WIN = 8.0
const SCORE_BLACK_DRAW = 5.0
const SCORE_BLACK_LOSS = 1.0
const SCORE_UNKNOWN = 0.0
const YEARLY_DECAY = 0.85
const HIGH_ELO_FACTOR = 6.0
const MAX_PLY = 60
const MIN_SCORE = 0
const MIN_GAME_COUNT = 5


function computescore(result, color, elo, date)::Float32
    base = if result == "1-0" && color == WHITE
        SCORE_WHITE_WIN
    elseif result == "1/2-1/2" && color == WHITE
        SCORE_WHITE_DRAW
    elseif result == "0-1" && color == WHITE
        SCORE_WHITE_LOSS
    elseif result == "0-1" && color == BLACK
        SCORE_BLACK_WIN
    elseif result == "1/2-1/2" && color == BLACK
        SCORE_BLACK_DRAW
    elseif result == "1-0" && color == BLACK
        SCORE_BLACK_LOSS
    else
        SCORE_UNKNOWN
    end
    base *
        max(1.0, 0.01 * HIGH_ELO_FACTOR * (2300 - elo)) *
        exp(log(YEARLY_DECAY) *
            (Dates.value(today() - date) / 365.25))
end


function mergeentries(entries::Vector{BookEntry})::BookEntry
    BookEntry(
        entries[1].key,
        entries[1].move,
        maximum(e -> e.elo, entries),
        maximum(e -> e.oppelo, entries),
        sum(e -> e.wins, entries),
        sum(e -> e.draws, entries),
        sum(e -> e.losses, entries),
        maximum(e -> e.year, entries),
        sum(e -> e.score, entries)
    )
end


function mergeable(e1::BookEntry, e2::BookEntry)::Bool
    e1.key == e2.key && e1.move == e2.move
end


function merge(e1::BookEntry, e2::BookEntry)::BookEntry
    BookEntry(e1.key, e1.move, max(e1.elo, e2.elo), max(e1.oppelo, e2.oppelo),
              e1.wins + e2.wins, e2.draws + e2.draws, e1.losses + e2.losses,
              max(e1.year, e2.year), e1.score + e2.score)
end


function compress!(entries::Vector{BookEntry})
    i = 1; j = 1; n = length(entries)
    iterations = 0
    while j + 1 < n
        for k ∈ j + 1 : n
            if !mergeable(entries[i], entries[k]) || k == n
                j = k
                i += 1
                entries[i] = entries[k]
                break
            end
            entries[i] = merge(entries[i], entries[k])
        end
    end
    entries[1 : i - 1]
end



function compareentries(e1::BookEntry, e2::BookEntry)::Bool
    e1.key < e2.key || (e1.key == e2.key && e1.move < e2.move)
end


function sortentries!(entries::Vector{BookEntry})
    sort!(entries, lt = compareentries)
end


function addgame!(entries::Vector{BookEntry}, g::SimpleGame)
    result = headervalue(g, "Result")
    if result ≠ "*"
        w = result == "1-0" ? 1 : 0
        d = result == "1/2-1/2" ? 1 : 0
        l = result == "0-1" ? 1 : 0
        welo = whiteelo(g) ≠ nothing ? whiteelo(g) : 0
        belo = blackelo(g) ≠ nothing ? blackelo(g) : 0
        date = dateplayed(g) ≠ nothing ? dateplayed(g) : Date(1900, 1, 1)
        year = Dates.year(date)
        wscore = computescore(result, WHITE, welo, date)
        bscore = computescore(result, BLACK, belo, date)

        tobeginning!(g)
        while !isatend(g) && g.ply <= MAX_PLY
            b = board(g)
            wtm = sidetomove(b) == WHITE
            m = nextmove(g)
            push!(entries, BookEntry(b.key, m.val,
                                     wtm ? welo : belo, wtm ? belo : welo,
                                     wtm ? w : l, d, wtm ? l : w, year,
                                     wtm ? wscore : bscore))
            forward!(g)
        end
    end
end


function addgamefile!(entries::Vector{BookEntry}, filename::String, count = 0)
    for g ∈ PGN.gamesinfile(filename)
        addgame!(entries, g)
        count += 1
        if count % 1000 == 0
            println("$count games added.")
        end
    end
    count
end


function createbook(filenames::Vararg{String})
    result = Vector{BookEntry}()
    count = 0
    for filename ∈ filenames
        count = addgamefile!(result, filename, count)
    end
    compress!(sortentries!(result))
end
