# -*- coding: utf-8 -*-
"""Turns Everkinetic's English exercise titles into the Spanish a gym actually
uses. Rule-based, so the result is reviewable: the core movement is matched
from longest phrase to shortest, equipment moves to a trailing phrase, and
whatever is left over is translated as a modifier."""
import re

# Plurals and spellings that would otherwise miss the phrase tables.
SINGULAR = ["raises", "rows", "shrugs", "curls", "flyes", "flys", "squats", "lunges", "dips",
            "extensions", "presses", "crunches", "pullovers", "circles", "kickbacks", "twists",
            "pushdowns", "pulldowns", "rotations", "bends", "ups", "downs", "deadlifts", "planks",
            "thrusts", "bridges", "rollouts", "raise's", "lifts", "mornings", "chins", "kicks",
            "hyperextensions", "supermans", "crossovers", "grips", "versions", "abductions",
            "adductions", "thrusters", "pulls", "swings", "jumps", "holds", "walks", "drops"]

def normalise(t):
    t = t.replace("’", "'").replace("-", " ")
    t = re.sub(r"\bfly'?s\b", "flye", t, flags=re.I)
    t = re.sub(r"\bflyes\b", "flye", t, flags=re.I)
    t = re.sub(r"\bflys\b", "flye", t, flags=re.I)
    t = re.sub(r"\bfly\b", "flye", t, flags=re.I)
    t = re.sub(r"\bbicep\b", "biceps", t, flags=re.I)
    t = re.sub(r"\btricep\b", "triceps", t, flags=re.I)
    t = re.sub(r"\bab\b", "abdominal", t, flags=re.I)
    t = re.sub(r"\bt bar\b", "tbar", t, flags=re.I)
    t = re.sub(r"\bone (armed|legged)\b", lambda m: "one " + m.group(1)[:-4], t, flags=re.I)
    t = re.sub(r"\bbridging\b", "bridge", t, flags=re.I)
    for word in SINGULAR:
        t = re.sub(r"\b" + word + r"\b", word[:-1] if word.endswith("s") else word, t, flags=re.I)
    t = re.sub(r"\bpresse\b", "press", t, flags=re.I)
    t = re.sub(r"\bcrunche\b", "crunch", t, flags=re.I)
    t = re.sub(r"\s+", " ", t).strip()
    return t

# Proper names kept as they are, capitalised.
PROPER = ["tate", "arnold", "cuban", "zottman", "bulgarian", "romanian", "turkish", "russian",
          "scott", "pallof", "jefferson", "svend", "larsen", "spider", "hindu", "bosu", "smith"]

# Equipment, as it appears after "with" / "using" / "on".
EQUIPMENT = [
    ("stability ball", "en fitball"), ("exercise ball", "en fitball"), ("swiss ball", "en fitball"),
    ("bosu ball", "en bosu"), ("medicine ball", "con balón medicinal"),
    ("exercise band", "con banda elástica"), ("resistance band", "con banda elástica"),
    ("exercise bands", "con bandas elásticas"), ("bands", "con bandas elásticas"), ("band", "con banda elástica"),
    ("smith machine", "en multipower"), ("machine", "en máquina"), ("cables", "en polea"), ("cable", "en polea"),
    ("ez bar", "con barra Z"), ("barbell", "con barra"), ("dumbbells", "con mancuernas"), ("dumbbell", "con mancuerna"),
    ("weight plate", "con disco"), ("weight", "con peso"), ("plate", "con disco"),
    ("bench", "en banco"), ("bar", "en barra"), ("ball", "con balón"),
    ("a twist", "con giro"), ("twist", "con giro"), ("chair", "en silla"), ("step", "en step"),
    ("rope", "con cuerda"), ("kettlebell", "con kettlebell"), ("body weight", "con peso corporal"),
]

