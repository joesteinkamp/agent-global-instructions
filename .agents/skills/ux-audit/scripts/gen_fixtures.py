#!/usr/bin/env python3
"""Generate deterministic fixture screenshots with seeded UX flaws.

Each fixture's deliberate flaws are documented in its expected.json.
"""
import argparse
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
FIX = ROOT / "fixtures"
DEJAVU = "/usr/share/fonts/truetype/dejavu/DejaVuSans{}.ttf"


def font(size, bold=False):
    try:
        return ImageFont.truetype(DEJAVU.format("-Bold" if bold else ""), size)
    except OSError:
        return ImageFont.load_default()


def text_c(d, cx, cy, s, f, fill):
    b = d.textbbox((0, 0), s, font=f)
    d.text((cx - (b[2] - b[0]) / 2, cy - (b[3] - b[1]) / 2 - b[1]), s, font=f, fill=fill)


def button(d, box, label, bg, fg, size=16, radius=8):
    d.rounded_rectangle(box, radius=radius, fill=bg)
    text_c(d, (box[0] + box[2]) / 2, (box[1] + box[3]) / 2, label, font(size, True), fg)


def input_box(d, box, placeholder=None, label=None, value=None):
    if label:
        d.text((box[0], box[1] - 24), label, font=font(14, True), fill="#2a2f3a")
    d.rounded_rectangle(box, radius=6, outline="#d0d4da", width=2, fill="#ffffff")
    if placeholder:
        d.text((box[0] + 14, (box[1] + box[3]) / 2 - 9), placeholder,
               font=font(15), fill="#c2c7cf")
    if value:
        d.text((box[0] + 14, (box[1] + box[3]) / 2 - 9), value,
               font=font(15), fill="#1f2330")


def header(d, w, name, links, dark="#1f2330"):
    d.rectangle([0, 0, w, 70], fill=dark)
    d.text((40, 22), name, font=font(22, True), fill="#ffffff")
    x = w - 60
    for link in reversed(links):
        b = d.textbbox((0, 0), link, font=font(14))
        x -= (b[2] - b[0]) + 36
        d.text((x, 28), link, font=font(14), fill="#aab2bf")


def flawed_checkout():
    """Seeded: placeholder-only labels, 3 equal CTAs, vague labels, no order total,
    low-contrast delivery text + CTA text, tiny remove links."""
    img = Image.new("RGB", (1440, 900), "#ffffff")
    d = ImageDraw.Draw(img)
    header(d, 1440, "SHOPLY", ["Shop", "Deals", "Account", "Cart (3)"])
    d.text((80, 110), "Checkout", font=font(28, True), fill="#1f2330")
    for i, ph in enumerate(["Email address", "Card number", "Expiry", "CVC"]):
        input_box(d, [80, 170 + i * 70, 700, 220 + i * 70], placeholder=ph)
    # three identically weighted CTAs with mechanism labels; pale-blue bg with
    # white text = seeded contrast failure
    for i, lbl in enumerate(["Submit", "Continue", "Apply"]):
        button(d, [80 + i * 220, 480, 280 + i * 220, 530], lbl, "#a8c4f0", "#ffffff")
    d.text((80, 560), "Delivery in 3-5 business days", font=font(14), fill="#c9cdd4")
    # order summary without a total
    d.rounded_rectangle([800, 110, 1360, 560], radius=10, outline="#d0d4da", width=2)
    d.text((830, 130), "Order summary", font=font(20, True), fill="#1f2330")
    items = [("Trail running shoes", "$89.00"), ("Wool socks x2", "$24.00"),
             ("Hydration vest", "$129.00")]
    for i, (name, price) in enumerate(items):
        y = 190 + i * 60
        d.text((830, y), name, font=font(15), fill="#1f2330")
        d.text((1230, y), price, font=font(15), fill="#1f2330")
        d.text((830, y + 22), "Remove", font=font(11), fill="#b8bec7")
    d.text((830, 400), "Shipping calculated at next step*", font=font(13), fill="#9aa3ae")
    d.rounded_rectangle([800, 600, 1360, 700], radius=10, fill="#fff3cd")
    text_c(d, 1080, 650, "LIMITED TIME: Save 10% with code SAVE10!", font(18, True), "#8a6d00")
    return {"screen-0.png": img}


