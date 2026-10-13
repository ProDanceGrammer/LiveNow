import 'package:flutter_riverpod/legacy.dart'
    show StateController, StateProvider;

/// The actions ticked in the Actions > All list (checkboxes, marquee). A set
/// of ids, so it survives the list re-sorting after a bulk edit; the view
/// prunes ids that left the filtered list.
final allSelectionProvider = StateProvider<Set<String>>((ref) => const {});

extension AllSelectionOps on StateController<Set<String>> {
  void toggle(String id) {
    final next = {...state};
    if (!next.remove(id)) next.add(id);
    state = next;
  }

  void clear() {
    if (state.isNotEmpty) state = const {};
  }

  void setAll(Iterable<String> ids) => state = {...ids};

  void addAll(Iterable<String> ids) => state = {...state, ...ids};
}
