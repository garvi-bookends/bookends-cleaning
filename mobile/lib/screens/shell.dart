import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../data/constants.dart';
import '../data/logic.dart';
import '../data/store.dart';
import 'checklists.dart';
import 'cleaning.dart';
import 'expiry.dart';
import 'home.dart';
import 'labels.dart';
import 'manage.dart';
import 'profile.dart';

/// Which tab is open and the filters that survive switching tabs (the
/// website's `S` object).
class Nav extends ChangeNotifier {
  String tab = 'home';
  String manage = 'home'; // home | users | jobs | review
  String cleanFilter = 'all';
  String expFilter = 'all';
  String labFilter = 'all';
  String reviewFilter = 'waiting';

  void go(String t, {String? manageTo, String? clean, String? exp}) {
    tab = t;
    if (manageTo != null) manage = manageTo;
    if (clean != null) cleanFilter = clean;
    if (exp != null) expFilter = exp;
    notifyListeners();
  }

  void refresh() => notifyListeners();
}

/// One per app; reachable from sheets opened outside the Shell.
final Nav navState = Nav();

class TabDef {
  final String key, label;
  final IconData icon;
  const TabDef(this.key, this.label, this.icon);
}

const _allTabs = [
  TabDef('manage', 'Manage', Icons.shield_outlined),
  TabDef('home', 'Home', Icons.home_outlined),
  TabDef('chk', 'Checklist', Icons.fact_check_outlined),
  TabDef('clean', 'Cleaning', Icons.cleaning_services_outlined),
  TabDef('exp', 'Expiry', Icons.event_note_outlined),
  TabDef('lab', 'Labels', Icons.sell_outlined),
];

const _typeTab = {'cleaning': 'clean', 'labelling': 'lab', 'labeling': 'lab', 'checklist': 'chk'};

bool tabAllowed(String tab) {
  final p = S.perm;
  if (tab == 'manage') return p.superadmin;
  if (tab == 'home' || p.superadmin) return true;
  final types = ((S.me?['jobTypes'] as List?) ?? const []).map((e) => '$e').toList();
  if (types.isEmpty) return true;
  final claimed = _typeTab.entries.where((e) => e.value == tab).map((e) => e.key).toList();
  if (claimed.isEmpty) return true;
  return claimed.any(types.contains);
}

List<TabDef> visibleTabs() => _allTabs.where((t) => tabAllowed(t.key)).toList();

class Shell extends StatefulWidget {
  final VoidCallback onSignOut;
  const Shell({super.key, required this.onSignOut});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  Nav get nav => navState;

  @override
  void initState() {
    super.initState();
    nav.tab = S.perm.superadmin ? 'manage' : 'home';
  }

  /// Kitchen choices that make sense for this tab (router fixes in render()).
  void _fixLoc() {
    final vis = visibleLocations();
    final s = Store.I;
    if (nav.tab == 'clean' && s.loc == 'ALL') s.loc = vis.isNotEmpty ? vis.first : kLocations.first.id;
    if ((nav.tab == 'exp' || nav.tab == 'lab') && !s.perm.all) {
      s.loc = (s.me?['loc'] as String?) ?? (vis.isNotEmpty ? vis.first : kLocations.first.id);
    }
    if (s.loc != 'ALL' && !vis.contains(s.loc) && vis.isNotEmpty) s.loc = vis.first;
    if (s.loc == 'ALL' && !s.perm.all) s.loc = vis.isNotEmpty ? vis.first : kLocations.first.id;
  }

