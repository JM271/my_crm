import 'package:flutter/material.dart';

import 'crm_store.dart';
import 'models.dart';
import 'pages/consignment_page.dart';
import 'pages/contacts_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/deals_page.dart';
import 'pages/reports_page.dart';
import 'pages/tasks_page.dart';
import 'theme.dart';
import 'widgets/common.dart';
import 'widgets/forms.dart';
import 'format.dart';
import 'pages/products_page.dart';
import 'widgets/data_tools.dart';
import 'widgets/consignment_forms.dart';
import 'widgets/import_dialog.dart';

class _Destination {
  const _Destination(this.label, this.shortLabel, this.icon);
  final String label;
  final String shortLabel;
  final IconData icon;
}

const _destinations = [
  _Destination('Overview', 'Overview', Icons.grid_view_rounded),
  _Destination('Dealers', 'Dealers', Icons.storefront_outlined),
  _Destination('Deals', 'Deals', Icons.trending_up_rounded),
  _Destination('Consignment', 'Depot', Icons.pedal_bike_rounded),
  _Destination('Tasks', 'Tasks', Icons.check_circle_outline_rounded),
  _Destination('Reports', 'Reports', Icons.bar_chart_rounded),
];

class CrmShell extends StatefulWidget {
  const CrmShell({super.key, this.onFirstOpen});

  final Future<void> Function(BuildContext context)? onFirstOpen;

  @override
  State<CrmShell> createState() => _CrmShellState();
}

/// Dev aid: `--dart-define=START_PAGE=2` opens a specific page on launch.
const _startPage = int.fromEnvironment('START_PAGE');

class _CrmShellState extends State<CrmShell> {
  int _page = _startPage.clamp(0, _destinations.length - 1);
  String _query = '';
  ContactStatus? _status;
  ShopType? _type;
  DealerSort _sort = DealerSort.newest;

