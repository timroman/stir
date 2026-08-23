# Sounds

Every sound here is synthesized — nothing is licensed or downloaded.
Regenerate with:

    python3 tools/synthesize-sounds.py <outdir>
    afconvert -f m4af -d aac -b 128000 <name>.wav <name>.m4a

The six looping beds (white/pink/brown noise, fan, wind, ocean waves) are built
sample-continuous end-to-start so they repeat gaplessly with no runtime
crossfade. The short wake tones (gentle chime, soft bells, singing bowl, dawn)
are one-shot. `rain` is generated but not shipped.

`.md` files here are excluded from the app target by project.yml.
