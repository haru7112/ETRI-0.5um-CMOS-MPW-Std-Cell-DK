#!/usr/bin/env python3
"""Cross check snake_chip.cel2 against the RTL port list and the pad frame.

A typo in a twpin_ name is not an error to graywolf - the pin simply ends up
unconstrained and lands wherever the placer likes, which is exactly what the
file exists to prevent.  Nothing else in the flow notices, so check it here.

    python3 check_cel2.py

Checks:
  * every port of snake_chip appears exactly once
  * no twpin_ name that is not a port
  * no side carries more pads than the frame has slots on that side, counted
    from pads_ETRI/MPW_PAD_28Pin_IO.mag rather than assumed
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


def main():
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