  Widget _page() {
    switch (nav.tab) {
      case 'manage':
        return const ManageScreen();
      case 'chk':
        return const ChecklistScreen();
      case 'clean':
        return const CleaningScreen();
      case 'exp':
        return const ExpiryScreen();
      case 'lab':
        return const LabelsScreen();
      default:
        return const HomeScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: nav,
      child: Consumer2<Store, Nav>(builder: (context, store, nav, _) {
        if (!tabAllowed(nav.tab)) nav.tab = 'home';
        _fixLoc();
        final tabs = visibleTabs();
        final wide = MediaQuery.of(context).size.width >= 900;
        final body = Column(children: [
          if (store.offline || store.syncState == 'offline')
            Container(
              width: double.infinity,
              color: const Color(0xFF8A5F00),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              child: const Text('No internet — your work is being saved and will upload automatically',
                  style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
          Expanded(child: KeyedSubtree(key: ValueKey('${nav.tab}-${nav.manage}'), child: _page())),
        ]);
        final scaffold = Scaffold(
          body: wide
              ? Row(children: [_Sidebar(tabs: tabs, nav: nav), Expanded(child: body)])
              : body,
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  height: 66,
                  backgroundColor: Colors.white,
                  indicatorColor: const Color(0xFFE8ECFB),
                  labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                  selectedIndex: tabs.indexWhere((t) => t.key == nav.tab).clamp(0, tabs.length - 1),
                  onDestinationSelected: (i) => nav.go(tabs[i].key),
                  destinations: [
                    for (final t in tabs)
                      NavigationDestination(
                        icon: _badged(t.key, Icon(t.icon, color: C.mut)),
                        selectedIcon: _badged(t.key, Icon(t.icon, color: C.brand)),
                        label: t.label,
                      ),
                  ],
                ),
        );
        return PopScope(
          canPop: nav.tab == (S.perm.superadmin ? 'manage' : 'home') && nav.manage == 'home',
          onPopInvokedWithResult: (did, _) {
            if (did) return;
            if (nav.tab == 'manage' && nav.manage != 'home') {
              nav.go('manage', manageTo: 'home');
            } else {
              nav.go(S.perm.superadmin ? 'manage' : 'home');
            }
          },
          child: _SignOutScope(onSignOut: widget.onSignOut, child: scaffold),
        );
      }),
    );
  }

  Widget _badged(String key, Widget icon) {
    int n = 0;
    if (key == 'manage') n = tasksAwaitingApproval().length + adminQueueCount;
    if (n == 0) return icon;
    return Badge(label: Text(n > 99 ? '99+' : '$n'), backgroundColor: C.red, child: icon);
  }
}

class _Sidebar extends StatelessWidget {
  final List<TabDef> tabs;
  final Nav nav;
  const _Sidebar({required this.tabs, required this.nav});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 232,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [C.brandMid, C.brand, Color(0xFF141C58)], stops: [0, .5, 1]),
      ),
      child: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(22, 22, 16, 18),
            child: Text('BOOKENDS', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 2)),
          ),
          for (final t in tabs) ...[
            _item(t.label == 'Manage' ? 'Management' : t.label, t.icon, nav.tab == t.key && (t.key != 'manage' || nav.manage == 'home'),
                () => nav.go(t.key, manageTo: t.key == 'manage' ? 'home' : null)),
            if (t.key == 'manage')
              for (final (k, l, i) in [
                ('users', 'User Management', Icons.person_outline),
                ('jobs', 'Job Management', Icons.work_outline),
                ('review', 'Task Review', Icons.task_alt),
              ])
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: _item(l, i, nav.tab == 'manage' && nav.manage == k, () => nav.go('manage', manageTo: k)),
                ),
          ],
        ]),
      ),
    );
  }

  Widget _item(String label, IconData icon, bool active, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        child: Material(
          color: active ? Colors.white.withValues(alpha: .16) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: active
                  ? const BoxDecoration(border: Border(left: BorderSide(color: C.accent, width: 3)))
                  : null,
              child: Row(children: [
                Icon(icon, color: Colors.white.withValues(alpha: active ? 1 : .75), size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(label,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: active ? 1 : .8), fontWeight: FontWeight.w700, fontSize: 14)),
                ),
              ]),
            ),
          ),
        ),
      );
}

class _SignOutScope extends InheritedWidget {
  final VoidCallback onSignOut;
  const _SignOutScope({required this.onSignOut, required super.child});
  @override
  bool updateShouldNotify(_SignOutScope o) => false;
}

void signOutFrom(BuildContext context) =>
    context.getInheritedWidgetOfExactType<_SignOutScope>()?.onSignOut();