  /// Which list the Dealers page shows.
  ContactKind _kind = ContactKind.dealer;
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    final first = widget.onFirstOpen;
    if (first != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) first(context);
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _selectPage(int index) {
    setState(() => _page = index);
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  void _onQueryChanged(String value) {
    setState(() {
      _query = value;
      // Search is about contacts: jump there from pages that don't show them.
      if (value.isNotEmpty && _page > 1) _page = 1;
    });
  }

  Future<void> _addContact() async {
    final contact = await showContactForm(context);
    if (contact == null || !mounted) return;
    setState(() {
      _kind = ContactKind.dealer;
      _status = null;
      _type = null;
      _query = '';
      _searchController.clear();
      _page = 1;
    });
    showMessage(context, '${contact.name} was added to your dealers.');
  }

  Future<void> _addPrivateCustomer() async {
    final customer = await showContactForm(context, kind: ContactKind.person);
    if (customer == null || !mounted) return;
    setState(() {
      _status = null;
      _query = '';
      _searchController.clear();
      _kind = ContactKind.person;
      _page = 1;
    });
    showMessage(context, '${customer.name} was added as a private customer.');
  }

  Future<void> _importContacts() async {
    final imported = await importContactsFromCsv(context);
    if (!imported || !mounted) return;
    setState(() {
      _status = null;
      _type = null;
      _query = '';
      _searchController.clear();
    });
    _selectPage(1);
  }

  /// The quick "add" action in the mobile top bar depends on the page.
  void _quickAdd() {
    switch (_page) {
      case 2:
        showDealForm(context);
      case 3:
        showBikeForm(context);
      case 4:
        showTaskForm(context);
      case 1 when _kind == ContactKind.person:
        _addPrivateCustomer();
      default:
        _addContact();
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = CrmScope.of(context);
    final filter = ContactFilter(
      query: _query,
      status: _status,
      onStatusChanged: (s) => setState(() => _status = s),
      type: _type,
      onTypeChanged: (t) => setState(() => _type = t),
      sort: _sort,
      onSortChanged: (s) => setState(() => _sort = s),
    );
    final contacts = filter.apply(
      store.contacts,
      lastContact: store.lastContactAt,
    );
    final listed = _kind == ContactKind.person
        ? filter.apply(store.privateCustomers, lastContact: store.lastContactAt)
        : contacts;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 1000;
        final isMobile = constraints.maxWidth < 680;
        final page = switch (_page) {
          1 => ContactsPage(
            contacts: listed,
            filter: filter,
            kind: _kind,
            onKindChanged: (k) => setState(() => _kind = k),
            onAddContact: _kind == ContactKind.person
                ? _addPrivateCustomer
                : _addContact,
            onImport: _importContacts,
          ),
          2 => const DealsPage(),
          3 => const ConsignmentPage(),
          4 => const TasksPage(),
          5 => const ReportsPage(),
          _ => DashboardPage(
            isMobile: isMobile,
            contacts: contacts,
            filter: filter,
            onPageSelect: _selectPage,
            onAddContact: _addContact,
          ),
        };
        return Scaffold(
          body: Row(
            children: [
              if (isDesktop)
                _SideNavigation(selected: _page, onSelect: _selectPage),
              Expanded(
                child: SafeArea(
                  child: Column(
                    children: [
                      _TopBar(
                        title: _destinations[_page].label,
                        isMobile: isMobile,
                        searchController: _searchController,
                        onQueryChanged: _onQueryChanged,
                        onOpenTasks: () => _selectPage(4),
                        onQuickAdd: _quickAdd,
                        onImport: _importContacts,
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          controller: _scrollController,
                          padding: EdgeInsets.fromLTRB(
                            isMobile ? 18 : 36,
                            24,
                            isMobile ? 18 : 36,
                            36,
                          ),
                          child: page,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          bottomNavigationBar: isDesktop
              ? null
              : NavigationBar(
                  height: 66,
                  selectedIndex: _page,
                  onDestinationSelected: _selectPage,
                  backgroundColor: Colors.white,
                  indicatorColor: sage,
                  labelBehavior:
                      NavigationDestinationLabelBehavior.onlyShowSelected,
                  destinations: [
                    for (final d in _destinations)
                      NavigationDestination(
                        icon: Icon(d.icon),
                        label: d.shortLabel,
                      ),
                  ],
                ),
        );
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.isMobile,
    required this.searchController,
    required this.onQueryChanged,
    required this.onOpenTasks,
    required this.onQuickAdd,
    required this.onImport,
  });

  final String title;
  final bool isMobile;
  final TextEditingController searchController;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onOpenTasks;
  final VoidCallback onQuickAdd;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final urgent = CrmScope.of(context).urgentTaskCount;
    final bell = IconButton(
      tooltip: urgent == 0 ? 'No tasks for today' : '$urgent tasks for today',
      onPressed: onOpenTasks,
      icon: Badge(
        isLabelVisible: urgent > 0,
        label: Text('$urgent'),
        backgroundColor: const Color(0xFFE68A52),
        child: const Icon(Icons.notifications_none_rounded, color: muted),
      ),
    );
    return Container(
      height: 76,
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 18 : 36),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: line)),
      ),
      child: Row(
        children: [
          if (isMobile) ...[const _Logo(size: 36), const SizedBox(width: 11)],
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: ink,
              ),
            ),
          ),
          if (!isMobile) ...[
            SizedBox(
              width: 260,
              height: 42,
              child: TextField(
                key: const Key('contact-search'),
                controller: searchController,
                onChanged: onQueryChanged,
                decoration: InputDecoration(
                  hintText: 'Search dealers, cities...',
                  hintStyle: const TextStyle(color: muted, fontSize: 13),
                  prefixIcon: const Icon(Icons.search_rounded, size: 19),
                  suffixIcon: ValueListenableBuilder(
                    valueListenable: searchController,
                    builder: (context, value, _) => value.text.isEmpty
                        ? const SizedBox.shrink()
                        : IconButton(
                            tooltip: 'Clear',
                            icon: const Icon(Icons.close_rounded, size: 17),
                            onPressed: () {
                              searchController.clear();
                              onQueryChanged('');
                            },
                          ),
                  ),
                  filled: true,
                  fillColor: canvas,
                  contentPadding: EdgeInsets.zero,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 18),
            bell,
            const SizedBox(width: 12),
            _AccountMenu(onImport: onImport),
          ] else ...[
            IconButton(
              tooltip: 'Search dealers',
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Search dealers'),
                  content: TextField(
                    autofocus: true,
                    controller: searchController,
                    onChanged: onQueryChanged,
                    decoration: const InputDecoration(
                      hintText: 'Shop, city, person or phone',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        searchController.clear();
                        onQueryChanged('');
                        Navigator.pop(context);
                      },
                      child: const Text('Clear'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Done'),
                    ),
                  ],
                ),
              ),
              icon: const Icon(Icons.search_rounded, color: muted),
            ),
            bell,
            IconButton(
              tooltip: 'Add',
              onPressed: onQuickAdd,
              icon: const Icon(Icons.add_circle_rounded, color: forest),
            ),
            _AccountMenu(onImport: onImport),
          ],
        ],
      ),
    );
  }
}

