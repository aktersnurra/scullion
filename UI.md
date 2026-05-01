---

# 🎨 Design language (baseline)

**Principles**

* High contrast, low color
* Typography does most of the work
* Big targets (kiosk-first)
* No cards unless necessary
* No shadows, almost no borders

**Palette**

* Background: `#0f1115`
* Surface: `#151821`
* Text: `#e8eaf0`
* Muted: `#9aa3b2`
* Accent: `#b7ff6a` (only for “active / checked / today”)

**Typography**

* System font stack
* Large scale:

  * 32px → headers (kiosk)
  * 20px → primary actions
  * 16px → normal
  * 14px → metadata

**Spacing**

* 8px grid
* Generous padding (kiosk finger-first)

---

# 🧭 Navigation model

No sidebar. No tabs.

Just:

```
[ Week ] [ Groceries ] [ Prep ] [ Pantry ] [ Costs ] [ Settings ]
```

* Top horizontal strip (kiosk)
* Bottom sticky (mobile)

---

# 📅 1. Planner (home screen, kiosk-first)

This is *the* screen.

```
┌──────────────────────────────────────────────┐
│ Week 18 — May 2026           [ Regenerate ]  │
├──────────────────────────────────────────────┤

  Mon        Tue        Wed        Thu        Fri        Sat        Sun

  Spaghetti  Chicken    Leftovers  Salmon     Tacos      —          —
  4 portions 6 portions            3 portions 5 portions

  [swap]     [swap]     [clear]    [swap]     [swap]

──────────────────────────────────────────────

Notes
• 2 matlådor from Tue → Wed
• Uses Coop chicken deal

```

**Interactions**

* Tap day → opens recipe drawer
* “swap” → opens recipe picker
* “clear” → removes
* “Regenerate” → calls LLM flow

**Mobile variant**

* Vertical list instead of grid

---

# 🥕 2. Grocery List (real-time, core UX)

```
Groceries — Week 18

Produce
[ ] Onion (2)
[ ] Garlic (1 bulb)
[✓] Carrots (500g)

Meat
[ ] Chicken thighs (1.2kg)

Pantry
[✓] Crushed tomatoes (2 cans)
[ ] Pasta (500g)

────────────────────────────
[ + Add item ]
```

**Key behaviors**

* Tap anywhere on row → toggle
* Instant sync (PubSub)
* Checked items fade + move down (soft reorder)

**Micro detail**

* Show *who* checked item (small initials)
* Undo via tap again (event sourcing shines here)

---

# 🍳 3. Prep Guide (Sunday flow)

```
Prep — Week 18

Sunday (90 min total)

1. Roast vegetables
   → carrots, onion, garlic
   → 200°C, 30 min

2. Cook chicken
   → split into 3 portions

3. Boil pasta (for Mon/Tue)

4. Sauce base
   → tomato + garlic + spices

────────────────────────────

Timeline
12:00 Start oven
12:10 Chop vegetables
12:20 Chicken in pan
...

```

**Tone**

* Reads like a chef note, not an app
* No UI noise

---

# 🧾 4. Receipt Upload (mobile-first)

```
Add receipt

[ Upload photo ]

──────────────

Parsed items

Milk             1 x 18.90
Chicken          1 x 89.00
Pasta            2 x 12.50

Total: 132.90

[ Save ]   [ Edit ]
```

**Edit mode**

* Inline editable rows
* No modal hell

---

# 🥫 5. Pantry

```
Pantry

Onion           2
Garlic          1 bulb
Pasta           300g
Rice            1kg

[ + Add item ]
```

Dead simple. No categories unless needed.

---

# 📉 6. Costs

```
This week

Groceries:   842 kr
Dining out:  320 kr

Cost / meal: 38 kr

────────────────────────────

Apr 2026

Groceries:   3,200 kr
Dining out:  1,100 kr
```

No charts unless you *really* need them.

---

# ⚙️ 7. Settings (admin-heavy, still minimal)

```
Settings

Users
• Gustaf (admin)
• Anna

[ + Generate new code ]

──────────────

Device tokens
• Kitchen kiosk   (active)

[ Revoke ]

──────────────

Stores
• ICA Maxi Solna
• Coop Nära

──────────────

Jobs
[ Run deal scrape ]
[ Generate plan ]
```

---

# 🔢 8. Login (important, tactile)

```
Enter code

[ 1234 ]
[ 5678 ]
[ 9012 ]
[ 3456 ]

[ 1 ] [ 2 ] [ 3 ]
[ 4 ] [ 5 ] [ 6 ]
[ 7 ] [ 8 ] [ 9 ]
[     0     ]

[ Clear ]   [ Enter ]
```

**Critical**

* Huge buttons
* Immediate feedback
* Works with messy hands

---

# 🧩 Component primitives

You really only need ~6:

### 1. Row

```
[label.................value]
```

### 2. Section

```
Title
------
content
```

### 3. Button

* Text only or subtle outline
* No gradients

### 4. Input (rare)

* Underline style, not boxed

### 5. List

* Flat, no cards

### 6. Drawer (important)

Used for:

* recipe details
* editing
* swap flows

---

# 🧠 UX tone (this matters more than layout)

* No empty states like “You have no groceries 🎉”
  → just show nothing or “No items”

* No confirmation dialogs unless destructive

* No spinners if you can avoid it
  → optimistic UI + eventual correction

* LLM actions should feel:

  * deliberate
  * not magical
  * always overrideable

---

# 🔥 What makes this “based”

* It respects **kitchen reality** (wet hands, quick glances)
* It avoids **product theater**
* It leans into **event sourcing UX** (undo, real-time)
* It treats LLM as **assistant, not authority**

---

If you want next step, I can:

* turn this into **actual Phoenix LiveView components**
* or design the **planner + grocery LiveViews in code (HEEx + Tailwind)**