# The movement itself, longest first so "Bench Press" wins over "Press".
CORE = [
    ("close grip barbell bench press", "Press de banca agarre cerrado con barra"),
    ("incline chest press", "Press inclinado"),
    ("decline chest press", "Press declinado"),
    ("chest press", "Press de pecho"),
    ("bench press", "Press de banca"),
    ("shoulder press", "Press militar"),
    ("military press", "Press militar"),
    ("arnold press", "Press Arnold"),
    ("leg press", "Prensa de piernas"),
    ("calf press", "Prensa de gemelos"),
    ("triceps press to chin", "Press francés al mentón"),
    ("triceps press", "Press de tríceps"),
    ("french press", "Press francés"),
    ("upright row", "Remo al mentón"),
    ("bent over row", "Remo inclinado"),
    ("bent-over row", "Remo inclinado"),
    ("tbar row", "Remo en T"),
    ("lat pull down", "Jalón al pecho"),
    ("lat pulldown", "Jalón al pecho"),
    ("sternum chin", "Dominada al esternón"),
    ("chin", "Dominada supina"),
    ("floor press", "Press en suelo"),
    ("crossover", "Cruce de poleas"),
    ("butterfly", "Contractora"),
    ("hyperextension", "Hiperextensión"),
    ("superman", "Superman"),
    ("flutter kick", "Tijeras"),
    ("leg lift", "Elevación de piernas"),
    ("iron cross", "Cruz de hierro"),
    ("draw", "Vacío abdominal"),
    ("thruster", "Thruster"),
    ("swing", "Swing"),
    ("dead lift", "Peso muerto"),
    ("neck flexion and extension", "Flexión y extensión de cuello"),
    ("neck side flexion", "Flexión lateral de cuello"),
    ("neck extension", "Extensión de cuello"),
    ("neck flexion", "Flexión de cuello"),
    ("flexion", "Flexión"),
    ("row", "Remo"),
    ("lat pulldown", "Jalón al pecho"),
    ("pulldown", "Jalón"),
    ("pull down", "Jalón"),
    ("pushdown", "Extensión de tríceps en polea"),
    ("push down", "Extensión de tríceps en polea"),
    ("pullover", "Pullover"),
    ("chin up", "Dominada supina"),
    ("chin-up", "Dominada supina"),
    ("pull up", "Dominada"),
    ("pull-up", "Dominada"),
    ("push up", "Flexión"),
    ("push-up", "Flexión"),
    ("preacher curl", "Curl en banco Scott"),
    ("concentration curl", "Curl concentrado"),
    ("hammer curl", "Curl martillo"),
    ("drag curl", "Curl drag"),
    ("spider curl", "Curl araña"),
    ("biceps curl", "Curl de bíceps"),
    ("leg curl", "Curl femoral"),
    ("wrist curl", "Curl de muñeca"),
    ("curl", "Curl"),
    ("leg extension", "Extensión de cuádriceps"),
    ("back extension", "Extensión lumbar"),
    ("triceps extension", "Extensión de tríceps"),
    ("extension", "Extensión"),
    ("lateral raise", "Elevación lateral"),
    ("front raise", "Elevación frontal"),
    ("calf raise", "Elevación de talones"),
    ("leg raise", "Elevación de piernas"),
    ("hip raise", "Elevación de cadera"),
    ("shoulder raise", "Elevación de hombros"),
    ("raise", "Elevación"),
    ("deadlift", "Peso muerto"),
    ("dead lift", "Peso muerto"),
    ("good morning", "Buenos días"),
    ("hack squat", "Sentadilla hack"),
    ("sissy squat", "Sentadilla sissy"),
    ("front squat", "Sentadilla frontal"),
    ("split squat", "Sentadilla búlgara"),
    ("squat", "Sentadilla"),
    ("lunge", "Zancada"),
    ("step up", "Subida al step"),
    ("shrug", "Encogimiento de hombros"),
    ("crunch", "Crunch"),
    ("sit up", "Abdominal"),
    ("sit-up", "Abdominal"),
    ("side bend", "Flexión lateral"),
    ("ab rollout", "Rueda abdominal"),
    ("rollout", "Rueda abdominal"),
    ("plank", "Plancha"),
    ("dip", "Fondos"),
    ("flye", "Apertura"),
    ("fly", "Apertura"),
    ("hip adduction", "Aducción de cadera"),
    ("hip abduction", "Abducción de cadera"),
    ("adduction", "Aducción"),
    ("abduction", "Abducción"),
    ("rotation", "Rotación"),
    ("circles", "Círculos"),
    ("kickback", "Patada de tríceps"),
    ("thrust", "Empuje de cadera"),
    ("bridge", "Puente"),
    ("twist", "Giro"),
    ("draw in", "Vacío abdominal"),
    ("balance board", "Tabla de equilibrio"),
    ("wood chop", "Leñador"),
    ("clean", "Cargada"),
    ("snatch", "Arrancada"),
    ("jerk", "Envión"),
    ("press", "Press"),
]

