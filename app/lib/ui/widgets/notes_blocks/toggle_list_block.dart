import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// ignore: depend_on_referenced_packages
import 'package:provider/provider.dart';

/// Block type string of the collapsible toggle list.
const String toggleListBlockType = 'toggle_list';

/// Attribute holding the collapsed flag (bool).
const String toggleListCollapsedKey = 'collapsed';

/// Builds a toggle list node. Node shape (persisted, do not change):
/// `{type: 'toggle_list', attributes: {delta, collapsed}, children}`.
Node toggleListNode({
  required String text,
  bool collapsed = false,
  List<Node> children = const [],
}) {
  return Node(
    type: toggleListBlockType,
    attributes: {
      blockComponentDelta: (Delta()..insert(text)).toJson(),
      toggleListCollapsedKey: collapsed,
    },
    children: children,
  );
}

class ToggleListBlockComponentBuilder extends BlockComponentBuilder {
  ToggleListBlockComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return ToggleListBlockComponentWidget(
      key: node.key,
      node: node,
      configuration: configuration,
      showActions: showActions(node),
      actionBuilder: (context, state) =>
          actionBuilder(blockComponentContext, state),
      actionTrailingBuilder: (context, state) =>
          actionTrailingBuilder(blockComponentContext, state),
    );
  }

  @override
  BlockComponentValidate get validate =>
      (node) => node.delta != null;
}

class ToggleListBlockComponentWidget extends BlockComponentStatefulWidget {
  const ToggleListBlockComponentWidget({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<ToggleListBlockComponentWidget> createState() =>
      _ToggleListBlockComponentWidgetState();
}

class _ToggleListBlockComponentWidgetState
    extends State<ToggleListBlockComponentWidget>
    with
        SelectableMixin,
        DefaultSelectableMixin,
        BlockComponentConfigurable,
        BlockComponentBackgroundColorMixin,
        NestedBlockComponentStatefulWidgetMixin,
        BlockComponentTextDirectionMixin,
        BlockComponentAlignMixin {
  @override
  final forwardKey = GlobalKey(debugLabel: 'flowy_rich_text');

  @override
  GlobalKey<State<StatefulWidget>> get containerKey => widget.node.key;

  @override
  GlobalKey<State<StatefulWidget>> blockComponentKey = GlobalKey(
    debugLabel: toggleListBlockType,
  );

  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  bool get collapsed => widget.node.attributes[toggleListCollapsedKey] == true;

  /// Children stay in the document while collapsed; they are just not built.
  /// Each one is represented by an Offstage placeholder carrying its node key:
  /// the editor's hit test (double click, drag) lists a node's children as
  /// candidates unless their key's context sits under an Offstage, and an
  /// UNMOUNTED child looked visible to it, so a double click on the title of a
  /// closed toggle landed on a child with nothing to select and cleared the
  /// selection.
  @override
  Widget build(BuildContext context) {
    final Widget content;
    if (node.children.isEmpty) {
      content = buildComponent(context);
    } else if (collapsed) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          buildComponent(context),
          for (final child in node.children)
            Offstage(child: SizedBox.shrink(key: child.key)),
        ],
      );
    } else {
      content = buildComponentWithChildren(context);
    }
    return Padding(padding: configuration.margin(node), child: content);
  }

  @override
  Widget buildComponent(
    BuildContext context, {
    bool withBackgroundColor = true,
  }) {
    final textDirection = calculateTextDirection(
      layoutDirection: Directionality.maybeOf(context),
    );

    Widget child = Container(
      width: double.infinity,
      alignment: alignment,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        textDirection: textDirection,
        children: [
          _ToggleChevron(collapsed: collapsed, onTap: toggleCollapsed),
          Flexible(
            child: AppFlowyRichText(
              key: forwardKey,
              delegate: this,
              node: widget.node,
              editorState: editorState,
              textAlign: alignment?.toTextAlign ?? textAlign,
              placeholderText: placeholderText,
              textDirection: textDirection,
              textSpanDecorator: (textSpan) =>
                  textSpan.updateTextStyle(textStyleWithTextSpan()),
              placeholderTextSpanDecorator: (textSpan) =>
                  textSpan.updateTextStyle(
                    placeholderTextStyleWithTextSpan(textSpan: textSpan),
                  ),
              cursorColor: editorState.editorStyle.cursorColor,
              selectionColor: editorState.editorStyle.selectionColor,
              cursorWidth: editorState.editorStyle.cursorWidth,
            ),
          ),
        ],
      ),
    );

    child = Container(
      decoration: withBackgroundColor ? decoration : null,
      key: blockComponentKey,
      padding: padding,
      child: child,
    );

    child = BlockSelectionContainer(
      node: node,
      delegate: this,
      listenable: editorState.selectionNotifier,
      remoteSelection: editorState.remoteSelections,
      blockColor: editorState.editorStyle.selectionColor,
      supportTypes: const [BlockSelectionType.block],
      child: child,
    );

    if (widget.showActions && widget.actionBuilder != null) {
      child = BlockComponentActionWrapper(
        node: node,
        actionBuilder: widget.actionBuilder!,
        actionTrailingBuilder: widget.actionTrailingBuilder,
        child: child,
      );
    }
    return child;
  }

  void toggleCollapsed() {
    final transaction = editorState.transaction
      ..updateNode(widget.node, {toggleListCollapsedKey: !collapsed});
    editorState.apply(transaction, withUpdateSelection: false);
  }
}

