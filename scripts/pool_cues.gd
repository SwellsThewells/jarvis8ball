class_name PoolCues
extends RefCounted

# Cue skins, and the little save file that remembers which ones are owned.
# Each cue is built by PoolCueModel from the sections below: shaft, joint,
# rings, forearm, wrap and sleeve, each an art style ("p" is the pattern,
# "a"/"b"/"c" its colours, "m" metal, "r" roughness, "g" glow, "n" how many
# points, flames or stripes). A section can also be "flutes"/"twist" carved
# or cut into "facets". "bands" are raised metal rings, "gems" are stones set
# round the cue, and "helix", "studs", "fins", "gears" and "pommel" are parts
# that stand off it (see PoolCueModel.build). Price 0 means it is free.

const SAVE_PATH := "user://jarvis8pool.cfg"
# money for the bar: what's in your pocket the first time, and what a game pays
const START_CASH := 25
const WIN_CASH := 15
const LOSS_CASH := 5

const GOLD := {"p": "plain", "a": "d9a441", "m": 1.0, "r": 0.2}
const CHROME := {"p": "plain", "a": "c9ccd2", "m": 1.0, "r": 0.12}
const BLACK_CHROME := {"p": "plain", "a": "26272a", "m": 1.0, "r": 0.18}
const MAPLE := {"p": "wood", "a": "d9bf8c", "r": 0.25, "coat": 0.7}

