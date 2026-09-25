# Jarvis 8 Pool

Eight-ball against a computer opponent, on a nine-foot table in a dim bar.
Godot 4.3 or newer, Forward+ renderer. Almost everything is built in code
when the game starts: every mesh and light, the wood, the balls. The only
image files are the J ball badge (`icon.png` / `icon.ico`, also the window and
exe icon, and the letter on the 8 ball) and `textures/cloth_detail.png`, the
fibres of a photographed felt with its lighting taken out and made to tile.

## Download and play (Windows)

Grab `build/Jarvis 8 Pool - Windows.zip`, unzip it anywhere, and run
`Jarvis 8 Pool.exe`. Keep the `.pck` next to the exe: it holds the game.
`Jarvis 8 Pool.console.exe` is the same game with a log window, handy if
something goes wrong.

## Running it from source

1. Open Godot, choose **Import**, and select `project.godot` in this folder.
2. Press **F5**. The first launch takes a second or two while textures are generated.

You land on the title screen, with the table turning slowly in the room
behind it. **Play** picks how good the house player is, 1 to 10, and whether
the aim guide is on. **Shop** holds the cues, each one turning in 3D beside
the list (drag it to spin it yourself). **How to play** has the controls and
the house rules, so nothing is printed over the table while you're playing.
**Settings** has sound, controls and screen options, and your profile sits
in the top right corner.

## Shop and saving

Owned cues, the one in your hand, and your chosen difficulty live in
`user://jarvis8pool.cfg`. Adding a cue is one entry in `CUES` in
`scripts/pool_cues.gd` and it appears in the shop on its own. Every section of
the cue takes an art pattern (wood, marble, flames, circuit board, holographic
foil, runes and so on), can be carved with flutes or a spiral, or cut into
facets, and a cue can carry parts that stand off it: a coiled serpent or
glowing tube (`helix`), spikes or studs (`studs`), `fins`, toothed `gears` or a
sword guard, gems, and a crystal or orb `pommel` on the butt. All of it is
built in `scripts/pool_cue_model.gd`. Price 0 means free, which is every cue
for now.

## Settings