/// Avatar with settings and data-management actions.
class _AccountMenu extends StatelessWidget {
  const _AccountMenu({required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final store = CrmScope.of(context);
    return PopupMenuButton<String>(
      tooltip: 'Account',
      onSelected: (action) async {
        switch (action) {
          case 'settings':
            showSettingsDialog(context);
          case 'products':
            openProducts(context);
          case 'import':
            onImport();
          case 'export':
            exportDealers(context);
          case 'backup':
            backupData(context);
          case 'restore':
            restoreData(context);
          case 'demo':
            final ok = await confirmDelete(
              context,
              title: 'Restore demo data?',
              message: 'All your current data will be replaced with the sample data.',
              actionLabel: 'Replace',
            );
            if (ok) await store.resetToDemo();
          case 'signout':
            await store.onSignOut?.call();
          case 'clear':
            final ok = await confirmDelete(
              context,
              title: 'Delete everything?',
              message:
                  'All dealers, deals, tasks, activity and products will be '
                  'deleted${store.onSignOut != null ? ' for everyone using the online database' : ''}. '
                  'This cannot be undone.',
            );
            if (ok) await store.clearAll();
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          enabled: false,
          child: Text(
            store.accountEmail == null
                ? store.userName
                : '${store.userName}\n${store.accountEmail}',
            style: const TextStyle(color: muted, fontSize: 12),
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'settings', child: Text('Settings')),
        const PopupMenuItem(value: 'products', child: Text('Products')),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'import',
          child: Text('Import dealers (CSV)'),
        ),
        const PopupMenuItem(
          value: 'export',
          child: Text('Export dealers (CSV)'),
        ),
        const PopupMenuItem(value: 'backup', child: Text('Back up all data')),
        const PopupMenuItem(value: 'restore', child: Text('Restore a backup')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'demo', child: Text('Restore demo data')),
        const PopupMenuItem(
          value: 'clear',
          child: Text('Delete all data', style: TextStyle(color: danger)),
        ),
        if (store.onSignOut != null) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(value: 'signout', child: Text('Sign out')),
        ],
      ],
      child: _UserAvatar(name: store.userName, radius: 19),
    );
  }
}

class _UserAvatar extends StatelessWidget {
  const _UserAvatar({required this.name, required this.radius});

  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFFF1E6DA),
      child: Text(
        initialsOf(name),
        style: TextStyle(
          fontSize: radius * 0.6,
          fontWeight: FontWeight.w700,
          color: forestDark,
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: forest,
        borderRadius: BorderRadius.circular(size / 3),
      ),
      child: Icon(Icons.grass_rounded, color: Colors.white, size: size * 0.58),
    );
  }
}

class _SideNavigation extends StatelessWidget {
  const _SideNavigation({required this.selected, required this.onSelect});

  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final store = CrmScope.of(context);
    final badges = <int, int>{
      1: store.contacts.length,
      2: store.openDeals.length,
      3: store.bikesAtDealers.length,
      4: store.urgentTaskCount,
    };
    return Container(
      width: 248,
      height: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: line)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 7, bottom: 38),
            child: Row(
              children: [
                _Logo(size: 39),
                SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'molenstraat',
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        softWrap: false,
                        style: TextStyle(
                          color: ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.35,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'RELATIONSHIPS & GROWTH',
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        softWrap: false,
                        style: TextStyle(
                          color: muted,
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(left: 10, bottom: 17),
            child: Text(
              'WORKSPACE',
              style: TextStyle(
                color: muted,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.15,
              ),
            ),
          ),
          for (var i = 0; i < _destinations.length; i++)
            _NavItem(
              icon: _destinations[i].icon,
              label: _destinations[i].label,
              selected: selected == i,
              badge: badges[i],
              onTap: () => onSelect(i),
            ),
          const Spacer(),
          Material(
            color: const Color(0xFFF5F7F4),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => showSettingsDialog(context),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    _UserAvatar(name: store.userName, radius: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            store.userName,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: ink,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Settings · ${store.currency}',
                            style: const TextStyle(color: muted, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.settings_outlined, size: 17, color: muted),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? sage : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Icon(icon, size: 19, color: selected ? forest : muted),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: selected ? forestDark : muted,
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                if (badge != null && badge! > 0)
                  Text(
                    '$badge',
                    style: TextStyle(
                      color: selected ? forest : muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
