#!/usr/bin/env python3
"""
Pre-flight check for the Zybo Z7-20 build, runnable without Vivado.

  1. every port of snake_zybo_top has exactly one PACKAGE_PIN, and every
     constrained port exists in the Verilog - a typo either way is a synthesis
     error that costs a full Vivado run to discover;
  2. every package pin is a real Zybo Z7 Rev.B pin and is the one Digilent's
     master XDC gives for the board signal we think we are using.

The pin table below is transcribed from Digilent/digilent-xdc
Zybo-Z7-Master.xdc.  Note the trap it avoids: JB/JC/JD are differential Pmods
whose array index runs p[1], n[1], p[2], n[2] ... so jc[1] is physical pin JC7,
not JC2.  JE is a standard Pmod and its index order is the pin order.

    python3 check_xdc.py
"""
import re, sys, os

HERE = os.path.dirname(os.path.abspath(__file__))

# package pin -> Zybo Z7 Rev.B board signal (from Zybo-Z7-Master.xdc)
ZYBO = {
    'K17': 'sysclk (125MHz)',
    'G15': 'sw[0]',  'P15': 'sw[1]',  'W13': 'sw[2]',  'T16': 'sw[3]',
    'K18': 'btn[0]', 'P16': 'btn[1]', 'K19': 'btn[2]', 'Y16': 'btn[3]',
    'M14': 'led[0]', 'M15': 'led[1]', 'G14': 'led[2]', 'D18': 'led[3]',
    # Pmod JE - standard Pmod, index order == physical pin order
    'V12': 'Pmod JE1', 'W16': 'Pmod JE2', 'J15': 'Pmod JE3', 'H15': 'Pmod JE4',
    'V13': 'Pmod JE7', 'U17': 'Pmod JE8', 'T17': 'Pmod JE9', 'Y17': 'Pmod JE10',
    # Pmod JC - differential; listed p[1], n[1], p[2], n[2] ...
    'V15': 'Pmod JC1', 'W15': 'Pmod JC7', 'T11': 'Pmod JC2', 'T10': 'Pmod JC8',
    'W14': 'Pmod JC3', 'Y14': 'Pmod JC9', 'T12': 'Pmod JC4', 'U12': 'Pmod JC10',
}

def verilog_ports(path):
    src = open(path).read()
    src = re.sub(r'//[^\n]*', '', src)
    body = src[src.index('module snake_zybo_top'):]
    body = body[body.index('(') + 1: body.index(');')]
    return [m.group(1) for m in
            re.finditer(r'\b(?:input|output|inout)\s+wire\s+(\w+)', body)]

def xdc_pins(path):
    pins = {}
    for line in open(path):
        m = re.search(r'PACKAGE_PIN\s+(\w+).*?get_ports\s+(\w+)', line)
        if m:
            pins.setdefault(m.group(2), []).append(m.group(1))
    return pins

def main():
    ports = verilog_ports(os.path.join(HERE, 'snake_zybo_top.v'))
    pins  = xdc_pins(os.path.join(HERE, 'zybo_z7_20.xdc'))
    bad = 0

    for p in ports:
        if p not in pins:
            print(f'[FAIL] port {p} has no PACKAGE_PIN'); bad += 1
        elif len(pins[p]) != 1:
            print(f'[FAIL] port {p} is constrained {len(pins[p])} times'); bad += 1
    for p in pins:
        if p not in ports:
            print(f'[FAIL] constrained port {p} does not exist in the Verilog'); bad += 1

    used = {}
    for p, (pin,) in ((p, v) for p, v in pins.items() if len(v) == 1):
        if pin not in ZYBO:
            print(f'[FAIL] {p}: {pin} is not a Zybo Z7 pin in the master XDC'); bad += 1
        elif pin in used:
            print(f'[FAIL] {p} and {used[pin]} both drive pin {pin}'); bad += 1
        else:
            used[pin] = p
            print(f'  {p:12s} {pin:5s}  {ZYBO[pin]}')

    print()
    print('==== XDC CHECK PASSED ====' if bad == 0 else
          f'==== XDC CHECK FAILED, {bad} problem(s) ====')
    return 1 if bad else 0

if __name__ == '__main__':
    sys.exit(main())
