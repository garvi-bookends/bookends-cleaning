/// Fixed lists from index.html (LOCATIONS, ROLES, CLEAN_TEMPLATE, …).
library;

class Location {
  final String id, name, city, code, head;
  const Location(this.id, this.name, this.city, this.code, this.head);
}

const kLocations = [
  Location('SUR-PREP', 'Surat Prep Kitchen', 'Surat', 'SPK', 'Rahul'),
  Location('SUR-CAP-PIP', 'Capiche Piplod', 'Surat', 'CPP', 'Amisha'),
  Location('SUR-CAP-VES', 'Capiche Vesu', 'Surat', 'CPV', 'Rahil'),
  Location('SUR-AIKO', 'Aiko Pal', 'Surat', 'AKP', 'Harish'),
  Location('AHM-PREP', 'Ahmedabad Prep Kitchen', 'Ahmedabad', 'APK', 'Raju'),
  Location('AHM-CAP-AMB', 'Capiche Ambli', 'Ahmedabad', 'CPA', 'Pankaj'),
  Location('AHM-CAP-UNI', 'Capiche Uni', 'Ahmedabad', 'CPU', 'Atul'),
  Location('AHM-AIKO', 'Aiko Ambli', 'Ahmedabad', 'AKA', 'Akshay'),
];

const kCities = ['Surat', 'Ahmedabad'];

Location? locById(String? id) {
  for (final l in kLocations) {
    if (l.id == id) return l;
  }
  return null;
}

String locName(String? id) => id == 'ALL' ? 'All ${kLocations.length} kitchens' : (locById(id)?.name ?? '—');

class Role {
  final String key, label;
  final bool all, approve, edit, manage, readonly, superadmin;
  const Role(this.key, this.label,
      {this.all = false,
      this.approve = false,
      this.edit = false,
      this.manage = false,
      this.readonly = false,
      this.superadmin = false});
}

const kRoles = {
  'superadmin': Role('superadmin', 'Super Admin',
      all: true, approve: true, edit: true, manage: true, superadmin: true),
  'exec': Role('exec', 'Execution Head', all: true, edit: true, manage: true),
  'aexec': Role('aexec', 'Assistant Execution Head', all: true, edit: true, manage: true),
  'admin': Role('admin', 'Admin', all: true, edit: true, manage: true),
  'hok': Role('hok', 'Head of Kitchen', all: true, edit: true),
  'manager': Role('manager', 'Location Manager'),
  'staff': Role('staff', 'Kitchen Staff'),
  'auditor': Role('auditor', 'Auditor', all: true, readonly: true),
};

Role roleOf(String? key) => kRoles[key] ?? kRoles['staff']!;
List<String> get assignableRoles => kRoles.keys.where((k) => k != 'superadmin').toList();

const kCategories = [
  'Dairy', 'Meat & Poultry', 'Seafood', 'Produce', 'Sauces & Prep', 'Dry Goods', 'Frozen', 'Bakery', 'Beverage'
];
const kStorage = [
  'Chiller 1 (0–4°C)', 'Chiller 2 (0–4°C)', 'Walk-in Chiller', 'Freezer (−18°C)', 'Dry Store', 'Ambient Prep', 'Bar Fridge'
];
const kUnits = ['kg', 'g', 'L', 'ml', 'pcs', 'pack', 'tray'];
const kDayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const kFreqs = [('D', 'Daily'), ('W', 'Weekly'), ('M', 'Monthly')];

class TemplateJob {
  final String area, zone, freq;
  final int? day; // pinned weekday offset from Monday
  const TemplateJob(this.area, this.zone, this.freq, [this.day]);
}

