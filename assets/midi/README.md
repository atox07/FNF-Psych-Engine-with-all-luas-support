
This folder is where the Chart Editor looks for `.mid` / `.midi` files when you
use **File → Import MIDI...**.

You can also browse for a MIDI from anywhere else on your PC using the
**Browse...** button inside the import window; files placed in this folder
just show up in the list automatically.

---

 How it works

The Chart Editor imports **two separate MIDIs**: one for **Dad** and one for
**BF**. Each file is imported on its own and the notes are **added** to the
chart that is currently open, so you can import Dad first, then BF (or the
other way around) and end up with both sides in the same chart.

- **Import as Dad** → every note goes to (opponent side).
- **Import as BF**  → every note goes to (player side).

`mustHitSection` is set automatically so the camera follows whoever is
playing more in each section. Dad-only sections get `mustHitSection = false`,
BF sections get `mustHitSection = true`.

---

## Exporting the MIDIs from FL Studio

You need to export **one MIDI per character** (one for Dad, one for BF).
Do **not** export the whole song as a single file: this importer expects
two files, and it will line them up with each other automatically since
both start at tick 0.

### Step by step

1. In FL Studio, open the project.
2. Select the **pattern that contains Dad's notes**.
3. Go to **File → Export → MIDI file**.
4. Choose a location and save it as `dad.mid` (or anything you want).
5. Select the **pattern that contains BF's notes**.
6. Again **File → Export → MIDI file**, save it as `bf.mid`.
7. Copy both files into this `midi/` folder (or keep them anywhere) and use
   the **Browse...** button in the editor).


## Using the import window

1. Open the **Chart Editor**.
2. Click **File → Import MIDI...** (top-left of the editor).
3. The window shows the `.mid` / `.midi` files found in this folder.
4. Click a file to select it, then press **Import as Dad** or
   **Import as BF**.
5. The notes are added to the chart and the window stays open so you can
   import the other side right away.
6. Use **Clear Chart** if you want to start over (this deletes every note
   in the chart, but keeps the sections and events).
7. Press **ESC** or **Cancel** to close the window.

### Browse...

If your MIDI is not in this folder, click **Browse...** to open a
standard file dialog. Pick the file, then press **Import as Dad** or
**Import as BF** — the file dialog opens first, and once you pick a file
it is imported immediately with the button you pressed.

### BPM

- The **first** MIDI you import into an empty chart sets the chart's BPM.
- The **second** MIDI uses the chart's current BPM, even if its own tempo
  is different. You'll get an on-screen warning if the two don't match.
- If a MIDI contains **BPM changes**, only the first BPM is used. You'll
  also get a warning in the footer when that happens.

### Sustain notes

Notes that last at least **4 steps** (a quarter note) become **sustain
notes** in the chart. Shorter notes are placed as regular notes.

### Duplicates

If you import the same MIDI twice, or two MIDIs share the same lane and
time, the duplicate is skipped and reported in the footer.

---

## What if my MIDI has more than one track?

The importer reads **every track** of the file and treats all of them as a
single side (Dad or BF). If your MIDI has multiple instruments, that's
fine — they'll all be combined into one part.

If you need to separate them, export each instrument to its own pattern
in FL Studio and use two separate exports (one for Dad, one for BF).

---

## A note on timing

Both MIDIs start at tick 0, so they line up with each other
automatically. If one of your parts starts a bit later than the other
(for example, Dad enters after 8 bars), that offset is **kept as-is**:
the notes will be placed at the correct time in the chart.

---

Have fun charting! :P
