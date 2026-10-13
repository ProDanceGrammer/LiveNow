import 'package:flutter/material.dart';

import '../../domain/all_actions_view_rules.dart' show SortField;
import '../../domain/budget_tx_view_rules.dart' show TxSortField;
import '../../domain/template_sort.dart' show TemplateSortField;
import 'param_icons.dart';

/// The icon drawn left of a sort field's name in every sort menu (chips and
/// the "Add sort" list). Kept on the UI side so the domain enums stay free of
/// Flutter types.
Widget sortFieldIcon(Object field, {double size = 16}) {
  Widget material(IconData icon) => Icon(icon, size: size);
  return switch (field) {
    SortField.name => material(Icons.sort_by_alpha),
    SortField.start => material(Icons.play_circle_outline),
    SortField.end => material(Icons.stop_circle_outlined),
    SortField.duration => material(Icons.timelapse),
    SortField.urgency => ParamIcon.urgency(size: size, tooltip: false),
    SortField.lastEdited => material(Icons.history),
    SortField.created => material(Icons.add_circle_outline),
    SortField.done => material(Icons.check_circle_outline),
    TxSortField.date => material(Icons.event),
    TxSortField.amount => material(Icons.payments_outlined),
    TxSortField.name => material(Icons.sort_by_alpha),
    TxSortField.category => material(Icons.category_outlined),
    TemplateSortField.name => material(Icons.sort_by_alpha),
    TemplateSortField.direction => material(Icons.insights),
    TemplateSortField.urgency => ParamIcon.urgency(size: size, tooltip: false),
    TemplateSortField.average => material(Icons.timelapse),
    TemplateSortField.manual => material(Icons.edit_note),
    _ => material(Icons.sort),
  };
}
