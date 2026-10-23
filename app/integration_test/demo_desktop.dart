// The Windows (wide layout) part of the screen-recording demo. Run with
// claude_dev/run_demo.ps1 (whole demo) or `flutter test
// integration_test/demo_desktop_run_test.dart -d windows` (this part only).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'demo_support.dart';

Future<void> desktopDemo(WidgetTester tester, Demo demo) async {
    Finder inKey(String key, String text) => find.descendant(
      of: find.byKey(ValueKey(key)),
      matching: find.text(text),
    );
    Future<void> tab(String key, String text) =>
        demo.tap(inKey(key, text), note: 'tab $text');
    Future<void> actionsTab(String text) => tab('actions-switch', text);
    // The rail may be icon-only (a saved preference), so go by icon.
    Future<void> rail(IconData icon) => demo.tap(
      find.descendant(
        of: find.byWidgetPredicate((w) => w.runtimeType.toString() == 'InstantRail'),
        matching: find.byIcon(icon),
      ),
      note: 'rail $icon',
    );
    Future<void> save() => demo.tapText('Save');
    final nameField = find.byType(TextFormField);

    // ------------------------------------------------------------------ Actions
    await demo.scene('Welcome - Current Actions board', 2500);
    await rail(Icons.checklist_rounded);
    await actionsTab('Current Actions');
    await demo.scroll(dy: 400);

    await demo.scene('Hover a card: the quick tools appear');
    final card = find.textContaining('Deep work');
    await demo.hover(card, after: 1800);
    await demo.tapTooltip('Prolong 30 min');
    await demo.tapTooltip('Continue with same action');
    await demo.hover(find.textContaining('Team stand-up'), after: 1500);
    await demo.tapTooltip('Postpone: tomorrow morning');
    await demo.key(LogicalKeyboardKey.keyZ, ctrl: true); // Undo
    await demo.pause(1200);

    await demo.scene('Direction icons switch and search on the board');
    await demo.tapKey('current-icons-toggle');
    await demo.tapKey('current-icons-toggle');
    await demo.tapKey('current-search-toggle');
    await demo.type(find.byKey(const ValueKey('current-search-field')), 'lunch');
    await demo.pause(1200);
    await demo.tapKey('current-search-toggle');

    await demo.scene('New action: type a name, set it up, save');
    await demo.tapTooltip('New action');
    await demo.type(nameField, 'Prepare the demo presentation');
    await demo.tapText('Notes', after: 1000);
    await demo.typeInNotes('Slides, script, rehearsal');
    await demo.pause(1200);
    await demo.scroll(dy: 500);
    await save();
    await demo.pause(1000);

    await demo.scene('Open a running action: notes with checklist, toggle and code');
    await demo.tap(find.textContaining('Deep work').first, after: 1800, note: 'Deep work card');
    await demo.scroll(dy: 700);
    await demo.tapTooltip('Start');
    await demo.pause(800);
    await demo.closeDialog();

    // ----------------------------------------------------------------- Calendar
    await demo.scene('Calendar');
    await actionsTab('Calendar');
    await demo.tapKey('calendar-now');
    await demo.tapTooltip('Next');
    await demo.tapTooltip('Previous');
    await demo.tapTooltip('Show more hours (Ctrl+−)');
    await demo.tapTooltip('Show fewer hours (Ctrl++)');
    await demo.tapKey('calendar-icons-toggle');
    await demo.tapKey('calendar-icons-toggle');
    await demo.tapKey('calendar-allday-toggle');
    await demo.tapKey('calendar-allday-toggle');
    for (final n in ['3', '5', '7', '1']) {
      await demo.tap(
        find.descendant(of: find.byType(SegmentedButton<int>), matching: find.text(n)),
        note: 'days $n',
      );
    }
    await demo.scroll(dy: 500);
    await demo.hover(find.textContaining('Lunch with Anna').first, after: 1500);
    await demo.doubleTap(find.textContaining('Lunch with Anna').first, after: 1500);
    await demo.tapText('Notes', after: 600);
    await demo.closeDialog();

    // ---------------------------------------------------------------------- All
    await demo.scene('All actions: search, flags, sort and filters, summary');
    await actionsTab('All');
    await demo.type(find.byKey(const ValueKey('allSearchField')), 'run');
    await demo.tapKey('searchFlagNotes');
    await demo.tapKey('searchFlagDirections');
    await demo.tapKey('allOptionsToggle', after: 1500);
    await demo.scroll(dy: 300);
    await demo.tapKey('allOptionsToggle');
    await demo.tapKey('allSearchClear');
    await demo.type(find.byKey(const ValueKey('allSearchField')), 'Client');
    await demo.pause(1500);
    await demo.tapKey('allSearchClear');

    await demo.scene('The diary: "What is done?" from yesterday\'s tagged work');
    await demo.type(find.byKey(const ValueKey('allSearchField')), 'Diary');
    await demo.tap(
    find.descendant(of: find.byType(ListView), matching: find.text('Diary')).first,
    after: 1500,
    note: 'Diary row',
  );
    await demo.tapText('Notes', after: 800);
    await demo.tapKey('diary-transfer', after: 2500);
    await demo.scroll(dy: 400);
    await demo.closeDialog();
    await demo.tapKey('allSearchClear');

    // ---------------------------------------------------------------- Templates
    await demo.scene('Templates: average time, start and finish now');
    await actionsTab('Templates');
    await demo.type(find.byKey(const ValueKey('templates-search')), 'run');
    await demo.pause(1000);
    await demo.tap(find.textContaining('Morning run').first, note: 'template tile');
    await demo.tapKey('template-use-average');
    await demo.closeDialog();
    await demo.clearField(find.byKey(const ValueKey('templates-search')));
    await demo.tapTooltip('Start now');
    await demo.pause(1500);
    await demo.scroll(dy: 300);
    await demo.tapTooltip('New template');
    await demo.type(nameField, 'Evening stretch');
    await demo.type(find.byKey(const ValueKey('template-duration')), '20');
    await demo.closeDialog();

    // ------------------------------------------------------------------- Growth
    await demo.scene('Growth directions: balance boards');
    await rail(Icons.insights);
    await demo.scroll(dy: 700);
    await demo.scene('List');
    await demo.tap(find.text('List').first, note: 'List tab');
    await demo.scroll(dy: 600);
    await demo.scrollToTop();
    await demo.tap(find.textContaining('I am healthy').first, note: 'direction row');
    await demo.scroll(dy: 300);
    await demo.closeDialog();

    await demo.scene('Mindmap');
    await demo.tap(find.text('Mindmap').first, note: 'Mindmap tab');
    await demo.pause(1500);
    await demo.tapText('Tree layout', after: 1500);
    await demo.tapText('Auto layout', after: 1500);
    await demo.tapTooltip('Zoom out');
    await demo.tapTooltip('Zoom in');
    await demo.tapTooltip('Fit all');
    await demo.tapKey('mindmap-search-toggle');
    await demo.type(find.byKey(const ValueKey('mindmap-search-field')), 'sleep');
    await demo.pause(1200);
    await demo.tapKey('mindmap-search-toggle');
    await demo.doubleTap(find.byKey(const ValueKey('mindmapCanvas')), after: 800);
    await demo.closeDialog();
    await demo.tapTooltip('New growth direction');
    await demo.type(nameField, 'I write every day');
    await demo.closeDialog();

    // ------------------------------------------------------------------- Budget
    await demo.scene('Budget: overview');
    await rail(Icons.account_balance_wallet_outlined);
    await demo.tapKey('budget-months-plus');
    await demo.tapKey('budget-months-minus');
    await demo.tapKey('budget-leaves-only', after: 1500);
    await demo.scroll(dy: 800);
    await demo.tapKey('budget-leaves-only');
    await demo.scrollToTop();
    await demo.tapKey('budget-as-of', after: 1000);
    await demo.tapText('OK', after: 900);
    await demo.tapKey('budget-as-of-reset');

    await demo.scene('Budget: categories');
    await tab('budget-switch', 'Categories');
    await demo.type(find.byKey(const ValueKey('budget-categories-search')), 'coffee');
    await demo.pause(1200);
    await demo.clearField(find.byKey(const ValueKey('budget-categories-search')));
    await demo.scroll(dy: 800);
    await demo.tapKey('budget-fab');
    await demo.type(find.byKey(const ValueKey('category-name')), 'Books');
    await demo.type(find.byKey(const ValueKey('category-price')), '25');
    await demo.tapKey('category-parent', after: 1200);
    await demo.type(find.byKey(const ValueKey('budget-category-search')), 'food');
    await demo.pause(1000);
    await demo.closeDialog();
    await demo.closeDialog();

    await demo.scene('Budget: transactions');
    await tab('budget-switch', 'Transactions');
    await demo.type(find.byKey(const ValueKey('budget-transactions-search')), 'rent');
    await demo.pause(1200);
    await demo.clearField(find.byKey(const ValueKey('budget-transactions-search')));
    await demo.tapKey('budget-tx-options-toggle', after: 1500);
    await demo.tapKey('budget-tx-options-toggle');
    await demo.scroll(dy: 800);
    await demo.tapKey('budget-fab');
    await demo.pause(1200);
    await demo.closeDialog();

    await demo.scene('Budget: accounts');
    await tab('budget-switch', 'Accounts');
    await demo.scroll(dy: 400);
    await demo.tapKey('budget-fab');
    await demo.type(find.byKey(const ValueKey('account-name')), 'Savings');
    await demo.closeDialog();
    await demo.tapKey('budget-settings', after: 1200);
    await demo.closeDialog();

    // ----------------------------------------------------------------- Settings
    await demo.scene('Settings and dark mode');
    await demo.tap(find.byType(SubmenuButton).first, note: 'File menu');
    await demo.tapKey('menu-settings', after: 1500);
    await demo.scroll(dy: 900);
    await demo.tapText('Dark');
    await demo.pause(1500);
    await demo.tapText('Light');
    await demo.tap(find.byType(BackButton), note: 'settings back');
    await demo.tap(find.byType(SubmenuButton).at(1), note: 'View menu');
    await demo.tap(find.byType(CheckboxMenuButton).first, note: 'Dark mode');
    await demo.pause(2500);
    await demo.scene('Calendar in the dark');
    await rail(Icons.checklist_rounded);
    await actionsTab('Calendar');
    await demo.pause(2000);
    await demo.tap(find.byType(SubmenuButton).at(1), note: 'View menu');
    await demo.tap(find.byType(CheckboxMenuButton).first, note: 'Light mode');
    await demo.pause(2000);

    await demo.scene('Delete and Undo');
    await actionsTab('Current Actions');
    await demo.hover(find.textContaining('Read a book').first, after: 1200);
    await demo.tapTooltip('Delete');
    await demo.pause(1500);
    await demo.tapText('Undo', after: 1500);

    await demo.scene('The end', 2500);
}