// ---------------------------------------------------------------------------
// Page header: title, subtitle, kitchen selector, bell, profile
// ---------------------------------------------------------------------------
class PageHeader extends StatelessWidget {
  final String title;
  final String? sub;
  final bool showLoc, allowAll;
  final Widget? leading;
  const PageHeader(this.title, {super.key, this.sub, this.showLoc = true, this.allowAll = true, this.leading});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final unread = unreadAlerts().length;
    final top = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(14, top + 10, 12, 12),
      decoration: const BoxDecoration(
        gradient: C.headerGradient,
        boxShadow: [BoxShadow(color: Color(0x381E2A78), blurRadius: 18, offset: Offset(0, 4))],
      ),
      child: Column(children: [
        Row(children: [
          if (leading != null) ...[leading!, const SizedBox(width: 8)],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: .3)),
              if (sub != null)
                Row(children: [
                  Flexible(
                    child: Text(sub!.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: .72), fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: .6)),
                  ),
                  if (store.perm.manage) ...[
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => syncSheet(context),
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: switch (store.syncState) {
                            'syncing' => C.accent,
                            'error' => C.red,
                            'offline' => const Color(0xFFC8CEE2),
                            _ => const Color(0xFFA9C4EC),
                          },
                        ),
                      ),
                    ),
                  ],
                ]),
            ]),
          ),
          _HeadBtn(
            onTap: () => alertsSheet(context),
            badge: unread,
            child: const Icon(Icons.notifications_none_rounded, color: Colors.white),
          ),
          const SizedBox(width: 8),
          _HeadBtn(
            onTap: () => meSheet(context),
            child: Text(initials(store.me?['name'] as String?),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
          ),
        ]),
        if (showLoc) ...[const SizedBox(height: 10), LocSelect(allowAll: allowAll)],
      ]),
    );
  }
}

class _HeadBtn extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  final int badge;
  const _HeadBtn({required this.child, required this.onTap, this.badge = 0});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Stack(clipBehavior: Clip.none, children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: .14), borderRadius: BorderRadius.circular(12)),
            child: child,
          ),
          if (badge > 0)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                constraints: const BoxConstraints(minWidth: 19, minHeight: 19),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: C.red, borderRadius: BorderRadius.circular(10), border: Border.all(color: C.brand, width: 2)),
                child: Text(badge > 99 ? '99+' : '$badge',
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
              ),
            ),
        ]),
      );
}

class LocSelect extends StatelessWidget {
  final bool allowAll;
  const LocSelect({super.key, this.allowAll = true});
  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final vis = visibleLocations();
    final items = <DropdownMenuItem<String>>[
      if (allowAll && store.perm.all) DropdownMenuItem(value: 'ALL', child: Text('All ${kLocations.length} locations')),
      for (final city in kCities)
        for (final l in kLocations.where((l) => l.city == city && vis.contains(l.id)))
          DropdownMenuItem(value: l.id, child: Text('${l.name} · ${l.city}')),
    ];
    final value = items.any((i) => i.value == store.loc) ? store.loc : (items.isNotEmpty ? items.first.value : null);
    if (items.length <= 1 && items.isNotEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .13),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: .22)),
        ),
        child: Text(locName(value), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: .22)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: C.brand,
          iconEnabledColor: Colors.white,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
          items: items,
          onChanged: (v) {
            if (v == null) return;
            store.loc = v;
            store.save();
          },
        ),
      ),
    );
  }
}

/// Standard scrolling page under a header, max 760 wide like the site.
class PageBody extends StatelessWidget {
  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  final Widget? fab;
  const PageBody({super.key, required this.children, this.onRefresh, this.fab});
  @override
  Widget build(BuildContext context) {
    Widget list = ListView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 100),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ),
      ],
    );
    list = RefreshIndicator(onRefresh: onRefresh ?? () => S.sync(), child: list);
    if (fab == null) return list;
    return Stack(children: [list, Positioned(right: 16, bottom: 16, child: fab!)]);
  }
}

class Fab extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const Fab(this.label, this.onTap, {super.key});
  @override
  Widget build(BuildContext context) => FloatingActionButton.extended(
        onPressed: onTap,
        backgroundColor: C.brand,
        foregroundColor: Colors.white,
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      );
}