/// CLEAN_TEMPLATE in index.html order. Slot keys are W0.. / M0.. by index
/// within each frequency — append new jobs at the end only.
const kCleanTemplate = [
  TemplateJob('Kitchen floor — scrub, degrease & sanitise', 'Floors', 'W'),
  TemplateJob('Floor drains & channel gratings', 'Floors', 'W'),
  TemplateJob('Grease trap — empty, scrape & flush', 'Floors', 'W'),
  TemplateJob('Store, corridor & entrance floors', 'Floors', 'W'),
  TemplateJob('Wall tiles & splashbacks on the cooking line', 'Walls & ceiling', 'W'),
  TemplateJob('Skirting, corners & wall–floor joints', 'Walls & ceiling', 'W'),
  TemplateJob('Prep tables — tops, legs & undershelves', 'Tables & surfaces', 'W'),
  TemplateJob('Chopping boards — deep sanitise & wear check', 'Tables & surfaces', 'W'),
  TemplateJob('Stainless shelving & wall racks', 'Tables & surfaces', 'W'),
  TemplateJob('Sinks, taps & drainer boards — descale', 'Tables & surfaces', 'W'),
  TemplateJob('Hand-wash station — sanitise, soap & towel refill', 'Tables & surfaces', 'W'),
  TemplateJob('Walk-in chiller — shelves, floor & door seals', 'Fridges & freezers', 'W'),
  TemplateJob('Under-counter fridges — inside, trays & seals', 'Fridges & freezers', 'W'),
  TemplateJob('Freezer — ice build-up, gaskets & drain', 'Fridges & freezers', 'W'),
  TemplateJob('Fridge & freezer temperature check — record it', 'Fridges & freezers', 'W'),
  TemplateJob('Induction hobs — glass tops, edges & controls', 'Machines', 'W'),
  TemplateJob('Electric combi oven — inside, racks, seals & rinse', 'Machines', 'W'),
  TemplateJob('Electric griddle / flat top — scrape & drip tray', 'Machines', 'W'),
  TemplateJob('Electric fryer — drain, boil-out & filter oil', 'Machines', 'W'),
  TemplateJob('Salamander / electric grill — elements & tray', 'Machines', 'W'),
  TemplateJob('Microwave & hot holding cabinet', 'Machines', 'W'),
  TemplateJob('Dishwasher — filters, wash arms & descale', 'Machines', 'W'),
  TemplateJob('Ice machine — descale & sanitise the bin', 'Machines', 'W'),
  TemplateJob('Coffee machine & grinder — backflush, burr clean', 'Machines', 'W'),
  TemplateJob('Blender, mixer & food processor — strip & sanitise', 'Machines', 'W'),
  TemplateJob('Extraction hood, canopy & baffle filters', 'Machines', 'W'),
  TemplateJob('Dry store racks & containers — wipe & rotate stock', 'Storage', 'W'),
  TemplateJob('Bin area & waste room wash', 'Waste', 'W'),
  TemplateJob('Plug points, switches & cables — dry wipe only', 'Electrical safety', 'W'),
  TemplateJob('All walls — full height wash & sanitise', 'Walls & ceiling', 'M'),
  TemplateJob('Ceiling, light fittings & diffusers', 'Walls & ceiling', 'M'),
  TemplateJob('Windows, doors, tracks & fly screens', 'Walls & ceiling', 'M'),
  TemplateJob('Pull out every machine — clean behind & underneath', 'Floors', 'M'),
  TemplateJob('Drain lines flush & pest-proofing check', 'Floors', 'M'),
  TemplateJob('Chiller & freezer condenser coils and fan grills', 'Fridges & freezers', 'M'),
  TemplateJob('Walk-in chiller — empty out, wash walls & floor', 'Fridges & freezers', 'M'),
  TemplateJob('Combi oven — descale steam generator & elements', 'Machines', 'M'),
  TemplateJob('Fryer — full strip down, tank & element clean', 'Machines', 'M'),
  TemplateJob('Dishwasher — strip down, boiler descale & tank', 'Machines', 'M'),
  TemplateJob('Extraction ducting & fan housing — deep clean', 'Machines', 'M'),
  TemplateJob('Dry store — empty shelves, wash & restock', 'Storage', 'M'),
  TemplateJob('Staff area, lockers & changing room', 'Staff area', 'M'),
  TemplateJob('Wall cleaning — all kitchen walls', 'Walls & ceiling', 'W'),
  TemplateJob('All GN pan stands — wash, degrease & sanitise', 'Tables & surfaces', 'W'),
  TemplateJob('Drainage cleaning — drains, lines & gratings', 'Floors', 'W'),
  TemplateJob('Housekeeping area cleaning', 'Housekeeping', 'W', 1),
];

class BuiltinJob {
  final String tk;
  final TemplateJob t;
  const BuiltinJob(this.tk, this.t);
}

final List<BuiltinJob> kBuiltinWeekly = () {
  final w = kCleanTemplate.where((j) => j.freq == 'W').toList();
  return [for (var i = 0; i < w.length; i++) BuiltinJob('W$i', w[i])];
}();

final List<BuiltinJob> kBuiltinMonthly = () {
  final m = kCleanTemplate.where((j) => j.freq == 'M').toList();
  return [for (var i = 0; i < m.length; i++) BuiltinJob('M$i', m[i])];
}();

BuiltinJob? builtinByTk(String tk) {
  for (final b in [...kBuiltinWeekly, ...kBuiltinMonthly]) {
    if (b.tk == tk) return b;
  }
  return null;
}
