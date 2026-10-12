// The phone (iPhone-style layout) part of the demo: the same app in a 375x812
// window, then sideways. Touch-style marker; swipes and long presses.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'demo_support.dart';

Future<void> phoneDemo(
  WidgetTester tester,
  Demo demo, {
  required Future<void> Function() landscape,
  required Future<void> Function() portrait,
}) async {
  Finder inKey(String key, String text) => find.descendant(
    of: find.byKey(ValueKey(key)),
    matching: find.text(text),
  );
  Future<void> actionsTab(String text) =>
      demo.tap(inKey('actions-switch', text), note: 'tab $text');
  Future<void> nav(String label) => demo.tap(
    find.descendant(
      of: find.byKey(const ValueKey('phone-nav')),
      matching: find.text(label),
    ),
    note: 'nav $label',
  );
  final nameField = find.byType(TextFormField);

  // ------------------------------------------------------------------ Actions
  await demo.scene('LiveNow on the phone - Current Actions', 2500);
  await demo.tapKey('board-switch-done');
  await demo.scroll(dy: 500);
  await demo.tapKey('board-switch-notdone');
  await demo.scroll(dy: 500);

  await demo.scene('Swipe a card right to start it');
  await demo.drag(
    find.textContaining('Lunch with Anna').first,
    const Offset(240, 0),
    after: 1500,
  );
  await demo.scene('Swipe left to delete - and Undo');
  await demo.drag(
    find.textContaining('Read a book').first,
    const Offset(-240, 0),
    after: 1200,
  );
  await demo.tapText('Undo', after: 1500);

  await demo.scene('Long-press a card: every quick action, with words');
  await demo.longPress(find.textContaining('Team stand-up').first, after: 1500);
  await demo.tapKey('quick-action-Prolong 30 min', after: 2000);
  await demo.scene('Select several cards');
  await demo.scrollToTop();
  await demo.longPress(find.textContaining('Diary').first, after: 1500);
  await demo.tapKey('quick-action-select', after: 1200);
  await demo.tap(
    find.textContaining('Read a book').first,
    note: 'select second card',
  );
  await demo.pause(1200);
  await demo.tapTooltip('Clear selection');

  await demo.scene('Search the board');
  await demo.tapKey('current-search-toggle');
  await demo.type(find.byKey(const ValueKey('current-search-field')), 'run');
  await demo.pause(1000);
  await demo.tapKey('current-search-toggle');
  await demo.tapKey('current-icons-toggle');
  await demo.tapKey('current-icons-toggle');

  await demo.scene('New action');
  await demo.tapTooltip('New action');
  await demo.type(nameField, 'Buy a birthday present');
  await demo.tapText('Notes', after: 900);
  await demo.typeInNotes('Flowers and a book');
  await demo.scroll(dy: 600);
  await demo.tapText('Save');

  await demo.scene('Open an action: the editor with notes, toggle and code');
  await demo.scrollToTop();
  await demo.tap(
    find.textContaining('Deep work').first,
    after: 1600,
    note: 'Deep work card',
  );
  await demo.scroll(dy: 900);
  await demo.tapText('Cancel');

  // ----------------------------------------------------------------- Calendar
  await demo.scene('Calendar - full screen');
  await actionsTab('Calendar');
  await demo.pause(1500);
  await demo.scroll(dy: 500);
  await demo.scene('Swipe sideways to change the day');
  await demo.drag(
    find.byKey(const ValueKey('day-header-0')),
    const Offset(-220, 0),
    after: 1200,
  );
  await demo.drag(
    find.byKey(const ValueKey('day-header-0')),
    const Offset(220, 0),
    after: 1200,
  );
  await demo.tapKey('calendar-now-phone');
  await demo.tapKey('calendar-menu', after: 1000);
  await demo.tapKey('calendar-menu-days-3', after: 1200);
  await demo.tapKey('calendar-menu', after: 1000);
  await demo.tapKey('calendar-menu-icons', after: 1000);
  await demo.tapKey('calendar-menu', after: 1000);
  await demo.tapKey('calendar-menu-allday', after: 1000);
  await demo.tapKey('calendar-menu', after: 1000);
  await demo.tapKey('calendar-menu-days-1', after: 1000);
  await demo.tap(
    find.textContaining('Lunch with Anna').first,
    after: 1500,
    note: 'calendar block',
  );
  await demo.tapText('Cancel');
  await demo.scene('Leave full screen and come back');
  await demo.tapKey('calendar-full-toggle', after: 1500);
  await demo.tapKey('calendar-full-toggle', after: 1500);

  // ---------------------------------------------------------------------- All
  await demo.tapKey('calendar-full-toggle', after: 1200);
  await demo.scene('All actions: search and summary');
  await actionsTab('All');
  await demo.type(find.byKey(const ValueKey('allSearchField')), 'run');
  await demo.tapKey('searchFlagNotes');
  await demo.tapKey('allOptionsToggle', after: 1500);
  await demo.scroll(dy: 300);
  await demo.tapKey('allOptionsToggle');
  await demo.tapKey('allSearchClear');

  await demo.scene("The diary from yesterday's work");
  await demo.type(find.byKey(const ValueKey('allSearchField')), 'Diary');
  await demo.tap(
    find.descendant(of: find.byType(ListView), matching: find.text('Diary')).first,
    after: 1500,
    note: 'Diary row',
  );
  await demo.scroll(dy: 400, back: false);
  await demo.tapText('Notes', after: 1000);
  await demo.scroll(dy: 400, back: false);
  await demo.tapKey('diary-transfer', after: 2500);
  await demo.scroll(dy: 500);
  await demo.tapText('Cancel');
  await demo.tapKey('allSearchClear');

  // ---------------------------------------------------------------- Templates
  await demo.scene('Templates');
  await actionsTab('Templates');
  await demo.scroll(dy: 300);
  await demo.tapTooltip('Start now');
  await demo.tap(
    find.textContaining('Morning run').first,
    note: 'template tile',
  );
  await demo.tapKey('template-use-average');
  await demo.tapText('Cancel');

  // ------------------------------------------------------------------- Growth
  await demo.scene('Growth directions');
  await nav('Growth Directions');
  await demo.scroll(dy: 700);
  await demo.tap(find.text('List').first, note: 'List tab');
  await demo.scroll(dy: 600);
  await demo.scrollToTop();
  await demo.tap(
    find.textContaining('I am healthy').first,
    note: 'direction row',
  );
  await demo.scroll(dy: 300);
  await demo.tapText('Cancel');
  await demo.scene('Mindmap with touch');
  await demo.tap(find.text('Mindmap').first, note: 'Mindmap tab');
  await demo.pause(1500);
  await demo.tapTooltip('Tree layout');
  await demo.tapTooltip('Auto layout', after: 1500);
  await demo.tapTooltip('Fit all');
  await demo.tapTooltip('Find a direction');
  await demo.type(find.byKey(const ValueKey('mindmap-search-field')), 'sleep');
  await demo.pause(1000);
  await demo.tapTooltip('Close search');
  await demo.scene('Full-screen mindmap');
  await demo.tapTooltip('Full screen', after: 2000);
  await demo.tapTooltip('Leave full screen', after: 1200);

  // ------------------------------------------------------------------- Budget
  await demo.scene('Budget');
  await nav('Budget');
  await demo.scroll(dy: 700);
  await demo.tapKey('budget-leaves-only', after: 1500);
  await demo.tapKey('budget-leaves-only');
  await demo.tap(find.text('Categories').first, note: 'tab Categories');
  await demo.type(
    find.byKey(const ValueKey('budget-categories-search')),
    'coffee',
  );
  await demo.pause(1000);
  await demo.clearField(find.byKey(const ValueKey('budget-categories-search')));
  await demo.scroll(dy: 700);
  await demo.tapKey('budget-fab');
  await demo.type(find.byKey(const ValueKey('category-name')), 'Books');
  await demo.tapKey('category-parent', after: 1200);
  await demo.type(find.byKey(const ValueKey('budget-category-search')), 'food');
  await demo.pause(900);
  await demo.tapText('Cancel');
  await demo.tapText('Cancel');
  await demo.tap(find.text('Transactions').first, note: 'tab Transactions');
  await demo.scroll(dy: 700);
  await demo.tap(find.text('Accounts').first, note: 'tab Accounts');
  await demo.scroll(dy: 300);

  // ----------------------------------------------------------------- Settings
  await demo.scene('Menu: settings and dark mode');
  await nav('Actions');
  await demo.tapKey('phone-menu', after: 1000);
  await demo.tapKey('phone-menu-settings', after: 1500);
  await demo.scroll(dy: 900);
  await demo.tap(find.byType(BackButton), note: 'settings back');
  await demo.tapKey('phone-menu', after: 1000);
  await demo.tapText('Dark mode', after: 2500);
  await actionsTab('Calendar');
  await demo.pause(2000);
  await demo.tapKey('calendar-full-toggle', after: 1200);
  await demo.tapKey('phone-menu', after: 1000);
  await demo.tapText('Dark mode', after: 2000);

  // ---------------------------------------------------------------- Landscape
  await demo.scene('Turn the phone sideways');
  await landscape();
  await demo.pause(1800);
  await actionsTab('Current');
  await demo.pause(2000);
  await actionsTab('Calendar');
  await demo.pause(1500);
  await demo.tapKey('calendar-menu', after: 1000);
  await demo.tapKey('calendar-menu-days-5', after: 2000);
  await demo.tapKey('calendar-menu', after: 1000);
  await demo.tapKey('calendar-menu-days-1', after: 1200);
  await demo.tapKey('calendar-full-toggle', after: 1500);
  await demo.tap(
    find.byKey(const ValueKey('phone-rail-1')),
    note: 'rail Growth',
    after: 1500,
  );
  await demo.tap(find.text('Mindmap').first, note: 'Mindmap tab');
  await demo.pause(1500);
  await demo.tap(
    find.byKey(const ValueKey('phone-rail-2')),
    note: 'rail Budget',
    after: 1500,
  );
  await demo.tap(
    find.byKey(const ValueKey('phone-rail-0')),
    note: 'rail Actions',
    after: 1200,
  );
  await demo.scene('Back upright');
  await portrait();
  await demo.pause(1500);
  await demo.scene('The end', 2500);
}