class _ToggleChevron extends StatelessWidget {
  const _ToggleChevron({required this.collapsed, required this.onTap});

  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scale = context.read<EditorState>().editorStyle.textScaleFactor;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints:
              const BoxConstraints(minWidth: 26, minHeight: 24) * scale,
          padding: const EdgeInsets.only(right: 4),
          alignment: Alignment.center,
          child: Icon(
            collapsed ? Icons.chevron_right : Icons.expand_more,
            size: 20,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shortcuts
// ---------------------------------------------------------------------------

/// `> ` at the very start of a paragraph turns it into a toggle list
/// (following text and children are kept). Does not fire mid-text.
final CharacterShortcutEvent formatGreaterToToggleList = CharacterShortcutEvent(
  key: 'format greater to toggle list',
  character: ' ',
  handler: (editorState) => formatMarkdownSymbol(
    editorState,
    (node) => node.type == ParagraphBlockKeys.type,
    (_, text, _) => text == '>',
    (_, node, delta) => [
      node.copyWith(
        type: toggleListBlockType,
        attributes: {
          blockComponentDelta: delta.compose(Delta()..delete(1)).toJson(),
          toggleListCollapsedKey: false,
        },
      ),
    ],
  ),
);

/// Enter handling for toggle lists and for empty paragraphs inside a toggle.
///
/// * Empty toggle: outdent if nested, else convert to paragraph.
/// * Expanded toggle that has children: the text after the cursor (empty at
///   the end of the title) goes into a new first child paragraph.
/// * Collapsed or childless toggle: a sibling paragraph is inserted after it
///   (children stay with the toggle).
/// * Empty child paragraph of a toggle: moved out after the toggle.
final CharacterShortcutEvent insertNewLineInToggleList = CharacterShortcutEvent(
  key: 'insert new line in toggle list',
  character: '\n',
  handler: (editorState) async {
    if (HardwareKeyboard.instance.isShiftPressed) return false;
    final selection = editorState.selection;
    if (selection == null || !selection.isCollapsed) return false;
    final node = editorState.getNodeAtPath(selection.end.path);
    final delta = node?.delta;
    if (node == null || delta == null) return false;

    if (node.type == ParagraphBlockKeys.type) {
      final parent = node.parent;
      if (parent == null ||
          parent.type != toggleListBlockType ||
          delta.isNotEmpty ||
          node.children.isNotEmpty) {
        return false;
      }
      final target = parent.path.next;
      final transaction = editorState.transaction
        ..deleteNode(node)
        ..insertNode(target, paragraphNode())
        ..afterSelection = Selection.collapsed(Position(path: target));
      await editorState.apply(transaction);
      return true;
    }

    if (node.type != toggleListBlockType) return false;
    final offset = selection.end.offset;

    if (delta.isEmpty) {
      if (node.path.length > 1) {
        final target = node.parent!.path.next;
        final transaction = editorState.transaction
          ..deleteNode(node)
          ..insertNode(
            target,
            paragraphNode(
              attributes: {blockComponentDelta: delta.toJson()},
              children: node.children.map((e) => e.deepCopy()).toList(),
            ),
          )
          ..afterSelection = Selection.collapsed(Position(path: target));
        await editorState.apply(transaction);
      } else {
        await convertToParagraph(editorState, node);
      }
      return true;
    }

    final expanded = node.attributes[toggleListCollapsedKey] != true;
    // An expanded toggle always takes the new line as its first child (like
    // Notion), also when it has none yet; a collapsed one gets a sibling.
    final asChild = expanded;
    final tail = delta.slice(offset);
    final target = asChild ? [...node.path, 0] : node.path.next;
    final transaction = editorState.transaction
      ..deleteText(node, offset, delta.length - offset)
      ..insertNode(
        target,
        paragraphNode(attributes: {blockComponentDelta: tail.toJson()}),
      )
      ..afterSelection = Selection.collapsed(Position(path: target));
    await editorState.apply(transaction);
    return true;
  },
);

/// Replaces [node] (which has a delta) with a paragraph keeping text and
/// children; puts the cursor at its start.
Future<void> convertToParagraph(EditorState editorState, Node node) {
  final path = node.path;
  final transaction = editorState.transaction
    ..insertNode(
      path,
      paragraphNode(
        attributes: {blockComponentDelta: node.delta!.toJson()},
        children: node.children.map((e) => e.deepCopy()).toList(),
      ),
    )
    ..deleteNode(node)
    ..afterSelection = Selection.collapsed(Position(path: path));
  return editorState.apply(transaction);
}

/// Backspace at the start of a toggle turns it into a paragraph.
final CommandShortcutEvent toggleListBackspaceCommand = CommandShortcutEvent(
  key: 'toggle list backspace to paragraph',
  getDescription: () => 'Convert toggle list to paragraph',
  command: 'backspace',
  handler: (editorState) {
    final selection = editorState.selection;
    if (selection == null || !selection.isCollapsed) {
      return KeyEventResult.ignored;
    }
    final node = editorState.getNodeAtPath(selection.end.path);
    if (node == null ||
        node.type != toggleListBlockType ||
        node.delta == null ||
        selection.end.offset != 0) {
      return KeyEventResult.ignored;
    }
    convertToParagraph(editorState, node);
    return KeyEventResult.handled;
  },
);