def polished_settings():
    """Clean control fixture: labeled inputs, one primary CTA, active nav state."""
    img = Image.new("RGB", (1440, 900), "#ffffff")
    d = ImageDraw.Draw(img)
    header(d, 1440, "Ledgerly", ["Docs", "Support", "jordan@…"])
    d.rectangle([0, 70, 260, 900], fill="#f5f6f8")
    for i, (item, active) in enumerate([("Profile", True), ("Billing", False),
                                        ("Team", False), ("Notifications", False)]):
        y = 110 + i * 48
        if active:
            d.rectangle([0, y - 8, 4, y + 28], fill="#1d4ed8")
            d.text((28, y), item, font=font(15, True), fill="#1d4ed8")
        else:
            d.text((28, y), item, font=font(15), fill="#3f4654")
    d.text((320, 110), "Profile settings", font=font(26, True), fill="#1f2330")
    input_box(d, [320, 200, 860, 248], label="Full name", value="Jordan Steinka")
    input_box(d, [320, 300, 860, 348], label="Email address", value="jordan@example.com")
    d.text((320, 358), "We'll only use this for receipts.", font=font(13), fill="#5b6472")
    button(d, [320, 420, 480, 468], "Save changes", "#1d4ed8", "#ffffff", 15)
    d.rounded_rectangle([500, 420, 610, 468], radius=8, outline="#aab2bf", width=2)
    text_c(d, 555, 444, "Cancel", font(15), "#3f4654")
    return {"screen-0.png": img}


def mobile_small_targets():
    """Seeded: 18px touch targets with 6px gaps, 11px cramped text links."""
    img = Image.new("RGB", (390, 844), "#14161c")
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([45, 80, 345, 380], radius=14, fill="#2b3040")
    text_c(d, 195, 230, "♪", font(80, True), "#5b6480")
    text_c(d, 195, 430, "Midnight Drive", font(22, True), "#ffffff")
    text_c(d, 195, 465, "The Lanterns", font(15), "#8b93a1")
    d.rounded_rectangle([45, 520, 345, 526], radius=3, fill="#2b3040")
    d.rounded_rectangle([45, 520, 165, 526], radius=3, fill="#6aa9ff")
    d.text((45, 538), "1:24", font=font(11), fill="#8b93a1")
    d.text((318, 538), "3:51", font=font(11), fill="#8b93a1")
    # 5 tiny 18x18 controls, 6px apart, centered around x=195
    icons = ["⏮", "−", "▶", "+", "⏭"]
    start = 195 - (5 * 18 + 4 * 6) // 2
    for i, ic in enumerate(icons):
        x = start + i * 24
        d.rectangle([x, 600, x + 18, 618], outline="#8b93a1", width=1)
        text_c(d, x + 9, 609, ic, font(10), "#d7dce4")
    links = "Lyrics   Queue   Share   Sleep timer"
    text_c(d, 195, 700, links, font(11), "#8b93a1")
    return {"screen-0.png": img}


