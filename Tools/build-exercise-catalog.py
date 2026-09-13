# -*- coding: utf-8 -*-
"""Builds Veyra's exercise catalogue from the Everkinetic dataset (CC BY-SA 4.0).

The artwork is a black silhouette on white. Converted to an alpha mask it can be
tinted by the app, which means one file works in light and dark mode and looks
like it belongs to Veyra rather than pasted in.
"""
import json, os, re, sys, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from importlib.machinery import SourceFileLoader
spanish = SourceFileLoader("veyra_translate", os.path.join(os.path.dirname(os.path.abspath(__file__)), "exercise-name-translation.py")).load_module().spanish
from PIL import Image

SOURCE = "/tmp/ekdata"
DEST = "/Users/diego/Proyectos/Personales/Veyra/Resources"
ART = os.path.join(DEST, "ExerciseArt")
HEIGHT = 420          # tallest frame of each pair, in pixels

MUSCLE = {
    "chest": "chest", "triceps": "triceps", "biceps": "biceps", "arms": "biceps",
    "shoulders": "shoulders", "lateral deltoid": "shoulders", "rear deltoid": "shoulders",
    "posterior deltoid": "shoulders", "trapezius": "traps", "middle back": "back",
    "lats": "lats", "back": "back", "lower back": "lowerBack", "abdominals": "abs",
    "lower abdominals": "abs", "obliques": "obliques", "core": "abs", "quadriceps": "quadriceps",
    "hamstring": "hamstrings", "hamstrings": "hamstrings", "gluts": "glutes", "glutes": "glutes",
    "calves": "calves", "neck extensors": "neck", "neck flexors": "neck",
    "neck side flexors": "neck", "forearms": "forearms",
}
GROUP = {
    "chest": "chest", "triceps": "arms", "biceps": "arms", "forearms": "arms",
    "shoulders": "shoulders", "traps": "back", "back": "back", "lats": "back",
    "lowerBack": "back", "abs": "core", "obliques": "core",
    "quadriceps": "legs", "hamstrings": "legs", "glutes": "legs", "calves": "legs",
    "neck": "other",
}
EQUIPMENT = {
    "barbell": "barbell", "dumbbell": "dumbbell", "dumbbells": "dumbbell", "cable": "cable",
    "cables": "cable", "machine": "machine", "smith machine": "smith", "bench": "bench",
    "stability ball": "ball", "exercise ball": "ball", "ball": "ball", "medicine ball": "ball",
    "bosu": "ball", "dome": "ball", "band": "band", "bands": "band", "exercise band": "band",
    "ez bar": "ezbar", "weight plate": "plate", "plate": "plate", "weight": "plate",
    "bar": "barbell", "kettlebell": "kettlebell", "body weight": "bodyweight",
    "bodyweight": "bodyweight", "towel": "other", "chair": "other", "step": "other",
    "rope": "cable", "roman chair": "other", "pull up bar": "bar", "dip bar": "bar",
}

# The source leaves a few entries unclassified. One case, fixed by hand.
PRIMARY_FIX = {"push-up-feet-elevated": ["chest"]}

def muscles(value):
    if not value: return []
    parts = [p.strip().lower() for p in re.split(r"[,/]", value if isinstance(value, str) else ", ".join(value))]
    out = []
    for part in parts:
        key = MUSCLE.get(part)
        if key and key not in out: out.append(key)
    return out

def equipment_keys(values):
    out = []
    for value in values or []:
        key = EQUIPMENT.get(value.strip().lower())
        if key and key not in out: out.append(key)
    return out

def pattern(title, primary):
    low = title.lower()
    if re.search(r"squat|lunge|leg press|step up|hack", low): return "squat"
    if re.search(r"deadlift|dead lift|good morning|hip|bridge|thrust|hyperextension|back extension", low): return "hinge"
    if primary in ("abs", "obliques"): return "core"
    if primary in ("chest", "shoulders", "triceps"): return "push"
    if primary in ("back", "lats", "traps", "biceps", "lowerBack"): return "pull"
    if primary in ("quadriceps",): return "squat"
    if primary in ("hamstrings", "glutes"): return "hinge"
    return "other"

def convert(pair, stem):
    """Both frames, cropped to their own figure but scaled by a single factor so
    the animation between them does not jump, then written as an alpha mask."""
    images = []
    for path in pair:
        grey = Image.open(path).convert("L")
        mask = grey.point(lambda v: 255 - v)          # figure opaque, paper clear
        box = mask.getbbox()
        if box: mask = mask.crop(box)
        images.append(mask)
    tallest = max(im.height for im in images)
    scale = HEIGHT / tallest
    written = []
    for index, mask in enumerate(images):
        size = (max(1, round(mask.width * scale)), max(1, round(mask.height * scale)))
        mask = mask.resize(size, Image.LANCZOS)
        out = Image.new("LA", size, (0, 0))
        out.putalpha(mask)
        name = f"{stem}-{index + 1}.png"
        out.save(os.path.join(ART, name), optimize=True)
        written.append(name)
    return written