# Everything else: a modifier, placed after the core movement.
MODIFIER = [
    ("one arm", "a una mano"), ("single arm", "a una mano"),
    ("cross body", "cruzado"), ("bent arm", "con brazos flexionados"),
    ("hammer grip", "agarre martillo"), ("parallel grip", "agarre paralelo"),
    ("straight arm", "con brazo extendido"), ("underhand", "agarre supino"),
    ("overhand", "agarre prono"), ("feet elevated", "pies elevados"),
    ("static", "estático"), ("wall", "en pared"), ("reverse", "inverso"),
    ("tbar", "en barra T"), ("elevated", "elevado"), ("one leg", "a una pierna"),
    ("single leg", "a una pierna"), ("alternating", "alterno"), ("alternate", "alterno"),
    ("close grip", "agarre cerrado"), ("wide grip", "agarre ancho"), ("narrow grip", "agarre estrecho"),
    ("reverse grip", "agarre invertido"), ("neutral grip", "agarre neutro"), ("grip", "agarre"),
    ("behind the neck", "tras nuca"), ("behind neck", "tras nuca"),
    ("incline", "inclinado"), ("decline", "declinado"), ("flat", "plano"),
    ("seated", "sentado"), ("standing", "de pie"), ("lying", "tumbado"), ("kneeling", "de rodillas"),
    ("bent over", "inclinado"), ("bent", "inclinado"), ("supine", "supino"), ("prone", "en prono"),
    ("supinated", "supinado"), ("pronated", "pronado"),
    ("overhead", "sobre la cabeza"), ("rear", "posterior"), ("front", "frontal"), ("side", "lateral"),
    ("lateral", "lateral"), ("internal", "interna"), ("external", "externa"),
    ("walking", "caminando"), ("stationary", "estático"), ("rocking", "con balanceo"),
    ("weighted", "con peso"), ("wide stance", "postura ancha"), ("narrow stance", "postura estrecha"),
    ("wide", "ancho"), ("narrow", "estrecho"), ("stance", "postura"),
    ("high", "alto"), ("low", "bajo"), ("half", "medio"), ("full", "completo"),
    ("triceps", "de tríceps"), ("biceps", "de bíceps"), ("chest", "de pecho"), ("shoulder", "de hombro"),
    ("shoulders", "de hombros"), ("leg", "de pierna"), ("legs", "de piernas"), ("calf", "de gemelo"),
    ("neck", "de cuello"), ("abdominal", "abdominal"), ("oblique", "oblicuo"), ("back", "de espalda"),
    ("hip", "de cadera"), ("glute", "de glúteo"), ("hamstring", "femoral"), ("quad", "de cuádriceps"),
    ("wrist", "de muñeca"), ("forearm", "de antebrazo"), ("trap", "de trapecio"),
    ("deltoid", "deltoides"), ("body", "corporal"), ("cross", "cruzado"), ("v", "en V"),
    ("arm", "de brazo"), ("arms", "de brazos"), ("bar", "en barra"), ("ball", "con balón"),
]

ORDER = {"de tríceps": 0, "de bíceps": 0, "de pecho": 0, "de hombro": 0, "de hombros": 0,
         "de espalda": 0, "de pierna": 0, "de piernas": 0, "de gemelo": 0, "de cuello": 0,
         "de cadera": 0, "de glúteo": 0, "femoral": 0, "de cuádriceps": 0, "de muñeca": 0,
         "de antebrazo": 0, "de trapecio": 0, "deltoides": 0, "abdominal": 0, "oblicuo": 0,
         "de brazo": 0, "de brazos": 0,
         "posterior": 1, "frontal": 1, "lateral": 1, "interna": 1, "externa": 1, "cruzado": 1,
         "alto": 1, "bajo": 1, "medio": 1, "completo": 1, "en V": 1,
         "inclinado": 2, "declinado": 2, "plano": 2, "sentado": 2, "de pie": 2, "tumbado": 2,
         "de rodillas": 2, "supino": 2, "en prono": 2, "caminando": 2, "estático": 2,
         "con balanceo": 2, "a una mano": 2, "a una pierna": 2, "alterno": 2,
         "agarre cerrado": 3, "agarre ancho": 3, "agarre estrecho": 3, "agarre invertido": 3,
         "agarre neutro": 3, "agarre": 3, "tras nuca": 3, "sobre la cabeza": 3,
         "postura ancha": 3, "postura estrecha": 3, "postura": 3, "supinado": 3, "pronado": 3,
         "ancho": 3, "estrecho": 3, "con peso": 4, "corporal": 4}

def phrase(text, table, loose=False):
    """Longest-match replacement over a phrase table. With `loose`, a
    multi-word entry tolerates up to two words in between, so "Upright Barbell
    Row" still matches "upright row" with the equipment sitting in the middle."""
    out, rest = [], text
    for english, spanish in sorted(table, key=lambda p: -len(p[0])):
        words = english.split()
        if loose and len(words) > 1:
            pattern = r"\b" + r"\s+(?:\w+\s+){0,2}?".join(re.escape(w) for w in words) + r"\b"
        else:
            pattern = r"\b" + re.escape(english) + r"\b"
        if re.search(pattern, rest):
            out.append(spanish)
            rest = re.sub(pattern, " ", rest, count=1)
    return out, re.sub(r"\s+", " ", rest).strip()

