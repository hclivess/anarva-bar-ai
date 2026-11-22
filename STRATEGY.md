# Anarvā — strategy and tactics: principles to mechanisms

Anarvā doesn't copy moves. It encodes the **reasoning** behind them. Each principle below is tied to
the code that implements it. Sources (public domain, kept locally under `ref/strategy/`): Sun Tzu, *The
Art of War* (Giles translation); Clausewitz, *On War*; Napoleon's *Military Maxims*.

## 1. Know the enemy: scouting decides everything

> "If you know the enemy and know yourself, you need not fear the result of a hundred battles."
> — Sun Tzu III.18
>
> "…foreknowledge cannot be elicited from spirits…" — XIII.5 (it must come from scouts)

- **Army vs. scaling** (`Brain::Director`). Each update, the scouted enemy mobile threat is compared
  with our power and drives the core's constructor-vs-army knob (`aiFactoryMgr.buildpowerRatio`):
  - enemy weak → scale (more constructors, expand, tech)
  - enemy strong → army
  - **blind** → hedge and push scouts, because scaling on a guess is a gamble
- A permanent scout quota of at least 3 rises when we're blind or jammed. Air scouts are bought on
  jammer alert.
- **What we can't see** (`Brain::Intel`):
  - A seen jammer is treated as a hidden army, a phantom threat on its cluster.
  - Places where we keep dying get Dragon's Eyes, because sight is the only thing a jammer can't
    stop.
  - Junos clear jammers and radar.

## 2. Measure strength, then choose the fight (Sun Tzu III.9-10)

> "If ten to the enemy's one, surround him; if five to one, attack him; if twice as numerous, divide
> our army into two. If equally matched, we can offer battle; if slightly inferior in numbers, we can
> avoid the enemy; if quite unequal in every way, we can flee from him."

The Director's postures follow this ladder, using our power ÷ the enemy's seen mobile threat:

| ratio | posture | behaviour |
|------:|---------|-----------|
| ≥ 4 | ALLIN | small waves, constant pressure, close the game |
| ≥ 1.6 | PRESSURE | frequent waves; raiders split off to hit the weak points |
| ~1 | BALANCED | offer battle with a large wave |
| < 0.75 | HOLD | avoid open battle, fight under our own defences, strike only with a big wave |
| < 0.4 | TURTLE | everything into army; defend the base (planned: static defence at chokes) |

## 3. Concentration of force (Napoleon, Clausewitz)

> "The first and most important rule… to concentrate as much as possible." — Clausewitz

- **Wave control** (`Brain::Army::MakeTask`). Every new combat unit joins *one* gathering wave, sized
  by the Director. When it's full it launches together. This replaces the core's habit of either
  never launching or trickling.
- **Broken-squad recall.** A squad that has lost most of its power is pulled back to regroup. Feeding
  units in one by one is the opposite of concentration.

## 4. Avoid strength, strike weakness (Sun Tzu VI.30-31)

> "The way is to avoid what is strong and to strike at what is weak… Water shapes its course according
> to the nature of the ground." — VI.30-31
>
> "Attack him where he is unprepared." — I.24

- Raiding packs (`raid` quota) go after eco and builders. The core's threat map steers them away from
  defences.
- **A greedy enemy** (lots of buildings, little army) is punished: we switch to PRESSURE instead of
  trying to out-boom him.
- Attack target choice compares our wave with each enemy group's strength
  (`thr_mod.attack` 0.85-1.05 instead of BARb's suicidal 0.6-0.8).

## 5. The culminating point (Clausewitz)

An attack loses strength as it advances; past its culminating point it should stop. That's the recall
threshold: below 40% of peak power, and weaker than a fresh wave, a squad turns back.

## 6. Economy is the base of war: efficiency, not imitation

- **Extractors:** a T1 extractor (50 metal, 3 E/s upkeep) pays for itself in about 25 s, so take every
  safe spot early. Moho/exploiter upgrades add about 6 m/s for 17-20 E/s, so they're gated by energy
  headroom (`Brain::Eco`). An energy stall slows everything.
- **Recycling** (`Brain::Recycler`). Obsolete eco gets turned back into metal:
  - solars and winds once fusion carries the base
  - fusions once advanced fusions carry the grid
  - T1 makers once T2 makers carry conversion
  - idle T1 units late in the game

## 7. Do not repeat yourself (Sun Tzu VI.28)

> "Do not repeat the tactics which have gained you one victory, but let your methods be regulated by
> the infinite variety of circumstances."

Postures are re-evaluated every update with hysteresis, never on a script timeline. Planned:
randomized wave timing and attack axes.

## 8. Preparation against what can't be seen

- Anti-nuke the moment a silo is seen, and proactively once rich.
- Shields over the most valuable infrastructure cluster.
- Static anti-air over infrastructure, scaled to the air metal we've seen.

## 9. Rapidity (Sun Tzu XI.19) and closing the game

> "Rapidity is the essence of war."

At 40 minutes BARb-style play is often far ahead and still hasn't won. A dominant force ratio switches
to ALLIN, so advantage turns into a decision before the enemy recovers.

## Planned

- Walls and dragon's teeth at chokes, in front of defence lines (Sun Tzu's terrain chapters; HOLD and
  TURTLE).
- Holding chokepoints with static defence in 1vN.
- Feints: a raid on one flank before the main wave hits another (I.20, "hold out baits").
- Production that picks the next unit by cost-effectiveness against the scouted composition.
