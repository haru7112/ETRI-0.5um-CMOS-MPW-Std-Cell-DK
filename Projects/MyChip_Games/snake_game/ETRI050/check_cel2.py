#!/usr/bin/env python3
"""Cross check snake_chip.cel2 against the RTL port list and the pad frame.

    python3 check_cel2.py          (or: make check_pins)

WHY THIS EXISTS

A typo in a twpin_ name is not an error to graywolf - the pin simply ends up
unconstrained and lands wherever the placer likes, which is exactly what the
file exists to prevent.  Nothing else in the flow notices.

AND WHY snake_chip.cel2 HAS NO COMMENTS

It is not a shell-commented format.  None of the 46 .cel2 files in this design
kit carry a '#' line, and between them they use only letters, digits, space,
'[', ']' and '_'.  qflow's place step feeds the file through tcsh, so a
backtick in a comment becomes command substitution and the run dies with
"Unmatched '"'." before graywolf is ever reached.  The documentation that
would otherwise sit at the top of the .cel2 lives here instead, and
check_charset() below rejects anything outside the character set the kit uses.

HOW A SIDE BECOMES A PACKAGE PIN

MPW_PAD_28Pin_IO.mag has seven pad slots per side, named PAD_0..PAD_27 - an
empty template, which is what makes a custom pinout possible at all.
MPW_PAD_28Pin_IO_Games.mag is the same frame already filled in, and reading
its instance names against MyChip_Game_Package.txt pins the correspondence
down exactly:

    side L -> package pins  1..7        side R -> package pins 15..21
    side B -> package pins  8..14       side T -> package pins 22..28

WHY ONE GROUP PER SIDE

Twelve signals and sixteen power pads share 28 slots.  The Games part puts
every signal on T and B and fills L and R with power, so current enters the
ring from two opposite sides only.  Spreading the signals over all four sides
leaves 2/3/5/6 free slots per side instead, so the power pads spread too and
the ring is fed from four sides - worth having with ~2400 cells switching at
25MHz.  Power itself is never named in a .cel2: inside the core it arrives on
the rails and the stripes addspacers builds, and around the core through the
PADVDD/PADGND cells placed in ../chip_top.

Grouping is the other half of the point.  A padgroup is what keeps pads
adjacent, so the five joystick lines come out as five consecutive package pins
and go to one connector, and so do the panel lines.  One group per pin would
ask graywolf for nothing.  SCL_OE, SDA_OE and SDA_I stay in one group because
they become two PADINOUT cells at chip_top.

'permute' is deliberately omitted, so that the joystick keeps UP/DOWN/LEFT/
RIGHT order.  Confirm what actually came out in layout/snake_chip.pin after
'make place'; grouping holds either way, only the order within a group depends
on this.

CHECKS

  * every port of snake_chip appears exactly once
  * no twpin_ name that is not a port
  * no side carries more pads than the frame has slots on that side, counted
    from pads_ETRI/MPW_PAD_28Pin_IO.mag rather than assumed
  * no character outside the set the kit's own .cel2 files use
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CEL2 = os.path.join(HERE, 'snake_chip.cel2')
RTL = os.path.join(HERE, '..', 'rtl', 'snake_chip.v')
FRAME = os.path.join(HERE, '..', '..', '..', '..',
                     'pads_ETRI', 'MPW_PAD_28Pin_IO.mag')


def frame_slots(path):
    """Pad slots per side of the pad frame, from the magic cell."""
    txt = open(path).read()
    uses = re.findall(
        r'use (\S+)\s+\S+\s*\ntimestamp \d+\n'
        r'transform ([-\d]+) ([-\d]+) ([-\d]+) ([-\d]+) ([-\d]+) ([-\d]+)\n'
        r'box ([-\d]+) ([-\d]+) ([-\d]+) ([-\d]+)', txt)
    pads = []
    for cell, a, b, c, d, e, f, x0, y0, x1, y1 in uses:
        a, b, c, d, e, f = map(int, (a, b, c, d, e, f))
        x0, y0, x1, y1 = map(int, (x0, y0, x1, y1))
        pts = [(a * x + b * y + c, d * x + e * y + f)
               for x in (x0, x1) for y in (y0, y1)]
        xs, ys = [p[0] for p in pts], [p[1] for p in pts]
        pads.append((cell, (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2))
    ax = [p[1] for p in pads]
    ay = [p[2] for p in pads]
    cx, cy = (min(ax) + max(ax)) / 2, (min(ay) + max(ay)) / 2
    slots = {'T': 0, 'B': 0, 'L': 0, 'R': 0}
    for cell, x, y in pads:
        if cell.startswith('IOFILLER') or cell.startswith('PCORNER'):
            continue
        dx, dy = x - cx, y - cy
        side = ('T' if dy > abs(dx) else 'B' if -dy > abs(dx) else
                'R' if dx > 0 else 'L')
        slots[side] += 1
    return slots


def check_charset(path):
    """Reject anything the kit's own .cel2 files never contain.

    qflow's place step runs the file through tcsh, so a backtick, a quote or a
    '#' comment breaks the run before graywolf sees it - and the error it dies
    with ("Unmatched") does not name this file.
    """
    allowed = set(" \tABCDEFGHIJKLMNOPQRSTUVWXYZ"
                  "abcdefghijklmnopqrstuvwxyz0123456789[]_")
    bad = []
    for n, line in enumerate(open(path), 1):
        for ch in line.rstrip('\n'):
            if ch not in allowed:
                bad.append((n, ch))
                break
    return bad


def parse_cel2(path):
    groups, cur = [], None
    for line in open(path):
        s = line.split('#')[0].strip()
        if not s:
            continue
        if s.startswith('padgroup'):
            cur = {'name': s.split()[1], 'pins': [], 'side': None}
            groups.append(cur)
        elif s.startswith('twpin_') and cur is not None:
            cur['pins'].append(s.split()[0][len('twpin_'):])
        elif s.startswith('restrict side') and cur is not None:
            cur['side'] = s.split()[-1]
    return groups


def rtl_ports(path):
    txt = open(path).read()
    body = txt[txt.index('module snake_chip'):txt.index(');')]
    names = []
    for decl in re.findall(r'(?:input|output)\s+wire\s+([A-Za-z_0-9, ]+)', body):
        names += [n.strip() for n in decl.split(',') if n.strip()]
    return names


def check_tcsh(path):
    """Lines whose quotes or backticks do not pair up.

    project_vars.sh is sourced by tcsh, which parses quotes and backticks even
    inside comments and does not join a backslash continued string.  Either
    mistake kills qflow with "Unmatched" and no filename - it showed up at
    `make place`, several steps after the file was read.  No other
    project_vars.sh in the kit has an unbalanced line, so flag any.
    """
    bad = []
    for n, line in enumerate(open(path), 1):
        s = line.rstrip('\n')
        for ch, what in (('"', 'double quote'), ('`', 'backtick')):
            if s.count(ch) % 2:
                bad.append((n, what, s.strip()))
        if s.endswith('\\'):
            bad.append((n, 'backslash continuation', s.strip()))
    return bad


def main():
    for n, what, text in check_tcsh(os.path.join(HERE, 'project_vars.sh')):
        print(f"FAIL  project_vars.sh:{n}  unbalanced {what} - tcsh parses "
              f"these even in comments")
        print(f"      {text[:70]}")
        return 1

    bad = check_charset(CEL2)
    if bad:
        for n, ch in bad:
            print(f"FAIL  line {n}: {ch!r} - .cel2 goes through tcsh, so only "
                  f"letters, digits, space, [ ] and _ are safe (no comments)")
        print(f"\n{len(bad)} problem(s)")
        return 1

    groups = parse_cel2(CEL2)
    ports = rtl_ports(RTL)
    slots = frame_slots(FRAME)

    per_side = {}
    listed = []
    for g in groups:
        if g['side'] is None:
            print(f"FAIL  padgroup {g['name']} has no 'restrict side'")
            return 1
        per_side.setdefault(g['side'], []).extend(g['pins'])
        listed += g['pins']

    errors = 0

    for g in groups:
        print(f"  {g['name']:12s} side {g['side']}  "
              f"{len(g['pins'])} pins  {' '.join(g['pins'])}")
    print()

    # Side to package pin range, read off MPW_PAD_28Pin_IO_Games.mag against
    # MyChip_Game_Package.txt.  Shown so the pinout the board will see is
    # visible here rather than worked out again by hand.
    PINS = {'L': '1..7', 'B': '8..14', 'R': '15..21', 'T': '22..28'}

    free = 0
    for side in ('T', 'R', 'B', 'L'):
        n, cap = len(per_side.get(side, [])), slots.get(side, 0)
        ok = n <= cap
        errors += 0 if ok else 1
        free += cap - n if ok else 0
        print(f"  side {side} (package pins {PINS[side]:>6s}): "
              f"{n} signal / {cap} slots, {cap - n} free for power  "
              f"{'' if ok else 'OVER CAPACITY'}")
    print(f"\n  {len(listed)} signal pads, {free} slots left for VDD/GND "
          f"across {sum(1 for s in 'TRBL' if slots.get(s, 0) - len(per_side.get(s, [])) > 0)} sides")
    print()

    missing = sorted(set(ports) - set(listed))
    unknown = sorted(set(listed) - set(ports))
    dupes = sorted({p for p in listed if listed.count(p) > 1})

    for name, bad in (('unconstrained port', missing),
                      ('twpin name that is not a port', unknown),
                      ('port listed twice', dupes)):
        if bad:
            errors += len(bad)
            for b in bad:
                print(f"FAIL  {name}: {b}")

    if errors:
        print(f"\n{errors} problem(s)")
        return 1
    print(f"  all {len(ports)} ports constrained, no side over capacity")
    print("\ncel2 OK")
    return 0


if __name__ == '__main__':
    sys.exit(main())
