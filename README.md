# OogwayHub

A Roblox executor hub for Anime Warriors III and other games.

## Structure
- `loader.lua` — one-liner users execute in their executor
- `sauce.lua` — main router, checks PlaceId and loads game script
- `games/AnimeWarriors3.lua` — full hub GUI for Anime Warriors III

## How it works
User runs loader.lua in their executor (Xeno, Solara, etc).
sauce.lua checks game.PlaceId and loads the matching game script from GitHub.
All scripts are client-side Lua for Roblox executor environments.

## Anime Warriors III (PlaceId: 10611639)
Features built so far:
- Auto Farm: world/enemy dropdown, teleports to nearest selected enemy type
- Enemy detection via UUID model names and `bounds` attribute
- Speed slider (16-500)
- Scan button to discover new enemy types per world
- Draggable GUI, side-panel dropdowns, OogwayHub ScreenGui naming

## Enemy detection
Enemies are UUID-named models in workspace with a `bounds` attribute.
First value of bounds identifies enemy type (e.g. 4 = Spirit, 24 = Deva).
Dead enemies have dead=true attribute.

## Known worlds and enemies (Rain Village mapped, others pending)
Rain Village: Spirit(4), Instinct(5.4), Enlightenment(7), Demon(9), Paper Angel(18), Deva(24)
Future City, Sand Village, Sky Island, Planet Nemak: pending mapping

## Todo
- Map remaining 4 worlds
- Auto Gauntlet (in-gauntlet auto farm works, join flow is manual)
- Jump power slider
- More games