**Settings** on the title screen has the volume for all sounds, sound
effects and voices (each on its own audio bus: `Master`, `SFX`, `Voice`),
mouse sensitivity, field of view, drink effects on or off (off, the drinks
still pour and go down, they just don't do anything to you), screen shake,
fullscreen, VSync, a frame rate cap, and the film grain and vignette. They
save in the `[settings]` section of the same save file. It's all in
`scripts/pool_settings.gd`.

## Profile and Steam

The top right corner of the title screen is your profile. Signed out, it
offers to sign in through Steam; signed in, it shows your Steam avatar, name,
level with XP bar, and trophies. Click it for the full profile: level,
trophies, and stats (games, wins and losses vs the house player, win rate,
streaks, toughest level beaten, shots, balls hit, balls potted, fouls, time
played, drinks, punches landed, times decked). It's in `scripts/pool_profile.gd`.

- **XP and levels:** a win against the house player is 60 XP plus 12 per level
  he's set to; a loss is 15 plus 3 per level; every ball you pot is 3. Each
  level takes 40 XP more than the last, starting at 100.
- **Trophies** are online wins. `record_mp_game(won)` is there ready for
  multiplayer and pays 200 XP for a win, 50 for a loss.
- **Where stats live:** as Steam stats on your account, and in the local save
  per Steam account (`[stats_<steamid>]`), merged by taking the larger of each.
  Anything you did before ever signing in carries over to the first account
  that signs in.

Steam isn't in the project yet, and the game runs fine without it. To switch
it on:

1. Add [GodotSteam](https://godotsteam.com) (the GDExtension from the Asset
   Library) to the project.
2. Put your app ID in `APP_ID` in `scripts/pool_profile.gd`, or in
   `steam_appid.txt` next to the exe. Until then it's 480, Valve's Spacewar
   test app, so sign-in can be tried now; stats won't stick on Spacewar.
3. In Steamworks, under Stats & Achievements, add one INT stat per name in
   `PoolProfile.STATS` (`xp`, `trophies`, `mp_losses`, `bot_wins`, …), set to
   be written by the client.

In an editor build without Steam, "Sign in through Steam" gives you a local
test profile instead, so the profile screens can be worked on; exported
builds just say Steam sign-in isn't available yet.

## Controls

It plays like standing at a real table. The keyboard only walks, bends you
down over the shot and pauses; everything else is your eyes and your hands.

| Input | Does |
|---|---|
| **W A S D** | Walk. Slows to a creep as you approach a wall, and you can walk right up to the rail. Turning round is full speed again |
| **Shift** | Hold to walk faster (1.6×) |
| **Mouse** | Look around. Down on a shot, it aims; slow movements are finer |
| **Space** | Get down on the shot along the line you're standing on, or stand back up. If the cue ball is out in the table you lean across to it from the rail, up to 1.5 m from the outside of the rail. Once down you can swing about 60° either way, as long as you could still reach the ball from behind the rail on that line; to shoot from elsewhere, stand up and walk there |
| **Hold left button, pull back, push through** | Take the shot. Push forward to nothing and release to cancel |
| **Hold right button and move** | Move the tip round the face of the cue ball for follow, draw and side. The view leans in over the ball while you do it |
| **Wheel** | Lean in closer or ease back while down |
| **Left click, on your feet** | With ball in hand, put the cue ball down. On the 8, call the pocket you're looking at |
| **Left click, looking at him** | Wind up and throw a punch (once every 30 s). Only when a click has nothing else to do |
| **Left click, on a card at the bar** | Order that drink |
| **Hold left button on your drink** | Pick it up. Move the mouse up to lift it to your mouth and drink; let go to put it down (or drop it, if you've wandered off) |
| **Esc** | Pause: resume, restart the rack, or go back to the menu |

**Ball in hand:** the cue ball is in your hand and sits wherever you are
looking on the table. Walk round to reach a different spot, and click to put
it down. If the spot is taken it settles just beside the ball in the way. On
the break you're kept behind the head string.

**Calling the 8:** when you're on the 8 you have to name a pocket before
you're allowed to get down on the shot. Look at a pocket and click it; it
lights up blue. Click it again to take the call back, or click another pocket
to move it. Calling only works while you're standing, so clicks while you're
down on the shot can never change it.

**Watching:** while the balls are running and you're on your feet, nothing
turns your head for you. Walk about and look where you like. Stand still for
two seconds and your eyes go to the shot, the way anyone's would.

## The house player

Your opponent is in the room with you: an old hand with a beard and shorts
(`characters/old_man/old_man.glb`, from Sketchfab). The model came with one
idle clip; everything else is animated on top of it in code, in
`scripts/pool_character.gd`:

- **Walking:** feet are planted on the floor and step only when the body has
  moved off them, so nothing slides; legs reach them with IK, the pelvis
  bobs, the free arm swings against the stride.
- **Thinking:** on his turn he strolls round the table with a hand on his
  chin, his eyes going from ball to ball, until he has decided.
- **Playing:** he fetches the cue ball if it's in hand, walks round the table
  (never through it) to where the shot is played from, puts the ball down,
  bends over it with his bridge hand on the cloth and the cue in his back
  hand, takes a couple of practice strokes and plays it.
- **Waiting:** on your turn he stands somewhere out of your line and watches
  the cue ball, the balls running, and now and then you. Crowd him, or line
  up a shot through where he's standing, and he moves.

His movement is in `scripts/pool_bot.gd`: where to stand, where to look,
and when.

**His voice:** he talks, in his own recorded voice (`audio/old_man/`), and
what he says goes up in a speech bubble over his head, timed to the words:
"Listen, kid... You think you're gonna beat me?" before a game or on his way
over to deck you, "Where do I even go?" when he's walking about, "Hey! Watch
it, kid!" when you bump him, "HEY!" as he picks himself up off the floor. He
sighs when it's his shot, sings to himself when he's been waiting a while,
and laughs when he wins or has just put you on the floor. The voice lines and
their bubble text are `VOICE` in `scripts/pool_bot.gd`.

**Messing about:** you're both solid. Walk into him and he rocks and turns to
look at you; keep doing it and he gets annoyed. Click on him and you throw a
punch, once every 30 seconds: your arm comes up and draws right back, then
goes in with everything, and if it lands (with his grunt right on it) he goes
full ragdoll: physics bodies on his pelvis, spine, chest, head, arms, legs and
feet, jointed like a person's, launched up and back so he tumbles heels over
head, bounces off the walls, bar, stools or table and crumples wherever he
lands. He lies there seeing stars, then comes round and struggles up by
stages: sat up, onto a knee, nearly there, legs going, up. The bodies collide
with the room but not with each other, which keeps it from jittering; the
physics runs on Jolt. It never changes the game: if he was down on a
shot, he walks back to it and plays exactly the same shot.

He'll do the same to you. Every minute or two, more likely if you just hit
him or keep bumping him, he walks over, winds up a haymaker and sends you
flying: heels over head, flat on your back, the ceiling going round with
stars in front of your eyes, then a wobbly climb back to your feet. You can
look about while you're down. Whatever you were doing is exactly as you left
it: aim, spin, call, ball in hand. He never does it in the middle of playing
his own shot.

## The bar

The bar along the far wall is somewhere to spend your winnings: every game
pays out, $15 for a win and $5 for a loss, and your money is saved with
your cues. Walk up to the counter, look at one of the little cards standing
on it and click to order. The bartender pours it and slides it down to you
(and if you're broke, it's on the house). Hold the button on the glass to pick
it up, move the mouse up to bring it to your mouth and tip it back, and let
go to put it back on the bar.

Neither drink does anything for your game. For about 45 seconds afterwards:

- **Blitzkraft** ($6, das Energie-Schnaps): the room breathes and ripples
  and the colours go round.
- **Old Wobbly** ($4, dark rum): double vision, the room sways, your feet
  wander off course, your aim won't sit still while you line up, and you
  hiccup.

It's in scripts/pool_bar.gd; the look of it is the post-process in
scripts/pool_postfx.gd.

## Your own sound effects

Every sound effect is made up in code, but any of them can be replaced with a
recording: put a file named after it in `audio/sfx/` (`.ogg`, `.wav` or
`.mp3`) and it's used instead. Several takes of the same sound can be named
`name_1`, `name_2`… and one is picked at random each time. Names:
`click`, `rail`, `drop`, `strike`, `step`, `bump`, `whoosh`,
`thud`, `gulp`, `hic`, `clink`, `smash`, `slide`, `till`, and for
the menu `ui_tick`, `ui_click`, `ui_equip`, `ui_start`.

## Discord Rich Presence

While the game is open, Discord shows the J ball and where you are: in the
menu, in the shop (and which cue you're looking at), playing (who against,
whose shot, how many of your group are left, time in the match), paused, the
result, or idle after a minute and a half without input. It talks straight to
the Discord app on your machine (`scripts/pool_discord.gd`), so there's
nothing to install, and if Discord isn't running the game doesn't care.

It needs a Discord application of your own, set up once:

1. Go to https://discord.com/developers/applications, click **New
   Application** and call it `Jarvis 8 Pool` (that name is what shows after
   "Playing").
2. Copy the **Application ID** from the General Information page. Either
   save it in a text file called `discord_app_id.txt` next to
   `Jarvis 8 Pool.exe` (no rebuild needed), or paste it into `APP_ID` at the
   top of `scripts/pool_discord.gd`.
3. Under **Rich Presence > Art Assets**, upload `discord/logo.png` and name it
   `logo`. New assets can take a few minutes to show up.
4. Make sure **Settings > Activity Privacy > Share my activity** is on in Discord.

## Rules

Standard eight-ball, simplified where house rules usually are:

- The table is open after the break; the first ball legally potted claims your group.
- Fouls (scratch, hitting nothing, hitting the wrong group first, no ball reaching a
  rail after contact) give your opponent ball in hand anywhere.
- An illegal break (fewer than four balls to a rail) passes the table over.
- The 8 on the break re-racks. The 8 early, in the wrong pocket, or scratching on
  the 8 loses the game.

## How it works

Pocket geometry follows the WPA/BCA equipment spec: corner mouths 4.55"
between the cushion noses, side mouths 5.06", cushion ends cut flat at 142°
(corners) and 103° (sides) rather than rounded, noses at 63.5% of a ball
diameter, and a 30mm shelf a ball has to reach before it drops. The facings
are real cushions, so pockets rattle.

**Physics** (`scripts/pool_sim.gd`) is a custom ball simulation rather than Godot's
rigid bodies, substepped at 720 Hz. Each ball carries full 3D spin, so draw,
follow and side spin fall out of the friction model instead of being faked:
a struck ball slides, then grips and rolls at 5/7 of its speed; object balls are
thrown by cut-shot friction; cushions contact slightly above centre and bend
the cue ball's path according to its spin. Pockets are gaps in the slate: a ball
drops when its centre crosses the mouth between the jaws.

**The opponent** (`scripts/pool_ai.gd`) runs on a background thread. It lists
possible pots, plays each through the same physics you're playing against,
scores where the cue ball finishes, replays the best few with its own aim error
to see which ones hold up, and falls back to a safety when nothing is worth it.
Then it misses a little, the way people do.

Crucially it also *solves* its aim. The ghost-ball line is only a first guess,
because friction between the two balls throws the object ball off it by a
couple of degrees — which is a miss from the length of the table. So it plays
the shot in its head, measures how far the ball passed the pocket, corrects by
the amount that miss implies, and plays it again. Strong players do this up to
three times and rehearse at the same physics step the table actually runs at;
weak ones fire at the naive line and get thrown off it. From level 5 up it also
looks at one-rail banks when nothing direct is on.

Difficulty 1 to 10 moves every dial at once: aim error falls from 2.4° to
0.055°, speed control tightens, it weighs position more heavily, it gets
braver about safeties, it considers more shots per turn, and it stops
settling for the second or third best thing on the table.

**The camera** is a person. `scripts/pool_player.gd` holds where they are
standing, where they are looking, and whether they are down on a shot, and
nothing else in that file reads the keyboard — so when a second player arrives
over a wire they are another one of these, fed from the network instead, and
drawn with the same body. Walking uses soft bounds rather than walls: only the
part of your motion heading further out is damped, so you creep to a halt at
an edge but get full speed back the instant you turn round.

How far the view pulls back after a shot depends on the shot: a gentle tap
keeps you down on the line, a firm pot lifts you a little, a break stands you
all the way up. Between shots you
walk round the rail on an ellipse; when you reach the line of the shot you
bend down onto it, and the whole approach is one eased parameter so there are
no cuts. Pulling the stroke back eases the view back with it, the strike
nudges it forward, and when the balls are moving you straighten up and watch.

## Tuning

| What | Where |
|---|---|
| Cloth speed, cushion bounce, throw | Constants at the top of `pool_sim.gd` (`MU_ROLL`, `E_RAIL`, `MU_BALL`, …) |
| Pocket size | `CORNER_GAP`, `SIDE_GAP` in `pool_sim.gd` |
| What each difficulty means | `aim_sigma()`, `speed_sigma()`, `safety_nerve()`, `variant_budget()`, `aim_passes()` in `pool_ai.gd` |
| Cues in the shop | `CUES` in `pool_cues.gd` |
| Max shot speed, pull length, aim and tip sensitivity | `MAX_SPEED`, `PULL_RANGE`, `AIM_SENS`, `TIP_SENS` in `game.gd` |
| How far the cue lifts over things | `CUE_MARGIN`, `CUE_MAX_ELEV` in `game.gd` |
| How long you stand still before you watch the shot | `WATCH_AFTER` in `game.gd` |
| Cloth colour and sheen | `CLOTH`, `CUSHION_COL` in `pool_table_view.gd`, `_CLOTH` in `pool_art.gd` |
| How you walk and stand | `EYE_H`, `WALK_A`, `WALK_B` and `_update_camera` in `game.gd` |
| Colours | `scripts/pool_theme.gd` |
| Lighting and haze | `scripts/bar_room.gd` |

## If multiplayer gets added later

The seams are already in place. Racks are built from `rack_seed` rather than
straight from the clock, so two machines can be dealt the same triangle, and
every shot in the game — yours and the opponent's — goes through `_play_shot`
as a dictionary of `{dir, speed, english, place, pocket}`. A remote player is
another source of that same dictionary. Nothing else in the turn flow needs to
know where a shot came from.

## Known limits

- No jump or massé shots; balls never leave the cloth surface. The cue lifts
  its butt automatically, only as far as it has to, so the stick passes just
  over any ball, cushion or rail behind the cue ball instead of through it,
  and your eye line rises with it. That angle is cosmetic: it doesn't change
  the physics.
- A cue ball frozen against another ball needs the butt well up (about 40°)
  to clear it, the same as at a real table.
