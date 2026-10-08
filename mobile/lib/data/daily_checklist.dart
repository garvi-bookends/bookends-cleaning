/// Lunch / Dinner / Closing checklist — same questions and windows as
/// server/services/checklistItems.js and checklistWindows.js. The server
/// decides whether a window is open; this copy is only for display.
library;

const List<(String, List<String>)> kChecklistSections = [
  ('General Cleanliness', [
    'Sweep and mop the floor (ensure no spills or hazards)',
    'Clean all surfaces (counters, tables, and workstations)',
    'Check for any food debris or leftover packaging in work areas and garbage bins.',
  ]),
  ('Equipment Check', [
    'Turn on all appliances (ovens, grills, fryers, etc.) and check for proper function.',
    'Inspect refrigeration units (ensure proper temperature, check for food safety compliance).',
    'Ensure the dishwasher is working and stocked with detergent.',
    'Check small appliances (microwave, mixers, blenders, etc.).',
  ]),
  ('Stock and Inventory', [
    'Check received prep & store purchase according to PO & vegetables order.',
    'Check inventory levels (ensure that essentials are stocked: flour, oil, prep etc.)',
    'Ensure proper storage of ingredients (check refrigerators, freezers, and dry storage areas).',
    'Restock prep areas with necessary ingredients and tools (knives, cutting boards, etc.).',
    'Check produce quality (freshness of fruits and vegetables).',
  ]),
  ('Food Safety and Hygiene', [
    'Check expiration dates on perishables and dispose of anything past date.',
    'Verify hand-washing stations are stocked with soap, sanitizer, and paper towels.',
    'Check first aid kits to ensure they are stocked and accessible.',
  ]),
  ('Setup for Food Prep', [
    'Organize prep stations with necessary tools (mixing bowls, knives, cutting boards).',
    'Set up workstation-specific items ( sauté pans, etc.) for your cooks.',
    'Thaw any frozen items that need prep (corn,green peas, dough, etc.).',
    'Check upon all the prep, vegetables & store purchase completed',
  ]),
  ('Staff Readiness', [
    'Ensure staff uniform compliance (check for clean aprons, gloves, and proper footwear).',
    'Hold a quick team briefing to discuss specials, expected rushes, and any concerns.',
    'Ensure all staff is aware of dietary restrictions and allergies that need to be noted for orders.',
  ]),
  ('Waste Management', ['Empty all trash bins and line with fresh bags.']),
  ('Final Walkthrough', ['Perform a final walkaround to ensure everything is clean, organized, and functioning.']),
];

int get kChecklistItemCount => kChecklistSections.fold(0, (n, s) => n + s.$2.length);

class ChecklistWindow {
  final String type, label;
  final int start, end; // minutes of the IST day, [start, end)
  const ChecklistWindow(this.type, this.label, this.start, this.end);
  bool get overnight => end <= start;
}

const kChecklistWindows = [
  ChecklistWindow('LUNCH', 'Lunch Checklist', 12 * 60, 13 * 60 + 30),
  ChecklistWindow('DINNER', 'Dinner Checklist', 17 * 60, 18 * 60),
  ChecklistWindow('CLOSING', 'Closing Checklist', 22 * 60, 1 * 60),
];

String fmtMinutes(int m) {
  final h = (m ~/ 60) % 24, mm = m % 60;
  final ap = h < 12 ? 'AM' : 'PM';
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:${mm.toString().padLeft(2, '0')} $ap';
}

String rangeLabel(ChecklistWindow w) => '${fmtMinutes(w.start)} to ${fmtMinutes(w.end)}';