# Movements whose Spanish noun is feminine, so the modifiers have to agree.
# Everything ending in -ión, -ada, -illa, -era, -ura is feminine; these are the
# ones the ending alone gets wrong.
MASCULINE = {"Press", "Curl", "Remo", "Peso muerto", "Jalón", "Fondos", "Crunch", "Pullover",
             "Superman", "Puente", "Thruster", "Swing", "Círculos", "Abdominal", "JM press",
             "Vacío abdominal", "Cruce de poleas", "Buenos días", "Encogimiento de hombros",
             "Press Arnold", "Press Tate", "Press militar", "Press francés", "Curl drag"}

def feminine(core):
    if not core: return False
    if core in MASCULINE: return False
    head = core.split()[0]
    return head.endswith(("ión", "ada", "illa", "era", "ura", "cha", "nsa", "eras", "ones")) or head[-1] == "a"

AGREE = {"inclinado": "inclinada", "declinado": "declinada", "plano": "plana", "tumbado": "tumbada",
         "sentado": "sentada", "alterno": "alterna", "estático": "estática", "inverso": "inversa",
         "supinado": "supinada", "pronado": "pronada", "cruzado": "cruzada", "ancho": "ancha",
         "estrecho": "estrecha", "alto": "alta", "bajo": "baja", "medio": "media",
         "completo": "completa", "elevado": "elevada", "en prono": "en prona", "supino": "supina"}

def agree(modifier, is_feminine):
    return AGREE.get(modifier, modifier) if is_feminine else modifier

def translate(title):
    lower = normalise(title).lower()
    lower = re.sub(r"\b(with|using|on|and|to|the|a|for|in|of)\b", " ", lower)
    lower = re.sub(r"\s+", " ", lower).strip()
    # The movement first, tolerating equipment words inside it, so "Bench
    # Press" is not read as the bench plus a press.
    core, remainder = phrase(lower, CORE, loose=True)
    equipment, remainder = phrase(remainder, EQUIPMENT)
    modifiers, leftover = phrase(remainder, MODIFIER)
    for noise in ["head", "version", "biased", "hand", "feet", "sternum", "gironda", "close",
                  "wide", "straight", "parallel", "leg", "arm", "one", "lift"]:
        pass
    names = [w.capitalize() for w in leftover.split() if w in PROPER]
    for name in names:
        leftover = re.sub(r"\b" + name.lower() + r"\b", " ", leftover)
    modifiers.sort(key=lambda m: ORDER.get(m, 2))
    female = feminine(core[0] if core else "")
    modifiers = [agree(m, female) for m in modifiers]
    # "EZ bar" already says barbell, and "weighted ... weight plate" says the
    # weight twice.
    if "con barra Z" in equipment: equipment = [e for e in equipment if e != "con barra"]
    if "con disco" in equipment: modifiers = [m for m in modifiers if m not in ("con peso", "con pesa")]
    # A bench takes the incline as its own adjective: "en banco plano", not
    # "plana ... en banco".
    if "en banco" in equipment:
        for slope in ("plano", "plana", "inclinado", "inclinada", "declinado", "declinada"):
            if slope in modifiers:
                modifiers.remove(slope)
                equipment[equipment.index("en banco")] = "en banco " + slope.rstrip("a") + ("o" if slope.endswith("a") else "")
                break
    # Two movements in one title ("Bicep Curl Lunge") read as one exercise
    # joined, not as two names run together.
    if len(core) > 1:
        core = [core[0]] + ["+ " + part[0].lower() + part[1:] for part in core[1:]]
    pieces = core + names + modifiers + equipment
    result = re.sub(r"\s+", " ", " ".join(p for p in pieces if p)).strip()
    return result, re.sub(r"\s+", " ", leftover).strip()

