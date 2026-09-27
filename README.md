# Maze Generator for KOReader

A KOReader plugin that generates printable mazes as PDFs you can draw on —
built for e-ink tablets with a stylus, like the Kindle Scribe.

## Features

- **Sizes** from 10x10 up to 100x100
- **Difficulties**: Easy (classic perfect maze), Medium, Hard (adds loops so
  dead-end elimination won't save you)
- **Shapes**: Square, Circle, Heart, Star, Diamond, Triangle, Crescent,
  Cross — or **Random** for a surprise every time
- Every PDF has 2 pages: the maze, then the maze with the solution drawn in
- Start (solid square) and finish (hollow square) markers, readable on B&W e-ink
- Page sized to the Kindle Scribe screen

## Install

1. Download `maze.koplugin.zip` from the releases page
   (or clone this repo) — you'll get a folder named `maze.koplugin`.
2. Plug your jailbroken Kindle Scribe into your computer over USB.
3. Copy the `maze.koplugin` folder into the `koreader/plugins/` folder on
   the Scribe (top level of the USB drive). If you're updating from an older
   version, delete the old `maze.koplugin` folder first.
4. Eject the Scribe and (re)start KOReader.
5. Open the KOReader main menu → Tools → **Maze generator**.
6. Pick Size, Difficulty and Shape, then tap **Generate maze**.
7. The PDF is saved to `documents/Mazes/` on the Scribe. Open it from your
   Kindle library (stock reader) and draw on it with the stylus.

## How it works

- `maze.koplugin/maze_gen.lua` — pure-Lua maze generation (randomized
  depth-first carve), braiding for difficulty, shape masks, BFS solver.
  No KOReader dependencies; runs on Lua 5.1 (LuaJIT) through 5.4.
- `maze.koplugin/maze_pdf.lua` — hand-rolled minimal PDF writer
  (KOReader has no PDF-writing API, so the bytes are built by hand).
- `maze.koplugin/main.lua` — the KOReader plugin glue (menu, settings,
  file saving).
- `maze.koplugin/_meta.lua` — plugin metadata.

## Samples

The release zip's `samples/` folder has ready-made mazes. Send one to your
Scribe with Send to Kindle to try drawing on one right now.

Built with Milo, 2026.
