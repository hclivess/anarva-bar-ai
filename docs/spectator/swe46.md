# Spectator: swe46 g00 - Anarvā (Armada) vs BARb hard (Cortex), Comet Catcher Remake 1.8

**Correction (coordinator):** swe46 was stopped on purpose because the owner opened BAR. spring.exe pid 21856 is the owner's own BAR client, not this game. No game ran, and there was no hang.

## Second start (22:1x): stuck in loading
The headless engine has been loading for over 7 minutes of engine time with no game frame. The last load step is `[LoadScreen::SetLoadMessage] text="Creating Projectile Textures"` at engine t=4:08.
Since then it has printed only watchdog warnings, `[Watchdog] Hang detection triggered for Spring 2026.09.03 (Headless)` with stack traces (12 so far, one every ~30 s; the first came at t=0:49 during map parsing).
No AI or harness line, so there is no anarva error. It is likely resource contention with the owner's BAR client, which is running alongside.

## Original note (wrong: pid 21856 is the owner's client)
The infolog stops at line 1375 during loading, at engine time 12 s, and has not grown for over 3 minutes of wall time (checked 22:07-22:10):
`[Game::Load][1] globalQuit=0 threaded=0`, `[LoadScreen::SetLoadMessage] text="Parsing Map Information"`.
spring.exe (pid 21856) is still running at 5.9-6.3 GB of memory and growing. There is no `[f=` frame, no AI line and no harness stats line.
The hang comes before the AI loads, so it is not an anarva script error. Not stopped by me (spectator rules).
