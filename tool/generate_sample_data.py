#!/usr/bin/env python3
"""Generates Bondbell's bundled SAMPLE lists.

Every number is random (fixed seed) apart from the planted sample wins.
Nothing is copied from NS&I's files: only the page layout is imitated so
the app's real parser runs on the sample. Run from the repo root:
    python3 tool/generate_sample_data.py
"""
import io, random, zipfile

random.seed(20261114)
LETTERS = "ABCDEFGHJKLMNPQRSTVWXYZ"
SAMPLE_RANGES = [("312KM", 104000, 104499), ("47DW", 185520, 185569)]
DRAW_WINS = {100: ["312KM104217"], 25: ["312KM104388"]}
UNCLAIMED_WINS = {50: ["47DW185533"]}
TIERS = [(1000000, 2), (100000, 4), (50000, 6), (25000, 8), (10000, 12),
         (5000, 16), (1000, 40), (500, 80), (100, 640), (50, 640), (25, 480)]
ROMAN = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI"]


def in_sample(n):
    for s, lo, hi in SAMPLE_RANGES:
        if n.startswith(s) and n[len(s):].isdigit() and len(n) - len(s) == 6:
            if lo <= int(n[len(s):]) <= hi:
                return True
    return False


def rand_bond():
    while True:
        p = random.choice(["", str(random.randint(1, 99)), str(random.randint(100, 692))])
        n = f"{p}{random.choice(LETTERS)}{random.choice(LETTERS)}{random.randint(0, 999999):06d}"
        if not in_sample(n):
            return n


def rows(nums, per=8):
    for i in range(0, len(nums), per):
        yield " ".join(f"{x:>11}" for x in nums[i:i + per])


def winners():
    out = io.StringIO()
    bar = "_" * 95
    out.write(f"{bar}\r\n\r\n\r\nPREMIUM BOND PRIZE DRAW{'Sample 2026':>72}\r\n{bar}\r\n\r\n")
    out.write("SAMPLE DATA - MADE-UP NUMBERS FOR DEMONSTRATION ONLY\r\n\r\n")
    total = sum(c for _, c in TIERS)
    fund = sum(v * c for v, c in TIERS)
    out.write(f"Notes:\r\n(i)  The amount for distribution is £{fund:,} which sum gives a total of {total:,} prizes. Parts I - XI as follows:\r\n\r\n")
    cells = [f"{ROMAN[i]}. {c:,} prize{'(s)' if i == 0 else 's'} of £{v:,}" for i, (v, c) in enumerate(TIERS)]
    for i in range(0, len(cells), 2):
        out.write("| " + " | ".join(f"{c:<44}" for c in cells[i:i + 2]) + " |\r\n" + bar + "\r\n")
    out.write("\r\n                             NUMBERS DRAWN FOR PRIZES IN THE MONTHLY DRAW\r\n\r\n")
    for i, (v, c) in enumerate(TIERS):
        planted = DRAW_WINS.get(v, [])
        nums = planted + [rand_bond() for _ in range(c - len(planted))]
        random.shuffle(nums)
        out.write(f"\r\n                Part {ROMAN[i]} - Numbers drawn for Prizes of £{v:,} each \r\n\r\n")
        for j, r in enumerate(rows(nums)):
            if j and j % 40 == 0:
                out.write(f"\r\n{'Page No. ' + str(j // 40 + 2):>86}\r\n\r\n                Part {ROMAN[i]} - Prizes of £{v:,} each (contd.)\r\n\r\n")
            out.write(r + "\r\n")
    return out.getvalue()


def unclaimed():
    out = io.StringIO()
    for section, tiers in (("UNCLAIMED", [(1000, 12), (500, 30), (100, 200), (50, 400), (25, 600)]),
                           ("ANONYMOUS", [(50, 10), (25, 12)])):
        for v, c in tiers:
            planted = UNCLAIMED_WINS.get(v, []) if section == "UNCLAIMED" else []
            nums = planted + [rand_bond() for _ in range(c - len(planted))]
            random.shuffle(nums)
            out.write(f"LGS {section} £{v}\r\n")
            for r in rows(nums):
                out.write(r + "\r\n")
            out.write(f"END OF £{v}, TOTAL BSN = {c}\r\n\r\n")
    return out.getvalue()


def write_zip(path, name, text):
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr(name, text.encode("latin-1"))


write_zip("assets/sample/sample_winners.zip", "SAMPLE_WINNERS.txt", winners())
write_zip("assets/sample/sample_unclaimed.zip", "SAMPLE_UNCLAIMED.txt", unclaimed())
print("written")