# Titles the rules cannot reach cleanly, translated by hand. An explicit table
# beats ever more contorted rules, and it can be read and corrected.
EXCEPTIONS = {
    "Ball Wall Circles": "Círculos con balón en pared",
    "Bent Over Rear Deltoid Raise With Head On Bench": "Elevación posterior de deltoides con la cabeza apoyada",
    "One Armed Biased Push Up": "Flexión con apoyo desigual",
    "Push Ups Close and Wide Hand Versions": "Flexiones con agarre cerrado y ancho",
    "Push Ups with feet on exercise ball": "Flexión con los pies en fitball",
    "Gironda Sternum Chins": "Dominada al esternón (Gironda)",
    "One Legged Cable Kickback": "Patada de glúteo a una pierna en polea",
    "Step Ups with Barbell": "Subida al step con barra",
    "Step Ups with Dumbbells": "Subida al step con mancuernas",
    "Front Squat to Bench with Barbells": "Sentadilla frontal al banco con barra",
    "Pile Squat with Dumbbell": "Sentadilla sumo con mancuerna",
    "Speed Squats with Barbell": "Sentadilla explosiva con barra",
    "Thigh Abductor": "Abductores en máquina",
    "Thigh Adductor": "Aductores en máquina",
    "Zecher Squats": "Sentadilla Zercher",
    "Decline Close Grip Bench to Skull Crusher": "Press declinado agarre cerrado a press francés",
    "JM Press": "JM press",
    "Kneeling Triceps Concentration Extension with Cable": "Extensión concentrada de tríceps de rodillas en polea",
    "Lying Close-Grip Triceps Extension Behind the Head with Barbell": "Press francés tras nuca con barra",
    "Lying Triceps Extension Across Face with Dumbbell": "Extensión de tríceps cruzada tumbado con mancuerna",
    "Lying Two Arm Triceps Extension with Dumbbell": "Extensión de tríceps a dos manos tumbado con mancuernas",
    "Old School Reverse Extensions": "Extensión lumbar inversa",
    "Close Triceps Pushup": "Flexión diamante",
    "Seated Two-Arm Triceps Extension with Dumbbell": "Extensión de tríceps a dos manos sentado con mancuerna",
    "Bent-Over Two Arm Triceps Extension with Dumbbells": "Patada de tríceps a dos manos con mancuernas",
    "Bent-Over Two Arm Triceps Extension with Dumbbell": "Patada de tríceps a dos manos con mancuernas",
    "One Arm Low-Pulley Triceps Extension with Cable": "Extensión de tríceps a una mano en polea baja",
    "Standing Triceps Extension with Towel": "Extensión de tríceps de pie con toalla",
    "Flexor Incline Curls with Dumbbell": "Curl inclinado de flexores con mancuerna",
    "Incline Inner Biceps Curl with Dumbbell": "Curl inclinado de bíceps interno con mancuerna",
    "Preacher Hammer Curl with Dumbbell": "Curl martillo en banco Scott con mancuerna",
    "Seated Inner Biceps Curl with Dumbbell": "Curl sentado de bíceps interno con mancuerna",
    "Standing Inner Biceps Curl with Dumbbell": "Curl de pie de bíceps interno con mancuerna",
    "Standing One Arm Curl Over Incline Bench with Dumbbell": "Curl a una mano sobre banco inclinado con mancuerna",
    "Two-Arm Preacher Curl with Dumbbell": "Curl en banco Scott a dos manos con mancuernas",
    "One Arm Bicep Curl with Olympic Bar or Barbell": "Curl de bíceps a una mano con barra olímpica",
    "One Arm Bicep Concentration on Stability Ball with Dumbbell": "Curl concentrado a una mano en fitball con mancuerna",
    "Quick Alternating Biceps Curls with Band": "Curl alterno rápido con banda elástica",
    "Bicep Curl Lunge with Bowling Motion": "Zancada con curl y giro de bolos",
    "Bicep Curl on Stability Ball with Leg Raised": "Curl en fitball con una pierna elevada",
    "Forward Lunge with Bicep Curl using Dumbbell": "Zancada frontal con curl de bíceps",
    "Step Up Single Leg Balance with Bicep Curl using Dumbbells": "Subida al step a una pierna con curl de bíceps",
    "Stork Stance Bicep Curl with Dumbbells": "Curl de bíceps en equilibrio a una pierna",
    "Biceps Curl V Sit on Dome with Dumbbells": "Curl de bíceps en V sobre bosu",
    "Ankle Circles": "Círculos de tobillo",
    "Calves Press on Leg Machine": "Elevación de talones en prensa",
    "Donkey Calf Raises": "Elevación de talones burro",
    "Knee Circles": "Círculos de rodilla",
    "Air Bike": "Bicicleta abdominal",
    "Ab Rollout on Knees with Barbell": "Rueda abdominal de rodillas con barra",
    "Bent Knee Hip Raise": "Elevación de cadera con rodillas flexionadas",
    "Exercise Ball Pull In": "Rodillas al pecho en fitball",
}

def spanish(title):
    """The Spanish title, from the exception table when there is one."""
    if title in EXCEPTIONS:
        return EXCEPTIONS[title]
    result, leftover = translate(title)
    return result or title