const CUES := [
	{
		"id": "house", "name": "House Stick", "tag": "Classic",
		"blurb": "Off the wall rack. Maple shaft, rosewood butt, Irish linen wrap.",
		"price": 0, "tip": "2c4a6e", "ferrule": "e6e0cf",
		"shaft": {"p": "wood", "a": "c49a5e", "r": 0.3},
		"joint": {"p": "plain", "a": "b08a3e", "m": 0.9, "r": 0.3},
		"rings": {"p": "plain", "a": "6b5426", "m": 0.6, "r": 0.35},
		"forearm": {"p": "wood", "a": "3a1a0c", "r": 0.3},
		"wrap": {"p": "linen", "a": "1a1614"},
		"sleeve": {"p": "wood", "a": "2a1006", "r": 0.3},
	},
	{
		"id": "sovereign", "name": "Brass Sovereign", "tag": "Tournament",
		"blurb": "Four ivory points with gold veneers on a navy forearm.",
		"price": 0, "tip": "2b2f7a", "ferrule": "f6f0e2",
		"shaft": MAPLE, "joint": GOLD, "rings": GOLD,
		"forearm": {"p": "points", "a": "16283a", "b": "ece0bf", "c": "d9a441", "n": 4, "coat": 0.9},
		"wrap": {"p": "leather", "a": "2f5f7d"},
		"sleeve": {"p": "filigree", "a": "16283a", "b": "d9a441", "n": 5, "coat": 0.9},
		"bands": [1.36, 1.41],
	},
	{
		"id": "carbon", "name": "Carbon Pro", "tag": "Low deflection",
		"blurb": "Woven carbon from tip to bumper, with a red pin at every joint.",
		"price": 0, "tip": "3a0d0d", "ferrule": "141414",
		"shaft": {"p": "carbon", "a": "3b3e44"},
		"joint": CHROME,
		"rings": {"p": "plain", "a": "d0202a", "m": 0.4, "r": 0.25},
		"forearm": {"p": "carbon", "a": "34373c"},
		"wrap": {"p": "leather", "a": "121214"},
		"sleeve": {"p": "carbon", "a": "34373c"},
		"bands": [0.60, 1.20],
	},
	{
		"id": "hellfire", "name": "Hellfire", "tag": "Glows",
		"blurb": "Flames climbing out of a black butt. They glow in a dark room.",
		"price": 0, "tip": "1a1a1a", "ferrule": "0f0f0f",
		"shaft": {"p": "plain", "a": "141111", "r": 0.2, "coat": 1.0},
		"joint": BLACK_CHROME,
		"rings": {"p": "plain", "a": "ff7a1a", "m": 0.6, "r": 0.25, "g": 0.6},
		"forearm": {"p": "flames", "a": "0d0a09", "b": "ff4e10", "c": "ffd24a", "g": 2.2, "n": 5},
		"wrap": {"p": "leather", "a": "1a0f0c"},
		"sleeve": {"p": "flames", "a": "0d0a09", "b": "ff4e10", "c": "ffd24a", "g": 2.2, "n": 6},
	},
	{
		"id": "neon", "name": "Neon Rider", "tag": "Glows",
		"blurb": "Black lacquer wound with cyan and magenta tube light.",
		"price": 0, "tip": "0e3b4a", "ferrule": "101216",
		"shaft": {"p": "neon", "a": "0b0d12", "c": "2ef2ff", "g": 2.4, "n": 1.0, "coat": 1.0},
		"joint": {"p": "plain", "a": "3a3f48", "m": 1.0, "r": 0.2},
		"rings": {"p": "plain", "a": "2ef2ff", "g": 2.5},
		"forearm": {"p": "neon", "a": "0b0d12", "c": "ff3df0", "g": 2.6, "n": 3.0, "coat": 1.0},
		"wrap": {"p": "leather", "a": "0a0a0e"},
		"sleeve": {"p": "neon", "a": "0b0d12", "c": "2ef2ff", "g": 2.6, "n": 2.0, "coat": 1.0},
	},
	{
		"id": "galaxy", "name": "Event Horizon", "tag": "Glows",
		"blurb": "Nebula and starfield under deep clear coat, crystals round the sleeve.",
		"price": 0, "tip": "1b1d4a", "ferrule": "d8dcf0",
		"shaft": {"p": "galaxy", "a": "070920", "b": "3a1a78", "c": "1e6ab6", "g": 0.8, "coat": 1.0},
		"joint": {"p": "plain", "a": "b8bcc8", "m": 1.0, "r": 0.15},
		"rings": {"p": "plain", "a": "b8bcc8", "m": 1.0, "r": 0.15},
		"forearm": {"p": "galaxy", "a": "05061a", "b": "5a2aa8", "c": "1e8ad6", "g": 1.2, "coat": 1.0},
		"wrap": {"p": "leather", "a": "0b0b18"},
		"sleeve": {"p": "galaxy", "a": "05061a", "b": "a82a8a", "c": "1e8ad6", "g": 1.2, "coat": 1.0},
		"gems": {"color": "9fe8ff", "count": 8, "at": [1.375], "glow": 1.4},
	},
	{
		"id": "marble", "name": "Marble Royale", "tag": "Gold inlay",
		"blurb": "White marble shot through with gold, set with a ring of gold stones.",
		"price": 0, "tip": "2c3a5e", "ferrule": "f4efe2",
		"shaft": {"p": "wood", "a": "ebdcb8", "r": 0.2, "coat": 0.9},
		"joint": GOLD, "rings": GOLD,
		"forearm": {"p": "marble", "a": "efece6", "b": "7a7570", "c": "d9a441"},
		"wrap": {"p": "leather", "a": "efe9dc"},
		"sleeve": {"p": "marble", "a": "efece6", "b": "7a7570", "c": "d9a441"},
		"gems": {"color": "f1c24e", "count": 6, "at": [0.7575], "glow": 0.5},
		"bands": [1.10, 1.27],
	},
	{
		"id": "damascus", "name": "Damascus", "tag": "Forged steel",
		"blurb": "Folded steel butt with a knurled grip where the wrap would be.",
		"price": 0, "tip": "222222", "ferrule": "cfd2d6",
		"shaft": {"p": "plain", "a": "3a3d42", "m": 0.7, "r": 0.28},
		"joint": BLACK_CHROME,
		"rings": {"p": "plain", "a": "b06a3a", "m": 1.0, "r": 0.2},
		"forearm": {"p": "damascus", "a": "b8bec6"},
		"wrap": {"p": "knurl", "a": "9aa0a8"},
		"sleeve": {"p": "damascus", "a": "b8bec6"},
		"bands": [0.92],
	},
	{
		"id": "dragon", "name": "Dragon Scale", "tag": "Ruby set",
		"blurb": "Green scale armour and six rubies round the joint.",
		"price": 0, "tip": "3a1010", "ferrule": "efe6cf",
		"shaft": {"p": "wood", "a": "d9c29a", "r": 0.25, "coat": 0.8},
		"joint": GOLD, "rings": GOLD,
		"forearm": {"p": "scales", "a": "2aa05a", "b": "071a0e", "m": 0.6, "r": 0.25, "n": 10},
		"wrap": {"p": "leather", "a": "0c1a10"},
		"sleeve": {"p": "scales", "a": "2aa05a", "b": "071a0e", "m": 0.6, "r": 0.25, "n": 12},
		"gems": {"color": "e3122a", "count": 6, "at": [0.7575, 1.375], "glow": 0.7},
	},
	{
		"id": "molten", "name": "Molten Core", "tag": "Glows",
		"blurb": "Cooling rock over a core that never quite went out.",
		"price": 0, "tip": "1a1210", "ferrule": "1a1512",
		"shaft": {"p": "lava", "a": "181210", "b": "ff4a10", "c": "ffb040", "g": 0.9, "r": 0.5},
		"joint": {"p": "plain", "a": "2a2522", "m": 1.0, "r": 0.3},
		"rings": {"p": "plain", "a": "ff6a20", "g": 1.8},
		"forearm": {"p": "lava", "a": "1a1210", "b": "ff4a10", "c": "ffc040", "g": 2.4},
		"wrap": {"p": "leather", "a": "120c0a"},
		"sleeve": {"p": "lava", "a": "1a1210", "b": "ff4a10", "c": "ffc040", "g": 2.4},
	},
	{
		"id": "barber", "name": "Barber Pole", "tag": "Loud",
		"blurb": "Red and white all the way up. Nobody will lose track of it.",
		"price": 0, "tip": "8a1a1a", "ferrule": "f4f4f4",
		"shaft": {"p": "stripes", "a": "f2f2f2", "b": "d8202a", "c": "1a1a1a", "n": 2.0, "coat": 1.0},
		"joint": CHROME,
		"rings": {"p": "plain", "a": "d8202a", "r": 0.2},
		"forearm": {"p": "stripes", "a": "f2f2f2", "b": "d8202a", "c": "1a3a8a", "n": 3.0, "coat": 1.0},
		"wrap": {"p": "leather", "a": "f0f0f0"},
		"sleeve": {"p": "stripes", "a": "f2f2f2", "b": "1a3a8a", "c": "d8202a", "n": 3.0, "coat": 1.0},
	},
	{
		"id": "viper", "name": "Viper", "tag": "Emerald eyes",
		"blurb": "Diamond-back pattern with a pair of green stones for eyes.",
		"price": 0, "tip": "1a2a10", "ferrule": "e6e0cf",
		"shaft": {"p": "snake", "a": "a89a58", "b": "2a2412", "c": "6a8a30", "n": 4.0, "r": 0.3, "coat": 0.8},
		"joint": BLACK_CHROME,
		"rings": {"p": "plain", "a": "4a8a20", "m": 0.5, "r": 0.25},
		"forearm": {"p": "snake", "a": "d8c040", "b": "121210", "c": "4a8a20", "n": 6.0},
		"wrap": {"p": "leather", "a": "101010"},
		"sleeve": {"p": "snake", "a": "d8c040", "b": "121210", "c": "4a8a20", "n": 7.0},
		"gems": {"color": "30ff70", "count": 2, "at": [1.07], "glow": 1.6, "size": 0.0038},
	},
	{
		"id": "gilded", "name": "Gilded Age", "tag": "Engraved",
		"blurb": "Hand-chased gold scrollwork from the joint to the cap.",
		"price": 0, "tip": "2a1a0a", "ferrule": "f2e6c8",
		"shaft": MAPLE,
		"joint": GOLD,
		"rings": {"p": "plain", "a": "2a1a0a", "r": 0.3},
		"forearm": {"p": "filigree", "a": "d6a84a", "b": "5a3a12", "m": 1.0, "r": 0.22, "n": 6},
		"wrap": {"p": "leather", "a": "1a0e06"},
		"sleeve": {"p": "filigree", "a": "d6a84a", "b": "5a3a12", "m": 1.0, "r": 0.22, "n": 7},
		"bands": [0.90, 1.00, 1.33, 1.42],
	},
	{
		"id": "frost", "name": "Frostbite", "tag": "Glows",
		"blurb": "Glacier-white lacquer, blue ice veins and a ring of ice crystals.",
		"price": 0, "tip": "1f3f5f", "ferrule": "f4f8fc",
		"shaft": {"p": "plain", "a": "dfeaf2", "r": 0.15, "coat": 1.0},
		"joint": CHROME,
		"rings": {"p": "plain", "a": "9fe8ff", "g": 0.9},
		"forearm": {"p": "marble", "a": "e8f4ff", "b": "3a8ad0", "c": "9fe8ff", "g": 1.2},
		"wrap": {"p": "leather", "a": "cfe0ee"},
		"sleeve": {"p": "marble", "a": "e8f4ff", "b": "3a8ad0", "c": "9fe8ff", "g": 1.2},
		"gems": {"color": "9fe8ff", "count": 8, "at": [0.7575, 1.375], "glow": 1.5},
	},
	{
		"id": "bloodwood", "name": "Bloodwood Six", "tag": "Six points",
		"blurb": "Ebony points on bloodwood with ivory veneers. Old-school.",
		"price": 0, "tip": "2c2c4a", "ferrule": "efe6cf",
		"shaft": {"p": "wood", "a": "e0c898", "r": 0.25, "coat": 0.8},
		"joint": {"p": "plain", "a": "e8dcc0", "r": 0.25},
		"rings": {"p": "plain", "a": "c9ccd2", "m": 1.0, "r": 0.15},
		"forearm": {"p": "points", "a": "6a1010", "b": "141010", "c": "e8d9b0", "n": 6, "coat": 0.9},
		"wrap": {"p": "linen", "a": "3a0a0a"},
		"sleeve": {"p": "wood", "a": "141010", "r": 0.25, "coat": 0.9},
		"bands": [1.36],
	},
	{
		"id": "tiger", "name": "Tiger Maple", "tag": "Figured wood",
		"blurb": "Curly maple with stripes so deep they look carved.",
		"price": 0, "tip": "2c4a6e", "ferrule": "efe6cf",
		"shaft": {"p": "tiger", "a": "e0b870", "b": "7a4a18", "r": 0.22, "coat": 0.9},
		"joint": {"p": "plain", "a": "b08a3e", "m": 0.9, "r": 0.25},
		"rings": {"p": "plain", "a": "141010", "r": 0.25},
		"forearm": {"p": "tiger", "a": "c88a38", "b": "3a1a08", "r": 0.2, "coat": 1.0},
		"wrap": {"p": "leather", "a": "2a1608"},
		"sleeve": {"p": "tiger", "a": "c88a38", "b": "3a1a08", "r": 0.2, "coat": 1.0},
	},
	{
		"id": "serpent", "name": "Serpent King", "tag": "Coiled snake",
		"blurb": "A gold serpent wound round the butt, emerald eyes on the table.",
		"price": 0, "tip": "1a2a10", "ferrule": "efe6cf",
		"shaft": MAPLE, "joint": GOLD, "rings": GOLD,
		"forearm": {"p": "scales", "a": "1f5c3a", "b": "06130b", "m": 0.5, "r": 0.3, "n": 10},
		"wrap": {"p": "leather", "a": "0c1a10"},
		"sleeve": {"p": "scales", "a": "1f5c3a", "b": "06130b", "m": 0.5, "r": 0.3, "n": 12},
		"helix": {"from": 0.80, "to": 1.42, "turns": 2.6, "r": 0.0034, "tail": 0.2, "head": true,
			"eyes": "30ff70", "style": {"p": "scales", "a": "e0b040", "b": "5a3a08", "m": 0.9, "r": 0.2, "n": 6}},
	},
	{
		"id": "clockwork", "name": "Clockwork", "tag": "Brass gears",
		"blurb": "Walnut and brass, with toothed gears at the joint and copper lines between.",
		"price": 0, "tip": "3a2010", "ferrule": "efe6cf",
		"shaft": MAPLE,
		"joint": {"p": "plain", "a": "b5823a", "m": 1.0, "r": 0.3},
		"rings": {"p": "plain", "a": "b5823a", "m": 1.0, "r": 0.3},
		"forearm": {"p": "wood", "a": "4a2410", "r": 0.3, "coat": 0.8},
		"wrap": {"p": "leather", "a": "3a1c0c"},
		"sleeve": {"p": "filigree", "a": "b5823a", "b": "3a2008", "m": 1.0, "r": 0.3, "n": 5},
		"gears": [
			{"at": [0.79, 1.07], "teeth": 16, "size": 0.0055, "thick": 0.004, "color": "c8923e", "rough": 0.35},
			{"at": [1.30], "teeth": 12, "size": 0.0045, "thick": 0.005, "color": "b87333", "rough": 0.3},
		],
		"helix": {"from": 0.80, "to": 1.06, "turns": 0.5, "count": 2, "r": 0.0014, "color": "b87333", "rough": 0.25},
	},
	{
		"id": "maiden", "name": "Iron Maiden", "tag": "Spiked",
		"blurb": "Black leather bristling with steel spikes. Hold it by the grip.",
		"price": 0, "tip": "1a1a1a", "ferrule": "141414",
		"shaft": {"p": "plain", "a": "1a1a1c", "r": 0.25, "coat": 1.0},
		"joint": BLACK_CHROME, "rings": CHROME,
		"forearm": {"p": "leather", "a": "121214"},
		"wrap": {"p": "knurl", "a": "6a6e74"},
		"sleeve": {"p": "leather", "a": "101012"},
		"studs": [
			{"from": 1.31, "to": 1.44, "rows": 3, "per_row": 8, "size": 0.0075, "shape": "spike", "color": "d6d9de", "rough": 0.15},
			{"from": 0.86, "to": 1.02, "rows": 2, "per_row": 6, "size": 0.006, "shape": "spike", "color": "d6d9de", "rough": 0.15},
		],
		"bands": [0.80, 1.05],
	},
	{
		"id": "amethyst", "name": "Amethyst", "tag": "Cut crystal",
		"blurb": "A six-sided crystal butt lit from inside, with a cut stone on the end.",
		"price": 0, "tip": "2a1040", "ferrule": "f0e8ff",
		"shaft": {"p": "plain", "a": "e8e0f0", "r": 0.15, "coat": 1.0},
		"joint": CHROME,
		"rings": {"p": "plain", "a": "b36bff", "g": 1.2},
		"forearm": {"p": "marble", "a": "6a2aa8", "b": "2a0a4a", "c": "e0b0ff", "g": 0.9, "facets": 6},
		"wrap": {"p": "leather", "a": "1a0a28"},
		"sleeve": {"p": "marble", "a": "6a2aa8", "b": "2a0a4a", "c": "e0b0ff", "g": 0.9, "facets": 6},
		"pommel": {"shape": "gem", "color": "c080ff", "glow": 1.6, "size": 0.011},
	},
	{
		"id": "colonnade", "name": "Colonnade", "tag": "Fluted marble",
		"blurb": "Carved like a temple column: white marble, twelve flutes, gold at every joint.",
		"price": 0, "tip": "2c3a5e", "ferrule": "f4efe2",
		"shaft": {"p": "wood", "a": "efe3c8", "r": 0.2, "coat": 0.9},
		"joint": GOLD, "rings": GOLD,
		"forearm": {"p": "marble", "a": "f2efe8", "b": "8a8680", "c": "d9a441", "flutes": 12, "depth": 0.14},
		"wrap": {"p": "leather", "a": "f0ebe0"},
		"sleeve": {"p": "marble", "a": "f2efe8", "b": "8a8680", "c": "d9a441", "flutes": 12, "depth": 0.14},
		"bands": [0.79, 1.07, 1.31, 1.44],
	},
	{
		"id": "twisted", "name": "Twisted Oak", "tag": "Spiral carved",
		"blurb": "Dark oak turned into a tight spiral, like the leg of an old tavern chair.",
		"price": 0, "tip": "2c4a6e", "ferrule": "efe6cf",
		"shaft": MAPLE,
		"joint": {"p": "plain", "a": "2a1a10", "r": 0.3},
		"rings": {"p": "plain", "a": "c9a060", "m": 0.9, "r": 0.3},
		"forearm": {"p": "wood", "a": "5a3218", "r": 0.35, "coat": 0.8, "flutes": 5, "depth": 0.18, "twist": 0.9},
		"wrap": {"p": "linen", "a": "2a1a10"},
		"sleeve": {"p": "wood", "a": "5a3218", "r": 0.35, "coat": 0.8, "flutes": 5, "depth": 0.18, "twist": 0.7},
	},
	{
		"id": "hologram", "name": "Hologram", "tag": "Shifts colour",
		"blurb": "Foil that runs through the whole rainbow as it turns under the lights.",
		"price": 0, "tip": "2a2a3a", "ferrule": "e8eaf0",
		"shaft": {"p": "holo", "a": "b8bcc8", "g": 0.4},
		"joint": CHROME, "rings": CHROME,
		"forearm": {"p": "holo", "a": "c0c4d0", "g": 0.5},
		"wrap": {"p": "leather", "a": "1a1a20"},
		"sleeve": {"p": "holo", "a": "c0c4d0", "g": 0.5},
	},
	{
		"id": "mainframe", "name": "Mainframe", "tag": "Glows",
		"blurb": "Circuit board under glass, with traces that pulse while you hold it.",
		"price": 0, "tip": "0a2018", "ferrule": "0d1a14",
		"shaft": {"p": "plain", "a": "0d1a14", "r": 0.2, "coat": 1.0},
		"joint": {"p": "plain", "a": "3a3f48", "m": 1.0, "r": 0.2},
		"rings": {"p": "plain", "a": "2dffb0", "g": 2.0},
		"forearm": {"p": "circuit", "a": "0a2a1a", "b": "c9a24a", "c": "2dffb0", "g": 3.0},
		"wrap": {"p": "leather", "a": "08120c"},
		"sleeve": {"p": "circuit", "a": "0a2a1a", "b": "c9a24a", "c": "2dffb0", "g": 3.0},
		"bands": [0.79, 1.07],
	},
	{
		"id": "hive", "name": "Hive", "tag": "Glows",
		"blurb": "Gold honeycomb with light pooling in every cell, amber set at the joint.",
		"price": 0, "tip": "3a2208", "ferrule": "efe0c0",
		"shaft": {"p": "wood", "a": "e6c890", "r": 0.25, "coat": 0.8},
		"joint": GOLD, "rings": GOLD,
		"forearm": {"p": "hex", "a": "3a2208", "b": "e8b030", "c": "ffb020", "g": 1.6, "n": 10},
		"wrap": {"p": "leather", "a": "2a1806"},
		"sleeve": {"p": "hex", "a": "3a2208", "b": "e8b030", "c": "ffb020", "g": 1.6, "n": 12},
		"gems": {"color": "ffa020", "count": 6, "at": [0.7575], "glow": 1.2},
	},
	{
		"id": "camo", "name": "Jungle Camo", "tag": "Camouflage",
		"blurb": "Four-colour woodland camo, matt all over. Good luck finding it on the rack.",
		"price": 0, "tip": "2a3a1a", "ferrule": "3a3a2a",
		"shaft": {"p": "camo", "a": "4a5a2a", "b": "2a3a1a", "c": "7a6a40", "r": 0.7},
		"joint": BLACK_CHROME,
		"rings": {"p": "plain", "a": "2a3a1a", "r": 0.6},
		"forearm": {"p": "camo", "a": "4a5a2a", "b": "2a3a1a", "c": "7a6a40", "r": 0.7},
		"wrap": {"p": "linen", "a": "2a3020"},
		"sleeve": {"p": "camo", "a": "4a5a2a", "b": "2a3a1a", "c": "7a6a40", "r": 0.7},
	},
	{
		"id": "checkered", "name": "Checkered Flag", "tag": "Race day",
		"blurb": "Chequered from the joint to the cap, with polished chrome between.",
		"price": 0, "tip": "121212", "ferrule": "f4f4f4",
		"shaft": {"p": "plain", "a": "f4f4f4", "r": 0.15, "coat": 1.0},
		"joint": CHROME, "rings": CHROME,
		"forearm": {"p": "check", "a": "f4f4f4", "b": "121212", "n": 8, "coat": 1.0},
		"wrap": {"p": "leather", "a": "121212"},
		"sleeve": {"p": "check", "a": "f4f4f4", "b": "121212", "n": 8, "coat": 1.0},
		"bands": [0.79, 1.07, 1.31],
	},
	{
		"id": "zebra", "name": "Zebra", "tag": "Animal print",
		"blurb": "Black and white stripes, no two alike, under a hard gloss.",
		"price": 0, "tip": "141414", "ferrule": "f2efe6",
		"shaft": MAPLE, "joint": CHROME,
		"rings": {"p": "plain", "a": "141414", "r": 0.3},
		"forearm": {"p": "zebra", "a": "f2efe6", "b": "141414", "coat": 0.9},
		"wrap": {"p": "leather", "a": "141414"},
		"sleeve": {"p": "zebra", "a": "f2efe6", "b": "141414", "coat": 0.9},
	},
	{
		"id": "leopard", "name": "Leopard", "tag": "Animal print",
		"blurb": "Gold and black rosettes, the loudest thing in the room after the jukebox.",
		"price": 0, "tip": "2a1a0a", "ferrule": "efe6cf",
		"shaft": MAPLE, "joint": GOLD, "rings": GOLD,
		"forearm": {"p": "leopard", "a": "d8a452", "b": "1a1208", "c": "a06a28", "n": 8},
		"wrap": {"p": "leather", "a": "2a1a0a"},
		"sleeve": {"p": "leopard", "a": "d8a452", "b": "1a1208", "c": "a06a28", "n": 9},
	},
	{
		"id": "runestone", "name": "Runestone", "tag": "Glows",
		"blurb": "Grey stone carved with runes that still burn blue, and an orb on the end.",
		"price": 0, "tip": "1a2a3a", "ferrule": "5a5e62",
		"shaft": {"p": "plain", "a": "5a5e62", "r": 0.6},
		"joint": {"p": "plain", "a": "3a3d40", "m": 0.6, "r": 0.5},
		"rings": {"p": "plain", "a": "4ac8ff", "g": 1.5},
		"forearm": {"p": "runes", "a": "6a6e72", "c": "4ac8ff", "g": 2.4, "n": 6},
		"wrap": {"p": "leather", "a": "1a1c1e"},
		"sleeve": {"p": "runes", "a": "6a6e72", "c": "4ac8ff", "g": 2.4, "n": 7},
		"pommel": {"shape": "orb", "color": "4ac8ff", "glow": 2.2, "size": 0.012, "metal_color": "5a5e62"},
	},
	{
		"id": "aurora", "name": "Aurora", "tag": "Glows",
		"blurb": "Northern lights over a night sky, drifting slowly under the lacquer.",
		"price": 0, "tip": "04080e", "ferrule": "d8e4f0",
		"shaft": {"p": "aurora", "a": "04080e", "b": "1aff8a", "c": "8a3aff", "g": 1.2, "coat": 1.0},
		"joint": CHROME,
		"rings": {"p": "plain", "a": "1aff8a", "g": 1.4},
		"forearm": {"p": "aurora", "a": "04080e", "b": "1aff8a", "c": "8a3aff", "g": 2.0, "coat": 1.0},
		"wrap": {"p": "leather", "a": "06080e"},
		"sleeve": {"p": "aurora", "a": "04080e", "b": "1aff8a", "c": "8a3aff", "g": 2.0, "coat": 1.0},
	},
	{
		"id": "abalone", "name": "Abalone", "tag": "Mother of pearl",
		"blurb": "Shell inlay that flashes blue and green as it turns, with silver rings.",
		"price": 0, "tip": "1a2a3a", "ferrule": "efe6cf",
		"shaft": MAPLE, "joint": CHROME, "rings": CHROME,
		"forearm": {"p": "pearl", "a": "5a8a9a"},
		"wrap": {"p": "leather", "a": "101010"},
		"sleeve": {"p": "pearl", "a": "5a8a9a"},
		"bands": [0.80, 1.06],
	},
	{
		"id": "sunset", "name": "Sunset Strip", "tag": "Retro",
		"blurb": "An eighties sunset, orange down to violet, with chrome like a car bumper.",
		"price": 0, "tip": "2a0a3a", "ferrule": "f4f4f4",
		"shaft": {"p": "gradient", "a": "ffb347", "b": "ff5e62", "c": "8a2be2", "g": 0.3, "coat": 1.0},
		"joint": CHROME, "rings": CHROME,
		"forearm": {"p": "gradient", "a": "ffd166", "b": "ff4f81", "c": "6a1b9a", "g": 0.4, "coat": 1.0},
		"wrap": {"p": "leather", "a": "2a0a3a"},
		"sleeve": {"p": "gradient", "a": "ff4f81", "b": "6a1b9a", "c": "1a0a3a", "g": 0.3, "coat": 1.0},
		"bands": [0.79, 1.07],
	},
	{
		"id": "eightbit", "name": "8-Bit", "tag": "Pixel art",
		"blurb": "Blocky pixels in arcade colours, like it fell out of a cabinet.",
		"price": 0, "tip": "2b2d42", "ferrule": "edf2f4",
		"shaft": {"p": "pixel", "a": "edf2f4", "b": "8d99ae", "c": "2b2d42", "n": 3.0},
		"joint": {"p": "plain", "a": "ef233c", "r": 0.4},
		"rings": {"p": "plain", "a": "2b2d42"},
		"forearm": {"p": "pixel", "a": "2b2d42", "b": "ef233c", "c": "8ecae6", "n": 4.0, "g": 1.2},
		"wrap": {"p": "leather", "a": "2b2d42"},
		"sleeve": {"p": "pixel", "a": "2b2d42", "b": "ef233c", "c": "8ecae6", "n": 4.0, "g": 1.2},
	},
	{
		"id": "thunder", "name": "Thunderstruck", "tag": "Glows",
		"blurb": "Storm cloud grey with lightning cracking up the butt.",
		"price": 0, "tip": "101216", "ferrule": "2a2e36",
		"shaft": {"p": "plain", "a": "2a2e36", "r": 0.25, "coat": 1.0},
		"joint": BLACK_CHROME,
		"rings": {"p": "plain", "a": "9fd8ff", "g": 1.8},
		"forearm": {"p": "lightning", "a": "14161c", "b": "3a4050", "c": "b8e4ff", "g": 3.0},
		"wrap": {"p": "leather", "a": "101216"},
		"sleeve": {"p": "lightning", "a": "14161c", "b": "3a4050", "c": "b8e4ff", "g": 3.0},
		"studs": {"from": 1.435, "to": 1.445, "rows": 1, "per_row": 6, "size": 0.006, "shape": "pyramid", "color": "c9ccd2", "rough": 0.2},
	},
	{
		"id": "greatwave", "name": "Great Wave", "tag": "Ocean",
		"blurb": "Deep blue swell with the crests breaking white all the way round.",
		"price": 0, "tip": "0a1a30", "ferrule": "f4f0e0",
		"shaft": MAPLE, "joint": CHROME,
		"rings": {"p": "plain", "a": "f4f0e0", "r": 0.3},
		"forearm": {"p": "wave", "a": "0e3a6a", "b": "1f5f9a", "c": "f4f0e0", "n": 3, "coat": 0.9},
		"wrap": {"p": "leather", "a": "0a1a30"},
		"sleeve": {"p": "wave", "a": "0e3a6a", "b": "1f5f9a", "c": "f4f0e0", "n": 4, "coat": 0.9},
	},
	{
		"id": "sakura", "name": "Sakura", "tag": "Cherry blossom",
		"blurb": "Pink blossom scattered over black lacquer, gold at the rings.",
		"price": 0, "tip": "2a1a20", "ferrule": "f4efe2",
		"shaft": {"p": "wood", "a": "e8d0b0", "r": 0.25, "coat": 0.8},
		"joint": {"p": "plain", "a": "ffb7c5", "r": 0.3},
		"rings": GOLD,
		"forearm": {"p": "sakura", "a": "1a0f14", "b": "ffb7c5", "c": "ffe066", "n": 6, "coat": 1.0},
		"wrap": {"p": "linen", "a": "2a1a20"},
		"sleeve": {"p": "sakura", "a": "1a0f14", "b": "ffb7c5", "c": "ffe066", "n": 7, "coat": 1.0},
	},
	{
		"id": "katana", "name": "Katana", "tag": "Sword guard",
		"blurb": "Black silk over white ray skin, a folded-steel shaft and a guard at the joint.",
		"price": 0, "tip": "141414", "ferrule": "c8ccd2",
		"shaft": {"p": "damascus", "a": "c8ccd2"},
		"joint": BLACK_CHROME,
		"rings": {"p": "plain", "a": "8a6a2a", "m": 1.0, "r": 0.3},
		"forearm": {"p": "plain", "a": "121212", "r": 0.2, "coat": 1.0},
		"wrap": {"p": "tsuka", "a": "141414", "b": "ece6d6", "n": 6},
		"sleeve": {"p": "plain", "a": "121212", "r": 0.2, "coat": 1.0},
		"gears": {"at": [0.757], "teeth": 0, "size": 0.012, "thick": 0.005, "color": "3a3a3e", "rough": 0.35},
		"bands": [1.075, 1.29],
	},
	{
		"id": "wyvern", "name": "Wyvern", "tag": "Spined",
		"blurb": "Red scales, black spines down the butt, and eyes like coals at the joint.",
		"price": 0, "tip": "2a0a08", "ferrule": "1a0604",
		"shaft": {"p": "plain", "a": "2a0a08", "r": 0.25, "coat": 1.0},
		"joint": BLACK_CHROME,
		"rings": {"p": "plain", "a": "ff3a10", "g": 1.0},
		"forearm": {"p": "scales", "a": "8a1a14", "b": "1a0604", "m": 0.4, "r": 0.3, "n": 10},
		"wrap": {"p": "leather", "a": "1a0604"},
		"sleeve": {"p": "scales", "a": "8a1a14", "b": "1a0604", "m": 0.4, "r": 0.3, "n": 12},
		"fins": [
			{"from": 0.84, "to": 1.06, "count": 4, "height": 0.011, "color": "d8c8a8", "metal": 0.0, "rough": 0.35},
			{"from": 1.31, "to": 1.445, "count": 4, "height": 0.012, "color": "d8c8a8", "metal": 0.0, "rough": 0.35, "offset": 0.785},
		],
		"gems": {"color": "ff3a10", "count": 2, "at": [0.80], "glow": 2.5, "size": 0.003},
	},
	{
		"id": "plasma", "name": "Plasma Coil", "tag": "Glows",
		"blurb": "A glowing tube wound round a black core, feeding the orb on the end.",
		"price": 0, "tip": "1a0a1a", "ferrule": "0c0c12",
		"shaft": {"p": "plain", "a": "0c0c12", "r": 0.2, "coat": 1.0},
		"joint": CHROME,
		"rings": {"p": "plain", "a": "ff3df0", "g": 2.5},
		"forearm": {"p": "plain", "a": "0c0c12", "r": 0.2, "coat": 1.0},
		"wrap": {"p": "leather", "a": "0a0a0e"},
		"sleeve": {"p": "carbon", "a": "2a2a34"},
		"helix": {"from": 0.79, "to": 1.07, "turns": 4.0, "count": 2, "r": 0.0016, "color": "ff3df0", "metal": 0.0, "rough": 0.2, "glow": 3.5},
		"pommel": {"shape": "orb", "color": "ff3df0", "glow": 3.0, "size": 0.011},
	},
	{
		"id": "crown", "name": "Crown Jewel", "tag": "Jewelled",
		"blurb": "Gold filigree, three rows of sapphires and a diamond on the butt.",
		"price": 0, "tip": "1a1440", "ferrule": "f4efe2",
		"shaft": MAPLE, "joint": GOLD, "rings": GOLD,
		"forearm": {"p": "filigree", "a": "e0b04a", "b": "8a6010", "m": 1.0, "r": 0.18, "n": 8},
		"wrap": {"p": "leather", "a": "1a1440"},
		"sleeve": {"p": "plain", "a": "e0b04a", "m": 1.0, "r": 0.15},
		"gems": {"color": "2a5aff", "count": 8, "at": [0.85, 0.93, 1.01], "glow": 0.9},
		"pommel": {"shape": "gem", "color": "eaf6ff", "glow": 0.8, "size": 0.012, "metal_color": "e0b04a"},
	},
	{
		"id": "rocknroll", "name": "Rock 'n' Roll", "tag": "Studded",
		"blurb": "Oxblood leather, rows of chrome studs, and a grip you can feel.",
		"price": 0, "tip": "1a0a0a", "ferrule": "141212",
		"shaft": {"p": "plain", "a": "141212", "r": 0.25, "coat": 1.0},
		"joint": CHROME, "rings": CHROME,
		"forearm": {"p": "leather", "a": "4a0e10"},
		"wrap": {"p": "leather", "a": "1a0a0a"},
		"sleeve": {"p": "leather", "a": "4a0e10"},
		"studs": [
			{"from": 0.82, "to": 1.04, "rows": 4, "per_row": 9, "size": 0.005, "shape": "dome", "color": "e0e2e6", "rough": 0.1},
			{"from": 1.32, "to": 1.43, "rows": 2, "per_row": 10, "size": 0.005, "shape": "dome", "color": "e0e2e6", "rough": 0.1},
		],
	},
	{
		"id": "scrimshaw", "name": "Scrimshaw", "tag": "Engraved ivory",
		"blurb": "Old ivory scratched with sea scenes and filled with ink.",
		"price": 0, "tip": "2a2018", "ferrule": "efe4cc",
		"shaft": {"p": "wood", "a": "e6d2a8", "r": 0.25, "coat": 0.8},
		"joint": {"p": "plain", "a": "2a2018", "r": 0.3},
		"rings": {"p": "plain", "a": "c9a060", "m": 1.0, "r": 0.3},
		"forearm": {"p": "bone", "a": "efe4cc", "b": "2a2018"},
		"wrap": {"p": "linen", "a": "4a3a28"},
		"sleeve": {"p": "bone", "a": "efe4cc", "b": "2a2018"},
	},
]