# Instructions translated from the source dataset, keyed by the original
# sentence. Built once by hand and kept in the repo so the catalogue can be
# regenerated without redoing the work.
STEPS = json.load(open(os.path.join(os.path.dirname(DEST), "Tools", "exercise-steps-es.json")))

def steps(raw):
    """Spanish instructions, with the source's stray HTML dropped."""
    out = []
    for step in raw or []:
        text = step.replace("\xa0", " ").strip()
        if not text or re.fullmatch(r"(<[^>]*>\s*)+|&nbsp;|Steps", text, re.I):
            continue
        translated = STEPS.get(step) or STEPS.get(text)
        if translated:
            out.append(translated)
    return out

def main():
    os.makedirs(ART, exist_ok=True)
    for old in os.listdir(ART):
        if old.endswith(".png"): os.remove(os.path.join(ART, old))
    source = json.load(open(os.path.join(SOURCE, "exercises.json")))
    catalogue, skipped = [], 0
    names = collections.Counter()
    for item in source:
        num = item.get("id_num")
        frames = [os.path.join(SOURCE, "dist/png", f"{num}-{kind}.png") for kind in ("relaxation", "tension")]
        frames = [f for f in frames if os.path.exists(f)]
        if not frames:
            skipped += 1
            continue
        primary = PRIMARY_FIX.get(item["name"]) or muscles(item.get("primary"))
        secondary = muscles(item.get("secondary"))
        equipment = equipment_keys(item.get("equipment"))
        title = spanish(item["title"])
        names[title] += 1
        art = convert(frames, item["name"])
        catalogue.append({
            "id": item["name"],
            "name": title,
            "englishName": item["title"],
            "primaryMuscles": primary,
            "secondaryMuscles": secondary,
            "group": GROUP.get(primary[0], "other") if primary else "other",
            "equipment": equipment[0] if equipment else "bodyweight",
            "allEquipment": equipment,
            "movementPattern": pattern(item["title"], primary[0] if primary else ""),
            "compound": item.get("type") == "compound",
            "unilateral": bool(re.search(r"one arm|single arm|one leg|single leg|one armed|one legged", item["title"], re.I)),
            "bodyweight": not equipment or equipment == ["bodyweight"],
            "steps": steps(item.get("steps")),
            "art": art,
        })
    # The source contains genuine duplicates — "One Leg Squat" and "Single Leg
    # Squat" are the same movement — so entries that translate to the same name
    # and use the same equipment are merged, keeping the shorter id. Names that
    # collide for different equipment are disambiguated instead.
    merged, seen = [], {}
    for entry in sorted(catalogue, key=lambda e: (e["name"], len(e["id"]))):
        key = (entry["name"], tuple(entry["allEquipment"]))
        if key in seen:
            continue
        seen[key] = entry
        merged.append(entry)
    catalogue = merged
    names = collections.Counter(e["name"] for e in catalogue)
    for entry in catalogue:
        if names[entry["name"]] > 1 and entry["allEquipment"]:
            entry["name"] = f"{entry['name']} ({entry['allEquipment'][0]})"
    catalogue.sort(key=lambda e: e["name"])
    assert len({e["name"] for e in catalogue}) == len(catalogue), "nombres duplicados"
    assert all(e["primaryMuscles"] and e["art"] and e["steps"] for e in catalogue), "entradas incompletas"
    with open(os.path.join(DEST, "exercises.json"), "w") as handle:
        json.dump(catalogue, handle, ensure_ascii=False, indent=1)
    # Drop artwork belonging to entries that were merged away.
    used = {name for entry in catalogue for name in entry["art"]}
    for name in os.listdir(ART):
        if name.endswith(".png") and name not in used:
            os.remove(os.path.join(ART, name))
    total = sum(os.path.getsize(os.path.join(ART, f)) for f in os.listdir(ART) if f.endswith(".png"))
    print(f"ejercicios: {len(catalogue)}  sin arte: {skipped}")
    print(f"imágenes: {len(os.listdir(ART))}  peso: {total/1024/1024:.1f} MB")
    print("grupos:", dict(collections.Counter(e['group'] for e in catalogue)))
    print("equipo:", dict(collections.Counter(e['equipment'] for e in catalogue)))
    print("patrones:", dict(collections.Counter(e['movementPattern'] for e in catalogue)))

main()