def flow_signup():
    """Seeded: CTA renamed mid-flow (screens 1->2), equal-weight plans with no
    default, no signup confirmation on the final screen, empty dashboard."""
    screens = {}
    # s0 landing
    img = Image.new("RGB", (1200, 800), "#ffffff")
    d = ImageDraw.Draw(img)
    header(d, 1200, "Tripfolk", ["Features", "Pricing", "Sign in"])
    text_c(d, 600, 280, "Plan trips together", font(44, True), "#1f2330")
    text_c(d, 600, 350, "Shared itineraries, budgets, and maps for groups.",
           font(18), "#5b6472")
    button(d, [490, 420, 710, 472], "Create account", "#2563eb", "#ffffff", 17)
    screens["screen-0.png"] = img
    # s1 form (consistent CTA)
    img = Image.new("RGB", (1200, 800), "#ffffff")
    d = ImageDraw.Draw(img)
    header(d, 1200, "Tripfolk", ["Sign in"])
    text_c(d, 600, 150, "Create your account", font(30, True), "#1f2330")
    input_box(d, [400, 240, 800, 288], label="Email address")
    input_box(d, [400, 350, 800, 398], label="Password")
    d.text((400, 408), "At least 12 characters.", font=font(13), fill="#5b6472")
    button(d, [400, 460, 620, 512], "Create account", "#2563eb", "#ffffff", 17)
    screens["screen-1.png"] = img
    # s2 plans (renamed CTA, 4 equal plans)
    img = Image.new("RGB", (1200, 800), "#ffffff")
    d = ImageDraw.Draw(img)
    header(d, 1200, "Tripfolk", ["Sign in"])
    text_c(d, 600, 140, "Choose your plan", font(30, True), "#1f2330")
    for i, (name, price) in enumerate([("Solo", "$0"), ("Duo", "$4/mo"),
                                       ("Crew", "$9/mo"), ("Caravan", "$19/mo")]):
        x = 90 + i * 270
        d.rounded_rectangle([x, 220, x + 240, 520], radius=10, outline="#d0d4da", width=2)
        text_c(d, x + 120, 270, name, font(20, True), "#1f2330")
        text_c(d, x + 120, 330, price, font(26, True), "#1f2330")
        text_c(d, x + 120, 420, "All core features", font(13), "#5b6472")
    button(d, [490, 600, 710, 652], "Register now", "#2563eb", "#ffffff", 17)
    screens["screen-2.png"] = img
    # s3 dashboard, no confirmation, empty
    img = Image.new("RGB", (1200, 800), "#ffffff")
    d = ImageDraw.Draw(img)
    header(d, 1200, "Tripfolk", ["Trips", "Budget", "Settings"])
    d.text((80, 110), "Trips", font=font(28, True), fill="#1f2330")
    d.rounded_rectangle([80, 170, 1120, 700], radius=10, outline="#e3e6ea", width=2)
    screens["screen-3.png"] = img
    return screens


def dark_pricing():
    """Seeded: fake countdown + scarcity on a digital good, pre-checked paid add-on,
    confirmshaming decline, hidden annual billing footnote."""
    img = Image.new("RGB", (1440, 900), "#ffffff")
    d = ImageDraw.Draw(img)
    header(d, 1440, "PixelForge Pro", ["Features", "Pricing", "Sign in"])
    text_c(d, 720, 150, "Go Pro today", font(38, True), "#1f2330")
    d.rounded_rectangle([560, 200, 880, 250], radius=8, fill="#fde8e8")
    text_c(d, 720, 225, "⏳ Offer ends in 04:59", font(18, True), "#c0392b")
    d.rounded_rectangle([470, 290, 970, 700], radius=12, outline="#d0d4da", width=2)
    text_c(d, 720, 340, "Pro plan", font(24, True), "#1f2330")
    text_c(d, 720, 410, "$9/mo*", font(48, True), "#1f2330")
    d.rounded_rectangle([590, 460, 850, 492], radius=999, fill="#fff3cd")
    text_c(d, 720, 476, "Only 2 licenses left!", font(14, True), "#8a6d00")
    # pre-checked paid add-on
    d.rectangle([560, 530, 580, 550], fill="#2563eb")
    text_c(d, 570, 540, "✓", font(14, True), "#ffffff")
    d.text((592, 532), "Add Priority Support  +$14/mo", font=font(15), fill="#1f2330")
    button(d, [560, 590, 880, 645], "Upgrade now", "#16a34a", "#ffffff", 19)
    text_c(d, 720, 672, "No thanks, I hate saving money", font(12), "#9aa3ae")
    d.text((60, 860), "*billed annually at $108 today", font=font(10), fill="#b9bec7")
    return {"screen-0.png": img}


FIXTURES = {
    "flawed-checkout": flawed_checkout,
    "polished-settings": polished_settings,
    "mobile-small-targets": mobile_small_targets,
    "flow-signup": flow_signup,
    "dark-pricing": dark_pricing,
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only")
    args = ap.parse_args()
    for name, fn in FIXTURES.items():
        if args.only and name != args.only:
            continue
        outdir = FIX / name
        outdir.mkdir(parents=True, exist_ok=True)
        for fname, img in fn().items():
            img.save(outdir / fname)
            print(f"wrote {outdir / fname}")


if __name__ == "__main__":
    main()