static func count() -> int:
	return CUES.size()


static func by_id(id: String) -> Dictionary:
	for c in CUES:
		if c.id == id:
			return c
	return CUES[0]


static func index_of(id: String) -> int:
	for i in CUES.size():
		if CUES[i].id == id:
			return i
	return 0


# Two colours that stand for a cue in lists: its forearm and its accent.
static func swatch(cue: Dictionary) -> Array:
	var fa: Dictionary = cue.get("forearm", {})
	var rg: Dictionary = cue.get("rings", {})
	var accent := str(fa.get("c", fa.get("b", rg.get("a", "888888"))))
	return [Color(str(fa.get("a", "444444"))), Color(accent)]


# ---------------------------------------------------------------------------
# Save file. Deliberately tiny and plain: a couple of keys, easy to extend
# later without breaking anyone's existing file.
# ---------------------------------------------------------------------------

static func load_state() -> Dictionary:
	var state := {"owned": ["house"], "equipped": "house", "difficulty": 5, "guides": true, "cash": START_CASH}
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return state
	var owned: Array = cfg.get_value("player", "owned", ["house"])
	var clean: Array = []
	for id in owned:
		if typeof(id) == TYPE_STRING and by_id(id).id == id:
			clean.append(id)
	if clean.is_empty():
		clean = ["house"]
	state.owned = clean
	var eq: String = str(cfg.get_value("player", "equipped", "house"))
	state.equipped = eq if clean.has(eq) else clean[0]
	state.difficulty = clampi(int(cfg.get_value("player", "difficulty", 5)), 1, 10)
	state.guides = bool(cfg.get_value("player", "guides", true))
	state.cash = maxi(0, int(cfg.get_value("player", "cash", START_CASH)))
	return state


static func save_state(state: Dictionary) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)          # settings and stats share the file; keep them
	cfg.set_value("player", "owned", state.get("owned", ["house"]))
	cfg.set_value("player", "equipped", state.get("equipped", "house"))
	cfg.set_value("player", "difficulty", state.get("difficulty", 5))
	cfg.set_value("player", "guides", state.get("guides", true))
	cfg.set_value("player", "cash", state.get("cash", START_CASH))
	cfg.save(SAVE_PATH)
