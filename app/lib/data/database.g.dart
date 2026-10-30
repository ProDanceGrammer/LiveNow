// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $CountableActivitiesTableTable extends CountableActivitiesTable
    with TableInfo<$CountableActivitiesTableTable, CountableActivity> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CountableActivitiesTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, createdAt, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'countable_activities';
  @override
  VerificationContext validateIntegrity(
    Insertable<CountableActivity> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CountableActivity map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CountableActivity(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $CountableActivitiesTableTable createAlias(String alias) {
    return $CountableActivitiesTableTable(attachedDatabase, alias);
  }
}

class CountableActivity extends DataClass
    implements Insertable<CountableActivity> {
  final String id;
  final String name;
  final String createdAt;
  final String updatedAt;
  const CountableActivity({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['created_at'] = Variable<String>(createdAt);
    map['updated_at'] = Variable<String>(updatedAt);
    return map;
  }

  CountableActivitiesTableCompanion toCompanion(bool nullToAbsent) {
    return CountableActivitiesTableCompanion(
      id: Value(id),
      name: Value(name),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory CountableActivity.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CountableActivity(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'createdAt': serializer.toJson<String>(createdAt),
      'updatedAt': serializer.toJson<String>(updatedAt),
    };
  }

  CountableActivity copyWith({
    String? id,
    String? name,
    String? createdAt,
    String? updatedAt,
  }) => CountableActivity(
    id: id ?? this.id,
    name: name ?? this.name,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  CountableActivity copyWithCompanion(CountableActivitiesTableCompanion data) {
    return CountableActivity(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CountableActivity(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CountableActivity &&
          other.id == this.id &&
          other.name == this.name &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class CountableActivitiesTableCompanion
    extends UpdateCompanion<CountableActivity> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> createdAt;
  final Value<String> updatedAt;
  final Value<int> rowid;
  const CountableActivitiesTableCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CountableActivitiesTableCompanion.insert({
    required String id,
    required String name,
    required String createdAt,
    required String updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<CountableActivity> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CountableActivitiesTableCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? createdAt,
    Value<String>? updatedAt,
    Value<int>? rowid,
  }) {
    return CountableActivitiesTableCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CountableActivitiesTableCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ActionsTableTable extends ActionsTable
    with TableInfo<$ActionsTableTable, ActionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ActionsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _doneMeta = const VerificationMeta('done');
  @override
  late final GeneratedColumn<bool> done = GeneratedColumn<bool>(
    'done',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("done" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _postponeFlexMeta = const VerificationMeta(
    'postponeFlex',
  );
  @override
  late final GeneratedColumn<String> postponeFlex = GeneratedColumn<String>(
    'postpone_flex',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('flexible'),
  );
  static const VerificationMeta _depthLevelMeta = const VerificationMeta(
    'depthLevel',
  );
  @override
  late final GeneratedColumn<String> depthLevel = GeneratedColumn<String>(
    'depth_level',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _startAtMeta = const VerificationMeta(
    'startAt',
  );
  @override
  late final GeneratedColumn<String> startAt = GeneratedColumn<String>(
    'start_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _endAtMeta = const VerificationMeta('endAt');
  @override
  late final GeneratedColumn<String> endAt = GeneratedColumn<String>(
    'end_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isAllDayMeta = const VerificationMeta(
    'isAllDay',
  );
  @override
  late final GeneratedColumn<bool> isAllDay = GeneratedColumn<bool>(
    'is_all_day',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_all_day" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _estimatedMinutesMeta = const VerificationMeta(
    'estimatedMinutes',
  );
  @override
  late final GeneratedColumn<int> estimatedMinutes = GeneratedColumn<int>(
    'estimated_minutes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _resultNoteMeta = const VerificationMeta(
    'resultNote',
  );
  @override
  late final GeneratedColumn<String> resultNote = GeneratedColumn<String>(
    'result_note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _notesTextMeta = const VerificationMeta(
    'notesText',
  );
  @override
  late final GeneratedColumn<String> notesText = GeneratedColumn<String>(
    'notes_text',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _completedAtMeta = const VerificationMeta(
    'completedAt',
  );
  @override
  late final GeneratedColumn<String> completedAt = GeneratedColumn<String>(
    'completed_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sequenceNumberMeta = const VerificationMeta(
    'sequenceNumber',
  );
  @override
  late final GeneratedColumn<int> sequenceNumber = GeneratedColumn<int>(
    'sequence_number',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _countableActivityIdMeta =
      const VerificationMeta('countableActivityId');
  @override
  late final GeneratedColumn<String> countableActivityId =
      GeneratedColumn<String>(
        'countable_activity_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES countable_activities (id) ON DELETE SET NULL',
        ),
      );
  static const VerificationMeta _planItemIdMeta = const VerificationMeta(
    'planItemId',
  );
  @override
  late final GeneratedColumn<String> planItemId = GeneratedColumn<String>(
    'plan_item_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _planKeyMeta = const VerificationMeta(
    'planKey',
  );
  @override
  late final GeneratedColumn<String> planKey = GeneratedColumn<String>(
    'plan_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    done,
    postponeFlex,
    depthLevel,
    startAt,
    endAt,
    isAllDay,
    estimatedMinutes,
    resultNote,
    notes,
    notesText,
    completedAt,
    sequenceNumber,
    countableActivityId,
    planItemId,
    planKey,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'actions';
  @override
  VerificationContext validateIntegrity(
    Insertable<ActionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('done')) {
      context.handle(
        _doneMeta,
        done.isAcceptableOrUnknown(data['done']!, _doneMeta),
      );
    }
    if (data.containsKey('postpone_flex')) {
      context.handle(
        _postponeFlexMeta,
        postponeFlex.isAcceptableOrUnknown(
          data['postpone_flex']!,
          _postponeFlexMeta,
        ),
      );
    }
    if (data.containsKey('depth_level')) {
      context.handle(
        _depthLevelMeta,
        depthLevel.isAcceptableOrUnknown(data['depth_level']!, _depthLevelMeta),
      );
    }
    if (data.containsKey('start_at')) {
      context.handle(
        _startAtMeta,
        startAt.isAcceptableOrUnknown(data['start_at']!, _startAtMeta),
      );
    }
    if (data.containsKey('end_at')) {
      context.handle(
        _endAtMeta,
        endAt.isAcceptableOrUnknown(data['end_at']!, _endAtMeta),
      );
    }
    if (data.containsKey('is_all_day')) {
      context.handle(
        _isAllDayMeta,
        isAllDay.isAcceptableOrUnknown(data['is_all_day']!, _isAllDayMeta),
      );
    }
    if (data.containsKey('estimated_minutes')) {
      context.handle(
        _estimatedMinutesMeta,
        estimatedMinutes.isAcceptableOrUnknown(
          data['estimated_minutes']!,
          _estimatedMinutesMeta,
        ),
      );
    }
    if (data.containsKey('result_note')) {
      context.handle(
        _resultNoteMeta,
        resultNote.isAcceptableOrUnknown(data['result_note']!, _resultNoteMeta),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('notes_text')) {
      context.handle(
        _notesTextMeta,
        notesText.isAcceptableOrUnknown(data['notes_text']!, _notesTextMeta),
      );
    }
    if (data.containsKey('completed_at')) {
      context.handle(
        _completedAtMeta,
        completedAt.isAcceptableOrUnknown(
          data['completed_at']!,
          _completedAtMeta,
        ),
      );
    }
    if (data.containsKey('sequence_number')) {
      context.handle(
        _sequenceNumberMeta,
        sequenceNumber.isAcceptableOrUnknown(
          data['sequence_number']!,
          _sequenceNumberMeta,
        ),
      );
    }
    if (data.containsKey('countable_activity_id')) {
      context.handle(
        _countableActivityIdMeta,
        countableActivityId.isAcceptableOrUnknown(
          data['countable_activity_id']!,
          _countableActivityIdMeta,
        ),
      );
    }
    if (data.containsKey('plan_item_id')) {
      context.handle(
        _planItemIdMeta,
        planItemId.isAcceptableOrUnknown(
          data['plan_item_id']!,
          _planItemIdMeta,
        ),
      );
    }
    if (data.containsKey('plan_key')) {
      context.handle(
        _planKeyMeta,
        planKey.isAcceptableOrUnknown(data['plan_key']!, _planKeyMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ActionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ActionRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      done: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}done'],
      )!,
      postponeFlex: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}postpone_flex'],
      )!,
      depthLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}depth_level'],
      ),
      startAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}start_at'],
      ),
      endAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}end_at'],
      ),
      isAllDay: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_all_day'],
      )!,
      estimatedMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}estimated_minutes'],
      ),
      resultNote: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}result_note'],
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      notesText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes_text'],
      ),
      completedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}completed_at'],
      ),
      sequenceNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sequence_number'],
      ),
      countableActivityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}countable_activity_id'],
      ),
      planItemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}plan_item_id'],
      ),
      planKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}plan_key'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ActionsTableTable createAlias(String alias) {
    return $ActionsTableTable(attachedDatabase, alias);
  }
}

class ActionRow extends DataClass implements Insertable<ActionRow> {
  final String id;
  final String name;
  final bool done;
  final String postponeFlex;
  final String? depthLevel;

  /// UTC ISO-8601 text, chosen over Drift's native DateTime column so the
  /// on-disk representation matches what a future Postgres sync target
  /// expects, rather than sqlite's integer default.
  final String? startAt;
  final String? endAt;
  final bool isAllDay;
  final int? estimatedMinutes;
  final String? resultNote;

  /// The action's rich-text description (checklists, bullets, headings…):
  /// the editor's Document JSON, or null when empty. Written by the notes
  /// editor in the action dialog; `result_note` stays a separate, unused
  /// plain "outcome" field.
  final String? notes;

  /// Lower-cased plain text of [notes], derived (see `notesPlainText`) and
  /// written next to it; only used by the All list's notes search.
  final String? notesText;
  final String? completedAt;

  /// Position in a "Continue with Same Action" chain (`[#2] Read a Bible`).
  /// The name prefix is display only; this column is the source of truth.
  final int? sequenceNumber;

  /// The repeatable activity type this action is an instance of; its past
  /// durations feed the predicted duration of a continuation.
  final String? countableActivityId;

  /// The plan item this action was generated from (schema v14; null = made by
  /// hand) and the occurrence it was (`YYYY-MM-DD#index`). A soft reference
  /// (the plan item may be deleted later); it makes a re-confirmation
  /// idempotent and lets "remove future actions" find what a plan made.
  final String? planItemId;
  final String? planKey;
  final String createdAt;
  final String updatedAt;
  const ActionRow({
    required this.id,
    required this.name,
    required this.done,
    required this.postponeFlex,
    this.depthLevel,
    this.startAt,
    this.endAt,
    required this.isAllDay,
    this.estimatedMinutes,
    this.resultNote,
    this.notes,
    this.notesText,
    this.completedAt,
    this.sequenceNumber,
    this.countableActivityId,
    this.planItemId,
    this.planKey,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['done'] = Variable<bool>(done);
    map['postpone_flex'] = Variable<String>(postponeFlex);
    if (!nullToAbsent || depthLevel != null) {
      map['depth_level'] = Variable<String>(depthLevel);
    }
    if (!nullToAbsent || startAt != null) {
      map['start_at'] = Variable<String>(startAt);
    }
    if (!nullToAbsent || endAt != null) {
      map['end_at'] = Variable<String>(endAt);
    }
    map['is_all_day'] = Variable<bool>(isAllDay);
    if (!nullToAbsent || estimatedMinutes != null) {
      map['estimated_minutes'] = Variable<int>(estimatedMinutes);
    }
    if (!nullToAbsent || resultNote != null) {
      map['result_note'] = Variable<String>(resultNote);
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    if (!nullToAbsent || notesText != null) {
      map['notes_text'] = Variable<String>(notesText);
    }
    if (!nullToAbsent || completedAt != null) {
      map['completed_at'] = Variable<String>(completedAt);
    }
    if (!nullToAbsent || sequenceNumber != null) {
      map['sequence_number'] = Variable<int>(sequenceNumber);
    }
    if (!nullToAbsent || countableActivityId != null) {
      map['countable_activity_id'] = Variable<String>(countableActivityId);
    }
    if (!nullToAbsent || planItemId != null) {
      map['plan_item_id'] = Variable<String>(planItemId);
    }
    if (!nullToAbsent || planKey != null) {
      map['plan_key'] = Variable<String>(planKey);
    }
    map['created_at'] = Variable<String>(createdAt);
    map['updated_at'] = Variable<String>(updatedAt);
    return map;
  }

  ActionsTableCompanion toCompanion(bool nullToAbsent) {
    return ActionsTableCompanion(
      id: Value(id),
      name: Value(name),
      done: Value(done),
      postponeFlex: Value(postponeFlex),
      depthLevel: depthLevel == null && nullToAbsent
          ? const Value.absent()
          : Value(depthLevel),
      startAt: startAt == null && nullToAbsent
          ? const Value.absent()
          : Value(startAt),
      endAt: endAt == null && nullToAbsent
          ? const Value.absent()
          : Value(endAt),
      isAllDay: Value(isAllDay),
      estimatedMinutes: estimatedMinutes == null && nullToAbsent
          ? const Value.absent()
          : Value(estimatedMinutes),
      resultNote: resultNote == null && nullToAbsent
          ? const Value.absent()
          : Value(resultNote),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      notesText: notesText == null && nullToAbsent
          ? const Value.absent()
          : Value(notesText),
      completedAt: completedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAt),
      sequenceNumber: sequenceNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(sequenceNumber),
      countableActivityId: countableActivityId == null && nullToAbsent
          ? const Value.absent()
          : Value(countableActivityId),
      planItemId: planItemId == null && nullToAbsent
          ? const Value.absent()
          : Value(planItemId),
      planKey: planKey == null && nullToAbsent
          ? const Value.absent()
          : Value(planKey),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory ActionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ActionRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      done: serializer.fromJson<bool>(json['done']),
      postponeFlex: serializer.fromJson<String>(json['postponeFlex']),
      depthLevel: serializer.fromJson<String?>(json['depthLevel']),
      startAt: serializer.fromJson<String?>(json['startAt']),
      endAt: serializer.fromJson<String?>(json['endAt']),
      isAllDay: serializer.fromJson<bool>(json['isAllDay']),
      estimatedMinutes: serializer.fromJson<int?>(json['estimatedMinutes']),
      resultNote: serializer.fromJson<String?>(json['resultNote']),
      notes: serializer.fromJson<String?>(json['notes']),
      notesText: serializer.fromJson<String?>(json['notesText']),
      completedAt: serializer.fromJson<String?>(json['completedAt']),
      sequenceNumber: serializer.fromJson<int?>(json['sequenceNumber']),
      countableActivityId: serializer.fromJson<String?>(
        json['countableActivityId'],
      ),
      planItemId: serializer.fromJson<String?>(json['planItemId']),
      planKey: serializer.fromJson<String?>(json['planKey']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'done': serializer.toJson<bool>(done),
      'postponeFlex': serializer.toJson<String>(postponeFlex),
      'depthLevel': serializer.toJson<String?>(depthLevel),
      'startAt': serializer.toJson<String?>(startAt),
      'endAt': serializer.toJson<String?>(endAt),
      'isAllDay': serializer.toJson<bool>(isAllDay),
      'estimatedMinutes': serializer.toJson<int?>(estimatedMinutes),
      'resultNote': serializer.toJson<String?>(resultNote),
      'notes': serializer.toJson<String?>(notes),
      'notesText': serializer.toJson<String?>(notesText),
      'completedAt': serializer.toJson<String?>(completedAt),
      'sequenceNumber': serializer.toJson<int?>(sequenceNumber),
      'countableActivityId': serializer.toJson<String?>(countableActivityId),
      'planItemId': serializer.toJson<String?>(planItemId),
      'planKey': serializer.toJson<String?>(planKey),
      'createdAt': serializer.toJson<String>(createdAt),
      'updatedAt': serializer.toJson<String>(updatedAt),
    };
  }

  ActionRow copyWith({
    String? id,
    String? name,
    bool? done,
    String? postponeFlex,
    Value<String?> depthLevel = const Value.absent(),
    Value<String?> startAt = const Value.absent(),
    Value<String?> endAt = const Value.absent(),
    bool? isAllDay,
    Value<int?> estimatedMinutes = const Value.absent(),
    Value<String?> resultNote = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    Value<String?> notesText = const Value.absent(),
    Value<String?> completedAt = const Value.absent(),
    Value<int?> sequenceNumber = const Value.absent(),
    Value<String?> countableActivityId = const Value.absent(),
    Value<String?> planItemId = const Value.absent(),
    Value<String?> planKey = const Value.absent(),
    String? createdAt,
    String? updatedAt,
  }) => ActionRow(
    id: id ?? this.id,
    name: name ?? this.name,
    done: done ?? this.done,
    postponeFlex: postponeFlex ?? this.postponeFlex,
    depthLevel: depthLevel.present ? depthLevel.value : this.depthLevel,
    startAt: startAt.present ? startAt.value : this.startAt,
    endAt: endAt.present ? endAt.value : this.endAt,
    isAllDay: isAllDay ?? this.isAllDay,
    estimatedMinutes: estimatedMinutes.present
        ? estimatedMinutes.value
        : this.estimatedMinutes,
    resultNote: resultNote.present ? resultNote.value : this.resultNote,
    notes: notes.present ? notes.value : this.notes,
    notesText: notesText.present ? notesText.value : this.notesText,
    completedAt: completedAt.present ? completedAt.value : this.completedAt,
    sequenceNumber: sequenceNumber.present
        ? sequenceNumber.value
        : this.sequenceNumber,
    countableActivityId: countableActivityId.present
        ? countableActivityId.value
        : this.countableActivityId,
    planItemId: planItemId.present ? planItemId.value : this.planItemId,
    planKey: planKey.present ? planKey.value : this.planKey,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ActionRow copyWithCompanion(ActionsTableCompanion data) {
    return ActionRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      done: data.done.present ? data.done.value : this.done,
      postponeFlex: data.postponeFlex.present
          ? data.postponeFlex.value
          : this.postponeFlex,
      depthLevel: data.depthLevel.present
          ? data.depthLevel.value
          : this.depthLevel,
      startAt: data.startAt.present ? data.startAt.value : this.startAt,
      endAt: data.endAt.present ? data.endAt.value : this.endAt,
      isAllDay: data.isAllDay.present ? data.isAllDay.value : this.isAllDay,
      estimatedMinutes: data.estimatedMinutes.present
          ? data.estimatedMinutes.value
          : this.estimatedMinutes,
      resultNote: data.resultNote.present
          ? data.resultNote.value
          : this.resultNote,
      notes: data.notes.present ? data.notes.value : this.notes,
      notesText: data.notesText.present ? data.notesText.value : this.notesText,
      completedAt: data.completedAt.present
          ? data.completedAt.value
          : this.completedAt,
      sequenceNumber: data.sequenceNumber.present
          ? data.sequenceNumber.value
          : this.sequenceNumber,
      countableActivityId: data.countableActivityId.present
          ? data.countableActivityId.value
          : this.countableActivityId,
      planItemId: data.planItemId.present
          ? data.planItemId.value
          : this.planItemId,
      planKey: data.planKey.present ? data.planKey.value : this.planKey,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ActionRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('done: $done, ')
          ..write('postponeFlex: $postponeFlex, ')
          ..write('depthLevel: $depthLevel, ')
          ..write('startAt: $startAt, ')
          ..write('endAt: $endAt, ')
          ..write('isAllDay: $isAllDay, ')
          ..write('estimatedMinutes: $estimatedMinutes, ')
          ..write('resultNote: $resultNote, ')
          ..write('notes: $notes, ')
          ..write('notesText: $notesText, ')
          ..write('completedAt: $completedAt, ')
          ..write('sequenceNumber: $sequenceNumber, ')
          ..write('countableActivityId: $countableActivityId, ')
          ..write('planItemId: $planItemId, ')
          ..write('planKey: $planKey, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    done,
    postponeFlex,
    depthLevel,
    startAt,
    endAt,
    isAllDay,
    estimatedMinutes,
    resultNote,
    notes,
    notesText,
    completedAt,
    sequenceNumber,
    countableActivityId,
    planItemId,
    planKey,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ActionRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.done == this.done &&
          other.postponeFlex == this.postponeFlex &&
          other.depthLevel == this.depthLevel &&
          other.startAt == this.startAt &&
          other.endAt == this.endAt &&
          other.isAllDay == this.isAllDay &&
          other.estimatedMinutes == this.estimatedMinutes &&
          other.resultNote == this.resultNote &&
          other.notes == this.notes &&
          other.notesText == this.notesText &&
          other.completedAt == this.completedAt &&
          other.sequenceNumber == this.sequenceNumber &&
          other.countableActivityId == this.countableActivityId &&
          other.planItemId == this.planItemId &&
          other.planKey == this.planKey &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ActionsTableCompanion extends UpdateCompanion<ActionRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<bool> done;
  final Value<String> postponeFlex;
  final Value<String?> depthLevel;
  final Value<String?> startAt;
  final Value<String?> endAt;
  final Value<bool> isAllDay;
  final Value<int?> estimatedMinutes;
  final Value<String?> resultNote;
  final Value<String?> notes;
  final Value<String?> notesText;
  final Value<String?> completedAt;
  final Value<int?> sequenceNumber;
  final Value<String?> countableActivityId;
  final Value<String?> planItemId;
  final Value<String?> planKey;
  final Value<String> createdAt;
  final Value<String> updatedAt;
  final Value<int> rowid;
  const ActionsTableCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.done = const Value.absent(),
    this.postponeFlex = const Value.absent(),
    this.depthLevel = const Value.absent(),
    this.startAt = const Value.absent(),
    this.endAt = const Value.absent(),
    this.isAllDay = const Value.absent(),
    this.estimatedMinutes = const Value.absent(),
    this.resultNote = const Value.absent(),
    this.notes = const Value.absent(),
    this.notesText = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.sequenceNumber = const Value.absent(),
    this.countableActivityId = const Value.absent(),
    this.planItemId = const Value.absent(),
    this.planKey = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ActionsTableCompanion.insert({
    required String id,
    required String name,
    this.done = const Value.absent(),
    this.postponeFlex = const Value.absent(),
    this.depthLevel = const Value.absent(),
    this.startAt = const Value.absent(),
    this.endAt = const Value.absent(),
    this.isAllDay = const Value.absent(),
    this.estimatedMinutes = const Value.absent(),
    this.resultNote = const Value.absent(),
    this.notes = const Value.absent(),
    this.notesText = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.sequenceNumber = const Value.absent(),
    this.countableActivityId = const Value.absent(),
    this.planItemId = const Value.absent(),
    this.planKey = const Value.absent(),
    required String createdAt,
    required String updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<ActionRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<bool>? done,
    Expression<String>? postponeFlex,
    Expression<String>? depthLevel,
    Expression<String>? startAt,
    Expression<String>? endAt,
    Expression<bool>? isAllDay,
    Expression<int>? estimatedMinutes,
    Expression<String>? resultNote,
    Expression<String>? notes,
    Expression<String>? notesText,
    Expression<String>? completedAt,
    Expression<int>? sequenceNumber,
    Expression<String>? countableActivityId,
    Expression<String>? planItemId,
    Expression<String>? planKey,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (done != null) 'done': done,
      if (postponeFlex != null) 'postpone_flex': postponeFlex,
      if (depthLevel != null) 'depth_level': depthLevel,
      if (startAt != null) 'start_at': startAt,
      if (endAt != null) 'end_at': endAt,
      if (isAllDay != null) 'is_all_day': isAllDay,
      if (estimatedMinutes != null) 'estimated_minutes': estimatedMinutes,
      if (resultNote != null) 'result_note': resultNote,
      if (notes != null) 'notes': notes,
      if (notesText != null) 'notes_text': notesText,
      if (completedAt != null) 'completed_at': completedAt,
      if (sequenceNumber != null) 'sequence_number': sequenceNumber,
      if (countableActivityId != null)
        'countable_activity_id': countableActivityId,
      if (planItemId != null) 'plan_item_id': planItemId,
      if (planKey != null) 'plan_key': planKey,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ActionsTableCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<bool>? done,
    Value<String>? postponeFlex,
    Value<String?>? depthLevel,
    Value<String?>? startAt,
    Value<String?>? endAt,
    Value<bool>? isAllDay,
    Value<int?>? estimatedMinutes,
    Value<String?>? resultNote,
    Value<String?>? notes,
    Value<String?>? notesText,
    Value<String?>? completedAt,
    Value<int?>? sequenceNumber,
    Value<String?>? countableActivityId,
    Value<String?>? planItemId,
    Value<String?>? planKey,
    Value<String>? createdAt,
    Value<String>? updatedAt,
    Value<int>? rowid,
  }) {
    return ActionsTableCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      done: done ?? this.done,
      postponeFlex: postponeFlex ?? this.postponeFlex,
      depthLevel: depthLevel ?? this.depthLevel,
      startAt: startAt ?? this.startAt,
      endAt: endAt ?? this.endAt,
      isAllDay: isAllDay ?? this.isAllDay,
      estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
      resultNote: resultNote ?? this.resultNote,
      notes: notes ?? this.notes,
      notesText: notesText ?? this.notesText,
      completedAt: completedAt ?? this.completedAt,
      sequenceNumber: sequenceNumber ?? this.sequenceNumber,
      countableActivityId: countableActivityId ?? this.countableActivityId,
      planItemId: planItemId ?? this.planItemId,
      planKey: planKey ?? this.planKey,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (done.present) {
      map['done'] = Variable<bool>(done.value);
    }
    if (postponeFlex.present) {
      map['postpone_flex'] = Variable<String>(postponeFlex.value);
    }
    if (depthLevel.present) {
      map['depth_level'] = Variable<String>(depthLevel.value);
    }
    if (startAt.present) {
      map['start_at'] = Variable<String>(startAt.value);
    }
    if (endAt.present) {
      map['end_at'] = Variable<String>(endAt.value);
    }
    if (isAllDay.present) {
      map['is_all_day'] = Variable<bool>(isAllDay.value);
    }
    if (estimatedMinutes.present) {
      map['estimated_minutes'] = Variable<int>(estimatedMinutes.value);
    }
    if (resultNote.present) {
      map['result_note'] = Variable<String>(resultNote.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (notesText.present) {
      map['notes_text'] = Variable<String>(notesText.value);
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<String>(completedAt.value);
    }
    if (sequenceNumber.present) {
      map['sequence_number'] = Variable<int>(sequenceNumber.value);
    }
    if (countableActivityId.present) {
      map['countable_activity_id'] = Variable<String>(
        countableActivityId.value,
      );
    }
    if (planItemId.present) {
      map['plan_item_id'] = Variable<String>(planItemId.value);
    }
    if (planKey.present) {
      map['plan_key'] = Variable<String>(planKey.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ActionsTableCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('done: $done, ')
          ..write('postponeFlex: $postponeFlex, ')
          ..write('depthLevel: $depthLevel, ')
          ..write('startAt: $startAt, ')
          ..write('endAt: $endAt, ')
          ..write('isAllDay: $isAllDay, ')
          ..write('estimatedMinutes: $estimatedMinutes, ')
          ..write('resultNote: $resultNote, ')
          ..write('notes: $notes, ')
          ..write('notesText: $notesText, ')
          ..write('completedAt: $completedAt, ')
          ..write('sequenceNumber: $sequenceNumber, ')
          ..write('countableActivityId: $countableActivityId, ')
          ..write('planItemId: $planItemId, ')
          ..write('planKey: $planKey, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ActionDependenciesTableTable extends ActionDependenciesTable
    with TableInfo<$ActionDependenciesTableTable, ActionDependency> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ActionDependenciesTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _predecessorIdMeta = const VerificationMeta(
    'predecessorId',
  );
  @override
  late final GeneratedColumn<String> predecessorId = GeneratedColumn<String>(
    'predecessor_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES actions (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _successorIdMeta = const VerificationMeta(
    'successorId',
  );
  @override
  late final GeneratedColumn<String> successorId = GeneratedColumn<String>(
    'successor_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES actions (id) ON DELETE CASCADE',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [id, predecessorId, successorId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'action_dependencies';
  @override
  VerificationContext validateIntegrity(
    Insertable<ActionDependency> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('predecessor_id')) {
      context.handle(
        _predecessorIdMeta,
        predecessorId.isAcceptableOrUnknown(
          data['predecessor_id']!,
          _predecessorIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_predecessorIdMeta);
    }
    if (data.containsKey('successor_id')) {
      context.handle(
        _successorIdMeta,
        successorId.isAcceptableOrUnknown(
          data['successor_id']!,
          _successorIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_successorIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ActionDependency map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ActionDependency(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      predecessorId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}predecessor_id'],
      )!,
      successorId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}successor_id'],
      )!,
    );
  }

  @override
  $ActionDependenciesTableTable createAlias(String alias) {
    return $ActionDependenciesTableTable(attachedDatabase, alias);
  }
}

class ActionDependency extends DataClass
    implements Insertable<ActionDependency> {
  final String id;
  final String predecessorId;
  final String successorId;
  const ActionDependency({
    required this.id,
    required this.predecessorId,
    required this.successorId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['predecessor_id'] = Variable<String>(predecessorId);
    map['successor_id'] = Variable<String>(successorId);
    return map;
  }

  ActionDependenciesTableCompanion toCompanion(bool nullToAbsent) {
    return ActionDependenciesTableCompanion(
      id: Value(id),
      predecessorId: Value(predecessorId),
      successorId: Value(successorId),
    );
  }

  factory ActionDependency.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ActionDependency(
      id: serializer.fromJson<String>(json['id']),
      predecessorId: serializer.fromJson<String>(json['predecessorId']),
      successorId: serializer.fromJson<String>(json['successorId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'predecessorId': serializer.toJson<String>(predecessorId),
      'successorId': serializer.toJson<String>(successorId),
    };
  }

  ActionDependency copyWith({
    String? id,
    String? predecessorId,
    String? successorId,
  }) => ActionDependency(
    id: id ?? this.id,
    predecessorId: predecessorId ?? this.predecessorId,
    successorId: successorId ?? this.successorId,
  );
  ActionDependency copyWithCompanion(ActionDependenciesTableCompanion data) {
    return ActionDependency(
      id: data.id.present ? data.id.value : this.id,
      predecessorId: data.predecessorId.present
          ? data.predecessorId.value
          : this.predecessorId,
      successorId: data.successorId.present
          ? data.successorId.value
          : this.successorId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ActionDependency(')
          ..write('id: $id, ')
          ..write('predecessorId: $predecessorId, ')
          ..write('successorId: $successorId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, predecessorId, successorId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ActionDependency &&
          other.id == this.id &&
          other.predecessorId == this.predecessorId &&
          other.successorId == this.successorId);
}

class ActionDependenciesTableCompanion
    extends UpdateCompanion<ActionDependency> {
  final Value<String> id;
  final Value<String> predecessorId;
  final Value<String> successorId;
  final Value<int> rowid;
  const ActionDependenciesTableCompanion({
    this.id = const Value.absent(),
    this.predecessorId = const Value.absent(),
    this.successorId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ActionDependenciesTableCompanion.insert({
    required String id,
    required String predecessorId,
    required String successorId,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       predecessorId = Value(predecessorId),
       successorId = Value(successorId);
  static Insertable<ActionDependency> custom({
    Expression<String>? id,
    Expression<String>? predecessorId,
    Expression<String>? successorId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (predecessorId != null) 'predecessor_id': predecessorId,
      if (successorId != null) 'successor_id': successorId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ActionDependenciesTableCompanion copyWith({
    Value<String>? id,
    Value<String>? predecessorId,
    Value<String>? successorId,
    Value<int>? rowid,
  }) {
    return ActionDependenciesTableCompanion(
      id: id ?? this.id,
      predecessorId: predecessorId ?? this.predecessorId,
      successorId: successorId ?? this.successorId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (predecessorId.present) {
      map['predecessor_id'] = Variable<String>(predecessorId.value);
    }
    if (successorId.present) {
      map['successor_id'] = Variable<String>(successorId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ActionDependenciesTableCompanion(')
          ..write('id: $id, ')
          ..write('predecessorId: $predecessorId, ')
          ..write('successorId: $successorId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ActionOccurrencesTableTable extends ActionOccurrencesTable
    with TableInfo<$ActionOccurrencesTableTable, ActionOccurrence> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ActionOccurrencesTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _actionIdMeta = const VerificationMeta(
    'actionId',
  );
  @override
  late final GeneratedColumn<String> actionId = GeneratedColumn<String>(
    'action_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES actions (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<String> startedAt = GeneratedColumn<String>(
    'started_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _finishedAtMeta = const VerificationMeta(
    'finishedAt',
  );
  @override
  late final GeneratedColumn<String> finishedAt = GeneratedColumn<String>(
    'finished_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _outcomeMeta = const VerificationMeta(
    'outcome',
  );
  @override
  late final GeneratedColumn<String> outcome = GeneratedColumn<String>(
    'outcome',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    actionId,
    startedAt,
    finishedAt,
    outcome,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'action_occurrences';
  @override
  VerificationContext validateIntegrity(
    Insertable<ActionOccurrence> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('action_id')) {
      context.handle(
        _actionIdMeta,
        actionId.isAcceptableOrUnknown(data['action_id']!, _actionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_actionIdMeta);
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    }
    if (data.containsKey('finished_at')) {
      context.handle(
        _finishedAtMeta,
        finishedAt.isAcceptableOrUnknown(data['finished_at']!, _finishedAtMeta),
      );
    }
    if (data.containsKey('outcome')) {
      context.handle(
        _outcomeMeta,
        outcome.isAcceptableOrUnknown(data['outcome']!, _outcomeMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ActionOccurrence map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ActionOccurrence(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      actionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}action_id'],
      )!,
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}started_at'],
      ),
      finishedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}finished_at'],
      ),
      outcome: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}outcome'],
      ),
    );
  }

  @override
  $ActionOccurrencesTableTable createAlias(String alias) {
    return $ActionOccurrencesTableTable(attachedDatabase, alias);
  }
}

class ActionOccurrence extends DataClass
    implements Insertable<ActionOccurrence> {
  final String id;
  final String actionId;
  final String? startedAt;
  final String? finishedAt;
  final String? outcome;
  const ActionOccurrence({
    required this.id,
    required this.actionId,
    this.startedAt,
    this.finishedAt,
    this.outcome,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['action_id'] = Variable<String>(actionId);
    if (!nullToAbsent || startedAt != null) {
      map['started_at'] = Variable<String>(startedAt);
    }
    if (!nullToAbsent || finishedAt != null) {
      map['finished_at'] = Variable<String>(finishedAt);
    }
    if (!nullToAbsent || outcome != null) {
      map['outcome'] = Variable<String>(outcome);
    }
    return map;
  }

  ActionOccurrencesTableCompanion toCompanion(bool nullToAbsent) {
    return ActionOccurrencesTableCompanion(
      id: Value(id),
      actionId: Value(actionId),
      startedAt: startedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(startedAt),
      finishedAt: finishedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(finishedAt),
      outcome: outcome == null && nullToAbsent
          ? const Value.absent()
          : Value(outcome),
    );
  }

  factory ActionOccurrence.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ActionOccurrence(
      id: serializer.fromJson<String>(json['id']),
      actionId: serializer.fromJson<String>(json['actionId']),
      startedAt: serializer.fromJson<String?>(json['startedAt']),
      finishedAt: serializer.fromJson<String?>(json['finishedAt']),
      outcome: serializer.fromJson<String?>(json['outcome']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'actionId': serializer.toJson<String>(actionId),
      'startedAt': serializer.toJson<String?>(startedAt),
      'finishedAt': serializer.toJson<String?>(finishedAt),
      'outcome': serializer.toJson<String?>(outcome),
    };
  }

  ActionOccurrence copyWith({
    String? id,
    String? actionId,
    Value<String?> startedAt = const Value.absent(),
    Value<String?> finishedAt = const Value.absent(),
    Value<String?> outcome = const Value.absent(),
  }) => ActionOccurrence(
    id: id ?? this.id,
    actionId: actionId ?? this.actionId,
    startedAt: startedAt.present ? startedAt.value : this.startedAt,
    finishedAt: finishedAt.present ? finishedAt.value : this.finishedAt,
    outcome: outcome.present ? outcome.value : this.outcome,
  );
  ActionOccurrence copyWithCompanion(ActionOccurrencesTableCompanion data) {
    return ActionOccurrence(
      id: data.id.present ? data.id.value : this.id,
      actionId: data.actionId.present ? data.actionId.value : this.actionId,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      finishedAt: data.finishedAt.present
          ? data.finishedAt.value
          : this.finishedAt,
      outcome: data.outcome.present ? data.outcome.value : this.outcome,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ActionOccurrence(')
          ..write('id: $id, ')
          ..write('actionId: $actionId, ')
          ..write('startedAt: $startedAt, ')
          ..write('finishedAt: $finishedAt, ')
          ..write('outcome: $outcome')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, actionId, startedAt, finishedAt, outcome);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ActionOccurrence &&
          other.id == this.id &&
          other.actionId == this.actionId &&
          other.startedAt == this.startedAt &&
          other.finishedAt == this.finishedAt &&
          other.outcome == this.outcome);
}

class ActionOccurrencesTableCompanion
    extends UpdateCompanion<ActionOccurrence> {
  final Value<String> id;
  final Value<String> actionId;
  final Value<String?> startedAt;
  final Value<String?> finishedAt;
  final Value<String?> outcome;
  final Value<int> rowid;
  const ActionOccurrencesTableCompanion({
    this.id = const Value.absent(),
    this.actionId = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.finishedAt = const Value.absent(),
    this.outcome = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ActionOccurrencesTableCompanion.insert({
    required String id,
    required String actionId,
    this.startedAt = const Value.absent(),
    this.finishedAt = const Value.absent(),
    this.outcome = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       actionId = Value(actionId);
  static Insertable<ActionOccurrence> custom({
    Expression<String>? id,
    Expression<String>? actionId,
    Expression<String>? startedAt,
    Expression<String>? finishedAt,
    Expression<String>? outcome,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (actionId != null) 'action_id': actionId,
      if (startedAt != null) 'started_at': startedAt,
      if (finishedAt != null) 'finished_at': finishedAt,
      if (outcome != null) 'outcome': outcome,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ActionOccurrencesTableCompanion copyWith({
    Value<String>? id,
    Value<String>? actionId,
    Value<String?>? startedAt,
    Value<String?>? finishedAt,
    Value<String?>? outcome,
    Value<int>? rowid,
  }) {
    return ActionOccurrencesTableCompanion(
      id: id ?? this.id,
      actionId: actionId ?? this.actionId,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      outcome: outcome ?? this.outcome,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (actionId.present) {
      map['action_id'] = Variable<String>(actionId.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<String>(startedAt.value);
    }
    if (finishedAt.present) {
      map['finished_at'] = Variable<String>(finishedAt.value);
    }
    if (outcome.present) {
      map['outcome'] = Variable<String>(outcome.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ActionOccurrencesTableCompanion(')
          ..write('id: $id, ')
          ..write('actionId: $actionId, ')
          ..write('startedAt: $startedAt, ')
          ..write('finishedAt: $finishedAt, ')
          ..write('outcome: $outcome, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MetricsTableTable extends MetricsTable
    with TableInfo<$MetricsTableTable, Metric> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MetricsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _weightMeta = const VerificationMeta('weight');
  @override
  late final GeneratedColumn<double> weight = GeneratedColumn<double>(
    'weight',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('boolean'),
  );
  static const VerificationMeta _timeWindowMeta = const VerificationMeta(
    'timeWindow',
  );
  @override
  late final GeneratedColumn<String> timeWindow = GeneratedColumn<String>(
    'time_window',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _targetMeta = const VerificationMeta('target');
  @override
  late final GeneratedColumn<double> target = GeneratedColumn<double>(
    'target',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _isMainMeta = const VerificationMeta('isMain');
  @override
  late final GeneratedColumn<bool> isMain = GeneratedColumn<bool>(
    'is_main',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_main" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _importanceLevelMeta = const VerificationMeta(
    'importanceLevel',
  );
  @override
  late final GeneratedColumn<int> importanceLevel = GeneratedColumn<int>(
    'importance_level',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _iconMeta = const VerificationMeta('icon');
  @override
  late final GeneratedColumn<String> icon = GeneratedColumn<String>(
    'icon',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _posXMeta = const VerificationMeta('posX');
  @override
  late final GeneratedColumn<double> posX = GeneratedColumn<double>(
    'pos_x',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _posYMeta = const VerificationMeta('posY');
  @override
  late final GeneratedColumn<double> posY = GeneratedColumn<double>(
    'pos_y',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    weight,
    kind,
    timeWindow,
    target,
    isMain,
    importanceLevel,
    icon,
    posX,
    posY,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'metrics';
  @override
  VerificationContext validateIntegrity(
    Insertable<Metric> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('weight')) {
      context.handle(
        _weightMeta,
        weight.isAcceptableOrUnknown(data['weight']!, _weightMeta),
      );
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    }
    if (data.containsKey('time_window')) {
      context.handle(
        _timeWindowMeta,
        timeWindow.isAcceptableOrUnknown(data['time_window']!, _timeWindowMeta),
      );
    }
    if (data.containsKey('target')) {
      context.handle(
        _targetMeta,
        target.isAcceptableOrUnknown(data['target']!, _targetMeta),
      );
    }
    if (data.containsKey('is_main')) {
      context.handle(
        _isMainMeta,
        isMain.isAcceptableOrUnknown(data['is_main']!, _isMainMeta),
      );
    }
    if (data.containsKey('importance_level')) {
      context.handle(
        _importanceLevelMeta,
        importanceLevel.isAcceptableOrUnknown(
          data['importance_level']!,
          _importanceLevelMeta,
        ),
      );
    }
    if (data.containsKey('icon')) {
      context.handle(
        _iconMeta,
        icon.isAcceptableOrUnknown(data['icon']!, _iconMeta),
      );
    }
    if (data.containsKey('pos_x')) {
      context.handle(
        _posXMeta,
        posX.isAcceptableOrUnknown(data['pos_x']!, _posXMeta),
      );
    }
    if (data.containsKey('pos_y')) {
      context.handle(
        _posYMeta,
        posY.isAcceptableOrUnknown(data['pos_y']!, _posYMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Metric map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Metric(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      weight: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}weight'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      timeWindow: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}time_window'],
      ),
      target: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}target'],
      )!,
      isMain: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_main'],
      )!,
      importanceLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}importance_level'],
      )!,
      icon: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}icon'],
      ),
      posX: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}pos_x'],
      ),
      posY: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}pos_y'],
      ),
    );
  }

  @override
  $MetricsTableTable createAlias(String alias) {
    return $MetricsTableTable(attachedDatabase, alias);
  }
}

class Metric extends DataClass implements Insertable<Metric> {
  final String id;
  final String name;
  final double weight;
  final String kind;
  final String? timeWindow;
  final double target;
  final bool isMain;
  final int importanceLevel;
  final String? icon;

  /// Where the node sits on the Mindmap canvas (null = not placed yet).
  final double? posX;
  final double? posY;
  const Metric({
    required this.id,
    required this.name,
    required this.weight,
    required this.kind,
    this.timeWindow,
    required this.target,
    required this.isMain,
    required this.importanceLevel,
    this.icon,
    this.posX,
    this.posY,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['weight'] = Variable<double>(weight);
    map['kind'] = Variable<String>(kind);
    if (!nullToAbsent || timeWindow != null) {
      map['time_window'] = Variable<String>(timeWindow);
    }
    map['target'] = Variable<double>(target);
    map['is_main'] = Variable<bool>(isMain);
    map['importance_level'] = Variable<int>(importanceLevel);
    if (!nullToAbsent || icon != null) {
      map['icon'] = Variable<String>(icon);
    }
    if (!nullToAbsent || posX != null) {
      map['pos_x'] = Variable<double>(posX);
    }
    if (!nullToAbsent || posY != null) {
      map['pos_y'] = Variable<double>(posY);
    }
    return map;
  }

  MetricsTableCompanion toCompanion(bool nullToAbsent) {
    return MetricsTableCompanion(
      id: Value(id),
      name: Value(name),
      weight: Value(weight),
      kind: Value(kind),
      timeWindow: timeWindow == null && nullToAbsent
          ? const Value.absent()
          : Value(timeWindow),
      target: Value(target),
      isMain: Value(isMain),
      importanceLevel: Value(importanceLevel),
      icon: icon == null && nullToAbsent ? const Value.absent() : Value(icon),
      posX: posX == null && nullToAbsent ? const Value.absent() : Value(posX),
      posY: posY == null && nullToAbsent ? const Value.absent() : Value(posY),
    );
  }

  factory Metric.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Metric(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      weight: serializer.fromJson<double>(json['weight']),
      kind: serializer.fromJson<String>(json['kind']),
      timeWindow: serializer.fromJson<String?>(json['timeWindow']),
      target: serializer.fromJson<double>(json['target']),
      isMain: serializer.fromJson<bool>(json['isMain']),
      importanceLevel: serializer.fromJson<int>(json['importanceLevel']),
      icon: serializer.fromJson<String?>(json['icon']),
      posX: serializer.fromJson<double?>(json['posX']),
      posY: serializer.fromJson<double?>(json['posY']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'weight': serializer.toJson<double>(weight),
      'kind': serializer.toJson<String>(kind),
      'timeWindow': serializer.toJson<String?>(timeWindow),
      'target': serializer.toJson<double>(target),
      'isMain': serializer.toJson<bool>(isMain),
      'importanceLevel': serializer.toJson<int>(importanceLevel),
      'icon': serializer.toJson<String?>(icon),
      'posX': serializer.toJson<double?>(posX),
      'posY': serializer.toJson<double?>(posY),
    };
  }

  Metric copyWith({
    String? id,
    String? name,
    double? weight,
    String? kind,
    Value<String?> timeWindow = const Value.absent(),
    double? target,
    bool? isMain,
    int? importanceLevel,
    Value<String?> icon = const Value.absent(),
    Value<double?> posX = const Value.absent(),
    Value<double?> posY = const Value.absent(),
  }) => Metric(
    id: id ?? this.id,
    name: name ?? this.name,
    weight: weight ?? this.weight,
    kind: kind ?? this.kind,
    timeWindow: timeWindow.present ? timeWindow.value : this.timeWindow,
    target: target ?? this.target,
    isMain: isMain ?? this.isMain,
    importanceLevel: importanceLevel ?? this.importanceLevel,
    icon: icon.present ? icon.value : this.icon,
    posX: posX.present ? posX.value : this.posX,
    posY: posY.present ? posY.value : this.posY,
  );
  Metric copyWithCompanion(MetricsTableCompanion data) {
    return Metric(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      weight: data.weight.present ? data.weight.value : this.weight,
      kind: data.kind.present ? data.kind.value : this.kind,
      timeWindow: data.timeWindow.present
          ? data.timeWindow.value
          : this.timeWindow,
      target: data.target.present ? data.target.value : this.target,
      isMain: data.isMain.present ? data.isMain.value : this.isMain,
      importanceLevel: data.importanceLevel.present
          ? data.importanceLevel.value
          : this.importanceLevel,
      icon: data.icon.present ? data.icon.value : this.icon,
      posX: data.posX.present ? data.posX.value : this.posX,
      posY: data.posY.present ? data.posY.value : this.posY,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Metric(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('weight: $weight, ')
          ..write('kind: $kind, ')
          ..write('timeWindow: $timeWindow, ')
          ..write('target: $target, ')
          ..write('isMain: $isMain, ')
          ..write('importanceLevel: $importanceLevel, ')
          ..write('icon: $icon, ')
          ..write('posX: $posX, ')
          ..write('posY: $posY')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    weight,
    kind,
    timeWindow,
    target,
    isMain,
    importanceLevel,
    icon,
    posX,
    posY,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Metric &&
          other.id == this.id &&
          other.name == this.name &&
          other.weight == this.weight &&
          other.kind == this.kind &&
          other.timeWindow == this.timeWindow &&
          other.target == this.target &&
          other.isMain == this.isMain &&
          other.importanceLevel == this.importanceLevel &&
          other.icon == this.icon &&
          other.posX == this.posX &&
          other.posY == this.posY);
}

class MetricsTableCompanion extends UpdateCompanion<Metric> {
  final Value<String> id;
  final Value<String> name;
  final Value<double> weight;
  final Value<String> kind;
  final Value<String?> timeWindow;
  final Value<double> target;
  final Value<bool> isMain;
  final Value<int> importanceLevel;
  final Value<String?> icon;
  final Value<double?> posX;
  final Value<double?> posY;
  final Value<int> rowid;
  const MetricsTableCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.weight = const Value.absent(),
    this.kind = const Value.absent(),
    this.timeWindow = const Value.absent(),
    this.target = const Value.absent(),
    this.isMain = const Value.absent(),
    this.importanceLevel = const Value.absent(),
    this.icon = const Value.absent(),
    this.posX = const Value.absent(),
    this.posY = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MetricsTableCompanion.insert({
    required String id,
    required String name,
    this.weight = const Value.absent(),
    this.kind = const Value.absent(),
    this.timeWindow = const Value.absent(),
    this.target = const Value.absent(),
    this.isMain = const Value.absent(),
    this.importanceLevel = const Value.absent(),
    this.icon = const Value.absent(),
    this.posX = const Value.absent(),
    this.posY = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name);
  static Insertable<Metric> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<double>? weight,
    Expression<String>? kind,
    Expression<String>? timeWindow,
    Expression<double>? target,
    Expression<bool>? isMain,
    Expression<int>? importanceLevel,
    Expression<String>? icon,
    Expression<double>? posX,
    Expression<double>? posY,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (weight != null) 'weight': weight,
      if (kind != null) 'kind': kind,
      if (timeWindow != null) 'time_window': timeWindow,
      if (target != null) 'target': target,
      if (isMain != null) 'is_main': isMain,
      if (importanceLevel != null) 'importance_level': importanceLevel,
      if (icon != null) 'icon': icon,
      if (posX != null) 'pos_x': posX,
      if (posY != null) 'pos_y': posY,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MetricsTableCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<double>? weight,
    Value<String>? kind,
    Value<String?>? timeWindow,
    Value<double>? target,
    Value<bool>? isMain,
    Value<int>? importanceLevel,
    Value<String?>? icon,
    Value<double?>? posX,
    Value<double?>? posY,
    Value<int>? rowid,
  }) {
    return MetricsTableCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      weight: weight ?? this.weight,
      kind: kind ?? this.kind,
      timeWindow: timeWindow ?? this.timeWindow,
      target: target ?? this.target,
      isMain: isMain ?? this.isMain,
      importanceLevel: importanceLevel ?? this.importanceLevel,
      icon: icon ?? this.icon,
      posX: posX ?? this.posX,
      posY: posY ?? this.posY,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (weight.present) {
      map['weight'] = Variable<double>(weight.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (timeWindow.present) {
      map['time_window'] = Variable<String>(timeWindow.value);
    }
    if (target.present) {
      map['target'] = Variable<double>(target.value);
    }
    if (isMain.present) {
      map['is_main'] = Variable<bool>(isMain.value);
    }
    if (importanceLevel.present) {
      map['importance_level'] = Variable<int>(importanceLevel.value);
    }
    if (icon.present) {
      map['icon'] = Variable<String>(icon.value);
    }
    if (posX.present) {
      map['pos_x'] = Variable<double>(posX.value);
    }
    if (posY.present) {
      map['pos_y'] = Variable<double>(posY.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MetricsTableCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('weight: $weight, ')
          ..write('kind: $kind, ')
          ..write('timeWindow: $timeWindow, ')
          ..write('target: $target, ')
          ..write('isMain: $isMain, ')
          ..write('importanceLevel: $importanceLevel, ')
          ..write('icon: $icon, ')
          ..write('posX: $posX, ')
          ..write('posY: $posY, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ActionMetricsTableTable extends ActionMetricsTable
    with TableInfo<$ActionMetricsTableTable, ActionMetric> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ActionMetricsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _actionIdMeta = const VerificationMeta(
    'actionId',
  );
  @override
  late final GeneratedColumn<String> actionId = GeneratedColumn<String>(
    'action_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES actions (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _metricIdMeta = const VerificationMeta(
    'metricId',
  );
  @override
  late final GeneratedColumn<String> metricId = GeneratedColumn<String>(
    'metric_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES metrics (id) ON DELETE CASCADE',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [id, actionId, metricId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'action_metrics';
  @override
  VerificationContext validateIntegrity(
    Insertable<ActionMetric> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('action_id')) {
      context.handle(
        _actionIdMeta,
        actionId.isAcceptableOrUnknown(data['action_id']!, _actionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_actionIdMeta);
    }
    if (data.containsKey('metric_id')) {
      context.handle(
        _metricIdMeta,
        metricId.isAcceptableOrUnknown(data['metric_id']!, _metricIdMeta),
      );
    } else if (isInserting) {
      context.missing(_metricIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ActionMetric map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ActionMetric(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      actionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}action_id'],
      )!,
      metricId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}metric_id'],
      )!,
    );
  }

  @override
  $ActionMetricsTableTable createAlias(String alias) {
    return $ActionMetricsTableTable(attachedDatabase, alias);
  }
}

class ActionMetric extends DataClass implements Insertable<ActionMetric> {
  final String id;
  final String actionId;
  final String metricId;
  const ActionMetric({
    required this.id,
    required this.actionId,
    required this.metricId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['action_id'] = Variable<String>(actionId);
    map['metric_id'] = Variable<String>(metricId);
    return map;
  }

  ActionMetricsTableCompanion toCompanion(bool nullToAbsent) {
    return ActionMetricsTableCompanion(
      id: Value(id),
      actionId: Value(actionId),
      metricId: Value(metricId),
    );
  }

  factory ActionMetric.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ActionMetric(
      id: serializer.fromJson<String>(json['id']),
      actionId: serializer.fromJson<String>(json['actionId']),
      metricId: serializer.fromJson<String>(json['metricId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'actionId': serializer.toJson<String>(actionId),
      'metricId': serializer.toJson<String>(metricId),
    };
  }

  ActionMetric copyWith({String? id, String? actionId, String? metricId}) =>
      ActionMetric(
        id: id ?? this.id,
        actionId: actionId ?? this.actionId,
        metricId: metricId ?? this.metricId,
      );
  ActionMetric copyWithCompanion(ActionMetricsTableCompanion data) {
    return ActionMetric(
      id: data.id.present ? data.id.value : this.id,
      actionId: data.actionId.present ? data.actionId.value : this.actionId,
      metricId: data.metricId.present ? data.metricId.value : this.metricId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ActionMetric(')
          ..write('id: $id, ')
          ..write('actionId: $actionId, ')
          ..write('metricId: $metricId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, actionId, metricId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ActionMetric &&
          other.id == this.id &&
          other.actionId == this.actionId &&
          other.metricId == this.metricId);
}

class ActionMetricsTableCompanion extends UpdateCompanion<ActionMetric> {
  final Value<String> id;
  final Value<String> actionId;
  final Value<String> metricId;
  final Value<int> rowid;
  const ActionMetricsTableCompanion({
    this.id = const Value.absent(),
    this.actionId = const Value.absent(),
    this.metricId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ActionMetricsTableCompanion.insert({
    required String id,
    required String actionId,
    required String metricId,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       actionId = Value(actionId),
       metricId = Value(metricId);
  static Insertable<ActionMetric> custom({
    Expression<String>? id,
    Expression<String>? actionId,
    Expression<String>? metricId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (actionId != null) 'action_id': actionId,
      if (metricId != null) 'metric_id': metricId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ActionMetricsTableCompanion copyWith({
    Value<String>? id,
    Value<String>? actionId,
    Value<String>? metricId,
    Value<int>? rowid,
  }) {
    return ActionMetricsTableCompanion(
      id: id ?? this.id,
      actionId: actionId ?? this.actionId,
      metricId: metricId ?? this.metricId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (actionId.present) {
      map['action_id'] = Variable<String>(actionId.value);
    }
    if (metricId.present) {
      map['metric_id'] = Variable<String>(metricId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ActionMetricsTableCompanion(')
          ..write('id: $id, ')
          ..write('actionId: $actionId, ')
          ..write('metricId: $metricId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ActionTemplatesTableTable extends ActionTemplatesTable
    with TableInfo<$ActionTemplatesTableTable, ActionTemplate> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ActionTemplatesTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, payload];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'action_templates';
  @override
  VerificationContext validateIntegrity(
    Insertable<ActionTemplate> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ActionTemplate map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ActionTemplate(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
    );
  }

  @override
  $ActionTemplatesTableTable createAlias(String alias) {
    return $ActionTemplatesTableTable(attachedDatabase, alias);
  }
}

class ActionTemplate extends DataClass implements Insertable<ActionTemplate> {
  final String id;
  final String name;
  final String payload;
  const ActionTemplate({
    required this.id,
    required this.name,
    required this.payload,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['payload'] = Variable<String>(payload);
    return map;
  }

  ActionTemplatesTableCompanion toCompanion(bool nullToAbsent) {
    return ActionTemplatesTableCompanion(
      id: Value(id),
      name: Value(name),
      payload: Value(payload),
    );
  }

  factory ActionTemplate.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ActionTemplate(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      payload: serializer.fromJson<String>(json['payload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'payload': serializer.toJson<String>(payload),
    };
  }

  ActionTemplate copyWith({String? id, String? name, String? payload}) =>
      ActionTemplate(
        id: id ?? this.id,
        name: name ?? this.name,
        payload: payload ?? this.payload,
      );
  ActionTemplate copyWithCompanion(ActionTemplatesTableCompanion data) {
    return ActionTemplate(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      payload: data.payload.present ? data.payload.value : this.payload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ActionTemplate(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, payload);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ActionTemplate &&
          other.id == this.id &&
          other.name == this.name &&
          other.payload == this.payload);
}

class ActionTemplatesTableCompanion extends UpdateCompanion<ActionTemplate> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> payload;
  final Value<int> rowid;
  const ActionTemplatesTableCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.payload = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ActionTemplatesTableCompanion.insert({
    required String id,
    required String name,
    required String payload,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       payload = Value(payload);
  static Insertable<ActionTemplate> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? payload,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (payload != null) 'payload': payload,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ActionTemplatesTableCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? payload,
    Value<int>? rowid,
  }) {
    return ActionTemplatesTableCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      payload: payload ?? this.payload,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ActionTemplatesTableCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('payload: $payload, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MetricDependenciesTableTable extends MetricDependenciesTable
    with TableInfo<$MetricDependenciesTableTable, MetricDependency> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MetricDependenciesTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _metricIdMeta = const VerificationMeta(
    'metricId',
  );
  @override
  late final GeneratedColumn<String> metricId = GeneratedColumn<String>(
    'metric_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES metrics (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _dependsOnIdMeta = const VerificationMeta(
    'dependsOnId',
  );
  @override
  late final GeneratedColumn<String> dependsOnId = GeneratedColumn<String>(
    'depends_on_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES metrics (id) ON DELETE CASCADE',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [id, metricId, dependsOnId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'metric_dependencies';
  @override
  VerificationContext validateIntegrity(
    Insertable<MetricDependency> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('metric_id')) {
      context.handle(
        _metricIdMeta,
        metricId.isAcceptableOrUnknown(data['metric_id']!, _metricIdMeta),
      );
    } else if (isInserting) {
      context.missing(_metricIdMeta);
    }
    if (data.containsKey('depends_on_id')) {
      context.handle(
        _dependsOnIdMeta,
        dependsOnId.isAcceptableOrUnknown(
          data['depends_on_id']!,
          _dependsOnIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_dependsOnIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MetricDependency map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MetricDependency(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      metricId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}metric_id'],
      )!,
      dependsOnId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}depends_on_id'],
      )!,
    );
  }

  @override
  $MetricDependenciesTableTable createAlias(String alias) {
    return $MetricDependenciesTableTable(attachedDatabase, alias);
  }
}

class MetricDependency extends DataClass
    implements Insertable<MetricDependency> {
  final String id;
  final String metricId;
  final String dependsOnId;
  const MetricDependency({
    required this.id,
    required this.metricId,
    required this.dependsOnId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['metric_id'] = Variable<String>(metricId);
    map['depends_on_id'] = Variable<String>(dependsOnId);
    return map;
  }

  MetricDependenciesTableCompanion toCompanion(bool nullToAbsent) {
    return MetricDependenciesTableCompanion(
      id: Value(id),
      metricId: Value(metricId),
      dependsOnId: Value(dependsOnId),
    );
  }

  factory MetricDependency.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MetricDependency(
      id: serializer.fromJson<String>(json['id']),
      metricId: serializer.fromJson<String>(json['metricId']),
      dependsOnId: serializer.fromJson<String>(json['dependsOnId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'metricId': serializer.toJson<String>(metricId),
      'dependsOnId': serializer.toJson<String>(dependsOnId),
    };
  }

  MetricDependency copyWith({
    String? id,
    String? metricId,
    String? dependsOnId,
  }) => MetricDependency(
    id: id ?? this.id,
    metricId: metricId ?? this.metricId,
    dependsOnId: dependsOnId ?? this.dependsOnId,
  );
  MetricDependency copyWithCompanion(MetricDependenciesTableCompanion data) {
    return MetricDependency(
      id: data.id.present ? data.id.value : this.id,
      metricId: data.metricId.present ? data.metricId.value : this.metricId,
      dependsOnId: data.dependsOnId.present
          ? data.dependsOnId.value
          : this.dependsOnId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MetricDependency(')
          ..write('id: $id, ')
          ..write('metricId: $metricId, ')
          ..write('dependsOnId: $dependsOnId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, metricId, dependsOnId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MetricDependency &&
          other.id == this.id &&
          other.metricId == this.metricId &&
          other.dependsOnId == this.dependsOnId);
}

class MetricDependenciesTableCompanion
    extends UpdateCompanion<MetricDependency> {
  final Value<String> id;
  final Value<String> metricId;
  final Value<String> dependsOnId;
  final Value<int> rowid;
  const MetricDependenciesTableCompanion({
    this.id = const Value.absent(),
    this.metricId = const Value.absent(),
    this.dependsOnId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MetricDependenciesTableCompanion.insert({
    required String id,
    required String metricId,
    required String dependsOnId,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       metricId = Value(metricId),
       dependsOnId = Value(dependsOnId);
  static Insertable<MetricDependency> custom({
    Expression<String>? id,
    Expression<String>? metricId,
    Expression<String>? dependsOnId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (metricId != null) 'metric_id': metricId,
      if (dependsOnId != null) 'depends_on_id': dependsOnId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MetricDependenciesTableCompanion copyWith({
    Value<String>? id,
    Value<String>? metricId,
    Value<String>? dependsOnId,
    Value<int>? rowid,
  }) {
    return MetricDependenciesTableCompanion(
      id: id ?? this.id,
      metricId: metricId ?? this.metricId,
      dependsOnId: dependsOnId ?? this.dependsOnId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (metricId.present) {
      map['metric_id'] = Variable<String>(metricId.value);
    }
    if (dependsOnId.present) {
      map['depends_on_id'] = Variable<String>(dependsOnId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MetricDependenciesTableCompanion(')
          ..write('id: $id, ')
          ..write('metricId: $metricId, ')
          ..write('dependsOnId: $dependsOnId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BudgetAccountsTableTable extends BudgetAccountsTable
    with TableInfo<$BudgetAccountsTableTable, BudgetAccount> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BudgetAccountsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _currencyMeta = const VerificationMeta(
    'currency',
  );
  @override
  late final GeneratedColumn<String> currency = GeneratedColumn<String>(
    'currency',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rateToBaseMeta = const VerificationMeta(
    'rateToBase',
  );
  @override
  late final GeneratedColumn<double> rateToBase = GeneratedColumn<double>(
    'rate_to_base',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _openingBalanceMeta = const VerificationMeta(
    'openingBalance',
  );
  @override
  late final GeneratedColumn<double> openingBalance = GeneratedColumn<double>(
    'opening_balance',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _iconMeta = const VerificationMeta('icon');
  @override
  late final GeneratedColumn<String> icon = GeneratedColumn<String>(
    'icon',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    type,
    currency,
    rateToBase,
    openingBalance,
    icon,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'budget_accounts';
  @override
  VerificationContext validateIntegrity(
    Insertable<BudgetAccount> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    }
    if (data.containsKey('currency')) {
      context.handle(
        _currencyMeta,
        currency.isAcceptableOrUnknown(data['currency']!, _currencyMeta),
      );
    } else if (isInserting) {
      context.missing(_currencyMeta);
    }
    if (data.containsKey('rate_to_base')) {
      context.handle(
        _rateToBaseMeta,
        rateToBase.isAcceptableOrUnknown(
          data['rate_to_base']!,
          _rateToBaseMeta,
        ),
      );
    }
    if (data.containsKey('opening_balance')) {
      context.handle(
        _openingBalanceMeta,
        openingBalance.isAcceptableOrUnknown(
          data['opening_balance']!,
          _openingBalanceMeta,
        ),
      );
    }
    if (data.containsKey('icon')) {
      context.handle(
        _iconMeta,
        icon.isAcceptableOrUnknown(data['icon']!, _iconMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  BudgetAccount map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BudgetAccount(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      ),
      currency: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}currency'],
      )!,
      rateToBase: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}rate_to_base'],
      )!,
      openingBalance: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}opening_balance'],
      )!,
      icon: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}icon'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $BudgetAccountsTableTable createAlias(String alias) {
    return $BudgetAccountsTableTable(attachedDatabase, alias);
  }
}

class BudgetAccount extends DataClass implements Insertable<BudgetAccount> {
  final String id;
  final String name;

  /// Free label: electronic money / cash / crypto. Optional, for readability.
  final String? type;
  final String currency;
  final double rateToBase;
  final double openingBalance;

  /// The account's picture: a square PNG (96 px) as base64 text, or null (the
  /// purse icon is shown instead). Text rather than a BLOB so the sync log and
  /// the JSON backup carry it like any other column.
  final String? icon;
  final String createdAt;
  final String updatedAt;
  const BudgetAccount({
    required this.id,
    required this.name,
    this.type,
    required this.currency,
    required this.rateToBase,
    required this.openingBalance,
    this.icon,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || type != null) {
      map['type'] = Variable<String>(type);
    }
    map['currency'] = Variable<String>(currency);
    map['rate_to_base'] = Variable<double>(rateToBase);
    map['opening_balance'] = Variable<double>(openingBalance);
    if (!nullToAbsent || icon != null) {
      map['icon'] = Variable<String>(icon);
    }
    map['created_at'] = Variable<String>(createdAt);
    map['updated_at'] = Variable<String>(updatedAt);
    return map;
  }

  BudgetAccountsTableCompanion toCompanion(bool nullToAbsent) {
    return BudgetAccountsTableCompanion(
      id: Value(id),
      name: Value(name),
      type: type == null && nullToAbsent ? const Value.absent() : Value(type),
      currency: Value(currency),
      rateToBase: Value(rateToBase),
      openingBalance: Value(openingBalance),
      icon: icon == null && nullToAbsent ? const Value.absent() : Value(icon),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory BudgetAccount.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BudgetAccount(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      type: serializer.fromJson<String?>(json['type']),
      currency: serializer.fromJson<String>(json['currency']),
      rateToBase: serializer.fromJson<double>(json['rateToBase']),
      openingBalance: serializer.fromJson<double>(json['openingBalance']),
      icon: serializer.fromJson<String?>(json['icon']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'type': serializer.toJson<String?>(type),
      'currency': serializer.toJson<String>(currency),
      'rateToBase': serializer.toJson<double>(rateToBase),
      'openingBalance': serializer.toJson<double>(openingBalance),
      'icon': serializer.toJson<String?>(icon),
      'createdAt': serializer.toJson<String>(createdAt),
      'updatedAt': serializer.toJson<String>(updatedAt),
    };
  }

  BudgetAccount copyWith({
    String? id,
    String? name,
    Value<String?> type = const Value.absent(),
    String? currency,
    double? rateToBase,
    double? openingBalance,
    Value<String?> icon = const Value.absent(),
    String? createdAt,
    String? updatedAt,
  }) => BudgetAccount(
    id: id ?? this.id,
    name: name ?? this.name,
    type: type.present ? type.value : this.type,
    currency: currency ?? this.currency,
    rateToBase: rateToBase ?? this.rateToBase,
    openingBalance: openingBalance ?? this.openingBalance,
    icon: icon.present ? icon.value : this.icon,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  BudgetAccount copyWithCompanion(BudgetAccountsTableCompanion data) {
    return BudgetAccount(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      type: data.type.present ? data.type.value : this.type,
      currency: data.currency.present ? data.currency.value : this.currency,
      rateToBase: data.rateToBase.present
          ? data.rateToBase.value
          : this.rateToBase,
      openingBalance: data.openingBalance.present
          ? data.openingBalance.value
          : this.openingBalance,
      icon: data.icon.present ? data.icon.value : this.icon,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BudgetAccount(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('currency: $currency, ')
          ..write('rateToBase: $rateToBase, ')
          ..write('openingBalance: $openingBalance, ')
          ..write('icon: $icon, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    type,
    currency,
    rateToBase,
    openingBalance,
    icon,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BudgetAccount &&
          other.id == this.id &&
          other.name == this.name &&
          other.type == this.type &&
          other.currency == this.currency &&
          other.rateToBase == this.rateToBase &&
          other.openingBalance == this.openingBalance &&
          other.icon == this.icon &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class BudgetAccountsTableCompanion extends UpdateCompanion<BudgetAccount> {
  final Value<String> id;
  final Value<String> name;
  final Value<String?> type;
  final Value<String> currency;
  final Value<double> rateToBase;
  final Value<double> openingBalance;
  final Value<String?> icon;
  final Value<String> createdAt;
  final Value<String> updatedAt;
  final Value<int> rowid;
  const BudgetAccountsTableCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.type = const Value.absent(),
    this.currency = const Value.absent(),
    this.rateToBase = const Value.absent(),
    this.openingBalance = const Value.absent(),
    this.icon = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BudgetAccountsTableCompanion.insert({
    required String id,
    required String name,
    this.type = const Value.absent(),
    required String currency,
    this.rateToBase = const Value.absent(),
    this.openingBalance = const Value.absent(),
    this.icon = const Value.absent(),
    required String createdAt,
    required String updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       currency = Value(currency),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<BudgetAccount> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? type,
    Expression<String>? currency,
    Expression<double>? rateToBase,
    Expression<double>? openingBalance,
    Expression<String>? icon,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (type != null) 'type': type,
      if (currency != null) 'currency': currency,
      if (rateToBase != null) 'rate_to_base': rateToBase,
      if (openingBalance != null) 'opening_balance': openingBalance,
      if (icon != null) 'icon': icon,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BudgetAccountsTableCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String?>? type,
    Value<String>? currency,
    Value<double>? rateToBase,
    Value<double>? openingBalance,
    Value<String?>? icon,
    Value<String>? createdAt,
    Value<String>? updatedAt,
    Value<int>? rowid,
  }) {
    return BudgetAccountsTableCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      currency: currency ?? this.currency,
      rateToBase: rateToBase ?? this.rateToBase,
      openingBalance: openingBalance ?? this.openingBalance,
      icon: icon ?? this.icon,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (currency.present) {
      map['currency'] = Variable<String>(currency.value);
    }
    if (rateToBase.present) {
      map['rate_to_base'] = Variable<double>(rateToBase.value);
    }
    if (openingBalance.present) {
      map['opening_balance'] = Variable<double>(openingBalance.value);
    }
    if (icon.present) {
      map['icon'] = Variable<String>(icon.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BudgetAccountsTableCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('currency: $currency, ')
          ..write('rateToBase: $rateToBase, ')
          ..write('openingBalance: $openingBalance, ')
          ..write('icon: $icon, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BudgetCategoriesTableTable extends BudgetCategoriesTable
    with TableInfo<$BudgetCategoriesTableTable, BudgetCategory> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BudgetCategoriesTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isIncomeMeta = const VerificationMeta(
    'isIncome',
  );
  @override
  late final GeneratedColumn<bool> isIncome = GeneratedColumn<bool>(
    'is_income',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_income" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _oneTimeMeta = const VerificationMeta(
    'oneTime',
  );
  @override
  late final GeneratedColumn<bool> oneTime = GeneratedColumn<bool>(
    'one_time',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("one_time" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _unitMeta = const VerificationMeta('unit');
  @override
  late final GeneratedColumn<String> unit = GeneratedColumn<String>(
    'unit',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('month'),
  );
  static const VerificationMeta _endDateMeta = const VerificationMeta(
    'endDate',
  );
  @override
  late final GeneratedColumn<String> endDate = GeneratedColumn<String>(
    'end_date',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _priceMeta = const VerificationMeta('price');
  @override
  late final GeneratedColumn<double> price = GeneratedColumn<double>(
    'price',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _percentMeta = const VerificationMeta(
    'percent',
  );
  @override
  late final GeneratedColumn<double> percent = GeneratedColumn<double>(
    'percent',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _frequencyMonthsMeta = const VerificationMeta(
    'frequencyMonths',
  );
  @override
  late final GeneratedColumn<double> frequencyMonths = GeneratedColumn<double>(
    'frequency_months',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _unitsPerMonthMeta = const VerificationMeta(
    'unitsPerMonth',
  );
  @override
  late final GeneratedColumn<double> unitsPerMonth = GeneratedColumn<double>(
    'units_per_month',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _parentIdMeta = const VerificationMeta(
    'parentId',
  );
  @override
  late final GeneratedColumn<String> parentId = GeneratedColumn<String>(
    'parent_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES budget_categories (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _countPercentOfIdMeta = const VerificationMeta(
    'countPercentOfId',
  );
  @override
  late final GeneratedColumn<String> countPercentOfId = GeneratedColumn<String>(
    'count_percent_of_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES budget_categories (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _accountCountIdMeta = const VerificationMeta(
    'accountCountId',
  );
  @override
  late final GeneratedColumn<String> accountCountId = GeneratedColumn<String>(
    'account_count_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES budget_accounts (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _accountUseIdMeta = const VerificationMeta(
    'accountUseId',
  );
  @override
  late final GeneratedColumn<String> accountUseId = GeneratedColumn<String>(
    'account_use_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES budget_accounts (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    isIncome,
    oneTime,
    unit,
    endDate,
    price,
    percent,
    frequencyMonths,
    unitsPerMonth,
    parentId,
    countPercentOfId,
    accountCountId,
    accountUseId,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'budget_categories';
  @override
  VerificationContext validateIntegrity(
    Insertable<BudgetCategory> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('is_income')) {
      context.handle(
        _isIncomeMeta,
        isIncome.isAcceptableOrUnknown(data['is_income']!, _isIncomeMeta),
      );
    }
    if (data.containsKey('one_time')) {
      context.handle(
        _oneTimeMeta,
        oneTime.isAcceptableOrUnknown(data['one_time']!, _oneTimeMeta),
      );
    }
    if (data.containsKey('unit')) {
      context.handle(
        _unitMeta,
        unit.isAcceptableOrUnknown(data['unit']!, _unitMeta),
      );
    }
    if (data.containsKey('end_date')) {
      context.handle(
        _endDateMeta,
        endDate.isAcceptableOrUnknown(data['end_date']!, _endDateMeta),
      );
    }
    if (data.containsKey('price')) {
      context.handle(
        _priceMeta,
        price.isAcceptableOrUnknown(data['price']!, _priceMeta),
      );
    }
    if (data.containsKey('percent')) {
      context.handle(
        _percentMeta,
        percent.isAcceptableOrUnknown(data['percent']!, _percentMeta),
      );
    }
    if (data.containsKey('frequency_months')) {
      context.handle(
        _frequencyMonthsMeta,
        frequencyMonths.isAcceptableOrUnknown(
          data['frequency_months']!,
          _frequencyMonthsMeta,
        ),
      );
    }
    if (data.containsKey('units_per_month')) {
      context.handle(
        _unitsPerMonthMeta,
        unitsPerMonth.isAcceptableOrUnknown(
          data['units_per_month']!,
          _unitsPerMonthMeta,
        ),
      );
    }
    if (data.containsKey('parent_id')) {
      context.handle(
        _parentIdMeta,
        parentId.isAcceptableOrUnknown(data['parent_id']!, _parentIdMeta),
      );
    }
    if (data.containsKey('count_percent_of_id')) {
      context.handle(
        _countPercentOfIdMeta,
        countPercentOfId.isAcceptableOrUnknown(
          data['count_percent_of_id']!,
          _countPercentOfIdMeta,
        ),
      );
    }
    if (data.containsKey('account_count_id')) {
      context.handle(
        _accountCountIdMeta,
        accountCountId.isAcceptableOrUnknown(
          data['account_count_id']!,
          _accountCountIdMeta,
        ),
      );
    }
    if (data.containsKey('account_use_id')) {
      context.handle(
        _accountUseIdMeta,
        accountUseId.isAcceptableOrUnknown(
          data['account_use_id']!,
          _accountUseIdMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  BudgetCategory map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BudgetCategory(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      isIncome: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_income'],
      )!,
      oneTime: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}one_time'],
      )!,
      unit: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}unit'],
      )!,
      endDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}end_date'],
      ),
      price: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}price'],
      ),
      percent: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}percent'],
      ),
      frequencyMonths: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}frequency_months'],
      ),
      unitsPerMonth: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}units_per_month'],
      ),
      parentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_id'],
      ),
      countPercentOfId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}count_percent_of_id'],
      ),
      accountCountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_count_id'],
      ),
      accountUseId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_use_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $BudgetCategoriesTableTable createAlias(String alias) {
    return $BudgetCategoriesTableTable(attachedDatabase, alias);
  }
}

class BudgetCategory extends DataClass implements Insertable<BudgetCategory> {
  final String id;
  final String name;
  final bool isIncome;
  final bool oneTime;

  /// piece | kilogram | month | percent_per_month
  final String unit;

  /// UTC ISO-8601 text; the category stops counting after it.
  final String? endDate;
  final double? price;
  final double? percent;
  final double? frequencyMonths;
  final double? unitsPerMonth;
  final String? parentId;

  /// For `percent_per_month`: the (leaf) category the percentage is taken of.
  final String? countPercentOfId;

  /// Account whose currency the category is COUNTED in / that money actually
  /// moves through ("Account to count" / "Account to use" in the spec).
  final String? accountCountId;
  final String? accountUseId;
  final String createdAt;
  final String updatedAt;
  const BudgetCategory({
    required this.id,
    required this.name,
    required this.isIncome,
    required this.oneTime,
    required this.unit,
    this.endDate,
    this.price,
    this.percent,
    this.frequencyMonths,
    this.unitsPerMonth,
    this.parentId,
    this.countPercentOfId,
    this.accountCountId,
    this.accountUseId,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['is_income'] = Variable<bool>(isIncome);
    map['one_time'] = Variable<bool>(oneTime);
    map['unit'] = Variable<String>(unit);
    if (!nullToAbsent || endDate != null) {
      map['end_date'] = Variable<String>(endDate);
    }
    if (!nullToAbsent || price != null) {
      map['price'] = Variable<double>(price);
    }
    if (!nullToAbsent || percent != null) {
      map['percent'] = Variable<double>(percent);
    }
    if (!nullToAbsent || frequencyMonths != null) {
      map['frequency_months'] = Variable<double>(frequencyMonths);
    }
    if (!nullToAbsent || unitsPerMonth != null) {
      map['units_per_month'] = Variable<double>(unitsPerMonth);
    }
    if (!nullToAbsent || parentId != null) {
      map['parent_id'] = Variable<String>(parentId);
    }
    if (!nullToAbsent || countPercentOfId != null) {
      map['count_percent_of_id'] = Variable<String>(countPercentOfId);
    }
    if (!nullToAbsent || accountCountId != null) {
      map['account_count_id'] = Variable<String>(accountCountId);
    }
    if (!nullToAbsent || accountUseId != null) {
      map['account_use_id'] = Variable<String>(accountUseId);
    }
    map['created_at'] = Variable<String>(createdAt);
    map['updated_at'] = Variable<String>(updatedAt);
    return map;
  }

  BudgetCategoriesTableCompanion toCompanion(bool nullToAbsent) {
    return BudgetCategoriesTableCompanion(
      id: Value(id),
      name: Value(name),
      isIncome: Value(isIncome),
      oneTime: Value(oneTime),
      unit: Value(unit),
      endDate: endDate == null && nullToAbsent
          ? const Value.absent()
          : Value(endDate),
      price: price == null && nullToAbsent
          ? const Value.absent()
          : Value(price),
      percent: percent == null && nullToAbsent
          ? const Value.absent()
          : Value(percent),
      frequencyMonths: frequencyMonths == null && nullToAbsent
          ? const Value.absent()
          : Value(frequencyMonths),
      unitsPerMonth: unitsPerMonth == null && nullToAbsent
          ? const Value.absent()
          : Value(unitsPerMonth),
      parentId: parentId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentId),
      countPercentOfId: countPercentOfId == null && nullToAbsent
          ? const Value.absent()
          : Value(countPercentOfId),
      accountCountId: accountCountId == null && nullToAbsent
          ? const Value.absent()
          : Value(accountCountId),
      accountUseId: accountUseId == null && nullToAbsent
          ? const Value.absent()
          : Value(accountUseId),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory BudgetCategory.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BudgetCategory(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      isIncome: serializer.fromJson<bool>(json['isIncome']),
      oneTime: serializer.fromJson<bool>(json['oneTime']),
      unit: serializer.fromJson<String>(json['unit']),
      endDate: serializer.fromJson<String?>(json['endDate']),
      price: serializer.fromJson<double?>(json['price']),
      percent: serializer.fromJson<double?>(json['percent']),
      frequencyMonths: serializer.fromJson<double?>(json['frequencyMonths']),
      unitsPerMonth: serializer.fromJson<double?>(json['unitsPerMonth']),
      parentId: serializer.fromJson<String?>(json['parentId']),
      countPercentOfId: serializer.fromJson<String?>(json['countPercentOfId']),
      accountCountId: serializer.fromJson<String?>(json['accountCountId']),
      accountUseId: serializer.fromJson<String?>(json['accountUseId']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'isIncome': serializer.toJson<bool>(isIncome),
      'oneTime': serializer.toJson<bool>(oneTime),
      'unit': serializer.toJson<String>(unit),
      'endDate': serializer.toJson<String?>(endDate),
      'price': serializer.toJson<double?>(price),
      'percent': serializer.toJson<double?>(percent),
      'frequencyMonths': serializer.toJson<double?>(frequencyMonths),
      'unitsPerMonth': serializer.toJson<double?>(unitsPerMonth),
      'parentId': serializer.toJson<String?>(parentId),
      'countPercentOfId': serializer.toJson<String?>(countPercentOfId),
      'accountCountId': serializer.toJson<String?>(accountCountId),
      'accountUseId': serializer.toJson<String?>(accountUseId),
      'createdAt': serializer.toJson<String>(createdAt),
      'updatedAt': serializer.toJson<String>(updatedAt),
    };
  }

  BudgetCategory copyWith({
    String? id,
    String? name,
    bool? isIncome,
    bool? oneTime,
    String? unit,
    Value<String?> endDate = const Value.absent(),
    Value<double?> price = const Value.absent(),
    Value<double?> percent = const Value.absent(),
    Value<double?> frequencyMonths = const Value.absent(),
    Value<double?> unitsPerMonth = const Value.absent(),
    Value<String?> parentId = const Value.absent(),
    Value<String?> countPercentOfId = const Value.absent(),
    Value<String?> accountCountId = const Value.absent(),
    Value<String?> accountUseId = const Value.absent(),
    String? createdAt,
    String? updatedAt,
  }) => BudgetCategory(
    id: id ?? this.id,
    name: name ?? this.name,
    isIncome: isIncome ?? this.isIncome,
    oneTime: oneTime ?? this.oneTime,
    unit: unit ?? this.unit,
    endDate: endDate.present ? endDate.value : this.endDate,
    price: price.present ? price.value : this.price,
    percent: percent.present ? percent.value : this.percent,
    frequencyMonths: frequencyMonths.present
        ? frequencyMonths.value
        : this.frequencyMonths,
    unitsPerMonth: unitsPerMonth.present
        ? unitsPerMonth.value
        : this.unitsPerMonth,
    parentId: parentId.present ? parentId.value : this.parentId,
    countPercentOfId: countPercentOfId.present
        ? countPercentOfId.value
        : this.countPercentOfId,
    accountCountId: accountCountId.present
        ? accountCountId.value
        : this.accountCountId,
    accountUseId: accountUseId.present ? accountUseId.value : this.accountUseId,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  BudgetCategory copyWithCompanion(BudgetCategoriesTableCompanion data) {
    return BudgetCategory(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      isIncome: data.isIncome.present ? data.isIncome.value : this.isIncome,
      oneTime: data.oneTime.present ? data.oneTime.value : this.oneTime,
      unit: data.unit.present ? data.unit.value : this.unit,
      endDate: data.endDate.present ? data.endDate.value : this.endDate,
      price: data.price.present ? data.price.value : this.price,
      percent: data.percent.present ? data.percent.value : this.percent,
      frequencyMonths: data.frequencyMonths.present
          ? data.frequencyMonths.value
          : this.frequencyMonths,
      unitsPerMonth: data.unitsPerMonth.present
          ? data.unitsPerMonth.value
          : this.unitsPerMonth,
      parentId: data.parentId.present ? data.parentId.value : this.parentId,
      countPercentOfId: data.countPercentOfId.present
          ? data.countPercentOfId.value
          : this.countPercentOfId,
      accountCountId: data.accountCountId.present
          ? data.accountCountId.value
          : this.accountCountId,
      accountUseId: data.accountUseId.present
          ? data.accountUseId.value
          : this.accountUseId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BudgetCategory(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('isIncome: $isIncome, ')
          ..write('oneTime: $oneTime, ')
          ..write('unit: $unit, ')
          ..write('endDate: $endDate, ')
          ..write('price: $price, ')
          ..write('percent: $percent, ')
          ..write('frequencyMonths: $frequencyMonths, ')
          ..write('unitsPerMonth: $unitsPerMonth, ')
          ..write('parentId: $parentId, ')
          ..write('countPercentOfId: $countPercentOfId, ')
          ..write('accountCountId: $accountCountId, ')
          ..write('accountUseId: $accountUseId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    isIncome,
    oneTime,
    unit,
    endDate,
    price,
    percent,
    frequencyMonths,
    unitsPerMonth,
    parentId,
    countPercentOfId,
    accountCountId,
    accountUseId,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BudgetCategory &&
          other.id == this.id &&
          other.name == this.name &&
          other.isIncome == this.isIncome &&
          other.oneTime == this.oneTime &&
          other.unit == this.unit &&
          other.endDate == this.endDate &&
          other.price == this.price &&
          other.percent == this.percent &&
          other.frequencyMonths == this.frequencyMonths &&
          other.unitsPerMonth == this.unitsPerMonth &&
          other.parentId == this.parentId &&
          other.countPercentOfId == this.countPercentOfId &&
          other.accountCountId == this.accountCountId &&
          other.accountUseId == this.accountUseId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class BudgetCategoriesTableCompanion extends UpdateCompanion<BudgetCategory> {
  final Value<String> id;
  final Value<String> name;
  final Value<bool> isIncome;
  final Value<bool> oneTime;
  final Value<String> unit;
  final Value<String?> endDate;
  final Value<double?> price;
  final Value<double?> percent;
  final Value<double?> frequencyMonths;
  final Value<double?> unitsPerMonth;
  final Value<String?> parentId;
  final Value<String?> countPercentOfId;
  final Value<String?> accountCountId;
  final Value<String?> accountUseId;
  final Value<String> createdAt;
  final Value<String> updatedAt;
  final Value<int> rowid;
  const BudgetCategoriesTableCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.isIncome = const Value.absent(),
    this.oneTime = const Value.absent(),
    this.unit = const Value.absent(),
    this.endDate = const Value.absent(),
    this.price = const Value.absent(),
    this.percent = const Value.absent(),
    this.frequencyMonths = const Value.absent(),
    this.unitsPerMonth = const Value.absent(),
    this.parentId = const Value.absent(),
    this.countPercentOfId = const Value.absent(),
    this.accountCountId = const Value.absent(),
    this.accountUseId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BudgetCategoriesTableCompanion.insert({
    required String id,
    required String name,
    this.isIncome = const Value.absent(),
    this.oneTime = const Value.absent(),
    this.unit = const Value.absent(),
    this.endDate = const Value.absent(),
    this.price = const Value.absent(),
    this.percent = const Value.absent(),
    this.frequencyMonths = const Value.absent(),
    this.unitsPerMonth = const Value.absent(),
    this.parentId = const Value.absent(),
    this.countPercentOfId = const Value.absent(),
    this.accountCountId = const Value.absent(),
    this.accountUseId = const Value.absent(),
    required String createdAt,
    required String updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<BudgetCategory> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<bool>? isIncome,
    Expression<bool>? oneTime,
    Expression<String>? unit,
    Expression<String>? endDate,
    Expression<double>? price,
    Expression<double>? percent,
    Expression<double>? frequencyMonths,
    Expression<double>? unitsPerMonth,
    Expression<String>? parentId,
    Expression<String>? countPercentOfId,
    Expression<String>? accountCountId,
    Expression<String>? accountUseId,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (isIncome != null) 'is_income': isIncome,
      if (oneTime != null) 'one_time': oneTime,
      if (unit != null) 'unit': unit,
      if (endDate != null) 'end_date': endDate,
      if (price != null) 'price': price,
      if (percent != null) 'percent': percent,
      if (frequencyMonths != null) 'frequency_months': frequencyMonths,
      if (unitsPerMonth != null) 'units_per_month': unitsPerMonth,
      if (parentId != null) 'parent_id': parentId,
      if (countPercentOfId != null) 'count_percent_of_id': countPercentOfId,
      if (accountCountId != null) 'account_count_id': accountCountId,
      if (accountUseId != null) 'account_use_id': accountUseId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BudgetCategoriesTableCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<bool>? isIncome,
    Value<bool>? oneTime,
    Value<String>? unit,
    Value<String?>? endDate,
    Value<double?>? price,
    Value<double?>? percent,
    Value<double?>? frequencyMonths,
    Value<double?>? unitsPerMonth,
    Value<String?>? parentId,
    Value<String?>? countPercentOfId,
    Value<String?>? accountCountId,
    Value<String?>? accountUseId,
    Value<String>? createdAt,
    Value<String>? updatedAt,
    Value<int>? rowid,
  }) {
    return BudgetCategoriesTableCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      isIncome: isIncome ?? this.isIncome,
      oneTime: oneTime ?? this.oneTime,
      unit: unit ?? this.unit,
      endDate: endDate ?? this.endDate,
      price: price ?? this.price,
      percent: percent ?? this.percent,
      frequencyMonths: frequencyMonths ?? this.frequencyMonths,
      unitsPerMonth: unitsPerMonth ?? this.unitsPerMonth,
      parentId: parentId ?? this.parentId,
      countPercentOfId: countPercentOfId ?? this.countPercentOfId,
      accountCountId: accountCountId ?? this.accountCountId,
      accountUseId: accountUseId ?? this.accountUseId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (isIncome.present) {
      map['is_income'] = Variable<bool>(isIncome.value);
    }
    if (oneTime.present) {
      map['one_time'] = Variable<bool>(oneTime.value);
    }
    if (unit.present) {
      map['unit'] = Variable<String>(unit.value);
    }
    if (endDate.present) {
      map['end_date'] = Variable<String>(endDate.value);
    }
    if (price.present) {
      map['price'] = Variable<double>(price.value);
    }
    if (percent.present) {
      map['percent'] = Variable<double>(percent.value);
    }
    if (frequencyMonths.present) {
      map['frequency_months'] = Variable<double>(frequencyMonths.value);
    }
    if (unitsPerMonth.present) {
      map['units_per_month'] = Variable<double>(unitsPerMonth.value);
    }
    if (parentId.present) {
      map['parent_id'] = Variable<String>(parentId.value);
    }
    if (countPercentOfId.present) {
      map['count_percent_of_id'] = Variable<String>(countPercentOfId.value);
    }
    if (accountCountId.present) {
      map['account_count_id'] = Variable<String>(accountCountId.value);
    }
    if (accountUseId.present) {
      map['account_use_id'] = Variable<String>(accountUseId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BudgetCategoriesTableCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('isIncome: $isIncome, ')
          ..write('oneTime: $oneTime, ')
          ..write('unit: $unit, ')
          ..write('endDate: $endDate, ')
          ..write('price: $price, ')
          ..write('percent: $percent, ')
          ..write('frequencyMonths: $frequencyMonths, ')
          ..write('unitsPerMonth: $unitsPerMonth, ')
          ..write('parentId: $parentId, ')
          ..write('countPercentOfId: $countPercentOfId, ')
          ..write('accountCountId: $accountCountId, ')
          ..write('accountUseId: $accountUseId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BudgetTransactionsTableTable extends BudgetTransactionsTable
    with TableInfo<$BudgetTransactionsTableTable, BudgetTransaction> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BudgetTransactionsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
    'category_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES budget_categories (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _actionIdMeta = const VerificationMeta(
    'actionId',
  );
  @override
  late final GeneratedColumn<String> actionId = GeneratedColumn<String>(
    'action_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES actions (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _occurredAtMeta = const VerificationMeta(
    'occurredAt',
  );
  @override
  late final GeneratedColumn<String> occurredAt = GeneratedColumn<String>(
    'occurred_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _quantityMeta = const VerificationMeta(
    'quantity',
  );
  @override
  late final GeneratedColumn<double> quantity = GeneratedColumn<double>(
    'quantity',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _unitPriceMeta = const VerificationMeta(
    'unitPrice',
  );
  @override
  late final GeneratedColumn<double> unitPrice = GeneratedColumn<double>(
    'unit_price',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _isIncomeMeta = const VerificationMeta(
    'isIncome',
  );
  @override
  late final GeneratedColumn<bool> isIncome = GeneratedColumn<bool>(
    'is_income',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_income" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isAmountMeta = const VerificationMeta(
    'isAmount',
  );
  @override
  late final GeneratedColumn<bool> isAmount = GeneratedColumn<bool>(
    'is_amount',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_amount" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _accountCountIdMeta = const VerificationMeta(
    'accountCountId',
  );
  @override
  late final GeneratedColumn<String> accountCountId = GeneratedColumn<String>(
    'account_count_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES budget_accounts (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _accountUseIdMeta = const VerificationMeta(
    'accountUseId',
  );
  @override
  late final GeneratedColumn<String> accountUseId = GeneratedColumn<String>(
    'account_use_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES budget_accounts (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _rateCountMeta = const VerificationMeta(
    'rateCount',
  );
  @override
  late final GeneratedColumn<double> rateCount = GeneratedColumn<double>(
    'rate_count',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rateInteractMeta = const VerificationMeta(
    'rateInteract',
  );
  @override
  late final GeneratedColumn<double> rateInteract = GeneratedColumn<double>(
    'rate_interact',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    categoryId,
    actionId,
    occurredAt,
    quantity,
    unitPrice,
    isIncome,
    isAmount,
    accountCountId,
    accountUseId,
    rateCount,
    rateInteract,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'budget_transactions';
  @override
  VerificationContext validateIntegrity(
    Insertable<BudgetTransaction> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    }
    if (data.containsKey('action_id')) {
      context.handle(
        _actionIdMeta,
        actionId.isAcceptableOrUnknown(data['action_id']!, _actionIdMeta),
      );
    }
    if (data.containsKey('occurred_at')) {
      context.handle(
        _occurredAtMeta,
        occurredAt.isAcceptableOrUnknown(data['occurred_at']!, _occurredAtMeta),
      );
    } else if (isInserting) {
      context.missing(_occurredAtMeta);
    }
    if (data.containsKey('quantity')) {
      context.handle(
        _quantityMeta,
        quantity.isAcceptableOrUnknown(data['quantity']!, _quantityMeta),
      );
    }
    if (data.containsKey('unit_price')) {
      context.handle(
        _unitPriceMeta,
        unitPrice.isAcceptableOrUnknown(data['unit_price']!, _unitPriceMeta),
      );
    }
    if (data.containsKey('is_income')) {
      context.handle(
        _isIncomeMeta,
        isIncome.isAcceptableOrUnknown(data['is_income']!, _isIncomeMeta),
      );
    }
    if (data.containsKey('is_amount')) {
      context.handle(
        _isAmountMeta,
        isAmount.isAcceptableOrUnknown(data['is_amount']!, _isAmountMeta),
      );
    }
    if (data.containsKey('account_count_id')) {
      context.handle(
        _accountCountIdMeta,
        accountCountId.isAcceptableOrUnknown(
          data['account_count_id']!,
          _accountCountIdMeta,
        ),
      );
    }
    if (data.containsKey('account_use_id')) {
      context.handle(
        _accountUseIdMeta,
        accountUseId.isAcceptableOrUnknown(
          data['account_use_id']!,
          _accountUseIdMeta,
        ),
      );
    }
    if (data.containsKey('rate_count')) {
      context.handle(
        _rateCountMeta,
        rateCount.isAcceptableOrUnknown(data['rate_count']!, _rateCountMeta),
      );
    }
    if (data.containsKey('rate_interact')) {
      context.handle(
        _rateInteractMeta,
        rateInteract.isAcceptableOrUnknown(
          data['rate_interact']!,
          _rateInteractMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  BudgetTransaction map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BudgetTransaction(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category_id'],
      ),
      actionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}action_id'],
      ),
      occurredAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}occurred_at'],
      )!,
      quantity: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}quantity'],
      )!,
      unitPrice: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}unit_price'],
      )!,
      isIncome: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_income'],
      )!,
      isAmount: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_amount'],
      )!,
      accountCountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_count_id'],
      ),
      accountUseId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_use_id'],
      ),
      rateCount: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}rate_count'],
      ),
      rateInteract: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}rate_interact'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $BudgetTransactionsTableTable createAlias(String alias) {
    return $BudgetTransactionsTableTable(attachedDatabase, alias);
  }
}

class BudgetTransaction extends DataClass
    implements Insertable<BudgetTransaction> {
  final String id;
  final String name;
  final String? categoryId;
  final String? actionId;
  final String occurredAt;
  final double quantity;

  /// Price per unit actually used (snapshot of the category price).
  final double unitPrice;
  final bool isIncome;

  /// True for percent categories: `quantity` already IS the amount.
  final bool isAmount;
  final String? accountCountId;
  final String? accountUseId;
  final double? rateCount;
  final double? rateInteract;
  final String createdAt;
  final String updatedAt;
  const BudgetTransaction({
    required this.id,
    required this.name,
    this.categoryId,
    this.actionId,
    required this.occurredAt,
    required this.quantity,
    required this.unitPrice,
    required this.isIncome,
    required this.isAmount,
    this.accountCountId,
    this.accountUseId,
    this.rateCount,
    this.rateInteract,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || categoryId != null) {
      map['category_id'] = Variable<String>(categoryId);
    }
    if (!nullToAbsent || actionId != null) {
      map['action_id'] = Variable<String>(actionId);
    }
    map['occurred_at'] = Variable<String>(occurredAt);
    map['quantity'] = Variable<double>(quantity);
    map['unit_price'] = Variable<double>(unitPrice);
    map['is_income'] = Variable<bool>(isIncome);
    map['is_amount'] = Variable<bool>(isAmount);
    if (!nullToAbsent || accountCountId != null) {
      map['account_count_id'] = Variable<String>(accountCountId);
    }
    if (!nullToAbsent || accountUseId != null) {
      map['account_use_id'] = Variable<String>(accountUseId);
    }
    if (!nullToAbsent || rateCount != null) {
      map['rate_count'] = Variable<double>(rateCount);
    }
    if (!nullToAbsent || rateInteract != null) {
      map['rate_interact'] = Variable<double>(rateInteract);
    }
    map['created_at'] = Variable<String>(createdAt);
    map['updated_at'] = Variable<String>(updatedAt);
    return map;
  }

  BudgetTransactionsTableCompanion toCompanion(bool nullToAbsent) {
    return BudgetTransactionsTableCompanion(
      id: Value(id),
      name: Value(name),
      categoryId: categoryId == null && nullToAbsent
          ? const Value.absent()
          : Value(categoryId),
      actionId: actionId == null && nullToAbsent
          ? const Value.absent()
          : Value(actionId),
      occurredAt: Value(occurredAt),
      quantity: Value(quantity),
      unitPrice: Value(unitPrice),
      isIncome: Value(isIncome),
      isAmount: Value(isAmount),
      accountCountId: accountCountId == null && nullToAbsent
          ? const Value.absent()
          : Value(accountCountId),
      accountUseId: accountUseId == null && nullToAbsent
          ? const Value.absent()
          : Value(accountUseId),
      rateCount: rateCount == null && nullToAbsent
          ? const Value.absent()
          : Value(rateCount),
      rateInteract: rateInteract == null && nullToAbsent
          ? const Value.absent()
          : Value(rateInteract),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory BudgetTransaction.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BudgetTransaction(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      categoryId: serializer.fromJson<String?>(json['categoryId']),
      actionId: serializer.fromJson<String?>(json['actionId']),
      occurredAt: serializer.fromJson<String>(json['occurredAt']),
      quantity: serializer.fromJson<double>(json['quantity']),
      unitPrice: serializer.fromJson<double>(json['unitPrice']),
      isIncome: serializer.fromJson<bool>(json['isIncome']),
      isAmount: serializer.fromJson<bool>(json['isAmount']),
      accountCountId: serializer.fromJson<String?>(json['accountCountId']),
      accountUseId: serializer.fromJson<String?>(json['accountUseId']),
      rateCount: serializer.fromJson<double?>(json['rateCount']),
      rateInteract: serializer.fromJson<double?>(json['rateInteract']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'categoryId': serializer.toJson<String?>(categoryId),
      'actionId': serializer.toJson<String?>(actionId),
      'occurredAt': serializer.toJson<String>(occurredAt),
      'quantity': serializer.toJson<double>(quantity),
      'unitPrice': serializer.toJson<double>(unitPrice),
      'isIncome': serializer.toJson<bool>(isIncome),
      'isAmount': serializer.toJson<bool>(isAmount),
      'accountCountId': serializer.toJson<String?>(accountCountId),
      'accountUseId': serializer.toJson<String?>(accountUseId),
      'rateCount': serializer.toJson<double?>(rateCount),
      'rateInteract': serializer.toJson<double?>(rateInteract),
      'createdAt': serializer.toJson<String>(createdAt),
      'updatedAt': serializer.toJson<String>(updatedAt),
    };
  }

  BudgetTransaction copyWith({
    String? id,
    String? name,
    Value<String?> categoryId = const Value.absent(),
    Value<String?> actionId = const Value.absent(),
    String? occurredAt,
    double? quantity,
    double? unitPrice,
    bool? isIncome,
    bool? isAmount,
    Value<String?> accountCountId = const Value.absent(),
    Value<String?> accountUseId = const Value.absent(),
    Value<double?> rateCount = const Value.absent(),
    Value<double?> rateInteract = const Value.absent(),
    String? createdAt,
    String? updatedAt,
  }) => BudgetTransaction(
    id: id ?? this.id,
    name: name ?? this.name,
    categoryId: categoryId.present ? categoryId.value : this.categoryId,
    actionId: actionId.present ? actionId.value : this.actionId,
    occurredAt: occurredAt ?? this.occurredAt,
    quantity: quantity ?? this.quantity,
    unitPrice: unitPrice ?? this.unitPrice,
    isIncome: isIncome ?? this.isIncome,
    isAmount: isAmount ?? this.isAmount,
    accountCountId: accountCountId.present
        ? accountCountId.value
        : this.accountCountId,
    accountUseId: accountUseId.present ? accountUseId.value : this.accountUseId,
    rateCount: rateCount.present ? rateCount.value : this.rateCount,
    rateInteract: rateInteract.present ? rateInteract.value : this.rateInteract,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  BudgetTransaction copyWithCompanion(BudgetTransactionsTableCompanion data) {
    return BudgetTransaction(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
      actionId: data.actionId.present ? data.actionId.value : this.actionId,
      occurredAt: data.occurredAt.present
          ? data.occurredAt.value
          : this.occurredAt,
      quantity: data.quantity.present ? data.quantity.value : this.quantity,
      unitPrice: data.unitPrice.present ? data.unitPrice.value : this.unitPrice,
      isIncome: data.isIncome.present ? data.isIncome.value : this.isIncome,
      isAmount: data.isAmount.present ? data.isAmount.value : this.isAmount,
      accountCountId: data.accountCountId.present
          ? data.accountCountId.value
          : this.accountCountId,
      accountUseId: data.accountUseId.present
          ? data.accountUseId.value
          : this.accountUseId,
      rateCount: data.rateCount.present ? data.rateCount.value : this.rateCount,
      rateInteract: data.rateInteract.present
          ? data.rateInteract.value
          : this.rateInteract,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BudgetTransaction(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('categoryId: $categoryId, ')
          ..write('actionId: $actionId, ')
          ..write('occurredAt: $occurredAt, ')
          ..write('quantity: $quantity, ')
          ..write('unitPrice: $unitPrice, ')
          ..write('isIncome: $isIncome, ')
          ..write('isAmount: $isAmount, ')
          ..write('accountCountId: $accountCountId, ')
          ..write('accountUseId: $accountUseId, ')
          ..write('rateCount: $rateCount, ')
          ..write('rateInteract: $rateInteract, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    categoryId,
    actionId,
    occurredAt,
    quantity,
    unitPrice,
    isIncome,
    isAmount,
    accountCountId,
    accountUseId,
    rateCount,
    rateInteract,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BudgetTransaction &&
          other.id == this.id &&
          other.name == this.name &&
          other.categoryId == this.categoryId &&
          other.actionId == this.actionId &&
          other.occurredAt == this.occurredAt &&
          other.quantity == this.quantity &&
          other.unitPrice == this.unitPrice &&
          other.isIncome == this.isIncome &&
          other.isAmount == this.isAmount &&
          other.accountCountId == this.accountCountId &&
          other.accountUseId == this.accountUseId &&
          other.rateCount == this.rateCount &&
          other.rateInteract == this.rateInteract &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class BudgetTransactionsTableCompanion
    extends UpdateCompanion<BudgetTransaction> {
  final Value<String> id;
  final Value<String> name;
  final Value<String?> categoryId;
  final Value<String?> actionId;
  final Value<String> occurredAt;
  final Value<double> quantity;
  final Value<double> unitPrice;
  final Value<bool> isIncome;
  final Value<bool> isAmount;
  final Value<String?> accountCountId;
  final Value<String?> accountUseId;
  final Value<double?> rateCount;
  final Value<double?> rateInteract;
  final Value<String> createdAt;
  final Value<String> updatedAt;
  final Value<int> rowid;
  const BudgetTransactionsTableCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.actionId = const Value.absent(),
    this.occurredAt = const Value.absent(),
    this.quantity = const Value.absent(),
    this.unitPrice = const Value.absent(),
    this.isIncome = const Value.absent(),
    this.isAmount = const Value.absent(),
    this.accountCountId = const Value.absent(),
    this.accountUseId = const Value.absent(),
    this.rateCount = const Value.absent(),
    this.rateInteract = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BudgetTransactionsTableCompanion.insert({
    required String id,
    this.name = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.actionId = const Value.absent(),
    required String occurredAt,
    this.quantity = const Value.absent(),
    this.unitPrice = const Value.absent(),
    this.isIncome = const Value.absent(),
    this.isAmount = const Value.absent(),
    this.accountCountId = const Value.absent(),
    this.accountUseId = const Value.absent(),
    this.rateCount = const Value.absent(),
    this.rateInteract = const Value.absent(),
    required String createdAt,
    required String updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       occurredAt = Value(occurredAt),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<BudgetTransaction> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? categoryId,
    Expression<String>? actionId,
    Expression<String>? occurredAt,
    Expression<double>? quantity,
    Expression<double>? unitPrice,
    Expression<bool>? isIncome,
    Expression<bool>? isAmount,
    Expression<String>? accountCountId,
    Expression<String>? accountUseId,
    Expression<double>? rateCount,
    Expression<double>? rateInteract,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (categoryId != null) 'category_id': categoryId,
      if (actionId != null) 'action_id': actionId,
      if (occurredAt != null) 'occurred_at': occurredAt,
      if (quantity != null) 'quantity': quantity,
      if (unitPrice != null) 'unit_price': unitPrice,
      if (isIncome != null) 'is_income': isIncome,
      if (isAmount != null) 'is_amount': isAmount,
      if (accountCountId != null) 'account_count_id': accountCountId,
      if (accountUseId != null) 'account_use_id': accountUseId,
      if (rateCount != null) 'rate_count': rateCount,
      if (rateInteract != null) 'rate_interact': rateInteract,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BudgetTransactionsTableCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String?>? categoryId,
    Value<String?>? actionId,
    Value<String>? occurredAt,
    Value<double>? quantity,
    Value<double>? unitPrice,
    Value<bool>? isIncome,
    Value<bool>? isAmount,
    Value<String?>? accountCountId,
    Value<String?>? accountUseId,
    Value<double?>? rateCount,
    Value<double?>? rateInteract,
    Value<String>? createdAt,
    Value<String>? updatedAt,
    Value<int>? rowid,
  }) {
    return BudgetTransactionsTableCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      categoryId: categoryId ?? this.categoryId,
      actionId: actionId ?? this.actionId,
      occurredAt: occurredAt ?? this.occurredAt,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      isIncome: isIncome ?? this.isIncome,
      isAmount: isAmount ?? this.isAmount,
      accountCountId: accountCountId ?? this.accountCountId,
      accountUseId: accountUseId ?? this.accountUseId,
      rateCount: rateCount ?? this.rateCount,
      rateInteract: rateInteract ?? this.rateInteract,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
    }
    if (actionId.present) {
      map['action_id'] = Variable<String>(actionId.value);
    }
    if (occurredAt.present) {
      map['occurred_at'] = Variable<String>(occurredAt.value);
    }
    if (quantity.present) {
      map['quantity'] = Variable<double>(quantity.value);
    }
    if (unitPrice.present) {
      map['unit_price'] = Variable<double>(unitPrice.value);
    }
    if (isIncome.present) {
      map['is_income'] = Variable<bool>(isIncome.value);
    }
    if (isAmount.present) {
      map['is_amount'] = Variable<bool>(isAmount.value);
    }
    if (accountCountId.present) {
      map['account_count_id'] = Variable<String>(accountCountId.value);
    }
    if (accountUseId.present) {
      map['account_use_id'] = Variable<String>(accountUseId.value);
    }
    if (rateCount.present) {
      map['rate_count'] = Variable<double>(rateCount.value);
    }
    if (rateInteract.present) {
      map['rate_interact'] = Variable<double>(rateInteract.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BudgetTransactionsTableCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('categoryId: $categoryId, ')
          ..write('actionId: $actionId, ')
          ..write('occurredAt: $occurredAt, ')
          ..write('quantity: $quantity, ')
          ..write('unitPrice: $unitPrice, ')
          ..write('isIncome: $isIncome, ')
          ..write('isAmount: $isAmount, ')
          ..write('accountCountId: $accountCountId, ')
          ..write('accountUseId: $accountUseId, ')
          ..write('rateCount: $rateCount, ')
          ..write('rateInteract: $rateInteract, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BudgetSettingsTableTable extends BudgetSettingsTable
    with TableInfo<$BudgetSettingsTableTable, BudgetSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BudgetSettingsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'budget_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<BudgetSetting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  BudgetSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BudgetSetting(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $BudgetSettingsTableTable createAlias(String alias) {
    return $BudgetSettingsTableTable(attachedDatabase, alias);
  }
}

class BudgetSetting extends DataClass implements Insertable<BudgetSetting> {
  final String key;
  final String value;
  const BudgetSetting({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  BudgetSettingsTableCompanion toCompanion(bool nullToAbsent) {
    return BudgetSettingsTableCompanion(key: Value(key), value: Value(value));
  }

  factory BudgetSetting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BudgetSetting(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  BudgetSetting copyWith({String? key, String? value}) =>
      BudgetSetting(key: key ?? this.key, value: value ?? this.value);
  BudgetSetting copyWithCompanion(BudgetSettingsTableCompanion data) {
    return BudgetSetting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BudgetSetting(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BudgetSetting &&
          other.key == this.key &&
          other.value == this.value);
}

class BudgetSettingsTableCompanion extends UpdateCompanion<BudgetSetting> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const BudgetSettingsTableCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BudgetSettingsTableCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<BudgetSetting> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BudgetSettingsTableCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return BudgetSettingsTableCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BudgetSettingsTableCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SavedViewsTableTable extends SavedViewsTable
    with TableInfo<$SavedViewsTableTable, SavedView> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SavedViewsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _screenMeta = const VerificationMeta('screen');
  @override
  late final GeneratedColumn<String> screen = GeneratedColumn<String>(
    'screen',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('both'),
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _isDefaultMeta = const VerificationMeta(
    'isDefault',
  );
  @override
  late final GeneratedColumn<bool> isDefault = GeneratedColumn<bool>(
    'is_default',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_default" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    screen,
    name,
    kind,
    payload,
    isDefault,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'saved_views';
  @override
  VerificationContext validateIntegrity(
    Insertable<SavedView> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('screen')) {
      context.handle(
        _screenMeta,
        screen.isAcceptableOrUnknown(data['screen']!, _screenMeta),
      );
    } else if (isInserting) {
      context.missing(_screenMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    }
    if (data.containsKey('is_default')) {
      context.handle(
        _isDefaultMeta,
        isDefault.isAcceptableOrUnknown(data['is_default']!, _isDefaultMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SavedView map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SavedView(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      screen: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}screen'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      isDefault: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_default'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $SavedViewsTableTable createAlias(String alias) {
    return $SavedViewsTableTable(attachedDatabase, alias);
  }
}

class SavedView extends DataClass implements Insertable<SavedView> {
  final String id;
  final String screen;
  final String name;
  final String kind;
  final String payload;
  final bool isDefault;
  final String createdAt;
  final String updatedAt;
  const SavedView({
    required this.id,
    required this.screen,
    required this.name,
    required this.kind,
    required this.payload,
    required this.isDefault,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['screen'] = Variable<String>(screen);
    map['name'] = Variable<String>(name);
    map['kind'] = Variable<String>(kind);
    map['payload'] = Variable<String>(payload);
    map['is_default'] = Variable<bool>(isDefault);
    map['created_at'] = Variable<String>(createdAt);
    map['updated_at'] = Variable<String>(updatedAt);
    return map;
  }

  SavedViewsTableCompanion toCompanion(bool nullToAbsent) {
    return SavedViewsTableCompanion(
      id: Value(id),
      screen: Value(screen),
      name: Value(name),
      kind: Value(kind),
      payload: Value(payload),
      isDefault: Value(isDefault),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory SavedView.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SavedView(
      id: serializer.fromJson<String>(json['id']),
      screen: serializer.fromJson<String>(json['screen']),
      name: serializer.fromJson<String>(json['name']),
      kind: serializer.fromJson<String>(json['kind']),
      payload: serializer.fromJson<String>(json['payload']),
      isDefault: serializer.fromJson<bool>(json['isDefault']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'screen': serializer.toJson<String>(screen),
      'name': serializer.toJson<String>(name),
      'kind': serializer.toJson<String>(kind),
      'payload': serializer.toJson<String>(payload),
      'isDefault': serializer.toJson<bool>(isDefault),
      'createdAt': serializer.toJson<String>(createdAt),
      'updatedAt': serializer.toJson<String>(updatedAt),
    };
  }

  SavedView copyWith({
    String? id,
    String? screen,
    String? name,
    String? kind,
    String? payload,
    bool? isDefault,
    String? createdAt,
    String? updatedAt,
  }) => SavedView(
    id: id ?? this.id,
    screen: screen ?? this.screen,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    payload: payload ?? this.payload,
    isDefault: isDefault ?? this.isDefault,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  SavedView copyWithCompanion(SavedViewsTableCompanion data) {
    return SavedView(
      id: data.id.present ? data.id.value : this.id,
      screen: data.screen.present ? data.screen.value : this.screen,
      name: data.name.present ? data.name.value : this.name,
      kind: data.kind.present ? data.kind.value : this.kind,
      payload: data.payload.present ? data.payload.value : this.payload,
      isDefault: data.isDefault.present ? data.isDefault.value : this.isDefault,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SavedView(')
          ..write('id: $id, ')
          ..write('screen: $screen, ')
          ..write('name: $name, ')
          ..write('kind: $kind, ')
          ..write('payload: $payload, ')
          ..write('isDefault: $isDefault, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    screen,
    name,
    kind,
    payload,
    isDefault,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SavedView &&
          other.id == this.id &&
          other.screen == this.screen &&
          other.name == this.name &&
          other.kind == this.kind &&
          other.payload == this.payload &&
          other.isDefault == this.isDefault &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class SavedViewsTableCompanion extends UpdateCompanion<SavedView> {
  final Value<String> id;
  final Value<String> screen;
  final Value<String> name;
  final Value<String> kind;
  final Value<String> payload;
  final Value<bool> isDefault;
  final Value<String> createdAt;
  final Value<String> updatedAt;
  final Value<int> rowid;
  const SavedViewsTableCompanion({
    this.id = const Value.absent(),
    this.screen = const Value.absent(),
    this.name = const Value.absent(),
    this.kind = const Value.absent(),
    this.payload = const Value.absent(),
    this.isDefault = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SavedViewsTableCompanion.insert({
    required String id,
    required String screen,
    required String name,
    this.kind = const Value.absent(),
    this.payload = const Value.absent(),
    this.isDefault = const Value.absent(),
    required String createdAt,
    required String updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       screen = Value(screen),
       name = Value(name),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<SavedView> custom({
    Expression<String>? id,
    Expression<String>? screen,
    Expression<String>? name,
    Expression<String>? kind,
    Expression<String>? payload,
    Expression<bool>? isDefault,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (screen != null) 'screen': screen,
      if (name != null) 'name': name,
      if (kind != null) 'kind': kind,
      if (payload != null) 'payload': payload,
      if (isDefault != null) 'is_default': isDefault,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SavedViewsTableCompanion copyWith({
    Value<String>? id,
    Value<String>? screen,
    Value<String>? name,
    Value<String>? kind,
    Value<String>? payload,
    Value<bool>? isDefault,
    Value<String>? createdAt,
    Value<String>? updatedAt,
    Value<int>? rowid,
  }) {
    return SavedViewsTableCompanion(
      id: id ?? this.id,
      screen: screen ?? this.screen,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      payload: payload ?? this.payload,
      isDefault: isDefault ?? this.isDefault,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (screen.present) {
      map['screen'] = Variable<String>(screen.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (isDefault.present) {
      map['is_default'] = Variable<bool>(isDefault.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SavedViewsTableCompanion(')
          ..write('id: $id, ')
          ..write('screen: $screen, ')
          ..write('name: $name, ')
          ..write('kind: $kind, ')
          ..write('payload: $payload, ')
          ..write('isDefault: $isDefault, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PlanItemsTableTable extends PlanItemsTable
    with TableInfo<$PlanItemsTableTable, PlanItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlanItemsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _templateIdMeta = const VerificationMeta(
    'templateId',
  );
  @override
  late final GeneratedColumn<String> templateId = GeneratedColumn<String>(
    'template_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('cycle'),
  );
  static const VerificationMeta _startDateMeta = const VerificationMeta(
    'startDate',
  );
  @override
  late final GeneratedColumn<String> startDate = GeneratedColumn<String>(
    'start_date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endDateMeta = const VerificationMeta(
    'endDate',
  );
  @override
  late final GeneratedColumn<String> endDate = GeneratedColumn<String>(
    'end_date',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _foreverMeta = const VerificationMeta(
    'forever',
  );
  @override
  late final GeneratedColumn<bool> forever = GeneratedColumn<bool>(
    'forever',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("forever" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _pausedMeta = const VerificationMeta('paused');
  @override
  late final GeneratedColumn<bool> paused = GeneratedColumn<bool>(
    'paused',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("paused" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _ruleMeta = const VerificationMeta('rule');
  @override
  late final GeneratedColumn<String> rule = GeneratedColumn<String>(
    'rule',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _collectionsMeta = const VerificationMeta(
    'collections',
  );
  @override
  late final GeneratedColumn<String> collections = GeneratedColumn<String>(
    'collections',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    templateId,
    kind,
    startDate,
    endDate,
    forever,
    paused,
    rule,
    collections,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'plan_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<PlanItem> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('template_id')) {
      context.handle(
        _templateIdMeta,
        templateId.isAcceptableOrUnknown(data['template_id']!, _templateIdMeta),
      );
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    }
    if (data.containsKey('start_date')) {
      context.handle(
        _startDateMeta,
        startDate.isAcceptableOrUnknown(data['start_date']!, _startDateMeta),
      );
    } else if (isInserting) {
      context.missing(_startDateMeta);
    }
    if (data.containsKey('end_date')) {
      context.handle(
        _endDateMeta,
        endDate.isAcceptableOrUnknown(data['end_date']!, _endDateMeta),
      );
    }
    if (data.containsKey('forever')) {
      context.handle(
        _foreverMeta,
        forever.isAcceptableOrUnknown(data['forever']!, _foreverMeta),
      );
    }
    if (data.containsKey('paused')) {
      context.handle(
        _pausedMeta,
        paused.isAcceptableOrUnknown(data['paused']!, _pausedMeta),
      );
    }
    if (data.containsKey('rule')) {
      context.handle(
        _ruleMeta,
        rule.isAcceptableOrUnknown(data['rule']!, _ruleMeta),
      );
    }
    if (data.containsKey('collections')) {
      context.handle(
        _collectionsMeta,
        collections.isAcceptableOrUnknown(
          data['collections']!,
          _collectionsMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PlanItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlanItem(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      templateId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}template_id'],
      ),
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      startDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}start_date'],
      )!,
      endDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}end_date'],
      ),
      forever: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}forever'],
      )!,
      paused: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}paused'],
      )!,
      rule: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rule'],
      )!,
      collections: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}collections'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $PlanItemsTableTable createAlias(String alias) {
    return $PlanItemsTableTable(attachedDatabase, alias);
  }
}

class PlanItem extends DataClass implements Insertable<PlanItem> {
  final String id;
  final String name;
  final String? templateId;
  final String kind;
  final String startDate;
  final String? endDate;
  final bool forever;
  final bool paused;
  final String rule;

  /// JSON list of the ids of the plan collections this item belongs to (schema
  /// v16; null = none). Ids of deleted collections are ignored when read.
  final String? collections;
  final String createdAt;
  final String updatedAt;
  const PlanItem({
    required this.id,
    required this.name,
    this.templateId,
    required this.kind,
    required this.startDate,
    this.endDate,
    required this.forever,
    required this.paused,
    required this.rule,
    this.collections,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || templateId != null) {
      map['template_id'] = Variable<String>(templateId);
    }
    map['kind'] = Variable<String>(kind);
    map['start_date'] = Variable<String>(startDate);
    if (!nullToAbsent || endDate != null) {
      map['end_date'] = Variable<String>(endDate);
    }
    map['forever'] = Variable<bool>(forever);
    map['paused'] = Variable<bool>(paused);
    map['rule'] = Variable<String>(rule);
    if (!nullToAbsent || collections != null) {
      map['collections'] = Variable<String>(collections);
    }
    map['created_at'] = Variable<String>(createdAt);
    map['updated_at'] = Variable<String>(updatedAt);
    return map;
  }

  PlanItemsTableCompanion toCompanion(bool nullToAbsent) {
    return PlanItemsTableCompanion(
      id: Value(id),
      name: Value(name),
      templateId: templateId == null && nullToAbsent
          ? const Value.absent()
          : Value(templateId),
      kind: Value(kind),
      startDate: Value(startDate),
      endDate: endDate == null && nullToAbsent
          ? const Value.absent()
          : Value(endDate),
      forever: Value(forever),
      paused: Value(paused),
      rule: Value(rule),
      collections: collections == null && nullToAbsent
          ? const Value.absent()
          : Value(collections),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory PlanItem.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlanItem(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      templateId: serializer.fromJson<String?>(json['templateId']),
      kind: serializer.fromJson<String>(json['kind']),
      startDate: serializer.fromJson<String>(json['startDate']),
      endDate: serializer.fromJson<String?>(json['endDate']),
      forever: serializer.fromJson<bool>(json['forever']),
      paused: serializer.fromJson<bool>(json['paused']),
      rule: serializer.fromJson<String>(json['rule']),
      collections: serializer.fromJson<String?>(json['collections']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'templateId': serializer.toJson<String?>(templateId),
      'kind': serializer.toJson<String>(kind),
      'startDate': serializer.toJson<String>(startDate),
      'endDate': serializer.toJson<String?>(endDate),
      'forever': serializer.toJson<bool>(forever),
      'paused': serializer.toJson<bool>(paused),
      'rule': serializer.toJson<String>(rule),
      'collections': serializer.toJson<String?>(collections),
      'createdAt': serializer.toJson<String>(createdAt),
      'updatedAt': serializer.toJson<String>(updatedAt),
    };
  }

  PlanItem copyWith({
    String? id,
    String? name,
    Value<String?> templateId = const Value.absent(),
    String? kind,
    String? startDate,
    Value<String?> endDate = const Value.absent(),
    bool? forever,
    bool? paused,
    String? rule,
    Value<String?> collections = const Value.absent(),
    String? createdAt,
    String? updatedAt,
  }) => PlanItem(
    id: id ?? this.id,
    name: name ?? this.name,
    templateId: templateId.present ? templateId.value : this.templateId,
    kind: kind ?? this.kind,
    startDate: startDate ?? this.startDate,
    endDate: endDate.present ? endDate.value : this.endDate,
    forever: forever ?? this.forever,
    paused: paused ?? this.paused,
    rule: rule ?? this.rule,
    collections: collections.present ? collections.value : this.collections,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  PlanItem copyWithCompanion(PlanItemsTableCompanion data) {
    return PlanItem(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      templateId: data.templateId.present
          ? data.templateId.value
          : this.templateId,
      kind: data.kind.present ? data.kind.value : this.kind,
      startDate: data.startDate.present ? data.startDate.value : this.startDate,
      endDate: data.endDate.present ? data.endDate.value : this.endDate,
      forever: data.forever.present ? data.forever.value : this.forever,
      paused: data.paused.present ? data.paused.value : this.paused,
      rule: data.rule.present ? data.rule.value : this.rule,
      collections: data.collections.present
          ? data.collections.value
          : this.collections,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlanItem(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('templateId: $templateId, ')
          ..write('kind: $kind, ')
          ..write('startDate: $startDate, ')
          ..write('endDate: $endDate, ')
          ..write('forever: $forever, ')
          ..write('paused: $paused, ')
          ..write('rule: $rule, ')
          ..write('collections: $collections, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    templateId,
    kind,
    startDate,
    endDate,
    forever,
    paused,
    rule,
    collections,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlanItem &&
          other.id == this.id &&
          other.name == this.name &&
          other.templateId == this.templateId &&
          other.kind == this.kind &&
          other.startDate == this.startDate &&
          other.endDate == this.endDate &&
          other.forever == this.forever &&
          other.paused == this.paused &&
          other.rule == this.rule &&
          other.collections == this.collections &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class PlanItemsTableCompanion extends UpdateCompanion<PlanItem> {
  final Value<String> id;
  final Value<String> name;
  final Value<String?> templateId;
  final Value<String> kind;
  final Value<String> startDate;
  final Value<String?> endDate;
  final Value<bool> forever;
  final Value<bool> paused;
  final Value<String> rule;
  final Value<String?> collections;
  final Value<String> createdAt;
  final Value<String> updatedAt;
  final Value<int> rowid;
  const PlanItemsTableCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.templateId = const Value.absent(),
    this.kind = const Value.absent(),
    this.startDate = const Value.absent(),
    this.endDate = const Value.absent(),
    this.forever = const Value.absent(),
    this.paused = const Value.absent(),
    this.rule = const Value.absent(),
    this.collections = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PlanItemsTableCompanion.insert({
    required String id,
    required String name,
    this.templateId = const Value.absent(),
    this.kind = const Value.absent(),
    required String startDate,
    this.endDate = const Value.absent(),
    this.forever = const Value.absent(),
    this.paused = const Value.absent(),
    this.rule = const Value.absent(),
    this.collections = const Value.absent(),
    required String createdAt,
    required String updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       startDate = Value(startDate),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<PlanItem> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? templateId,
    Expression<String>? kind,
    Expression<String>? startDate,
    Expression<String>? endDate,
    Expression<bool>? forever,
    Expression<bool>? paused,
    Expression<String>? rule,
    Expression<String>? collections,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (templateId != null) 'template_id': templateId,
      if (kind != null) 'kind': kind,
      if (startDate != null) 'start_date': startDate,
      if (endDate != null) 'end_date': endDate,
      if (forever != null) 'forever': forever,
      if (paused != null) 'paused': paused,
      if (rule != null) 'rule': rule,
      if (collections != null) 'collections': collections,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PlanItemsTableCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String?>? templateId,
    Value<String>? kind,
    Value<String>? startDate,
    Value<String?>? endDate,
    Value<bool>? forever,
    Value<bool>? paused,
    Value<String>? rule,
    Value<String?>? collections,
    Value<String>? createdAt,
    Value<String>? updatedAt,
    Value<int>? rowid,
  }) {
    return PlanItemsTableCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      templateId: templateId ?? this.templateId,
      kind: kind ?? this.kind,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      forever: forever ?? this.forever,
      paused: paused ?? this.paused,
      rule: rule ?? this.rule,
      collections: collections ?? this.collections,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (templateId.present) {
      map['template_id'] = Variable<String>(templateId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (startDate.present) {
      map['start_date'] = Variable<String>(startDate.value);
    }
    if (endDate.present) {
      map['end_date'] = Variable<String>(endDate.value);
    }
    if (forever.present) {
      map['forever'] = Variable<bool>(forever.value);
    }
    if (paused.present) {
      map['paused'] = Variable<bool>(paused.value);
    }
    if (rule.present) {
      map['rule'] = Variable<String>(rule.value);
    }
    if (collections.present) {
      map['collections'] = Variable<String>(collections.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlanItemsTableCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('templateId: $templateId, ')
          ..write('kind: $kind, ')
          ..write('startDate: $startDate, ')
          ..write('endDate: $endDate, ')
          ..write('forever: $forever, ')
          ..write('paused: $paused, ')
          ..write('rule: $rule, ')
          ..write('collections: $collections, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PlanOverridesTableTable extends PlanOverridesTable
    with TableInfo<$PlanOverridesTableTable, PlanOverride> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlanOverridesTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _planItemIdMeta = const VerificationMeta(
    'planItemId',
  );
  @override
  late final GeneratedColumn<String> planItemId = GeneratedColumn<String>(
    'plan_item_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES plan_items (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<String> date = GeneratedColumn<String>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _occurrenceIndexMeta = const VerificationMeta(
    'occurrenceIndex',
  );
  @override
  late final GeneratedColumn<int> occurrenceIndex = GeneratedColumn<int>(
    'occurrence_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _startMinMeta = const VerificationMeta(
    'startMin',
  );
  @override
  late final GeneratedColumn<int> startMin = GeneratedColumn<int>(
    'start_min',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationMinMeta = const VerificationMeta(
    'durationMin',
  );
  @override
  late final GeneratedColumn<int> durationMin = GeneratedColumn<int>(
    'duration_min',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _skippedMeta = const VerificationMeta(
    'skipped',
  );
  @override
  late final GeneratedColumn<bool> skipped = GeneratedColumn<bool>(
    'skipped',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("skipped" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    planItemId,
    date,
    occurrenceIndex,
    startMin,
    durationMin,
    name,
    skipped,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'plan_overrides';
  @override
  VerificationContext validateIntegrity(
    Insertable<PlanOverride> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('plan_item_id')) {
      context.handle(
        _planItemIdMeta,
        planItemId.isAcceptableOrUnknown(
          data['plan_item_id']!,
          _planItemIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_planItemIdMeta);
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('occurrence_index')) {
      context.handle(
        _occurrenceIndexMeta,
        occurrenceIndex.isAcceptableOrUnknown(
          data['occurrence_index']!,
          _occurrenceIndexMeta,
        ),
      );
    }
    if (data.containsKey('start_min')) {
      context.handle(
        _startMinMeta,
        startMin.isAcceptableOrUnknown(data['start_min']!, _startMinMeta),
      );
    }
    if (data.containsKey('duration_min')) {
      context.handle(
        _durationMinMeta,
        durationMin.isAcceptableOrUnknown(
          data['duration_min']!,
          _durationMinMeta,
        ),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('skipped')) {
      context.handle(
        _skippedMeta,
        skipped.isAcceptableOrUnknown(data['skipped']!, _skippedMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PlanOverride map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlanOverride(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      planItemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}plan_item_id'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}date'],
      )!,
      occurrenceIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}occurrence_index'],
      )!,
      startMin: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}start_min'],
      ),
      durationMin: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_min'],
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      ),
      skipped: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}skipped'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $PlanOverridesTableTable createAlias(String alias) {
    return $PlanOverridesTableTable(attachedDatabase, alias);
  }
}

class PlanOverride extends DataClass implements Insertable<PlanOverride> {
  final String id;
  final String planItemId;
  final String date;
  final int occurrenceIndex;
  final int? startMin;
  final int? durationMin;
  final String? name;
  final bool skipped;
  final String createdAt;
  final String updatedAt;
  const PlanOverride({
    required this.id,
    required this.planItemId,
    required this.date,
    required this.occurrenceIndex,
    this.startMin,
    this.durationMin,
    this.name,
    required this.skipped,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['plan_item_id'] = Variable<String>(planItemId);
    map['date'] = Variable<String>(date);
    map['occurrence_index'] = Variable<int>(occurrenceIndex);
    if (!nullToAbsent || startMin != null) {
      map['start_min'] = Variable<int>(startMin);
    }
    if (!nullToAbsent || durationMin != null) {
      map['duration_min'] = Variable<int>(durationMin);
    }
    if (!nullToAbsent || name != null) {
      map['name'] = Variable<String>(name);
    }
    map['skipped'] = Variable<bool>(skipped);
    map['created_at'] = Variable<String>(createdAt);
    map['updated_at'] = Variable<String>(updatedAt);
    return map;
  }

  PlanOverridesTableCompanion toCompanion(bool nullToAbsent) {
    return PlanOverridesTableCompanion(
      id: Value(id),
      planItemId: Value(planItemId),
      date: Value(date),
      occurrenceIndex: Value(occurrenceIndex),
      startMin: startMin == null && nullToAbsent
          ? const Value.absent()
          : Value(startMin),
      durationMin: durationMin == null && nullToAbsent
          ? const Value.absent()
          : Value(durationMin),
      name: name == null && nullToAbsent ? const Value.absent() : Value(name),
      skipped: Value(skipped),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory PlanOverride.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlanOverride(
      id: serializer.fromJson<String>(json['id']),
      planItemId: serializer.fromJson<String>(json['planItemId']),
      date: serializer.fromJson<String>(json['date']),
      occurrenceIndex: serializer.fromJson<int>(json['occurrenceIndex']),
      startMin: serializer.fromJson<int?>(json['startMin']),
      durationMin: serializer.fromJson<int?>(json['durationMin']),
      name: serializer.fromJson<String?>(json['name']),
      skipped: serializer.fromJson<bool>(json['skipped']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'planItemId': serializer.toJson<String>(planItemId),
      'date': serializer.toJson<String>(date),
      'occurrenceIndex': serializer.toJson<int>(occurrenceIndex),
      'startMin': serializer.toJson<int?>(startMin),
      'durationMin': serializer.toJson<int?>(durationMin),
      'name': serializer.toJson<String?>(name),
      'skipped': serializer.toJson<bool>(skipped),
      'createdAt': serializer.toJson<String>(createdAt),
      'updatedAt': serializer.toJson<String>(updatedAt),
    };
  }

  PlanOverride copyWith({
    String? id,
    String? planItemId,
    String? date,
    int? occurrenceIndex,
    Value<int?> startMin = const Value.absent(),
    Value<int?> durationMin = const Value.absent(),
    Value<String?> name = const Value.absent(),
    bool? skipped,
    String? createdAt,
    String? updatedAt,
  }) => PlanOverride(
    id: id ?? this.id,
    planItemId: planItemId ?? this.planItemId,
    date: date ?? this.date,
    occurrenceIndex: occurrenceIndex ?? this.occurrenceIndex,
    startMin: startMin.present ? startMin.value : this.startMin,
    durationMin: durationMin.present ? durationMin.value : this.durationMin,
    name: name.present ? name.value : this.name,
    skipped: skipped ?? this.skipped,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  PlanOverride copyWithCompanion(PlanOverridesTableCompanion data) {
    return PlanOverride(
      id: data.id.present ? data.id.value : this.id,
      planItemId: data.planItemId.present
          ? data.planItemId.value
          : this.planItemId,
      date: data.date.present ? data.date.value : this.date,
      occurrenceIndex: data.occurrenceIndex.present
          ? data.occurrenceIndex.value
          : this.occurrenceIndex,
      startMin: data.startMin.present ? data.startMin.value : this.startMin,
      durationMin: data.durationMin.present
          ? data.durationMin.value
          : this.durationMin,
      name: data.name.present ? data.name.value : this.name,
      skipped: data.skipped.present ? data.skipped.value : this.skipped,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlanOverride(')
          ..write('id: $id, ')
          ..write('planItemId: $planItemId, ')
          ..write('date: $date, ')
          ..write('occurrenceIndex: $occurrenceIndex, ')
          ..write('startMin: $startMin, ')
          ..write('durationMin: $durationMin, ')
          ..write('name: $name, ')
          ..write('skipped: $skipped, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    planItemId,
    date,
    occurrenceIndex,
    startMin,
    durationMin,
    name,
    skipped,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlanOverride &&
          other.id == this.id &&
          other.planItemId == this.planItemId &&
          other.date == this.date &&
          other.occurrenceIndex == this.occurrenceIndex &&
          other.startMin == this.startMin &&
          other.durationMin == this.durationMin &&
          other.name == this.name &&
          other.skipped == this.skipped &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class PlanOverridesTableCompanion extends UpdateCompanion<PlanOverride> {
  final Value<String> id;
  final Value<String> planItemId;
  final Value<String> date;
  final Value<int> occurrenceIndex;
  final Value<int?> startMin;
  final Value<int?> durationMin;
  final Value<String?> name;
  final Value<bool> skipped;
  final Value<String> createdAt;
  final Value<String> updatedAt;
  final Value<int> rowid;
  const PlanOverridesTableCompanion({
    this.id = const Value.absent(),
    this.planItemId = const Value.absent(),
    this.date = const Value.absent(),
    this.occurrenceIndex = const Value.absent(),
    this.startMin = const Value.absent(),
    this.durationMin = const Value.absent(),
    this.name = const Value.absent(),
    this.skipped = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PlanOverridesTableCompanion.insert({
    required String id,
    required String planItemId,
    required String date,
    this.occurrenceIndex = const Value.absent(),
    this.startMin = const Value.absent(),
    this.durationMin = const Value.absent(),
    this.name = const Value.absent(),
    this.skipped = const Value.absent(),
    required String createdAt,
    required String updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       planItemId = Value(planItemId),
       date = Value(date),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<PlanOverride> custom({
    Expression<String>? id,
    Expression<String>? planItemId,
    Expression<String>? date,
    Expression<int>? occurrenceIndex,
    Expression<int>? startMin,
    Expression<int>? durationMin,
    Expression<String>? name,
    Expression<bool>? skipped,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (planItemId != null) 'plan_item_id': planItemId,
      if (date != null) 'date': date,
      if (occurrenceIndex != null) 'occurrence_index': occurrenceIndex,
      if (startMin != null) 'start_min': startMin,
      if (durationMin != null) 'duration_min': durationMin,
      if (name != null) 'name': name,
      if (skipped != null) 'skipped': skipped,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PlanOverridesTableCompanion copyWith({
    Value<String>? id,
    Value<String>? planItemId,
    Value<String>? date,
    Value<int>? occurrenceIndex,
    Value<int?>? startMin,
    Value<int?>? durationMin,
    Value<String?>? name,
    Value<bool>? skipped,
    Value<String>? createdAt,
    Value<String>? updatedAt,
    Value<int>? rowid,
  }) {
    return PlanOverridesTableCompanion(
      id: id ?? this.id,
      planItemId: planItemId ?? this.planItemId,
      date: date ?? this.date,
      occurrenceIndex: occurrenceIndex ?? this.occurrenceIndex,
      startMin: startMin ?? this.startMin,
      durationMin: durationMin ?? this.durationMin,
      name: name ?? this.name,
      skipped: skipped ?? this.skipped,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (planItemId.present) {
      map['plan_item_id'] = Variable<String>(planItemId.value);
    }
    if (date.present) {
      map['date'] = Variable<String>(date.value);
    }
    if (occurrenceIndex.present) {
      map['occurrence_index'] = Variable<int>(occurrenceIndex.value);
    }
    if (startMin.present) {
      map['start_min'] = Variable<int>(startMin.value);
    }
    if (durationMin.present) {
      map['duration_min'] = Variable<int>(durationMin.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (skipped.present) {
      map['skipped'] = Variable<bool>(skipped.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlanOverridesTableCompanion(')
          ..write('id: $id, ')
          ..write('planItemId: $planItemId, ')
          ..write('date: $date, ')
          ..write('occurrenceIndex: $occurrenceIndex, ')
          ..write('startMin: $startMin, ')
          ..write('durationMin: $durationMin, ')
          ..write('name: $name, ')
          ..write('skipped: $skipped, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BudgetTxTemplatesTableTable extends BudgetTxTemplatesTable
    with TableInfo<$BudgetTxTemplatesTableTable, BudgetTxTemplate> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BudgetTxTemplatesTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
    'category_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _quantityMeta = const VerificationMeta(
    'quantity',
  );
  @override
  late final GeneratedColumn<double> quantity = GeneratedColumn<double>(
    'quantity',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _unitPriceMeta = const VerificationMeta(
    'unitPrice',
  );
  @override
  late final GeneratedColumn<double> unitPrice = GeneratedColumn<double>(
    'unit_price',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    categoryId,
    quantity,
    unitPrice,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'budget_tx_templates';
  @override
  VerificationContext validateIntegrity(
    Insertable<BudgetTxTemplate> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    }
    if (data.containsKey('quantity')) {
      context.handle(
        _quantityMeta,
        quantity.isAcceptableOrUnknown(data['quantity']!, _quantityMeta),
      );
    }
    if (data.containsKey('unit_price')) {
      context.handle(
        _unitPriceMeta,
        unitPrice.isAcceptableOrUnknown(data['unit_price']!, _unitPriceMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  BudgetTxTemplate map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BudgetTxTemplate(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category_id'],
      ),
      quantity: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}quantity'],
      )!,
      unitPrice: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}unit_price'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $BudgetTxTemplatesTableTable createAlias(String alias) {
    return $BudgetTxTemplatesTableTable(attachedDatabase, alias);
  }
}

class BudgetTxTemplate extends DataClass
    implements Insertable<BudgetTxTemplate> {
  final String id;
  final String name;
  final String? categoryId;
  final double quantity;
  final double? unitPrice;
  final String createdAt;
  final String updatedAt;
  const BudgetTxTemplate({
    required this.id,
    required this.name,
    this.categoryId,
    required this.quantity,
    this.unitPrice,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || categoryId != null) {
      map['category_id'] = Variable<String>(categoryId);
    }
    map['quantity'] = Variable<double>(quantity);
    if (!nullToAbsent || unitPrice != null) {
      map['unit_price'] = Variable<double>(unitPrice);
    }
    map['created_at'] = Variable<String>(createdAt);
    map['updated_at'] = Variable<String>(updatedAt);
    return map;
  }

  BudgetTxTemplatesTableCompanion toCompanion(bool nullToAbsent) {
    return BudgetTxTemplatesTableCompanion(
      id: Value(id),
      name: Value(name),
      categoryId: categoryId == null && nullToAbsent
          ? const Value.absent()
          : Value(categoryId),
      quantity: Value(quantity),
      unitPrice: unitPrice == null && nullToAbsent
          ? const Value.absent()
          : Value(unitPrice),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory BudgetTxTemplate.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BudgetTxTemplate(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      categoryId: serializer.fromJson<String?>(json['categoryId']),
      quantity: serializer.fromJson<double>(json['quantity']),
      unitPrice: serializer.fromJson<double?>(json['unitPrice']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'categoryId': serializer.toJson<String?>(categoryId),
      'quantity': serializer.toJson<double>(quantity),
      'unitPrice': serializer.toJson<double?>(unitPrice),
      'createdAt': serializer.toJson<String>(createdAt),
      'updatedAt': serializer.toJson<String>(updatedAt),
    };
  }

  BudgetTxTemplate copyWith({
    String? id,
    String? name,
    Value<String?> categoryId = const Value.absent(),
    double? quantity,
    Value<double?> unitPrice = const Value.absent(),
    String? createdAt,
    String? updatedAt,
  }) => BudgetTxTemplate(
    id: id ?? this.id,
    name: name ?? this.name,
    categoryId: categoryId.present ? categoryId.value : this.categoryId,
    quantity: quantity ?? this.quantity,
    unitPrice: unitPrice.present ? unitPrice.value : this.unitPrice,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  BudgetTxTemplate copyWithCompanion(BudgetTxTemplatesTableCompanion data) {
    return BudgetTxTemplate(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
      quantity: data.quantity.present ? data.quantity.value : this.quantity,
      unitPrice: data.unitPrice.present ? data.unitPrice.value : this.unitPrice,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BudgetTxTemplate(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('categoryId: $categoryId, ')
          ..write('quantity: $quantity, ')
          ..write('unitPrice: $unitPrice, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    categoryId,
    quantity,
    unitPrice,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BudgetTxTemplate &&
          other.id == this.id &&
          other.name == this.name &&
          other.categoryId == this.categoryId &&
          other.quantity == this.quantity &&
          other.unitPrice == this.unitPrice &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class BudgetTxTemplatesTableCompanion
    extends UpdateCompanion<BudgetTxTemplate> {
  final Value<String> id;
  final Value<String> name;
  final Value<String?> categoryId;
  final Value<double> quantity;
  final Value<double?> unitPrice;
  final Value<String> createdAt;
  final Value<String> updatedAt;
  final Value<int> rowid;
  const BudgetTxTemplatesTableCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.quantity = const Value.absent(),
    this.unitPrice = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BudgetTxTemplatesTableCompanion.insert({
    required String id,
    this.name = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.quantity = const Value.absent(),
    this.unitPrice = const Value.absent(),
    required String createdAt,
    required String updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<BudgetTxTemplate> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? categoryId,
    Expression<double>? quantity,
    Expression<double>? unitPrice,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (categoryId != null) 'category_id': categoryId,
      if (quantity != null) 'quantity': quantity,
      if (unitPrice != null) 'unit_price': unitPrice,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BudgetTxTemplatesTableCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String?>? categoryId,
    Value<double>? quantity,
    Value<double?>? unitPrice,
    Value<String>? createdAt,
    Value<String>? updatedAt,
    Value<int>? rowid,
  }) {
    return BudgetTxTemplatesTableCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      categoryId: categoryId ?? this.categoryId,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
    }
    if (quantity.present) {
      map['quantity'] = Variable<double>(quantity.value);
    }
    if (unitPrice.present) {
      map['unit_price'] = Variable<double>(unitPrice.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BudgetTxTemplatesTableCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('categoryId: $categoryId, ')
          ..write('quantity: $quantity, ')
          ..write('unitPrice: $unitPrice, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PlanCollectionsTableTable extends PlanCollectionsTable
    with TableInfo<$PlanCollectionsTableTable, PlanCollection> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlanCollectionsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _visibleMeta = const VerificationMeta(
    'visible',
  );
  @override
  late final GeneratedColumn<bool> visible = GeneratedColumn<bool>(
    'visible',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("visible" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    visible,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'plan_collections';
  @override
  VerificationContext validateIntegrity(
    Insertable<PlanCollection> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('visible')) {
      context.handle(
        _visibleMeta,
        visible.isAcceptableOrUnknown(data['visible']!, _visibleMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PlanCollection map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlanCollection(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      visible: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}visible'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $PlanCollectionsTableTable createAlias(String alias) {
    return $PlanCollectionsTableTable(attachedDatabase, alias);
  }
}

class PlanCollection extends DataClass implements Insertable<PlanCollection> {
  final String id;
  final String name;
  final bool visible;
  final String createdAt;
  final String updatedAt;
  const PlanCollection({
    required this.id,
    required this.name,
    required this.visible,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['visible'] = Variable<bool>(visible);
    map['created_at'] = Variable<String>(createdAt);
    map['updated_at'] = Variable<String>(updatedAt);
    return map;
  }

  PlanCollectionsTableCompanion toCompanion(bool nullToAbsent) {
    return PlanCollectionsTableCompanion(
      id: Value(id),
      name: Value(name),
      visible: Value(visible),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory PlanCollection.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlanCollection(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      visible: serializer.fromJson<bool>(json['visible']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'visible': serializer.toJson<bool>(visible),
      'createdAt': serializer.toJson<String>(createdAt),
      'updatedAt': serializer.toJson<String>(updatedAt),
    };
  }

  PlanCollection copyWith({
    String? id,
    String? name,
    bool? visible,
    String? createdAt,
    String? updatedAt,
  }) => PlanCollection(
    id: id ?? this.id,
    name: name ?? this.name,
    visible: visible ?? this.visible,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  PlanCollection copyWithCompanion(PlanCollectionsTableCompanion data) {
    return PlanCollection(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      visible: data.visible.present ? data.visible.value : this.visible,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlanCollection(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('visible: $visible, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, visible, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlanCollection &&
          other.id == this.id &&
          other.name == this.name &&
          other.visible == this.visible &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class PlanCollectionsTableCompanion extends UpdateCompanion<PlanCollection> {
  final Value<String> id;
  final Value<String> name;
  final Value<bool> visible;
  final Value<String> createdAt;
  final Value<String> updatedAt;
  final Value<int> rowid;
  const PlanCollectionsTableCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.visible = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PlanCollectionsTableCompanion.insert({
    required String id,
    required String name,
    this.visible = const Value.absent(),
    required String createdAt,
    required String updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<PlanCollection> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<bool>? visible,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (visible != null) 'visible': visible,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PlanCollectionsTableCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<bool>? visible,
    Value<String>? createdAt,
    Value<String>? updatedAt,
    Value<int>? rowid,
  }) {
    return PlanCollectionsTableCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      visible: visible ?? this.visible,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (visible.present) {
      map['visible'] = Variable<bool>(visible.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlanCollectionsTableCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('visible: $visible, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FormsTableTable extends FormsTable
    with TableInfo<$FormsTableTable, FormRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FormsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    payload,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'forms';
  @override
  VerificationContext validateIntegrity(
    Insertable<FormRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FormRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FormRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $FormsTableTable createAlias(String alias) {
    return $FormsTableTable(attachedDatabase, alias);
  }
}

class FormRow extends DataClass implements Insertable<FormRow> {
  final String id;
  final String name;
  final String payload;
  final String createdAt;
  final String updatedAt;
  const FormRow({
    required this.id,
    required this.name,
    required this.payload,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['payload'] = Variable<String>(payload);
    map['created_at'] = Variable<String>(createdAt);
    map['updated_at'] = Variable<String>(updatedAt);
    return map;
  }

  FormsTableCompanion toCompanion(bool nullToAbsent) {
    return FormsTableCompanion(
      id: Value(id),
      name: Value(name),
      payload: Value(payload),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory FormRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FormRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      payload: serializer.fromJson<String>(json['payload']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'payload': serializer.toJson<String>(payload),
      'createdAt': serializer.toJson<String>(createdAt),
      'updatedAt': serializer.toJson<String>(updatedAt),
    };
  }

  FormRow copyWith({
    String? id,
    String? name,
    String? payload,
    String? createdAt,
    String? updatedAt,
  }) => FormRow(
    id: id ?? this.id,
    name: name ?? this.name,
    payload: payload ?? this.payload,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  FormRow copyWithCompanion(FormsTableCompanion data) {
    return FormRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      payload: data.payload.present ? data.payload.value : this.payload,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FormRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('payload: $payload, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, payload, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FormRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.payload == this.payload &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class FormsTableCompanion extends UpdateCompanion<FormRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> payload;
  final Value<String> createdAt;
  final Value<String> updatedAt;
  final Value<int> rowid;
  const FormsTableCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.payload = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FormsTableCompanion.insert({
    required String id,
    this.name = const Value.absent(),
    this.payload = const Value.absent(),
    required String createdAt,
    required String updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<FormRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? payload,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (payload != null) 'payload': payload,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FormsTableCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? payload,
    Value<String>? createdAt,
    Value<String>? updatedAt,
    Value<int>? rowid,
  }) {
    return FormsTableCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      payload: payload ?? this.payload,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FormsTableCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('payload: $payload, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CalendarZonesTableTable extends CalendarZonesTable
    with TableInfo<$CalendarZonesTableTable, CalendarZone> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CalendarZonesTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tzMeta = const VerificationMeta('tz');
  @override
  late final GeneratedColumn<String> tz = GeneratedColumn<String>(
    'tz',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    tz,
    label,
    position,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'calendar_zones';
  @override
  VerificationContext validateIntegrity(
    Insertable<CalendarZone> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('tz')) {
      context.handle(_tzMeta, tz.isAcceptableOrUnknown(data['tz']!, _tzMeta));
    } else if (isInserting) {
      context.missing(_tzMeta);
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CalendarZone map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CalendarZone(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      tz: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tz'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $CalendarZonesTableTable createAlias(String alias) {
    return $CalendarZonesTableTable(attachedDatabase, alias);
  }
}

class CalendarZone extends DataClass implements Insertable<CalendarZone> {
  final String id;
  final String tz;
  final String label;
  final int position;
  final String createdAt;
  final String updatedAt;
  const CalendarZone({
    required this.id,
    required this.tz,
    required this.label,
    required this.position,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['tz'] = Variable<String>(tz);
    map['label'] = Variable<String>(label);
    map['position'] = Variable<int>(position);
    map['created_at'] = Variable<String>(createdAt);
    map['updated_at'] = Variable<String>(updatedAt);
    return map;
  }

  CalendarZonesTableCompanion toCompanion(bool nullToAbsent) {
    return CalendarZonesTableCompanion(
      id: Value(id),
      tz: Value(tz),
      label: Value(label),
      position: Value(position),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory CalendarZone.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CalendarZone(
      id: serializer.fromJson<String>(json['id']),
      tz: serializer.fromJson<String>(json['tz']),
      label: serializer.fromJson<String>(json['label']),
      position: serializer.fromJson<int>(json['position']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'tz': serializer.toJson<String>(tz),
      'label': serializer.toJson<String>(label),
      'position': serializer.toJson<int>(position),
      'createdAt': serializer.toJson<String>(createdAt),
      'updatedAt': serializer.toJson<String>(updatedAt),
    };
  }

  CalendarZone copyWith({
    String? id,
    String? tz,
    String? label,
    int? position,
    String? createdAt,
    String? updatedAt,
  }) => CalendarZone(
    id: id ?? this.id,
    tz: tz ?? this.tz,
    label: label ?? this.label,
    position: position ?? this.position,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  CalendarZone copyWithCompanion(CalendarZonesTableCompanion data) {
    return CalendarZone(
      id: data.id.present ? data.id.value : this.id,
      tz: data.tz.present ? data.tz.value : this.tz,
      label: data.label.present ? data.label.value : this.label,
      position: data.position.present ? data.position.value : this.position,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CalendarZone(')
          ..write('id: $id, ')
          ..write('tz: $tz, ')
          ..write('label: $label, ')
          ..write('position: $position, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, tz, label, position, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CalendarZone &&
          other.id == this.id &&
          other.tz == this.tz &&
          other.label == this.label &&
          other.position == this.position &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class CalendarZonesTableCompanion extends UpdateCompanion<CalendarZone> {
  final Value<String> id;
  final Value<String> tz;
  final Value<String> label;
  final Value<int> position;
  final Value<String> createdAt;
  final Value<String> updatedAt;
  final Value<int> rowid;
  const CalendarZonesTableCompanion({
    this.id = const Value.absent(),
    this.tz = const Value.absent(),
    this.label = const Value.absent(),
    this.position = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CalendarZonesTableCompanion.insert({
    required String id,
    required String tz,
    this.label = const Value.absent(),
    this.position = const Value.absent(),
    required String createdAt,
    required String updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       tz = Value(tz),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<CalendarZone> custom({
    Expression<String>? id,
    Expression<String>? tz,
    Expression<String>? label,
    Expression<int>? position,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (tz != null) 'tz': tz,
      if (label != null) 'label': label,
      if (position != null) 'position': position,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CalendarZonesTableCompanion copyWith({
    Value<String>? id,
    Value<String>? tz,
    Value<String>? label,
    Value<int>? position,
    Value<String>? createdAt,
    Value<String>? updatedAt,
    Value<int>? rowid,
  }) {
    return CalendarZonesTableCompanion(
      id: id ?? this.id,
      tz: tz ?? this.tz,
      label: label ?? this.label,
      position: position ?? this.position,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (tz.present) {
      map['tz'] = Variable<String>(tz.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CalendarZonesTableCompanion(')
          ..write('id: $id, ')
          ..write('tz: $tz, ')
          ..write('label: $label, ')
          ..write('position: $position, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AiThreadsTableTable extends AiThreadsTable
    with TableInfo<$AiThreadsTableTable, AiThread> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AiThreadsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _archivedMeta = const VerificationMeta(
    'archived',
  );
  @override
  late final GeneratedColumn<bool> archived = GeneratedColumn<bool>(
    'archived',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("archived" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    archived,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ai_threads';
  @override
  VerificationContext validateIntegrity(
    Insertable<AiThread> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('archived')) {
      context.handle(
        _archivedMeta,
        archived.isAcceptableOrUnknown(data['archived']!, _archivedMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AiThread map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AiThread(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      archived: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}archived'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $AiThreadsTableTable createAlias(String alias) {
    return $AiThreadsTableTable(attachedDatabase, alias);
  }
}

class AiThread extends DataClass implements Insertable<AiThread> {
  final String id;
  final String title;
  final bool archived;
  final String createdAt;
  final String updatedAt;
  const AiThread({
    required this.id,
    required this.title,
    required this.archived,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['archived'] = Variable<bool>(archived);
    map['created_at'] = Variable<String>(createdAt);
    map['updated_at'] = Variable<String>(updatedAt);
    return map;
  }

  AiThreadsTableCompanion toCompanion(bool nullToAbsent) {
    return AiThreadsTableCompanion(
      id: Value(id),
      title: Value(title),
      archived: Value(archived),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory AiThread.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AiThread(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      archived: serializer.fromJson<bool>(json['archived']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'archived': serializer.toJson<bool>(archived),
      'createdAt': serializer.toJson<String>(createdAt),
      'updatedAt': serializer.toJson<String>(updatedAt),
    };
  }

  AiThread copyWith({
    String? id,
    String? title,
    bool? archived,
    String? createdAt,
    String? updatedAt,
  }) => AiThread(
    id: id ?? this.id,
    title: title ?? this.title,
    archived: archived ?? this.archived,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  AiThread copyWithCompanion(AiThreadsTableCompanion data) {
    return AiThread(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      archived: data.archived.present ? data.archived.value : this.archived,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AiThread(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('archived: $archived, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, title, archived, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AiThread &&
          other.id == this.id &&
          other.title == this.title &&
          other.archived == this.archived &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class AiThreadsTableCompanion extends UpdateCompanion<AiThread> {
  final Value<String> id;
  final Value<String> title;
  final Value<bool> archived;
  final Value<String> createdAt;
  final Value<String> updatedAt;
  final Value<int> rowid;
  const AiThreadsTableCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.archived = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AiThreadsTableCompanion.insert({
    required String id,
    this.title = const Value.absent(),
    this.archived = const Value.absent(),
    required String createdAt,
    required String updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<AiThread> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<bool>? archived,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (archived != null) 'archived': archived,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AiThreadsTableCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<bool>? archived,
    Value<String>? createdAt,
    Value<String>? updatedAt,
    Value<int>? rowid,
  }) {
    return AiThreadsTableCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      archived: archived ?? this.archived,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (archived.present) {
      map['archived'] = Variable<bool>(archived.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AiThreadsTableCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('archived: $archived, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AiMessagesTableTable extends AiMessagesTable
    with TableInfo<$AiMessagesTableTable, AiMessage> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AiMessagesTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _threadIdMeta = const VerificationMeta(
    'threadId',
  );
  @override
  late final GeneratedColumn<String> threadId = GeneratedColumn<String>(
    'thread_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
    'role',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('user'),
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('text'),
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _contentJsonMeta = const VerificationMeta(
    'contentJson',
  );
  @override
  late final GeneratedColumn<String> contentJson = GeneratedColumn<String>(
    'content_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _jobIdMeta = const VerificationMeta('jobId');
  @override
  late final GeneratedColumn<String> jobId = GeneratedColumn<String>(
    'job_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    threadId,
    role,
    kind,
    body,
    contentJson,
    jobId,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ai_messages';
  @override
  VerificationContext validateIntegrity(
    Insertable<AiMessage> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('thread_id')) {
      context.handle(
        _threadIdMeta,
        threadId.isAcceptableOrUnknown(data['thread_id']!, _threadIdMeta),
      );
    } else if (isInserting) {
      context.missing(_threadIdMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    }
    if (data.containsKey('content_json')) {
      context.handle(
        _contentJsonMeta,
        contentJson.isAcceptableOrUnknown(
          data['content_json']!,
          _contentJsonMeta,
        ),
      );
    }
    if (data.containsKey('job_id')) {
      context.handle(
        _jobIdMeta,
        jobId.isAcceptableOrUnknown(data['job_id']!, _jobIdMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AiMessage map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AiMessage(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      threadId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thread_id'],
      )!,
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      contentJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_json'],
      )!,
      jobId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}job_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $AiMessagesTableTable createAlias(String alias) {
    return $AiMessagesTableTable(attachedDatabase, alias);
  }
}

class AiMessage extends DataClass implements Insertable<AiMessage> {
  final String id;
  final String threadId;
  final String role;
  final String kind;
  final String body;
  final String contentJson;
  final String? jobId;
  final String createdAt;
  final String updatedAt;
  const AiMessage({
    required this.id,
    required this.threadId,
    required this.role,
    required this.kind,
    required this.body,
    required this.contentJson,
    this.jobId,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['thread_id'] = Variable<String>(threadId);
    map['role'] = Variable<String>(role);
    map['kind'] = Variable<String>(kind);
    map['body'] = Variable<String>(body);
    map['content_json'] = Variable<String>(contentJson);
    if (!nullToAbsent || jobId != null) {
      map['job_id'] = Variable<String>(jobId);
    }
    map['created_at'] = Variable<String>(createdAt);
    map['updated_at'] = Variable<String>(updatedAt);
    return map;
  }

  AiMessagesTableCompanion toCompanion(bool nullToAbsent) {
    return AiMessagesTableCompanion(
      id: Value(id),
      threadId: Value(threadId),
      role: Value(role),
      kind: Value(kind),
      body: Value(body),
      contentJson: Value(contentJson),
      jobId: jobId == null && nullToAbsent
          ? const Value.absent()
          : Value(jobId),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory AiMessage.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AiMessage(
      id: serializer.fromJson<String>(json['id']),
      threadId: serializer.fromJson<String>(json['threadId']),
      role: serializer.fromJson<String>(json['role']),
      kind: serializer.fromJson<String>(json['kind']),
      body: serializer.fromJson<String>(json['body']),
      contentJson: serializer.fromJson<String>(json['contentJson']),
      jobId: serializer.fromJson<String?>(json['jobId']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'threadId': serializer.toJson<String>(threadId),
      'role': serializer.toJson<String>(role),
      'kind': serializer.toJson<String>(kind),
      'body': serializer.toJson<String>(body),
      'contentJson': serializer.toJson<String>(contentJson),
      'jobId': serializer.toJson<String?>(jobId),
      'createdAt': serializer.toJson<String>(createdAt),
      'updatedAt': serializer.toJson<String>(updatedAt),
    };
  }

  AiMessage copyWith({
    String? id,
    String? threadId,
    String? role,
    String? kind,
    String? body,
    String? contentJson,
    Value<String?> jobId = const Value.absent(),
    String? createdAt,
    String? updatedAt,
  }) => AiMessage(
    id: id ?? this.id,
    threadId: threadId ?? this.threadId,
    role: role ?? this.role,
    kind: kind ?? this.kind,
    body: body ?? this.body,
    contentJson: contentJson ?? this.contentJson,
    jobId: jobId.present ? jobId.value : this.jobId,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  AiMessage copyWithCompanion(AiMessagesTableCompanion data) {
    return AiMessage(
      id: data.id.present ? data.id.value : this.id,
      threadId: data.threadId.present ? data.threadId.value : this.threadId,
      role: data.role.present ? data.role.value : this.role,
      kind: data.kind.present ? data.kind.value : this.kind,
      body: data.body.present ? data.body.value : this.body,
      contentJson: data.contentJson.present
          ? data.contentJson.value
          : this.contentJson,
      jobId: data.jobId.present ? data.jobId.value : this.jobId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AiMessage(')
          ..write('id: $id, ')
          ..write('threadId: $threadId, ')
          ..write('role: $role, ')
          ..write('kind: $kind, ')
          ..write('body: $body, ')
          ..write('contentJson: $contentJson, ')
          ..write('jobId: $jobId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    threadId,
    role,
    kind,
    body,
    contentJson,
    jobId,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AiMessage &&
          other.id == this.id &&
          other.threadId == this.threadId &&
          other.role == this.role &&
          other.kind == this.kind &&
          other.body == this.body &&
          other.contentJson == this.contentJson &&
          other.jobId == this.jobId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class AiMessagesTableCompanion extends UpdateCompanion<AiMessage> {
  final Value<String> id;
  final Value<String> threadId;
  final Value<String> role;
  final Value<String> kind;
  final Value<String> body;
  final Value<String> contentJson;
  final Value<String?> jobId;
  final Value<String> createdAt;
  final Value<String> updatedAt;
  final Value<int> rowid;
  const AiMessagesTableCompanion({
    this.id = const Value.absent(),
    this.threadId = const Value.absent(),
    this.role = const Value.absent(),
    this.kind = const Value.absent(),
    this.body = const Value.absent(),
    this.contentJson = const Value.absent(),
    this.jobId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AiMessagesTableCompanion.insert({
    required String id,
    required String threadId,
    this.role = const Value.absent(),
    this.kind = const Value.absent(),
    this.body = const Value.absent(),
    this.contentJson = const Value.absent(),
    this.jobId = const Value.absent(),
    required String createdAt,
    required String updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       threadId = Value(threadId),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<AiMessage> custom({
    Expression<String>? id,
    Expression<String>? threadId,
    Expression<String>? role,
    Expression<String>? kind,
    Expression<String>? body,
    Expression<String>? contentJson,
    Expression<String>? jobId,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (threadId != null) 'thread_id': threadId,
      if (role != null) 'role': role,
      if (kind != null) 'kind': kind,
      if (body != null) 'body': body,
      if (contentJson != null) 'content_json': contentJson,
      if (jobId != null) 'job_id': jobId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AiMessagesTableCompanion copyWith({
    Value<String>? id,
    Value<String>? threadId,
    Value<String>? role,
    Value<String>? kind,
    Value<String>? body,
    Value<String>? contentJson,
    Value<String?>? jobId,
    Value<String>? createdAt,
    Value<String>? updatedAt,
    Value<int>? rowid,
  }) {
    return AiMessagesTableCompanion(
      id: id ?? this.id,
      threadId: threadId ?? this.threadId,
      role: role ?? this.role,
      kind: kind ?? this.kind,
      body: body ?? this.body,
      contentJson: contentJson ?? this.contentJson,
      jobId: jobId ?? this.jobId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (threadId.present) {
      map['thread_id'] = Variable<String>(threadId.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (contentJson.present) {
      map['content_json'] = Variable<String>(contentJson.value);
    }
    if (jobId.present) {
      map['job_id'] = Variable<String>(jobId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AiMessagesTableCompanion(')
          ..write('id: $id, ')
          ..write('threadId: $threadId, ')
          ..write('role: $role, ')
          ..write('kind: $kind, ')
          ..write('body: $body, ')
          ..write('contentJson: $contentJson, ')
          ..write('jobId: $jobId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AiJobsTableTable extends AiJobsTable
    with TableInfo<$AiJobsTableTable, AiJob> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AiJobsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _threadIdMeta = const VerificationMeta(
    'threadId',
  );
  @override
  late final GeneratedColumn<String> threadId = GeneratedColumn<String>(
    'thread_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('receipt'),
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('queued'),
  );
  static const VerificationMeta _stageMeta = const VerificationMeta('stage');
  @override
  late final GeneratedColumn<String> stage = GeneratedColumn<String>(
    'stage',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _errorMeta = const VerificationMeta('error');
  @override
  late final GeneratedColumn<String> error = GeneratedColumn<String>(
    'error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    threadId,
    kind,
    state,
    stage,
    payloadJson,
    error,
    attempts,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ai_jobs';
  @override
  VerificationContext validateIntegrity(
    Insertable<AiJob> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('thread_id')) {
      context.handle(
        _threadIdMeta,
        threadId.isAcceptableOrUnknown(data['thread_id']!, _threadIdMeta),
      );
    } else if (isInserting) {
      context.missing(_threadIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    }
    if (data.containsKey('stage')) {
      context.handle(
        _stageMeta,
        stage.isAcceptableOrUnknown(data['stage']!, _stageMeta),
      );
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    }
    if (data.containsKey('error')) {
      context.handle(
        _errorMeta,
        error.isAcceptableOrUnknown(data['error']!, _errorMeta),
      );
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AiJob map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AiJob(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      threadId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thread_id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      stage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stage'],
      )!,
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
      error: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error'],
      ),
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $AiJobsTableTable createAlias(String alias) {
    return $AiJobsTableTable(attachedDatabase, alias);
  }
}

class AiJob extends DataClass implements Insertable<AiJob> {
  final String id;
  final String threadId;
  final String kind;
  final String state;
  final String stage;
  final String payloadJson;
  final String? error;
  final int attempts;
  final String createdAt;
  final String updatedAt;
  const AiJob({
    required this.id,
    required this.threadId,
    required this.kind,
    required this.state,
    required this.stage,
    required this.payloadJson,
    this.error,
    required this.attempts,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['thread_id'] = Variable<String>(threadId);
    map['kind'] = Variable<String>(kind);
    map['state'] = Variable<String>(state);
    map['stage'] = Variable<String>(stage);
    map['payload_json'] = Variable<String>(payloadJson);
    if (!nullToAbsent || error != null) {
      map['error'] = Variable<String>(error);
    }
    map['attempts'] = Variable<int>(attempts);
    map['created_at'] = Variable<String>(createdAt);
    map['updated_at'] = Variable<String>(updatedAt);
    return map;
  }

  AiJobsTableCompanion toCompanion(bool nullToAbsent) {
    return AiJobsTableCompanion(
      id: Value(id),
      threadId: Value(threadId),
      kind: Value(kind),
      state: Value(state),
      stage: Value(stage),
      payloadJson: Value(payloadJson),
      error: error == null && nullToAbsent
          ? const Value.absent()
          : Value(error),
      attempts: Value(attempts),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory AiJob.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AiJob(
      id: serializer.fromJson<String>(json['id']),
      threadId: serializer.fromJson<String>(json['threadId']),
      kind: serializer.fromJson<String>(json['kind']),
      state: serializer.fromJson<String>(json['state']),
      stage: serializer.fromJson<String>(json['stage']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      error: serializer.fromJson<String?>(json['error']),
      attempts: serializer.fromJson<int>(json['attempts']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'threadId': serializer.toJson<String>(threadId),
      'kind': serializer.toJson<String>(kind),
      'state': serializer.toJson<String>(state),
      'stage': serializer.toJson<String>(stage),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'error': serializer.toJson<String?>(error),
      'attempts': serializer.toJson<int>(attempts),
      'createdAt': serializer.toJson<String>(createdAt),
      'updatedAt': serializer.toJson<String>(updatedAt),
    };
  }

  AiJob copyWith({
    String? id,
    String? threadId,
    String? kind,
    String? state,
    String? stage,
    String? payloadJson,
    Value<String?> error = const Value.absent(),
    int? attempts,
    String? createdAt,
    String? updatedAt,
  }) => AiJob(
    id: id ?? this.id,
    threadId: threadId ?? this.threadId,
    kind: kind ?? this.kind,
    state: state ?? this.state,
    stage: stage ?? this.stage,
    payloadJson: payloadJson ?? this.payloadJson,
    error: error.present ? error.value : this.error,
    attempts: attempts ?? this.attempts,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  AiJob copyWithCompanion(AiJobsTableCompanion data) {
    return AiJob(
      id: data.id.present ? data.id.value : this.id,
      threadId: data.threadId.present ? data.threadId.value : this.threadId,
      kind: data.kind.present ? data.kind.value : this.kind,
      state: data.state.present ? data.state.value : this.state,
      stage: data.stage.present ? data.stage.value : this.stage,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
      error: data.error.present ? data.error.value : this.error,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AiJob(')
          ..write('id: $id, ')
          ..write('threadId: $threadId, ')
          ..write('kind: $kind, ')
          ..write('state: $state, ')
          ..write('stage: $stage, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('error: $error, ')
          ..write('attempts: $attempts, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    threadId,
    kind,
    state,
    stage,
    payloadJson,
    error,
    attempts,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AiJob &&
          other.id == this.id &&
          other.threadId == this.threadId &&
          other.kind == this.kind &&
          other.state == this.state &&
          other.stage == this.stage &&
          other.payloadJson == this.payloadJson &&
          other.error == this.error &&
          other.attempts == this.attempts &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class AiJobsTableCompanion extends UpdateCompanion<AiJob> {
  final Value<String> id;
  final Value<String> threadId;
  final Value<String> kind;
  final Value<String> state;
  final Value<String> stage;
  final Value<String> payloadJson;
  final Value<String?> error;
  final Value<int> attempts;
  final Value<String> createdAt;
  final Value<String> updatedAt;
  final Value<int> rowid;
  const AiJobsTableCompanion({
    this.id = const Value.absent(),
    this.threadId = const Value.absent(),
    this.kind = const Value.absent(),
    this.state = const Value.absent(),
    this.stage = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.error = const Value.absent(),
    this.attempts = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AiJobsTableCompanion.insert({
    required String id,
    required String threadId,
    this.kind = const Value.absent(),
    this.state = const Value.absent(),
    this.stage = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.error = const Value.absent(),
    this.attempts = const Value.absent(),
    required String createdAt,
    required String updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       threadId = Value(threadId),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<AiJob> custom({
    Expression<String>? id,
    Expression<String>? threadId,
    Expression<String>? kind,
    Expression<String>? state,
    Expression<String>? stage,
    Expression<String>? payloadJson,
    Expression<String>? error,
    Expression<int>? attempts,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (threadId != null) 'thread_id': threadId,
      if (kind != null) 'kind': kind,
      if (state != null) 'state': state,
      if (stage != null) 'stage': stage,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (error != null) 'error': error,
      if (attempts != null) 'attempts': attempts,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AiJobsTableCompanion copyWith({
    Value<String>? id,
    Value<String>? threadId,
    Value<String>? kind,
    Value<String>? state,
    Value<String>? stage,
    Value<String>? payloadJson,
    Value<String?>? error,
    Value<int>? attempts,
    Value<String>? createdAt,
    Value<String>? updatedAt,
    Value<int>? rowid,
  }) {
    return AiJobsTableCompanion(
      id: id ?? this.id,
      threadId: threadId ?? this.threadId,
      kind: kind ?? this.kind,
      state: state ?? this.state,
      stage: stage ?? this.stage,
      payloadJson: payloadJson ?? this.payloadJson,
      error: error ?? this.error,
      attempts: attempts ?? this.attempts,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (threadId.present) {
      map['thread_id'] = Variable<String>(threadId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (stage.present) {
      map['stage'] = Variable<String>(stage.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (error.present) {
      map['error'] = Variable<String>(error.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AiJobsTableCompanion(')
          ..write('id: $id, ')
          ..write('threadId: $threadId, ')
          ..write('kind: $kind, ')
          ..write('state: $state, ')
          ..write('stage: $stage, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('error: $error, ')
          ..write('attempts: $attempts, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AiBatchesTableTable extends AiBatchesTable
    with TableInfo<$AiBatchesTableTable, AiBatch> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AiBatchesTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _jobIdMeta = const VerificationMeta('jobId');
  @override
  late final GeneratedColumn<String> jobId = GeneratedColumn<String>(
    'job_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _threadIdMeta = const VerificationMeta(
    'threadId',
  );
  @override
  late final GeneratedColumn<String> threadId = GeneratedColumn<String>(
    'thread_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _messageIdMeta = const VerificationMeta(
    'messageId',
  );
  @override
  late final GeneratedColumn<String> messageId = GeneratedColumn<String>(
    'message_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _summaryMeta = const VerificationMeta(
    'summary',
  );
  @override
  late final GeneratedColumn<String> summary = GeneratedColumn<String>(
    'summary',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _undoneAtMeta = const VerificationMeta(
    'undoneAt',
  );
  @override
  late final GeneratedColumn<String> undoneAt = GeneratedColumn<String>(
    'undone_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    jobId,
    threadId,
    messageId,
    summary,
    undoneAt,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ai_batches';
  @override
  VerificationContext validateIntegrity(
    Insertable<AiBatch> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('job_id')) {
      context.handle(
        _jobIdMeta,
        jobId.isAcceptableOrUnknown(data['job_id']!, _jobIdMeta),
      );
    } else if (isInserting) {
      context.missing(_jobIdMeta);
    }
    if (data.containsKey('thread_id')) {
      context.handle(
        _threadIdMeta,
        threadId.isAcceptableOrUnknown(data['thread_id']!, _threadIdMeta),
      );
    } else if (isInserting) {
      context.missing(_threadIdMeta);
    }
    if (data.containsKey('message_id')) {
      context.handle(
        _messageIdMeta,
        messageId.isAcceptableOrUnknown(data['message_id']!, _messageIdMeta),
      );
    }
    if (data.containsKey('summary')) {
      context.handle(
        _summaryMeta,
        summary.isAcceptableOrUnknown(data['summary']!, _summaryMeta),
      );
    }
    if (data.containsKey('undone_at')) {
      context.handle(
        _undoneAtMeta,
        undoneAt.isAcceptableOrUnknown(data['undone_at']!, _undoneAtMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AiBatch map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AiBatch(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      jobId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}job_id'],
      )!,
      threadId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thread_id'],
      )!,
      messageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message_id'],
      ),
      summary: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}summary'],
      )!,
      undoneAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}undone_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $AiBatchesTableTable createAlias(String alias) {
    return $AiBatchesTableTable(attachedDatabase, alias);
  }
}

class AiBatch extends DataClass implements Insertable<AiBatch> {
  final String id;
  final String jobId;
  final String threadId;
  final String? messageId;
  final String summary;
  final String? undoneAt;
  final String createdAt;
  final String updatedAt;
  const AiBatch({
    required this.id,
    required this.jobId,
    required this.threadId,
    this.messageId,
    required this.summary,
    this.undoneAt,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['job_id'] = Variable<String>(jobId);
    map['thread_id'] = Variable<String>(threadId);
    if (!nullToAbsent || messageId != null) {
      map['message_id'] = Variable<String>(messageId);
    }
    map['summary'] = Variable<String>(summary);
    if (!nullToAbsent || undoneAt != null) {
      map['undone_at'] = Variable<String>(undoneAt);
    }
    map['created_at'] = Variable<String>(createdAt);
    map['updated_at'] = Variable<String>(updatedAt);
    return map;
  }

  AiBatchesTableCompanion toCompanion(bool nullToAbsent) {
    return AiBatchesTableCompanion(
      id: Value(id),
      jobId: Value(jobId),
      threadId: Value(threadId),
      messageId: messageId == null && nullToAbsent
          ? const Value.absent()
          : Value(messageId),
      summary: Value(summary),
      undoneAt: undoneAt == null && nullToAbsent
          ? const Value.absent()
          : Value(undoneAt),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory AiBatch.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AiBatch(
      id: serializer.fromJson<String>(json['id']),
      jobId: serializer.fromJson<String>(json['jobId']),
      threadId: serializer.fromJson<String>(json['threadId']),
      messageId: serializer.fromJson<String?>(json['messageId']),
      summary: serializer.fromJson<String>(json['summary']),
      undoneAt: serializer.fromJson<String?>(json['undoneAt']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'jobId': serializer.toJson<String>(jobId),
      'threadId': serializer.toJson<String>(threadId),
      'messageId': serializer.toJson<String?>(messageId),
      'summary': serializer.toJson<String>(summary),
      'undoneAt': serializer.toJson<String?>(undoneAt),
      'createdAt': serializer.toJson<String>(createdAt),
      'updatedAt': serializer.toJson<String>(updatedAt),
    };
  }

  AiBatch copyWith({
    String? id,
    String? jobId,
    String? threadId,
    Value<String?> messageId = const Value.absent(),
    String? summary,
    Value<String?> undoneAt = const Value.absent(),
    String? createdAt,
    String? updatedAt,
  }) => AiBatch(
    id: id ?? this.id,
    jobId: jobId ?? this.jobId,
    threadId: threadId ?? this.threadId,
    messageId: messageId.present ? messageId.value : this.messageId,
    summary: summary ?? this.summary,
    undoneAt: undoneAt.present ? undoneAt.value : this.undoneAt,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  AiBatch copyWithCompanion(AiBatchesTableCompanion data) {
    return AiBatch(
      id: data.id.present ? data.id.value : this.id,
      jobId: data.jobId.present ? data.jobId.value : this.jobId,
      threadId: data.threadId.present ? data.threadId.value : this.threadId,
      messageId: data.messageId.present ? data.messageId.value : this.messageId,
      summary: data.summary.present ? data.summary.value : this.summary,
      undoneAt: data.undoneAt.present ? data.undoneAt.value : this.undoneAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AiBatch(')
          ..write('id: $id, ')
          ..write('jobId: $jobId, ')
          ..write('threadId: $threadId, ')
          ..write('messageId: $messageId, ')
          ..write('summary: $summary, ')
          ..write('undoneAt: $undoneAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    jobId,
    threadId,
    messageId,
    summary,
    undoneAt,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AiBatch &&
          other.id == this.id &&
          other.jobId == this.jobId &&
          other.threadId == this.threadId &&
          other.messageId == this.messageId &&
          other.summary == this.summary &&
          other.undoneAt == this.undoneAt &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class AiBatchesTableCompanion extends UpdateCompanion<AiBatch> {
  final Value<String> id;
  final Value<String> jobId;
  final Value<String> threadId;
  final Value<String?> messageId;
  final Value<String> summary;
  final Value<String?> undoneAt;
  final Value<String> createdAt;
  final Value<String> updatedAt;
  final Value<int> rowid;
  const AiBatchesTableCompanion({
    this.id = const Value.absent(),
    this.jobId = const Value.absent(),
    this.threadId = const Value.absent(),
    this.messageId = const Value.absent(),
    this.summary = const Value.absent(),
    this.undoneAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AiBatchesTableCompanion.insert({
    required String id,
    required String jobId,
    required String threadId,
    this.messageId = const Value.absent(),
    this.summary = const Value.absent(),
    this.undoneAt = const Value.absent(),
    required String createdAt,
    required String updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       jobId = Value(jobId),
       threadId = Value(threadId),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<AiBatch> custom({
    Expression<String>? id,
    Expression<String>? jobId,
    Expression<String>? threadId,
    Expression<String>? messageId,
    Expression<String>? summary,
    Expression<String>? undoneAt,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (jobId != null) 'job_id': jobId,
      if (threadId != null) 'thread_id': threadId,
      if (messageId != null) 'message_id': messageId,
      if (summary != null) 'summary': summary,
      if (undoneAt != null) 'undone_at': undoneAt,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AiBatchesTableCompanion copyWith({
    Value<String>? id,
    Value<String>? jobId,
    Value<String>? threadId,
    Value<String?>? messageId,
    Value<String>? summary,
    Value<String?>? undoneAt,
    Value<String>? createdAt,
    Value<String>? updatedAt,
    Value<int>? rowid,
  }) {
    return AiBatchesTableCompanion(
      id: id ?? this.id,
      jobId: jobId ?? this.jobId,
      threadId: threadId ?? this.threadId,
      messageId: messageId ?? this.messageId,
      summary: summary ?? this.summary,
      undoneAt: undoneAt ?? this.undoneAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (jobId.present) {
      map['job_id'] = Variable<String>(jobId.value);
    }
    if (threadId.present) {
      map['thread_id'] = Variable<String>(threadId.value);
    }
    if (messageId.present) {
      map['message_id'] = Variable<String>(messageId.value);
    }
    if (summary.present) {
      map['summary'] = Variable<String>(summary.value);
    }
    if (undoneAt.present) {
      map['undone_at'] = Variable<String>(undoneAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AiBatchesTableCompanion(')
          ..write('id: $id, ')
          ..write('jobId: $jobId, ')
          ..write('threadId: $threadId, ')
          ..write('messageId: $messageId, ')
          ..write('summary: $summary, ')
          ..write('undoneAt: $undoneAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AiBatchItemsTableTable extends AiBatchItemsTable
    with TableInfo<$AiBatchItemsTableTable, AiBatchItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AiBatchItemsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _batchIdMeta = const VerificationMeta(
    'batchId',
  );
  @override
  late final GeneratedColumn<String> batchId = GeneratedColumn<String>(
    'batch_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityTypeMeta = const VerificationMeta(
    'entityType',
  );
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
    'entity_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _opMeta = const VerificationMeta('op');
  @override
  late final GeneratedColumn<String> op = GeneratedColumn<String>(
    'op',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('insert'),
  );
  static const VerificationMeta _beforeJsonMeta = const VerificationMeta(
    'beforeJson',
  );
  @override
  late final GeneratedColumn<String> beforeJson = GeneratedColumn<String>(
    'before_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _afterJsonMeta = const VerificationMeta(
    'afterJson',
  );
  @override
  late final GeneratedColumn<String> afterJson = GeneratedColumn<String>(
    'after_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    batchId,
    entityType,
    entityId,
    op,
    beforeJson,
    afterJson,
    position,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ai_batch_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<AiBatchItem> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('batch_id')) {
      context.handle(
        _batchIdMeta,
        batchId.isAcceptableOrUnknown(data['batch_id']!, _batchIdMeta),
      );
    } else if (isInserting) {
      context.missing(_batchIdMeta);
    }
    if (data.containsKey('entity_type')) {
      context.handle(
        _entityTypeMeta,
        entityType.isAcceptableOrUnknown(data['entity_type']!, _entityTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('op')) {
      context.handle(_opMeta, op.isAcceptableOrUnknown(data['op']!, _opMeta));
    }
    if (data.containsKey('before_json')) {
      context.handle(
        _beforeJsonMeta,
        beforeJson.isAcceptableOrUnknown(data['before_json']!, _beforeJsonMeta),
      );
    }
    if (data.containsKey('after_json')) {
      context.handle(
        _afterJsonMeta,
        afterJson.isAcceptableOrUnknown(data['after_json']!, _afterJsonMeta),
      );
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AiBatchItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AiBatchItem(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      batchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}batch_id'],
      )!,
      entityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_type'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      op: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}op'],
      )!,
      beforeJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}before_json'],
      ),
      afterJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}after_json'],
      ),
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $AiBatchItemsTableTable createAlias(String alias) {
    return $AiBatchItemsTableTable(attachedDatabase, alias);
  }
}

class AiBatchItem extends DataClass implements Insertable<AiBatchItem> {
  final String id;
  final String batchId;
  final String entityType;
  final String entityId;
  final String op;
  final String? beforeJson;
  final String? afterJson;
  final int position;
  final String createdAt;
  final String updatedAt;
  const AiBatchItem({
    required this.id,
    required this.batchId,
    required this.entityType,
    required this.entityId,
    required this.op,
    this.beforeJson,
    this.afterJson,
    required this.position,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['batch_id'] = Variable<String>(batchId);
    map['entity_type'] = Variable<String>(entityType);
    map['entity_id'] = Variable<String>(entityId);
    map['op'] = Variable<String>(op);
    if (!nullToAbsent || beforeJson != null) {
      map['before_json'] = Variable<String>(beforeJson);
    }
    if (!nullToAbsent || afterJson != null) {
      map['after_json'] = Variable<String>(afterJson);
    }
    map['position'] = Variable<int>(position);
    map['created_at'] = Variable<String>(createdAt);
    map['updated_at'] = Variable<String>(updatedAt);
    return map;
  }

  AiBatchItemsTableCompanion toCompanion(bool nullToAbsent) {
    return AiBatchItemsTableCompanion(
      id: Value(id),
      batchId: Value(batchId),
      entityType: Value(entityType),
      entityId: Value(entityId),
      op: Value(op),
      beforeJson: beforeJson == null && nullToAbsent
          ? const Value.absent()
          : Value(beforeJson),
      afterJson: afterJson == null && nullToAbsent
          ? const Value.absent()
          : Value(afterJson),
      position: Value(position),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory AiBatchItem.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AiBatchItem(
      id: serializer.fromJson<String>(json['id']),
      batchId: serializer.fromJson<String>(json['batchId']),
      entityType: serializer.fromJson<String>(json['entityType']),
      entityId: serializer.fromJson<String>(json['entityId']),
      op: serializer.fromJson<String>(json['op']),
      beforeJson: serializer.fromJson<String?>(json['beforeJson']),
      afterJson: serializer.fromJson<String?>(json['afterJson']),
      position: serializer.fromJson<int>(json['position']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'batchId': serializer.toJson<String>(batchId),
      'entityType': serializer.toJson<String>(entityType),
      'entityId': serializer.toJson<String>(entityId),
      'op': serializer.toJson<String>(op),
      'beforeJson': serializer.toJson<String?>(beforeJson),
      'afterJson': serializer.toJson<String?>(afterJson),
      'position': serializer.toJson<int>(position),
      'createdAt': serializer.toJson<String>(createdAt),
      'updatedAt': serializer.toJson<String>(updatedAt),
    };
  }

  AiBatchItem copyWith({
    String? id,
    String? batchId,
    String? entityType,
    String? entityId,
    String? op,
    Value<String?> beforeJson = const Value.absent(),
    Value<String?> afterJson = const Value.absent(),
    int? position,
    String? createdAt,
    String? updatedAt,
  }) => AiBatchItem(
    id: id ?? this.id,
    batchId: batchId ?? this.batchId,
    entityType: entityType ?? this.entityType,
    entityId: entityId ?? this.entityId,
    op: op ?? this.op,
    beforeJson: beforeJson.present ? beforeJson.value : this.beforeJson,
    afterJson: afterJson.present ? afterJson.value : this.afterJson,
    position: position ?? this.position,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  AiBatchItem copyWithCompanion(AiBatchItemsTableCompanion data) {
    return AiBatchItem(
      id: data.id.present ? data.id.value : this.id,
      batchId: data.batchId.present ? data.batchId.value : this.batchId,
      entityType: data.entityType.present
          ? data.entityType.value
          : this.entityType,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      op: data.op.present ? data.op.value : this.op,
      beforeJson: data.beforeJson.present
          ? data.beforeJson.value
          : this.beforeJson,
      afterJson: data.afterJson.present ? data.afterJson.value : this.afterJson,
      position: data.position.present ? data.position.value : this.position,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AiBatchItem(')
          ..write('id: $id, ')
          ..write('batchId: $batchId, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('op: $op, ')
          ..write('beforeJson: $beforeJson, ')
          ..write('afterJson: $afterJson, ')
          ..write('position: $position, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    batchId,
    entityType,
    entityId,
    op,
    beforeJson,
    afterJson,
    position,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AiBatchItem &&
          other.id == this.id &&
          other.batchId == this.batchId &&
          other.entityType == this.entityType &&
          other.entityId == this.entityId &&
          other.op == this.op &&
          other.beforeJson == this.beforeJson &&
          other.afterJson == this.afterJson &&
          other.position == this.position &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class AiBatchItemsTableCompanion extends UpdateCompanion<AiBatchItem> {
  final Value<String> id;
  final Value<String> batchId;
  final Value<String> entityType;
  final Value<String> entityId;
  final Value<String> op;
  final Value<String?> beforeJson;
  final Value<String?> afterJson;
  final Value<int> position;
  final Value<String> createdAt;
  final Value<String> updatedAt;
  final Value<int> rowid;
  const AiBatchItemsTableCompanion({
    this.id = const Value.absent(),
    this.batchId = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entityId = const Value.absent(),
    this.op = const Value.absent(),
    this.beforeJson = const Value.absent(),
    this.afterJson = const Value.absent(),
    this.position = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AiBatchItemsTableCompanion.insert({
    required String id,
    required String batchId,
    required String entityType,
    required String entityId,
    this.op = const Value.absent(),
    this.beforeJson = const Value.absent(),
    this.afterJson = const Value.absent(),
    this.position = const Value.absent(),
    required String createdAt,
    required String updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       batchId = Value(batchId),
       entityType = Value(entityType),
       entityId = Value(entityId),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<AiBatchItem> custom({
    Expression<String>? id,
    Expression<String>? batchId,
    Expression<String>? entityType,
    Expression<String>? entityId,
    Expression<String>? op,
    Expression<String>? beforeJson,
    Expression<String>? afterJson,
    Expression<int>? position,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (batchId != null) 'batch_id': batchId,
      if (entityType != null) 'entity_type': entityType,
      if (entityId != null) 'entity_id': entityId,
      if (op != null) 'op': op,
      if (beforeJson != null) 'before_json': beforeJson,
      if (afterJson != null) 'after_json': afterJson,
      if (position != null) 'position': position,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AiBatchItemsTableCompanion copyWith({
    Value<String>? id,
    Value<String>? batchId,
    Value<String>? entityType,
    Value<String>? entityId,
    Value<String>? op,
    Value<String?>? beforeJson,
    Value<String?>? afterJson,
    Value<int>? position,
    Value<String>? createdAt,
    Value<String>? updatedAt,
    Value<int>? rowid,
  }) {
    return AiBatchItemsTableCompanion(
      id: id ?? this.id,
      batchId: batchId ?? this.batchId,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      op: op ?? this.op,
      beforeJson: beforeJson ?? this.beforeJson,
      afterJson: afterJson ?? this.afterJson,
      position: position ?? this.position,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (batchId.present) {
      map['batch_id'] = Variable<String>(batchId.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (op.present) {
      map['op'] = Variable<String>(op.value);
    }
    if (beforeJson.present) {
      map['before_json'] = Variable<String>(beforeJson.value);
    }
    if (afterJson.present) {
      map['after_json'] = Variable<String>(afterJson.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AiBatchItemsTableCompanion(')
          ..write('id: $id, ')
          ..write('batchId: $batchId, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('op: $op, ')
          ..write('beforeJson: $beforeJson, ')
          ..write('afterJson: $afterJson, ')
          ..write('position: $position, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AiBlobsTableTable extends AiBlobsTable
    with TableInfo<$AiBlobsTableTable, AiBlob> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AiBlobsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _messageIdMeta = const VerificationMeta(
    'messageId',
  );
  @override
  late final GeneratedColumn<String> messageId = GeneratedColumn<String>(
    'message_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _jobIdMeta = const VerificationMeta('jobId');
  @override
  late final GeneratedColumn<String> jobId = GeneratedColumn<String>(
    'job_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('receipt'),
  );
  static const VerificationMeta _mimeMeta = const VerificationMeta('mime');
  @override
  late final GeneratedColumn<String> mime = GeneratedColumn<String>(
    'mime',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('image/jpeg'),
  );
  static const VerificationMeta _dataMeta = const VerificationMeta('data');
  @override
  late final GeneratedColumn<String> data = GeneratedColumn<String>(
    'data',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sha256Meta = const VerificationMeta('sha256');
  @override
  late final GeneratedColumn<String> sha256 = GeneratedColumn<String>(
    'sha256',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _widthMeta = const VerificationMeta('width');
  @override
  late final GeneratedColumn<int> width = GeneratedColumn<int>(
    'width',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _heightMeta = const VerificationMeta('height');
  @override
  late final GeneratedColumn<int> height = GeneratedColumn<int>(
    'height',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _storedOnHubAtMeta = const VerificationMeta(
    'storedOnHubAt',
  );
  @override
  late final GeneratedColumn<String> storedOnHubAt = GeneratedColumn<String>(
    'stored_on_hub_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    messageId,
    jobId,
    kind,
    mime,
    data,
    sha256,
    width,
    height,
    storedOnHubAt,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ai_blobs';
  @override
  VerificationContext validateIntegrity(
    Insertable<AiBlob> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('message_id')) {
      context.handle(
        _messageIdMeta,
        messageId.isAcceptableOrUnknown(data['message_id']!, _messageIdMeta),
      );
    }
    if (data.containsKey('job_id')) {
      context.handle(
        _jobIdMeta,
        jobId.isAcceptableOrUnknown(data['job_id']!, _jobIdMeta),
      );
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    }
    if (data.containsKey('mime')) {
      context.handle(
        _mimeMeta,
        mime.isAcceptableOrUnknown(data['mime']!, _mimeMeta),
      );
    }
    if (data.containsKey('data')) {
      context.handle(
        _dataMeta,
        this.data.isAcceptableOrUnknown(data['data']!, _dataMeta),
      );
    }
    if (data.containsKey('sha256')) {
      context.handle(
        _sha256Meta,
        sha256.isAcceptableOrUnknown(data['sha256']!, _sha256Meta),
      );
    }
    if (data.containsKey('width')) {
      context.handle(
        _widthMeta,
        width.isAcceptableOrUnknown(data['width']!, _widthMeta),
      );
    }
    if (data.containsKey('height')) {
      context.handle(
        _heightMeta,
        height.isAcceptableOrUnknown(data['height']!, _heightMeta),
      );
    }
    if (data.containsKey('stored_on_hub_at')) {
      context.handle(
        _storedOnHubAtMeta,
        storedOnHubAt.isAcceptableOrUnknown(
          data['stored_on_hub_at']!,
          _storedOnHubAtMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AiBlob map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AiBlob(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      messageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message_id'],
      ),
      jobId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}job_id'],
      ),
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      mime: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mime'],
      )!,
      data: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}data'],
      ),
      sha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sha256'],
      )!,
      width: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}width'],
      ),
      height: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}height'],
      ),
      storedOnHubAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stored_on_hub_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $AiBlobsTableTable createAlias(String alias) {
    return $AiBlobsTableTable(attachedDatabase, alias);
  }
}

class AiBlob extends DataClass implements Insertable<AiBlob> {
  final String id;
  final String? messageId;
  final String? jobId;
  final String kind;
  final String mime;
  final String? data;
  final String sha256;
  final int? width;
  final int? height;
  final String? storedOnHubAt;
  final String createdAt;
  final String updatedAt;
  const AiBlob({
    required this.id,
    this.messageId,
    this.jobId,
    required this.kind,
    required this.mime,
    this.data,
    required this.sha256,
    this.width,
    this.height,
    this.storedOnHubAt,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || messageId != null) {
      map['message_id'] = Variable<String>(messageId);
    }
    if (!nullToAbsent || jobId != null) {
      map['job_id'] = Variable<String>(jobId);
    }
    map['kind'] = Variable<String>(kind);
    map['mime'] = Variable<String>(mime);
    if (!nullToAbsent || data != null) {
      map['data'] = Variable<String>(data);
    }
    map['sha256'] = Variable<String>(sha256);
    if (!nullToAbsent || width != null) {
      map['width'] = Variable<int>(width);
    }
    if (!nullToAbsent || height != null) {
      map['height'] = Variable<int>(height);
    }
    if (!nullToAbsent || storedOnHubAt != null) {
      map['stored_on_hub_at'] = Variable<String>(storedOnHubAt);
    }
    map['created_at'] = Variable<String>(createdAt);
    map['updated_at'] = Variable<String>(updatedAt);
    return map;
  }

  AiBlobsTableCompanion toCompanion(bool nullToAbsent) {
    return AiBlobsTableCompanion(
      id: Value(id),
      messageId: messageId == null && nullToAbsent
          ? const Value.absent()
          : Value(messageId),
      jobId: jobId == null && nullToAbsent
          ? const Value.absent()
          : Value(jobId),
      kind: Value(kind),
      mime: Value(mime),
      data: data == null && nullToAbsent ? const Value.absent() : Value(data),
      sha256: Value(sha256),
      width: width == null && nullToAbsent
          ? const Value.absent()
          : Value(width),
      height: height == null && nullToAbsent
          ? const Value.absent()
          : Value(height),
      storedOnHubAt: storedOnHubAt == null && nullToAbsent
          ? const Value.absent()
          : Value(storedOnHubAt),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory AiBlob.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AiBlob(
      id: serializer.fromJson<String>(json['id']),
      messageId: serializer.fromJson<String?>(json['messageId']),
      jobId: serializer.fromJson<String?>(json['jobId']),
      kind: serializer.fromJson<String>(json['kind']),
      mime: serializer.fromJson<String>(json['mime']),
      data: serializer.fromJson<String?>(json['data']),
      sha256: serializer.fromJson<String>(json['sha256']),
      width: serializer.fromJson<int?>(json['width']),
      height: serializer.fromJson<int?>(json['height']),
      storedOnHubAt: serializer.fromJson<String?>(json['storedOnHubAt']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'messageId': serializer.toJson<String?>(messageId),
      'jobId': serializer.toJson<String?>(jobId),
      'kind': serializer.toJson<String>(kind),
      'mime': serializer.toJson<String>(mime),
      'data': serializer.toJson<String?>(data),
      'sha256': serializer.toJson<String>(sha256),
      'width': serializer.toJson<int?>(width),
      'height': serializer.toJson<int?>(height),
      'storedOnHubAt': serializer.toJson<String?>(storedOnHubAt),
      'createdAt': serializer.toJson<String>(createdAt),
      'updatedAt': serializer.toJson<String>(updatedAt),
    };
  }

  AiBlob copyWith({
    String? id,
    Value<String?> messageId = const Value.absent(),
    Value<String?> jobId = const Value.absent(),
    String? kind,
    String? mime,
    Value<String?> data = const Value.absent(),
    String? sha256,
    Value<int?> width = const Value.absent(),
    Value<int?> height = const Value.absent(),
    Value<String?> storedOnHubAt = const Value.absent(),
    String? createdAt,
    String? updatedAt,
  }) => AiBlob(
    id: id ?? this.id,
    messageId: messageId.present ? messageId.value : this.messageId,
    jobId: jobId.present ? jobId.value : this.jobId,
    kind: kind ?? this.kind,
    mime: mime ?? this.mime,
    data: data.present ? data.value : this.data,
    sha256: sha256 ?? this.sha256,
    width: width.present ? width.value : this.width,
    height: height.present ? height.value : this.height,
    storedOnHubAt: storedOnHubAt.present
        ? storedOnHubAt.value
        : this.storedOnHubAt,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  AiBlob copyWithCompanion(AiBlobsTableCompanion data) {
    return AiBlob(
      id: data.id.present ? data.id.value : this.id,
      messageId: data.messageId.present ? data.messageId.value : this.messageId,
      jobId: data.jobId.present ? data.jobId.value : this.jobId,
      kind: data.kind.present ? data.kind.value : this.kind,
      mime: data.mime.present ? data.mime.value : this.mime,
      data: data.data.present ? data.data.value : this.data,
      sha256: data.sha256.present ? data.sha256.value : this.sha256,
      width: data.width.present ? data.width.value : this.width,
      height: data.height.present ? data.height.value : this.height,
      storedOnHubAt: data.storedOnHubAt.present
          ? data.storedOnHubAt.value
          : this.storedOnHubAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AiBlob(')
          ..write('id: $id, ')
          ..write('messageId: $messageId, ')
          ..write('jobId: $jobId, ')
          ..write('kind: $kind, ')
          ..write('mime: $mime, ')
          ..write('data: $data, ')
          ..write('sha256: $sha256, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('storedOnHubAt: $storedOnHubAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    messageId,
    jobId,
    kind,
    mime,
    data,
    sha256,
    width,
    height,
    storedOnHubAt,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AiBlob &&
          other.id == this.id &&
          other.messageId == this.messageId &&
          other.jobId == this.jobId &&
          other.kind == this.kind &&
          other.mime == this.mime &&
          other.data == this.data &&
          other.sha256 == this.sha256 &&
          other.width == this.width &&
          other.height == this.height &&
          other.storedOnHubAt == this.storedOnHubAt &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class AiBlobsTableCompanion extends UpdateCompanion<AiBlob> {
  final Value<String> id;
  final Value<String?> messageId;
  final Value<String?> jobId;
  final Value<String> kind;
  final Value<String> mime;
  final Value<String?> data;
  final Value<String> sha256;
  final Value<int?> width;
  final Value<int?> height;
  final Value<String?> storedOnHubAt;
  final Value<String> createdAt;
  final Value<String> updatedAt;
  final Value<int> rowid;
  const AiBlobsTableCompanion({
    this.id = const Value.absent(),
    this.messageId = const Value.absent(),
    this.jobId = const Value.absent(),
    this.kind = const Value.absent(),
    this.mime = const Value.absent(),
    this.data = const Value.absent(),
    this.sha256 = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.storedOnHubAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AiBlobsTableCompanion.insert({
    required String id,
    this.messageId = const Value.absent(),
    this.jobId = const Value.absent(),
    this.kind = const Value.absent(),
    this.mime = const Value.absent(),
    this.data = const Value.absent(),
    this.sha256 = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.storedOnHubAt = const Value.absent(),
    required String createdAt,
    required String updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<AiBlob> custom({
    Expression<String>? id,
    Expression<String>? messageId,
    Expression<String>? jobId,
    Expression<String>? kind,
    Expression<String>? mime,
    Expression<String>? data,
    Expression<String>? sha256,
    Expression<int>? width,
    Expression<int>? height,
    Expression<String>? storedOnHubAt,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (messageId != null) 'message_id': messageId,
      if (jobId != null) 'job_id': jobId,
      if (kind != null) 'kind': kind,
      if (mime != null) 'mime': mime,
      if (data != null) 'data': data,
      if (sha256 != null) 'sha256': sha256,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (storedOnHubAt != null) 'stored_on_hub_at': storedOnHubAt,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AiBlobsTableCompanion copyWith({
    Value<String>? id,
    Value<String?>? messageId,
    Value<String?>? jobId,
    Value<String>? kind,
    Value<String>? mime,
    Value<String?>? data,
    Value<String>? sha256,
    Value<int?>? width,
    Value<int?>? height,
    Value<String?>? storedOnHubAt,
    Value<String>? createdAt,
    Value<String>? updatedAt,
    Value<int>? rowid,
  }) {
    return AiBlobsTableCompanion(
      id: id ?? this.id,
      messageId: messageId ?? this.messageId,
      jobId: jobId ?? this.jobId,
      kind: kind ?? this.kind,
      mime: mime ?? this.mime,
      data: data ?? this.data,
      sha256: sha256 ?? this.sha256,
      width: width ?? this.width,
      height: height ?? this.height,
      storedOnHubAt: storedOnHubAt ?? this.storedOnHubAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (messageId.present) {
      map['message_id'] = Variable<String>(messageId.value);
    }
    if (jobId.present) {
      map['job_id'] = Variable<String>(jobId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (mime.present) {
      map['mime'] = Variable<String>(mime.value);
    }
    if (data.present) {
      map['data'] = Variable<String>(data.value);
    }
    if (sha256.present) {
      map['sha256'] = Variable<String>(sha256.value);
    }
    if (width.present) {
      map['width'] = Variable<int>(width.value);
    }
    if (height.present) {
      map['height'] = Variable<int>(height.value);
    }
    if (storedOnHubAt.present) {
      map['stored_on_hub_at'] = Variable<String>(storedOnHubAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AiBlobsTableCompanion(')
          ..write('id: $id, ')
          ..write('messageId: $messageId, ')
          ..write('jobId: $jobId, ')
          ..write('kind: $kind, ')
          ..write('mime: $mime, ')
          ..write('data: $data, ')
          ..write('sha256: $sha256, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('storedOnHubAt: $storedOnHubAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProductAliasesTableTable extends ProductAliasesTable
    with TableInfo<$ProductAliasesTableTable, ProductAlias> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProductAliasesTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _patternMeta = const VerificationMeta(
    'pattern',
  );
  @override
  late final GeneratedColumn<String> pattern = GeneratedColumn<String>(
    'pattern',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
    'category_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _unitOverrideMeta = const VerificationMeta(
    'unitOverride',
  );
  @override
  late final GeneratedColumn<String> unitOverride = GeneratedColumn<String>(
    'unit_override',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _weightGramsDefaultMeta =
      const VerificationMeta('weightGramsDefault');
  @override
  late final GeneratedColumn<double> weightGramsDefault =
      GeneratedColumn<double>(
        'weight_grams_default',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _pieceDefaultMeta = const VerificationMeta(
    'pieceDefault',
  );
  @override
  late final GeneratedColumn<double> pieceDefault = GeneratedColumn<double>(
    'piece_default',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('ai'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    pattern,
    categoryId,
    unitOverride,
    weightGramsDefault,
    pieceDefault,
    source,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'product_aliases';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProductAlias> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('pattern')) {
      context.handle(
        _patternMeta,
        pattern.isAcceptableOrUnknown(data['pattern']!, _patternMeta),
      );
    } else if (isInserting) {
      context.missing(_patternMeta);
    }
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    }
    if (data.containsKey('unit_override')) {
      context.handle(
        _unitOverrideMeta,
        unitOverride.isAcceptableOrUnknown(
          data['unit_override']!,
          _unitOverrideMeta,
        ),
      );
    }
    if (data.containsKey('weight_grams_default')) {
      context.handle(
        _weightGramsDefaultMeta,
        weightGramsDefault.isAcceptableOrUnknown(
          data['weight_grams_default']!,
          _weightGramsDefaultMeta,
        ),
      );
    }
    if (data.containsKey('piece_default')) {
      context.handle(
        _pieceDefaultMeta,
        pieceDefault.isAcceptableOrUnknown(
          data['piece_default']!,
          _pieceDefaultMeta,
        ),
      );
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProductAlias map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProductAlias(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      pattern: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pattern'],
      )!,
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category_id'],
      ),
      unitOverride: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}unit_override'],
      ),
      weightGramsDefault: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}weight_grams_default'],
      ),
      pieceDefault: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}piece_default'],
      ),
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ProductAliasesTableTable createAlias(String alias) {
    return $ProductAliasesTableTable(attachedDatabase, alias);
  }
}

class ProductAlias extends DataClass implements Insertable<ProductAlias> {
  final String id;
  final String pattern;
  final String? categoryId;
  final String? unitOverride;
  final double? weightGramsDefault;
  final double? pieceDefault;
  final String source;
  final String createdAt;
  final String updatedAt;
  const ProductAlias({
    required this.id,
    required this.pattern,
    this.categoryId,
    this.unitOverride,
    this.weightGramsDefault,
    this.pieceDefault,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['pattern'] = Variable<String>(pattern);
    if (!nullToAbsent || categoryId != null) {
      map['category_id'] = Variable<String>(categoryId);
    }
    if (!nullToAbsent || unitOverride != null) {
      map['unit_override'] = Variable<String>(unitOverride);
    }
    if (!nullToAbsent || weightGramsDefault != null) {
      map['weight_grams_default'] = Variable<double>(weightGramsDefault);
    }
    if (!nullToAbsent || pieceDefault != null) {
      map['piece_default'] = Variable<double>(pieceDefault);
    }
    map['source'] = Variable<String>(source);
    map['created_at'] = Variable<String>(createdAt);
    map['updated_at'] = Variable<String>(updatedAt);
    return map;
  }

  ProductAliasesTableCompanion toCompanion(bool nullToAbsent) {
    return ProductAliasesTableCompanion(
      id: Value(id),
      pattern: Value(pattern),
      categoryId: categoryId == null && nullToAbsent
          ? const Value.absent()
          : Value(categoryId),
      unitOverride: unitOverride == null && nullToAbsent
          ? const Value.absent()
          : Value(unitOverride),
      weightGramsDefault: weightGramsDefault == null && nullToAbsent
          ? const Value.absent()
          : Value(weightGramsDefault),
      pieceDefault: pieceDefault == null && nullToAbsent
          ? const Value.absent()
          : Value(pieceDefault),
      source: Value(source),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory ProductAlias.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProductAlias(
      id: serializer.fromJson<String>(json['id']),
      pattern: serializer.fromJson<String>(json['pattern']),
      categoryId: serializer.fromJson<String?>(json['categoryId']),
      unitOverride: serializer.fromJson<String?>(json['unitOverride']),
      weightGramsDefault: serializer.fromJson<double?>(
        json['weightGramsDefault'],
      ),
      pieceDefault: serializer.fromJson<double?>(json['pieceDefault']),
      source: serializer.fromJson<String>(json['source']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'pattern': serializer.toJson<String>(pattern),
      'categoryId': serializer.toJson<String?>(categoryId),
      'unitOverride': serializer.toJson<String?>(unitOverride),
      'weightGramsDefault': serializer.toJson<double?>(weightGramsDefault),
      'pieceDefault': serializer.toJson<double?>(pieceDefault),
      'source': serializer.toJson<String>(source),
      'createdAt': serializer.toJson<String>(createdAt),
      'updatedAt': serializer.toJson<String>(updatedAt),
    };
  }

  ProductAlias copyWith({
    String? id,
    String? pattern,
    Value<String?> categoryId = const Value.absent(),
    Value<String?> unitOverride = const Value.absent(),
    Value<double?> weightGramsDefault = const Value.absent(),
    Value<double?> pieceDefault = const Value.absent(),
    String? source,
    String? createdAt,
    String? updatedAt,
  }) => ProductAlias(
    id: id ?? this.id,
    pattern: pattern ?? this.pattern,
    categoryId: categoryId.present ? categoryId.value : this.categoryId,
    unitOverride: unitOverride.present ? unitOverride.value : this.unitOverride,
    weightGramsDefault: weightGramsDefault.present
        ? weightGramsDefault.value
        : this.weightGramsDefault,
    pieceDefault: pieceDefault.present ? pieceDefault.value : this.pieceDefault,
    source: source ?? this.source,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ProductAlias copyWithCompanion(ProductAliasesTableCompanion data) {
    return ProductAlias(
      id: data.id.present ? data.id.value : this.id,
      pattern: data.pattern.present ? data.pattern.value : this.pattern,
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
      unitOverride: data.unitOverride.present
          ? data.unitOverride.value
          : this.unitOverride,
      weightGramsDefault: data.weightGramsDefault.present
          ? data.weightGramsDefault.value
          : this.weightGramsDefault,
      pieceDefault: data.pieceDefault.present
          ? data.pieceDefault.value
          : this.pieceDefault,
      source: data.source.present ? data.source.value : this.source,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProductAlias(')
          ..write('id: $id, ')
          ..write('pattern: $pattern, ')
          ..write('categoryId: $categoryId, ')
          ..write('unitOverride: $unitOverride, ')
          ..write('weightGramsDefault: $weightGramsDefault, ')
          ..write('pieceDefault: $pieceDefault, ')
          ..write('source: $source, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    pattern,
    categoryId,
    unitOverride,
    weightGramsDefault,
    pieceDefault,
    source,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProductAlias &&
          other.id == this.id &&
          other.pattern == this.pattern &&
          other.categoryId == this.categoryId &&
          other.unitOverride == this.unitOverride &&
          other.weightGramsDefault == this.weightGramsDefault &&
          other.pieceDefault == this.pieceDefault &&
          other.source == this.source &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ProductAliasesTableCompanion extends UpdateCompanion<ProductAlias> {
  final Value<String> id;
  final Value<String> pattern;
  final Value<String?> categoryId;
  final Value<String?> unitOverride;
  final Value<double?> weightGramsDefault;
  final Value<double?> pieceDefault;
  final Value<String> source;
  final Value<String> createdAt;
  final Value<String> updatedAt;
  final Value<int> rowid;
  const ProductAliasesTableCompanion({
    this.id = const Value.absent(),
    this.pattern = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.unitOverride = const Value.absent(),
    this.weightGramsDefault = const Value.absent(),
    this.pieceDefault = const Value.absent(),
    this.source = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProductAliasesTableCompanion.insert({
    required String id,
    required String pattern,
    this.categoryId = const Value.absent(),
    this.unitOverride = const Value.absent(),
    this.weightGramsDefault = const Value.absent(),
    this.pieceDefault = const Value.absent(),
    this.source = const Value.absent(),
    required String createdAt,
    required String updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       pattern = Value(pattern),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<ProductAlias> custom({
    Expression<String>? id,
    Expression<String>? pattern,
    Expression<String>? categoryId,
    Expression<String>? unitOverride,
    Expression<double>? weightGramsDefault,
    Expression<double>? pieceDefault,
    Expression<String>? source,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (pattern != null) 'pattern': pattern,
      if (categoryId != null) 'category_id': categoryId,
      if (unitOverride != null) 'unit_override': unitOverride,
      if (weightGramsDefault != null)
        'weight_grams_default': weightGramsDefault,
      if (pieceDefault != null) 'piece_default': pieceDefault,
      if (source != null) 'source': source,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProductAliasesTableCompanion copyWith({
    Value<String>? id,
    Value<String>? pattern,
    Value<String?>? categoryId,
    Value<String?>? unitOverride,
    Value<double?>? weightGramsDefault,
    Value<double?>? pieceDefault,
    Value<String>? source,
    Value<String>? createdAt,
    Value<String>? updatedAt,
    Value<int>? rowid,
  }) {
    return ProductAliasesTableCompanion(
      id: id ?? this.id,
      pattern: pattern ?? this.pattern,
      categoryId: categoryId ?? this.categoryId,
      unitOverride: unitOverride ?? this.unitOverride,
      weightGramsDefault: weightGramsDefault ?? this.weightGramsDefault,
      pieceDefault: pieceDefault ?? this.pieceDefault,
      source: source ?? this.source,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (pattern.present) {
      map['pattern'] = Variable<String>(pattern.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
    }
    if (unitOverride.present) {
      map['unit_override'] = Variable<String>(unitOverride.value);
    }
    if (weightGramsDefault.present) {
      map['weight_grams_default'] = Variable<double>(weightGramsDefault.value);
    }
    if (pieceDefault.present) {
      map['piece_default'] = Variable<double>(pieceDefault.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProductAliasesTableCompanion(')
          ..write('id: $id, ')
          ..write('pattern: $pattern, ')
          ..write('categoryId: $categoryId, ')
          ..write('unitOverride: $unitOverride, ')
          ..write('weightGramsDefault: $weightGramsDefault, ')
          ..write('pieceDefault: $pieceDefault, ')
          ..write('source: $source, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AiRulesMemoryTableTable extends AiRulesMemoryTable
    with TableInfo<$AiRulesMemoryTableTable, AiRule> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AiRulesMemoryTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueJsonMeta = const VerificationMeta(
    'valueJson',
  );
  @override
  late final GeneratedColumn<String> valueJson = GeneratedColumn<String>(
    'value_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _sourceMessageIdMeta = const VerificationMeta(
    'sourceMessageId',
  );
  @override
  late final GeneratedColumn<String> sourceMessageId = GeneratedColumn<String>(
    'source_message_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    key,
    valueJson,
    sourceMessageId,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ai_rules_memory';
  @override
  VerificationContext validateIntegrity(
    Insertable<AiRule> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value_json')) {
      context.handle(
        _valueJsonMeta,
        valueJson.isAcceptableOrUnknown(data['value_json']!, _valueJsonMeta),
      );
    }
    if (data.containsKey('source_message_id')) {
      context.handle(
        _sourceMessageIdMeta,
        sourceMessageId.isAcceptableOrUnknown(
          data['source_message_id']!,
          _sourceMessageIdMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AiRule map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AiRule(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      valueJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value_json'],
      )!,
      sourceMessageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_message_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $AiRulesMemoryTableTable createAlias(String alias) {
    return $AiRulesMemoryTableTable(attachedDatabase, alias);
  }
}

class AiRule extends DataClass implements Insertable<AiRule> {
  final String id;
  final String key;
  final String valueJson;
  final String? sourceMessageId;
  final String createdAt;
  final String updatedAt;
  const AiRule({
    required this.id,
    required this.key,
    required this.valueJson,
    this.sourceMessageId,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['key'] = Variable<String>(key);
    map['value_json'] = Variable<String>(valueJson);
    if (!nullToAbsent || sourceMessageId != null) {
      map['source_message_id'] = Variable<String>(sourceMessageId);
    }
    map['created_at'] = Variable<String>(createdAt);
    map['updated_at'] = Variable<String>(updatedAt);
    return map;
  }

  AiRulesMemoryTableCompanion toCompanion(bool nullToAbsent) {
    return AiRulesMemoryTableCompanion(
      id: Value(id),
      key: Value(key),
      valueJson: Value(valueJson),
      sourceMessageId: sourceMessageId == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceMessageId),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory AiRule.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AiRule(
      id: serializer.fromJson<String>(json['id']),
      key: serializer.fromJson<String>(json['key']),
      valueJson: serializer.fromJson<String>(json['valueJson']),
      sourceMessageId: serializer.fromJson<String?>(json['sourceMessageId']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'key': serializer.toJson<String>(key),
      'valueJson': serializer.toJson<String>(valueJson),
      'sourceMessageId': serializer.toJson<String?>(sourceMessageId),
      'createdAt': serializer.toJson<String>(createdAt),
      'updatedAt': serializer.toJson<String>(updatedAt),
    };
  }

  AiRule copyWith({
    String? id,
    String? key,
    String? valueJson,
    Value<String?> sourceMessageId = const Value.absent(),
    String? createdAt,
    String? updatedAt,
  }) => AiRule(
    id: id ?? this.id,
    key: key ?? this.key,
    valueJson: valueJson ?? this.valueJson,
    sourceMessageId: sourceMessageId.present
        ? sourceMessageId.value
        : this.sourceMessageId,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  AiRule copyWithCompanion(AiRulesMemoryTableCompanion data) {
    return AiRule(
      id: data.id.present ? data.id.value : this.id,
      key: data.key.present ? data.key.value : this.key,
      valueJson: data.valueJson.present ? data.valueJson.value : this.valueJson,
      sourceMessageId: data.sourceMessageId.present
          ? data.sourceMessageId.value
          : this.sourceMessageId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AiRule(')
          ..write('id: $id, ')
          ..write('key: $key, ')
          ..write('valueJson: $valueJson, ')
          ..write('sourceMessageId: $sourceMessageId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, key, valueJson, sourceMessageId, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AiRule &&
          other.id == this.id &&
          other.key == this.key &&
          other.valueJson == this.valueJson &&
          other.sourceMessageId == this.sourceMessageId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class AiRulesMemoryTableCompanion extends UpdateCompanion<AiRule> {
  final Value<String> id;
  final Value<String> key;
  final Value<String> valueJson;
  final Value<String?> sourceMessageId;
  final Value<String> createdAt;
  final Value<String> updatedAt;
  final Value<int> rowid;
  const AiRulesMemoryTableCompanion({
    this.id = const Value.absent(),
    this.key = const Value.absent(),
    this.valueJson = const Value.absent(),
    this.sourceMessageId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AiRulesMemoryTableCompanion.insert({
    required String id,
    required String key,
    this.valueJson = const Value.absent(),
    this.sourceMessageId = const Value.absent(),
    required String createdAt,
    required String updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       key = Value(key),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<AiRule> custom({
    Expression<String>? id,
    Expression<String>? key,
    Expression<String>? valueJson,
    Expression<String>? sourceMessageId,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (key != null) 'key': key,
      if (valueJson != null) 'value_json': valueJson,
      if (sourceMessageId != null) 'source_message_id': sourceMessageId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AiRulesMemoryTableCompanion copyWith({
    Value<String>? id,
    Value<String>? key,
    Value<String>? valueJson,
    Value<String?>? sourceMessageId,
    Value<String>? createdAt,
    Value<String>? updatedAt,
    Value<int>? rowid,
  }) {
    return AiRulesMemoryTableCompanion(
      id: id ?? this.id,
      key: key ?? this.key,
      valueJson: valueJson ?? this.valueJson,
      sourceMessageId: sourceMessageId ?? this.sourceMessageId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (valueJson.present) {
      map['value_json'] = Variable<String>(valueJson.value);
    }
    if (sourceMessageId.present) {
      map['source_message_id'] = Variable<String>(sourceMessageId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AiRulesMemoryTableCompanion(')
          ..write('id: $id, ')
          ..write('key: $key, ')
          ..write('valueJson: $valueJson, ')
          ..write('sourceMessageId: $sourceMessageId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AiSettingsTableTable extends AiSettingsTable
    with TableInfo<$AiSettingsTableTable, AiSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AiSettingsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ai_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<AiSetting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  AiSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AiSetting(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $AiSettingsTableTable createAlias(String alias) {
    return $AiSettingsTableTable(attachedDatabase, alias);
  }
}

class AiSetting extends DataClass implements Insertable<AiSetting> {
  final String key;
  final String value;
  const AiSetting({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  AiSettingsTableCompanion toCompanion(bool nullToAbsent) {
    return AiSettingsTableCompanion(key: Value(key), value: Value(value));
  }

  factory AiSetting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AiSetting(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  AiSetting copyWith({String? key, String? value}) =>
      AiSetting(key: key ?? this.key, value: value ?? this.value);
  AiSetting copyWithCompanion(AiSettingsTableCompanion data) {
    return AiSetting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AiSetting(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AiSetting &&
          other.key == this.key &&
          other.value == this.value);
}

class AiSettingsTableCompanion extends UpdateCompanion<AiSetting> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const AiSettingsTableCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AiSettingsTableCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<AiSetting> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AiSettingsTableCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return AiSettingsTableCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AiSettingsTableCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $CountableActivitiesTableTable countableActivitiesTable =
      $CountableActivitiesTableTable(this);
  late final $ActionsTableTable actionsTable = $ActionsTableTable(this);
  late final $ActionDependenciesTableTable actionDependenciesTable =
      $ActionDependenciesTableTable(this);
  late final $ActionOccurrencesTableTable actionOccurrencesTable =
      $ActionOccurrencesTableTable(this);
  late final $MetricsTableTable metricsTable = $MetricsTableTable(this);
  late final $ActionMetricsTableTable actionMetricsTable =
      $ActionMetricsTableTable(this);
  late final $ActionTemplatesTableTable actionTemplatesTable =
      $ActionTemplatesTableTable(this);
  late final $MetricDependenciesTableTable metricDependenciesTable =
      $MetricDependenciesTableTable(this);
  late final $BudgetAccountsTableTable budgetAccountsTable =
      $BudgetAccountsTableTable(this);
  late final $BudgetCategoriesTableTable budgetCategoriesTable =
      $BudgetCategoriesTableTable(this);
  late final $BudgetTransactionsTableTable budgetTransactionsTable =
      $BudgetTransactionsTableTable(this);
  late final $BudgetSettingsTableTable budgetSettingsTable =
      $BudgetSettingsTableTable(this);
  late final $SavedViewsTableTable savedViewsTable = $SavedViewsTableTable(
    this,
  );
  late final $PlanItemsTableTable planItemsTable = $PlanItemsTableTable(this);
  late final $PlanOverridesTableTable planOverridesTable =
      $PlanOverridesTableTable(this);
  late final $BudgetTxTemplatesTableTable budgetTxTemplatesTable =
      $BudgetTxTemplatesTableTable(this);
  late final $PlanCollectionsTableTable planCollectionsTable =
      $PlanCollectionsTableTable(this);
  late final $FormsTableTable formsTable = $FormsTableTable(this);
  late final $CalendarZonesTableTable calendarZonesTable =
      $CalendarZonesTableTable(this);
  late final $AiThreadsTableTable aiThreadsTable = $AiThreadsTableTable(this);
  late final $AiMessagesTableTable aiMessagesTable = $AiMessagesTableTable(
    this,
  );
  late final $AiJobsTableTable aiJobsTable = $AiJobsTableTable(this);
  late final $AiBatchesTableTable aiBatchesTable = $AiBatchesTableTable(this);
  late final $AiBatchItemsTableTable aiBatchItemsTable =
      $AiBatchItemsTableTable(this);
  late final $AiBlobsTableTable aiBlobsTable = $AiBlobsTableTable(this);
  late final $ProductAliasesTableTable productAliasesTable =
      $ProductAliasesTableTable(this);
  late final $AiRulesMemoryTableTable aiRulesMemoryTable =
      $AiRulesMemoryTableTable(this);
  late final $AiSettingsTableTable aiSettingsTable = $AiSettingsTableTable(
    this,
  );
  late final Index idxActionsDoneStart = Index(
    'idx_actions_done_start',
    'CREATE INDEX idx_actions_done_start ON actions (done, start_at)',
  );
  late final Index idxActionsAlldayStart = Index(
    'idx_actions_allday_start',
    'CREATE INDEX idx_actions_allday_start ON actions (is_all_day, start_at)',
  );
  late final Index idxActionsStart = Index(
    'idx_actions_start',
    'CREATE INDEX idx_actions_start ON actions (start_at)',
  );
  late final Index idxActionsPlan = Index(
    'idx_actions_plan',
    'CREATE INDEX idx_actions_plan ON actions (plan_item_id, plan_key)',
  );
  late final Index idxDepSuccessor = Index(
    'idx_dep_successor',
    'CREATE INDEX idx_dep_successor ON action_dependencies (successor_id)',
  );
  late final Index idxOccurrenceAction = Index(
    'idx_occurrence_action',
    'CREATE INDEX idx_occurrence_action ON action_occurrences (action_id)',
  );
  late final Index idxActionMetricsMetric = Index(
    'idx_action_metrics_metric',
    'CREATE INDEX idx_action_metrics_metric ON action_metrics (metric_id)',
  );
  late final Index idxMetricDepDependsOn = Index(
    'idx_metric_dep_depends_on',
    'CREATE INDEX idx_metric_dep_depends_on ON metric_dependencies (depends_on_id)',
  );
  late final Index idxBudgetCategoriesParent = Index(
    'idx_budget_categories_parent',
    'CREATE INDEX idx_budget_categories_parent ON budget_categories (parent_id)',
  );
  late final Index idxBudgetTxCategory = Index(
    'idx_budget_tx_category',
    'CREATE INDEX idx_budget_tx_category ON budget_transactions (category_id)',
  );
  late final Index idxBudgetTxAction = Index(
    'idx_budget_tx_action',
    'CREATE INDEX idx_budget_tx_action ON budget_transactions (action_id)',
  );
  late final Index idxPlanOverridesItem = Index(
    'idx_plan_overrides_item',
    'CREATE INDEX idx_plan_overrides_item ON plan_overrides (plan_item_id)',
  );
  late final Index idxAiMessagesThread = Index(
    'idx_ai_messages_thread',
    'CREATE INDEX idx_ai_messages_thread ON ai_messages (thread_id, created_at)',
  );
  late final Index idxAiJobsState = Index(
    'idx_ai_jobs_state',
    'CREATE INDEX idx_ai_jobs_state ON ai_jobs (state)',
  );
  late final Index idxAiBatchesJob = Index(
    'idx_ai_batches_job',
    'CREATE INDEX idx_ai_batches_job ON ai_batches (job_id)',
  );
  late final Index idxAiBatchItemsBatch = Index(
    'idx_ai_batch_items_batch',
    'CREATE INDEX idx_ai_batch_items_batch ON ai_batch_items (batch_id)',
  );
  late final Index idxAiBatchItemsEntity = Index(
    'idx_ai_batch_items_entity',
    'CREATE INDEX idx_ai_batch_items_entity ON ai_batch_items (entity_type, entity_id)',
  );
  late final Index idxAiBlobsMessage = Index(
    'idx_ai_blobs_message',
    'CREATE INDEX idx_ai_blobs_message ON ai_blobs (message_id)',
  );
  late final Index idxProductAliasesPattern = Index(
    'idx_product_aliases_pattern',
    'CREATE INDEX idx_product_aliases_pattern ON product_aliases (pattern)',
  );
  late final Index idxAiRulesKey = Index(
    'idx_ai_rules_key',
    'CREATE INDEX idx_ai_rules_key ON ai_rules_memory ("key")',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    countableActivitiesTable,
    actionsTable,
    actionDependenciesTable,
    actionOccurrencesTable,
    metricsTable,
    actionMetricsTable,
    actionTemplatesTable,
    metricDependenciesTable,
    budgetAccountsTable,
    budgetCategoriesTable,
    budgetTransactionsTable,
    budgetSettingsTable,
    savedViewsTable,
    planItemsTable,
    planOverridesTable,
    budgetTxTemplatesTable,
    planCollectionsTable,
    formsTable,
    calendarZonesTable,
    aiThreadsTable,
    aiMessagesTable,
    aiJobsTable,
    aiBatchesTable,
    aiBatchItemsTable,
    aiBlobsTable,
    productAliasesTable,
    aiRulesMemoryTable,
    aiSettingsTable,
    idxActionsDoneStart,
    idxActionsAlldayStart,
    idxActionsStart,
    idxActionsPlan,
    idxDepSuccessor,
    idxOccurrenceAction,
    idxActionMetricsMetric,
    idxMetricDepDependsOn,
    idxBudgetCategoriesParent,
    idxBudgetTxCategory,
    idxBudgetTxAction,
    idxPlanOverridesItem,
    idxAiMessagesThread,
    idxAiJobsState,
    idxAiBatchesJob,
    idxAiBatchItemsBatch,
    idxAiBatchItemsEntity,
    idxAiBlobsMessage,
    idxProductAliasesPattern,
    idxAiRulesKey,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'countable_activities',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('actions', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'actions',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('action_dependencies', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'actions',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('action_dependencies', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'actions',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('action_occurrences', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'actions',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('action_metrics', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'metrics',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('action_metrics', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'metrics',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('metric_dependencies', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'metrics',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('metric_dependencies', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'budget_categories',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('budget_categories', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'budget_categories',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('budget_categories', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'budget_accounts',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('budget_categories', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'budget_accounts',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('budget_categories', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'budget_categories',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('budget_transactions', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'actions',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('budget_transactions', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'budget_accounts',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('budget_transactions', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'budget_accounts',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('budget_transactions', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'plan_items',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('plan_overrides', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$CountableActivitiesTableTableCreateCompanionBuilder =
    CountableActivitiesTableCompanion Function({
      required String id,
      required String name,
      required String createdAt,
      required String updatedAt,
      Value<int> rowid,
    });
typedef $$CountableActivitiesTableTableUpdateCompanionBuilder =
    CountableActivitiesTableCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> createdAt,
      Value<String> updatedAt,
      Value<int> rowid,
    });

final class $$CountableActivitiesTableTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $CountableActivitiesTableTable,
          CountableActivity
        > {
  $$CountableActivitiesTableTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$ActionsTableTable, List<ActionRow>>
  _actionsTableRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.actionsTable,
    aliasName: 'countable_activities__id__actions__countable_activity_id',
  );

  $$ActionsTableTableProcessedTableManager get actionsTableRefs {
    final manager = $$ActionsTableTableTableManager($_db, $_db.actionsTable)
        .filter(
          (f) =>
              f.countableActivityId.id.sqlEquals($_itemColumn<String>('id')!),
        );

    final cache = $_typedResult.readTableOrNull(_actionsTableRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$CountableActivitiesTableTableFilterComposer
    extends Composer<_$AppDatabase, $CountableActivitiesTableTable> {
  $$CountableActivitiesTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> actionsTableRefs(
    Expression<bool> Function($$ActionsTableTableFilterComposer f) f,
  ) {
    final $$ActionsTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.actionsTable,
      getReferencedColumn: (t) => t.countableActivityId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionsTableTableFilterComposer(
            $db: $db,
            $table: $db.actionsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CountableActivitiesTableTableOrderingComposer
    extends Composer<_$AppDatabase, $CountableActivitiesTableTable> {
  $$CountableActivitiesTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CountableActivitiesTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $CountableActivitiesTableTable> {
  $$CountableActivitiesTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> actionsTableRefs<T extends Object>(
    Expression<T> Function($$ActionsTableTableAnnotationComposer a) f,
  ) {
    final $$ActionsTableTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.actionsTable,
      getReferencedColumn: (t) => t.countableActivityId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionsTableTableAnnotationComposer(
            $db: $db,
            $table: $db.actionsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CountableActivitiesTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CountableActivitiesTableTable,
          CountableActivity,
          $$CountableActivitiesTableTableFilterComposer,
          $$CountableActivitiesTableTableOrderingComposer,
          $$CountableActivitiesTableTableAnnotationComposer,
          $$CountableActivitiesTableTableCreateCompanionBuilder,
          $$CountableActivitiesTableTableUpdateCompanionBuilder,
          (CountableActivity, $$CountableActivitiesTableTableReferences),
          CountableActivity,
          PrefetchHooks Function({bool actionsTableRefs})
        > {
  $$CountableActivitiesTableTableTableManager(
    _$AppDatabase db,
    $CountableActivitiesTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CountableActivitiesTableTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$CountableActivitiesTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$CountableActivitiesTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CountableActivitiesTableCompanion(
                id: id,
                name: name,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String createdAt,
                required String updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => CountableActivitiesTableCompanion.insert(
                id: id,
                name: name,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<
                    $CountableActivitiesTableTable,
                    CountableActivity
                  >(table),
                  $$CountableActivitiesTableTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({actionsTableRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (actionsTableRefs) db.actionsTable],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (actionsTableRefs)
                    await $_getPrefetchedData<
                      CountableActivity,
                      $CountableActivitiesTableTable,
                      ActionRow
                    >(
                      currentTable: table,
                      referencedTable: $$CountableActivitiesTableTableReferences
                          ._actionsTableRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$CountableActivitiesTableTableReferences(
                            db,
                            table,
                            p0,
                          ).actionsTableRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where(
                            (e) => e.countableActivityId == item.id,
                          ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$CountableActivitiesTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CountableActivitiesTableTable,
      CountableActivity,
      $$CountableActivitiesTableTableFilterComposer,
      $$CountableActivitiesTableTableOrderingComposer,
      $$CountableActivitiesTableTableAnnotationComposer,
      $$CountableActivitiesTableTableCreateCompanionBuilder,
      $$CountableActivitiesTableTableUpdateCompanionBuilder,
      (CountableActivity, $$CountableActivitiesTableTableReferences),
      CountableActivity,
      PrefetchHooks Function({bool actionsTableRefs})
    >;
typedef $$ActionsTableTableCreateCompanionBuilder =
    ActionsTableCompanion Function({
      required String id,
      required String name,
      Value<bool> done,
      Value<String> postponeFlex,
      Value<String?> depthLevel,
      Value<String?> startAt,
      Value<String?> endAt,
      Value<bool> isAllDay,
      Value<int?> estimatedMinutes,
      Value<String?> resultNote,
      Value<String?> notes,
      Value<String?> notesText,
      Value<String?> completedAt,
      Value<int?> sequenceNumber,
      Value<String?> countableActivityId,
      Value<String?> planItemId,
      Value<String?> planKey,
      required String createdAt,
      required String updatedAt,
      Value<int> rowid,
    });
typedef $$ActionsTableTableUpdateCompanionBuilder =
    ActionsTableCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<bool> done,
      Value<String> postponeFlex,
      Value<String?> depthLevel,
      Value<String?> startAt,
      Value<String?> endAt,
      Value<bool> isAllDay,
      Value<int?> estimatedMinutes,
      Value<String?> resultNote,
      Value<String?> notes,
      Value<String?> notesText,
      Value<String?> completedAt,
      Value<int?> sequenceNumber,
      Value<String?> countableActivityId,
      Value<String?> planItemId,
      Value<String?> planKey,
      Value<String> createdAt,
      Value<String> updatedAt,
      Value<int> rowid,
    });

final class $$ActionsTableTableReferences
    extends BaseReferences<_$AppDatabase, $ActionsTableTable, ActionRow> {
  $$ActionsTableTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $CountableActivitiesTableTable _countableActivityIdTable(
    _$AppDatabase db,
  ) => db.countableActivitiesTable.createAlias(
    'actions__countable_activity_id__countable_activities__id',
  );

  $$CountableActivitiesTableTableProcessedTableManager?
  get countableActivityId {
    final $_column = $_itemColumn<String>('countable_activity_id');
    if ($_column == null) return null;
    final manager = $$CountableActivitiesTableTableTableManager(
      $_db,
      $_db.countableActivitiesTable,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_countableActivityIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<
    $ActionDependenciesTableTable,
    List<ActionDependency>
  >
  _predecessorDependenciesTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.actionDependenciesTable,
        aliasName: 'actions__id__action_dependencies__predecessor_id',
      );

  $$ActionDependenciesTableTableProcessedTableManager
  get predecessorDependencies {
    final manager = $$ActionDependenciesTableTableTableManager(
      $_db,
      $_db.actionDependenciesTable,
    ).filter((f) => f.predecessorId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _predecessorDependenciesTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $ActionDependenciesTableTable,
    List<ActionDependency>
  >
  _successorDependenciesTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.actionDependenciesTable,
        aliasName: 'actions__id__action_dependencies__successor_id',
      );

  $$ActionDependenciesTableTableProcessedTableManager
  get successorDependencies {
    final manager = $$ActionDependenciesTableTableTableManager(
      $_db,
      $_db.actionDependenciesTable,
    ).filter((f) => f.successorId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _successorDependenciesTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $ActionOccurrencesTableTable,
    List<ActionOccurrence>
  >
  _actionOccurrencesTableRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.actionOccurrencesTable,
        aliasName: 'actions__id__action_occurrences__action_id',
      );

  $$ActionOccurrencesTableTableProcessedTableManager
  get actionOccurrencesTableRefs {
    final manager = $$ActionOccurrencesTableTableTableManager(
      $_db,
      $_db.actionOccurrencesTable,
    ).filter((f) => f.actionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _actionOccurrencesTableRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ActionMetricsTableTable, List<ActionMetric>>
  _actionMetricsTableRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.actionMetricsTable,
        aliasName: 'actions__id__action_metrics__action_id',
      );

  $$ActionMetricsTableTableProcessedTableManager get actionMetricsTableRefs {
    final manager = $$ActionMetricsTableTableTableManager(
      $_db,
      $_db.actionMetricsTable,
    ).filter((f) => f.actionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _actionMetricsTableRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $BudgetTransactionsTableTable,
    List<BudgetTransaction>
  >
  _budgetTransactionsTableRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.budgetTransactionsTable,
        aliasName: 'actions__id__budget_transactions__action_id',
      );

  $$BudgetTransactionsTableTableProcessedTableManager
  get budgetTransactionsTableRefs {
    final manager = $$BudgetTransactionsTableTableTableManager(
      $_db,
      $_db.budgetTransactionsTable,
    ).filter((f) => f.actionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _budgetTransactionsTableRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ActionsTableTableFilterComposer
    extends Composer<_$AppDatabase, $ActionsTableTable> {
  $$ActionsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get done => $composableBuilder(
    column: $table.done,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get postponeFlex => $composableBuilder(
    column: $table.postponeFlex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get depthLevel => $composableBuilder(
    column: $table.depthLevel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get startAt => $composableBuilder(
    column: $table.startAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get endAt => $composableBuilder(
    column: $table.endAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isAllDay => $composableBuilder(
    column: $table.isAllDay,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get estimatedMinutes => $composableBuilder(
    column: $table.estimatedMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get resultNote => $composableBuilder(
    column: $table.resultNote,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notesText => $composableBuilder(
    column: $table.notesText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sequenceNumber => $composableBuilder(
    column: $table.sequenceNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get planItemId => $composableBuilder(
    column: $table.planItemId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get planKey => $composableBuilder(
    column: $table.planKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$CountableActivitiesTableTableFilterComposer get countableActivityId {
    final $$CountableActivitiesTableTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.countableActivityId,
          referencedTable: $db.countableActivitiesTable,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$CountableActivitiesTableTableFilterComposer(
                $db: $db,
                $table: $db.countableActivitiesTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }

  Expression<bool> predecessorDependencies(
    Expression<bool> Function($$ActionDependenciesTableTableFilterComposer f) f,
  ) {
    final $$ActionDependenciesTableTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.actionDependenciesTable,
          getReferencedColumn: (t) => t.predecessorId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ActionDependenciesTableTableFilterComposer(
                $db: $db,
                $table: $db.actionDependenciesTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<bool> successorDependencies(
    Expression<bool> Function($$ActionDependenciesTableTableFilterComposer f) f,
  ) {
    final $$ActionDependenciesTableTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.actionDependenciesTable,
          getReferencedColumn: (t) => t.successorId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ActionDependenciesTableTableFilterComposer(
                $db: $db,
                $table: $db.actionDependenciesTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<bool> actionOccurrencesTableRefs(
    Expression<bool> Function($$ActionOccurrencesTableTableFilterComposer f) f,
  ) {
    final $$ActionOccurrencesTableTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.actionOccurrencesTable,
          getReferencedColumn: (t) => t.actionId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ActionOccurrencesTableTableFilterComposer(
                $db: $db,
                $table: $db.actionOccurrencesTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<bool> actionMetricsTableRefs(
    Expression<bool> Function($$ActionMetricsTableTableFilterComposer f) f,
  ) {
    final $$ActionMetricsTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.actionMetricsTable,
      getReferencedColumn: (t) => t.actionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionMetricsTableTableFilterComposer(
            $db: $db,
            $table: $db.actionMetricsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> budgetTransactionsTableRefs(
    Expression<bool> Function($$BudgetTransactionsTableTableFilterComposer f) f,
  ) {
    final $$BudgetTransactionsTableTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.budgetTransactionsTable,
          getReferencedColumn: (t) => t.actionId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$BudgetTransactionsTableTableFilterComposer(
                $db: $db,
                $table: $db.budgetTransactionsTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$ActionsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $ActionsTableTable> {
  $$ActionsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get done => $composableBuilder(
    column: $table.done,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get postponeFlex => $composableBuilder(
    column: $table.postponeFlex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get depthLevel => $composableBuilder(
    column: $table.depthLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get startAt => $composableBuilder(
    column: $table.startAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get endAt => $composableBuilder(
    column: $table.endAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isAllDay => $composableBuilder(
    column: $table.isAllDay,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get estimatedMinutes => $composableBuilder(
    column: $table.estimatedMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get resultNote => $composableBuilder(
    column: $table.resultNote,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notesText => $composableBuilder(
    column: $table.notesText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sequenceNumber => $composableBuilder(
    column: $table.sequenceNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get planItemId => $composableBuilder(
    column: $table.planItemId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get planKey => $composableBuilder(
    column: $table.planKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$CountableActivitiesTableTableOrderingComposer get countableActivityId {
    final $$CountableActivitiesTableTableOrderingComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.countableActivityId,
          referencedTable: $db.countableActivitiesTable,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$CountableActivitiesTableTableOrderingComposer(
                $db: $db,
                $table: $db.countableActivitiesTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$ActionsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $ActionsTableTable> {
  $$ActionsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<bool> get done =>
      $composableBuilder(column: $table.done, builder: (column) => column);

  GeneratedColumn<String> get postponeFlex => $composableBuilder(
    column: $table.postponeFlex,
    builder: (column) => column,
  );

  GeneratedColumn<String> get depthLevel => $composableBuilder(
    column: $table.depthLevel,
    builder: (column) => column,
  );

  GeneratedColumn<String> get startAt =>
      $composableBuilder(column: $table.startAt, builder: (column) => column);

  GeneratedColumn<String> get endAt =>
      $composableBuilder(column: $table.endAt, builder: (column) => column);

  GeneratedColumn<bool> get isAllDay =>
      $composableBuilder(column: $table.isAllDay, builder: (column) => column);

  GeneratedColumn<int> get estimatedMinutes => $composableBuilder(
    column: $table.estimatedMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<String> get resultNote => $composableBuilder(
    column: $table.resultNote,
    builder: (column) => column,
  );

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<String> get notesText =>
      $composableBuilder(column: $table.notesText, builder: (column) => column);

  GeneratedColumn<String> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sequenceNumber => $composableBuilder(
    column: $table.sequenceNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get planItemId => $composableBuilder(
    column: $table.planItemId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get planKey =>
      $composableBuilder(column: $table.planKey, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$CountableActivitiesTableTableAnnotationComposer get countableActivityId {
    final $$CountableActivitiesTableTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.countableActivityId,
          referencedTable: $db.countableActivitiesTable,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$CountableActivitiesTableTableAnnotationComposer(
                $db: $db,
                $table: $db.countableActivitiesTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }

  Expression<T> predecessorDependencies<T extends Object>(
    Expression<T> Function($$ActionDependenciesTableTableAnnotationComposer a)
    f,
  ) {
    final $$ActionDependenciesTableTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.actionDependenciesTable,
          getReferencedColumn: (t) => t.predecessorId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ActionDependenciesTableTableAnnotationComposer(
                $db: $db,
                $table: $db.actionDependenciesTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> successorDependencies<T extends Object>(
    Expression<T> Function($$ActionDependenciesTableTableAnnotationComposer a)
    f,
  ) {
    final $$ActionDependenciesTableTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.actionDependenciesTable,
          getReferencedColumn: (t) => t.successorId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ActionDependenciesTableTableAnnotationComposer(
                $db: $db,
                $table: $db.actionDependenciesTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> actionOccurrencesTableRefs<T extends Object>(
    Expression<T> Function($$ActionOccurrencesTableTableAnnotationComposer a) f,
  ) {
    final $$ActionOccurrencesTableTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.actionOccurrencesTable,
          getReferencedColumn: (t) => t.actionId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ActionOccurrencesTableTableAnnotationComposer(
                $db: $db,
                $table: $db.actionOccurrencesTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> actionMetricsTableRefs<T extends Object>(
    Expression<T> Function($$ActionMetricsTableTableAnnotationComposer a) f,
  ) {
    final $$ActionMetricsTableTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.actionMetricsTable,
          getReferencedColumn: (t) => t.actionId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ActionMetricsTableTableAnnotationComposer(
                $db: $db,
                $table: $db.actionMetricsTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> budgetTransactionsTableRefs<T extends Object>(
    Expression<T> Function($$BudgetTransactionsTableTableAnnotationComposer a)
    f,
  ) {
    final $$BudgetTransactionsTableTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.budgetTransactionsTable,
          getReferencedColumn: (t) => t.actionId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$BudgetTransactionsTableTableAnnotationComposer(
                $db: $db,
                $table: $db.budgetTransactionsTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$ActionsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ActionsTableTable,
          ActionRow,
          $$ActionsTableTableFilterComposer,
          $$ActionsTableTableOrderingComposer,
          $$ActionsTableTableAnnotationComposer,
          $$ActionsTableTableCreateCompanionBuilder,
          $$ActionsTableTableUpdateCompanionBuilder,
          (ActionRow, $$ActionsTableTableReferences),
          ActionRow,
          PrefetchHooks Function({
            bool countableActivityId,
            bool predecessorDependencies,
            bool successorDependencies,
            bool actionOccurrencesTableRefs,
            bool actionMetricsTableRefs,
            bool budgetTransactionsTableRefs,
          })
        > {
  $$ActionsTableTableTableManager(_$AppDatabase db, $ActionsTableTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ActionsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ActionsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ActionsTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<bool> done = const Value.absent(),
                Value<String> postponeFlex = const Value.absent(),
                Value<String?> depthLevel = const Value.absent(),
                Value<String?> startAt = const Value.absent(),
                Value<String?> endAt = const Value.absent(),
                Value<bool> isAllDay = const Value.absent(),
                Value<int?> estimatedMinutes = const Value.absent(),
                Value<String?> resultNote = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<String?> notesText = const Value.absent(),
                Value<String?> completedAt = const Value.absent(),
                Value<int?> sequenceNumber = const Value.absent(),
                Value<String?> countableActivityId = const Value.absent(),
                Value<String?> planItemId = const Value.absent(),
                Value<String?> planKey = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ActionsTableCompanion(
                id: id,
                name: name,
                done: done,
                postponeFlex: postponeFlex,
                depthLevel: depthLevel,
                startAt: startAt,
                endAt: endAt,
                isAllDay: isAllDay,
                estimatedMinutes: estimatedMinutes,
                resultNote: resultNote,
                notes: notes,
                notesText: notesText,
                completedAt: completedAt,
                sequenceNumber: sequenceNumber,
                countableActivityId: countableActivityId,
                planItemId: planItemId,
                planKey: planKey,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<bool> done = const Value.absent(),
                Value<String> postponeFlex = const Value.absent(),
                Value<String?> depthLevel = const Value.absent(),
                Value<String?> startAt = const Value.absent(),
                Value<String?> endAt = const Value.absent(),
                Value<bool> isAllDay = const Value.absent(),
                Value<int?> estimatedMinutes = const Value.absent(),
                Value<String?> resultNote = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<String?> notesText = const Value.absent(),
                Value<String?> completedAt = const Value.absent(),
                Value<int?> sequenceNumber = const Value.absent(),
                Value<String?> countableActivityId = const Value.absent(),
                Value<String?> planItemId = const Value.absent(),
                Value<String?> planKey = const Value.absent(),
                required String createdAt,
                required String updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ActionsTableCompanion.insert(
                id: id,
                name: name,
                done: done,
                postponeFlex: postponeFlex,
                depthLevel: depthLevel,
                startAt: startAt,
                endAt: endAt,
                isAllDay: isAllDay,
                estimatedMinutes: estimatedMinutes,
                resultNote: resultNote,
                notes: notes,
                notesText: notesText,
                completedAt: completedAt,
                sequenceNumber: sequenceNumber,
                countableActivityId: countableActivityId,
                planItemId: planItemId,
                planKey: planKey,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ActionsTableTable, ActionRow>(table),
                  $$ActionsTableTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                countableActivityId = false,
                predecessorDependencies = false,
                successorDependencies = false,
                actionOccurrencesTableRefs = false,
                actionMetricsTableRefs = false,
                budgetTransactionsTableRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (predecessorDependencies) db.actionDependenciesTable,
                    if (successorDependencies) db.actionDependenciesTable,
                    if (actionOccurrencesTableRefs) db.actionOccurrencesTable,
                    if (actionMetricsTableRefs) db.actionMetricsTable,
                    if (budgetTransactionsTableRefs) db.budgetTransactionsTable,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (countableActivityId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.countableActivityId,
                            referencedTable: $$ActionsTableTableReferences
                                ._countableActivityIdTable(db),
                            referencedColumn: $$ActionsTableTableReferences
                                ._countableActivityIdTable(db)
                                .id,
                          ) as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (predecessorDependencies)
                        await $_getPrefetchedData<
                          ActionRow,
                          $ActionsTableTable,
                          ActionDependency
                        >(
                          currentTable: table,
                          referencedTable: $$ActionsTableTableReferences
                              ._predecessorDependenciesTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ActionsTableTableReferences(
                                db,
                                table,
                                p0,
                              ).predecessorDependencies,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.predecessorId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (successorDependencies)
                        await $_getPrefetchedData<
                          ActionRow,
                          $ActionsTableTable,
                          ActionDependency
                        >(
                          currentTable: table,
                          referencedTable: $$ActionsTableTableReferences
                              ._successorDependenciesTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ActionsTableTableReferences(
                                db,
                                table,
                                p0,
                              ).successorDependencies,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.successorId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (actionOccurrencesTableRefs)
                        await $_getPrefetchedData<
                          ActionRow,
                          $ActionsTableTable,
                          ActionOccurrence
                        >(
                          currentTable: table,
                          referencedTable: $$ActionsTableTableReferences
                              ._actionOccurrencesTableRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ActionsTableTableReferences(
                                db,
                                table,
                                p0,
                              ).actionOccurrencesTableRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.actionId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (actionMetricsTableRefs)
                        await $_getPrefetchedData<
                          ActionRow,
                          $ActionsTableTable,
                          ActionMetric
                        >(
                          currentTable: table,
                          referencedTable: $$ActionsTableTableReferences
                              ._actionMetricsTableRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ActionsTableTableReferences(
                                db,
                                table,
                                p0,
                              ).actionMetricsTableRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.actionId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (budgetTransactionsTableRefs)
                        await $_getPrefetchedData<
                          ActionRow,
                          $ActionsTableTable,
                          BudgetTransaction
                        >(
                          currentTable: table,
                          referencedTable: $$ActionsTableTableReferences
                              ._budgetTransactionsTableRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ActionsTableTableReferences(
                                db,
                                table,
                                p0,
                              ).budgetTransactionsTableRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.actionId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$ActionsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ActionsTableTable,
      ActionRow,
      $$ActionsTableTableFilterComposer,
      $$ActionsTableTableOrderingComposer,
      $$ActionsTableTableAnnotationComposer,
      $$ActionsTableTableCreateCompanionBuilder,
      $$ActionsTableTableUpdateCompanionBuilder,
      (ActionRow, $$ActionsTableTableReferences),
      ActionRow,
      PrefetchHooks Function({
        bool countableActivityId,
        bool predecessorDependencies,
        bool successorDependencies,
        bool actionOccurrencesTableRefs,
        bool actionMetricsTableRefs,
        bool budgetTransactionsTableRefs,
      })
    >;
typedef $$ActionDependenciesTableTableCreateCompanionBuilder =
    ActionDependenciesTableCompanion Function({
      required String id,
      required String predecessorId,
      required String successorId,
      Value<int> rowid,
    });
typedef $$ActionDependenciesTableTableUpdateCompanionBuilder =
    ActionDependenciesTableCompanion Function({
      Value<String> id,
      Value<String> predecessorId,
      Value<String> successorId,
      Value<int> rowid,
    });

final class $$ActionDependenciesTableTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $ActionDependenciesTableTable,
          ActionDependency
        > {
  $$ActionDependenciesTableTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ActionsTableTable _predecessorIdTable(_$AppDatabase db) => db
      .actionsTable
      .createAlias('action_dependencies__predecessor_id__actions__id');

  $$ActionsTableTableProcessedTableManager get predecessorId {
    final $_column = $_itemColumn<String>('predecessor_id')!;

    final manager = $$ActionsTableTableTableManager(
      $_db,
      $_db.actionsTable,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_predecessorIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $ActionsTableTable _successorIdTable(_$AppDatabase db) => db
      .actionsTable
      .createAlias('action_dependencies__successor_id__actions__id');

  $$ActionsTableTableProcessedTableManager get successorId {
    final $_column = $_itemColumn<String>('successor_id')!;

    final manager = $$ActionsTableTableTableManager(
      $_db,
      $_db.actionsTable,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_successorIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ActionDependenciesTableTableFilterComposer
    extends Composer<_$AppDatabase, $ActionDependenciesTableTable> {
  $$ActionDependenciesTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  $$ActionsTableTableFilterComposer get predecessorId {
    final $$ActionsTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.predecessorId,
      referencedTable: $db.actionsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionsTableTableFilterComposer(
            $db: $db,
            $table: $db.actionsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ActionsTableTableFilterComposer get successorId {
    final $$ActionsTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.successorId,
      referencedTable: $db.actionsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionsTableTableFilterComposer(
            $db: $db,
            $table: $db.actionsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ActionDependenciesTableTableOrderingComposer
    extends Composer<_$AppDatabase, $ActionDependenciesTableTable> {
  $$ActionDependenciesTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  $$ActionsTableTableOrderingComposer get predecessorId {
    final $$ActionsTableTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.predecessorId,
      referencedTable: $db.actionsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionsTableTableOrderingComposer(
            $db: $db,
            $table: $db.actionsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ActionsTableTableOrderingComposer get successorId {
    final $$ActionsTableTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.successorId,
      referencedTable: $db.actionsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionsTableTableOrderingComposer(
            $db: $db,
            $table: $db.actionsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ActionDependenciesTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $ActionDependenciesTableTable> {
  $$ActionDependenciesTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  $$ActionsTableTableAnnotationComposer get predecessorId {
    final $$ActionsTableTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.predecessorId,
      referencedTable: $db.actionsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionsTableTableAnnotationComposer(
            $db: $db,
            $table: $db.actionsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ActionsTableTableAnnotationComposer get successorId {
    final $$ActionsTableTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.successorId,
      referencedTable: $db.actionsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionsTableTableAnnotationComposer(
            $db: $db,
            $table: $db.actionsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ActionDependenciesTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ActionDependenciesTableTable,
          ActionDependency,
          $$ActionDependenciesTableTableFilterComposer,
          $$ActionDependenciesTableTableOrderingComposer,
          $$ActionDependenciesTableTableAnnotationComposer,
          $$ActionDependenciesTableTableCreateCompanionBuilder,
          $$ActionDependenciesTableTableUpdateCompanionBuilder,
          (ActionDependency, $$ActionDependenciesTableTableReferences),
          ActionDependency,
          PrefetchHooks Function({bool predecessorId, bool successorId})
        > {
  $$ActionDependenciesTableTableTableManager(
    _$AppDatabase db,
    $ActionDependenciesTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ActionDependenciesTableTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$ActionDependenciesTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ActionDependenciesTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> predecessorId = const Value.absent(),
                Value<String> successorId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ActionDependenciesTableCompanion(
                id: id,
                predecessorId: predecessorId,
                successorId: successorId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String predecessorId,
                required String successorId,
                Value<int> rowid = const Value.absent(),
              }) => ActionDependenciesTableCompanion.insert(
                id: id,
                predecessorId: predecessorId,
                successorId: successorId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ActionDependenciesTableTable, ActionDependency>(
                    table,
                  ),
                  $$ActionDependenciesTableTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({predecessorId = false, successorId = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (predecessorId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.predecessorId,
                            referencedTable:
                                $$ActionDependenciesTableTableReferences
                                    ._predecessorIdTable(db),
                            referencedColumn:
                                $$ActionDependenciesTableTableReferences
                                    ._predecessorIdTable(db)
                                    .id,
                          ) as T;
                        }
                        if (successorId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.successorId,
                            referencedTable:
                                $$ActionDependenciesTableTableReferences
                                    ._successorIdTable(db),
                            referencedColumn:
                                $$ActionDependenciesTableTableReferences
                                    ._successorIdTable(db)
                                    .id,
                          ) as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [];
                  },
                );
              },
        ),
      );
}

typedef $$ActionDependenciesTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ActionDependenciesTableTable,
      ActionDependency,
      $$ActionDependenciesTableTableFilterComposer,
      $$ActionDependenciesTableTableOrderingComposer,
      $$ActionDependenciesTableTableAnnotationComposer,
      $$ActionDependenciesTableTableCreateCompanionBuilder,
      $$ActionDependenciesTableTableUpdateCompanionBuilder,
      (ActionDependency, $$ActionDependenciesTableTableReferences),
      ActionDependency,
      PrefetchHooks Function({bool predecessorId, bool successorId})
    >;
typedef $$ActionOccurrencesTableTableCreateCompanionBuilder =
    ActionOccurrencesTableCompanion Function({
      required String id,
      required String actionId,
      Value<String?> startedAt,
      Value<String?> finishedAt,
      Value<String?> outcome,
      Value<int> rowid,
    });
typedef $$ActionOccurrencesTableTableUpdateCompanionBuilder =
    ActionOccurrencesTableCompanion Function({
      Value<String> id,
      Value<String> actionId,
      Value<String?> startedAt,
      Value<String?> finishedAt,
      Value<String?> outcome,
      Value<int> rowid,
    });

final class $$ActionOccurrencesTableTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $ActionOccurrencesTableTable,
          ActionOccurrence
        > {
  $$ActionOccurrencesTableTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ActionsTableTable _actionIdTable(_$AppDatabase db) =>
      db.actionsTable.createAlias('action_occurrences__action_id__actions__id');

  $$ActionsTableTableProcessedTableManager get actionId {
    final $_column = $_itemColumn<String>('action_id')!;

    final manager = $$ActionsTableTableTableManager(
      $_db,
      $_db.actionsTable,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_actionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ActionOccurrencesTableTableFilterComposer
    extends Composer<_$AppDatabase, $ActionOccurrencesTableTable> {
  $$ActionOccurrencesTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get finishedAt => $composableBuilder(
    column: $table.finishedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get outcome => $composableBuilder(
    column: $table.outcome,
    builder: (column) => ColumnFilters(column),
  );

  $$ActionsTableTableFilterComposer get actionId {
    final $$ActionsTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.actionId,
      referencedTable: $db.actionsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionsTableTableFilterComposer(
            $db: $db,
            $table: $db.actionsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ActionOccurrencesTableTableOrderingComposer
    extends Composer<_$AppDatabase, $ActionOccurrencesTableTable> {
  $$ActionOccurrencesTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get finishedAt => $composableBuilder(
    column: $table.finishedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get outcome => $composableBuilder(
    column: $table.outcome,
    builder: (column) => ColumnOrderings(column),
  );

  $$ActionsTableTableOrderingComposer get actionId {
    final $$ActionsTableTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.actionId,
      referencedTable: $db.actionsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionsTableTableOrderingComposer(
            $db: $db,
            $table: $db.actionsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ActionOccurrencesTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $ActionOccurrencesTableTable> {
  $$ActionOccurrencesTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<String> get finishedAt => $composableBuilder(
    column: $table.finishedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get outcome =>
      $composableBuilder(column: $table.outcome, builder: (column) => column);

  $$ActionsTableTableAnnotationComposer get actionId {
    final $$ActionsTableTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.actionId,
      referencedTable: $db.actionsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionsTableTableAnnotationComposer(
            $db: $db,
            $table: $db.actionsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ActionOccurrencesTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ActionOccurrencesTableTable,
          ActionOccurrence,
          $$ActionOccurrencesTableTableFilterComposer,
          $$ActionOccurrencesTableTableOrderingComposer,
          $$ActionOccurrencesTableTableAnnotationComposer,
          $$ActionOccurrencesTableTableCreateCompanionBuilder,
          $$ActionOccurrencesTableTableUpdateCompanionBuilder,
          (ActionOccurrence, $$ActionOccurrencesTableTableReferences),
          ActionOccurrence,
          PrefetchHooks Function({bool actionId})
        > {
  $$ActionOccurrencesTableTableTableManager(
    _$AppDatabase db,
    $ActionOccurrencesTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ActionOccurrencesTableTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$ActionOccurrencesTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ActionOccurrencesTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> actionId = const Value.absent(),
                Value<String?> startedAt = const Value.absent(),
                Value<String?> finishedAt = const Value.absent(),
                Value<String?> outcome = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ActionOccurrencesTableCompanion(
                id: id,
                actionId: actionId,
                startedAt: startedAt,
                finishedAt: finishedAt,
                outcome: outcome,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String actionId,
                Value<String?> startedAt = const Value.absent(),
                Value<String?> finishedAt = const Value.absent(),
                Value<String?> outcome = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ActionOccurrencesTableCompanion.insert(
                id: id,
                actionId: actionId,
                startedAt: startedAt,
                finishedAt: finishedAt,
                outcome: outcome,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ActionOccurrencesTableTable, ActionOccurrence>(
                    table,
                  ),
                  $$ActionOccurrencesTableTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({actionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (actionId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.actionId,
                        referencedTable: $$ActionOccurrencesTableTableReferences
                            ._actionIdTable(db),
                        referencedColumn:
                            $$ActionOccurrencesTableTableReferences
                                ._actionIdTable(db)
                                .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ActionOccurrencesTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ActionOccurrencesTableTable,
      ActionOccurrence,
      $$ActionOccurrencesTableTableFilterComposer,
      $$ActionOccurrencesTableTableOrderingComposer,
      $$ActionOccurrencesTableTableAnnotationComposer,
      $$ActionOccurrencesTableTableCreateCompanionBuilder,
      $$ActionOccurrencesTableTableUpdateCompanionBuilder,
      (ActionOccurrence, $$ActionOccurrencesTableTableReferences),
      ActionOccurrence,
      PrefetchHooks Function({bool actionId})
    >;
typedef $$MetricsTableTableCreateCompanionBuilder =
    MetricsTableCompanion Function({
      required String id,
      required String name,
      Value<double> weight,
      Value<String> kind,
      Value<String?> timeWindow,
      Value<double> target,
      Value<bool> isMain,
      Value<int> importanceLevel,
      Value<String?> icon,
      Value<double?> posX,
      Value<double?> posY,
      Value<int> rowid,
    });
typedef $$MetricsTableTableUpdateCompanionBuilder =
    MetricsTableCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<double> weight,
      Value<String> kind,
      Value<String?> timeWindow,
      Value<double> target,
      Value<bool> isMain,
      Value<int> importanceLevel,
      Value<String?> icon,
      Value<double?> posX,
      Value<double?> posY,
      Value<int> rowid,
    });

final class $$MetricsTableTableReferences
    extends BaseReferences<_$AppDatabase, $MetricsTableTable, Metric> {
  $$MetricsTableTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$ActionMetricsTableTable, List<ActionMetric>>
  _actionMetricsTableRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.actionMetricsTable,
        aliasName: 'metrics__id__action_metrics__metric_id',
      );

  $$ActionMetricsTableTableProcessedTableManager get actionMetricsTableRefs {
    final manager = $$ActionMetricsTableTableTableManager(
      $_db,
      $_db.actionMetricsTable,
    ).filter((f) => f.metricId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _actionMetricsTableRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $MetricDependenciesTableTable,
    List<MetricDependency>
  >
  _dependentMetricLinksTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.metricDependenciesTable,
    aliasName: 'metrics__id__metric_dependencies__metric_id',
  );

  $$MetricDependenciesTableTableProcessedTableManager get dependentMetricLinks {
    final manager = $$MetricDependenciesTableTableTableManager(
      $_db,
      $_db.metricDependenciesTable,
    ).filter((f) => f.metricId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _dependentMetricLinksTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $MetricDependenciesTableTable,
    List<MetricDependency>
  >
  _contributingMetricLinksTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.metricDependenciesTable,
        aliasName: 'metrics__id__metric_dependencies__depends_on_id',
      );

  $$MetricDependenciesTableTableProcessedTableManager
  get contributingMetricLinks {
    final manager = $$MetricDependenciesTableTableTableManager(
      $_db,
      $_db.metricDependenciesTable,
    ).filter((f) => f.dependsOnId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _contributingMetricLinksTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$MetricsTableTableFilterComposer
    extends Composer<_$AppDatabase, $MetricsTableTable> {
  $$MetricsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get weight => $composableBuilder(
    column: $table.weight,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get timeWindow => $composableBuilder(
    column: $table.timeWindow,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get target => $composableBuilder(
    column: $table.target,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isMain => $composableBuilder(
    column: $table.isMain,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get importanceLevel => $composableBuilder(
    column: $table.importanceLevel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get icon => $composableBuilder(
    column: $table.icon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get posX => $composableBuilder(
    column: $table.posX,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get posY => $composableBuilder(
    column: $table.posY,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> actionMetricsTableRefs(
    Expression<bool> Function($$ActionMetricsTableTableFilterComposer f) f,
  ) {
    final $$ActionMetricsTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.actionMetricsTable,
      getReferencedColumn: (t) => t.metricId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionMetricsTableTableFilterComposer(
            $db: $db,
            $table: $db.actionMetricsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> dependentMetricLinks(
    Expression<bool> Function($$MetricDependenciesTableTableFilterComposer f) f,
  ) {
    final $$MetricDependenciesTableTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.metricDependenciesTable,
          getReferencedColumn: (t) => t.metricId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$MetricDependenciesTableTableFilterComposer(
                $db: $db,
                $table: $db.metricDependenciesTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<bool> contributingMetricLinks(
    Expression<bool> Function($$MetricDependenciesTableTableFilterComposer f) f,
  ) {
    final $$MetricDependenciesTableTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.metricDependenciesTable,
          getReferencedColumn: (t) => t.dependsOnId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$MetricDependenciesTableTableFilterComposer(
                $db: $db,
                $table: $db.metricDependenciesTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$MetricsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $MetricsTableTable> {
  $$MetricsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get weight => $composableBuilder(
    column: $table.weight,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get timeWindow => $composableBuilder(
    column: $table.timeWindow,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get target => $composableBuilder(
    column: $table.target,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isMain => $composableBuilder(
    column: $table.isMain,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get importanceLevel => $composableBuilder(
    column: $table.importanceLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get icon => $composableBuilder(
    column: $table.icon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get posX => $composableBuilder(
    column: $table.posX,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get posY => $composableBuilder(
    column: $table.posY,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MetricsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $MetricsTableTable> {
  $$MetricsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<double> get weight =>
      $composableBuilder(column: $table.weight, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get timeWindow => $composableBuilder(
    column: $table.timeWindow,
    builder: (column) => column,
  );

  GeneratedColumn<double> get target =>
      $composableBuilder(column: $table.target, builder: (column) => column);

  GeneratedColumn<bool> get isMain =>
      $composableBuilder(column: $table.isMain, builder: (column) => column);

  GeneratedColumn<int> get importanceLevel => $composableBuilder(
    column: $table.importanceLevel,
    builder: (column) => column,
  );

  GeneratedColumn<String> get icon =>
      $composableBuilder(column: $table.icon, builder: (column) => column);

  GeneratedColumn<double> get posX =>
      $composableBuilder(column: $table.posX, builder: (column) => column);

  GeneratedColumn<double> get posY =>
      $composableBuilder(column: $table.posY, builder: (column) => column);

  Expression<T> actionMetricsTableRefs<T extends Object>(
    Expression<T> Function($$ActionMetricsTableTableAnnotationComposer a) f,
  ) {
    final $$ActionMetricsTableTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.actionMetricsTable,
          getReferencedColumn: (t) => t.metricId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ActionMetricsTableTableAnnotationComposer(
                $db: $db,
                $table: $db.actionMetricsTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> dependentMetricLinks<T extends Object>(
    Expression<T> Function($$MetricDependenciesTableTableAnnotationComposer a)
    f,
  ) {
    final $$MetricDependenciesTableTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.metricDependenciesTable,
          getReferencedColumn: (t) => t.metricId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$MetricDependenciesTableTableAnnotationComposer(
                $db: $db,
                $table: $db.metricDependenciesTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> contributingMetricLinks<T extends Object>(
    Expression<T> Function($$MetricDependenciesTableTableAnnotationComposer a)
    f,
  ) {
    final $$MetricDependenciesTableTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.metricDependenciesTable,
          getReferencedColumn: (t) => t.dependsOnId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$MetricDependenciesTableTableAnnotationComposer(
                $db: $db,
                $table: $db.metricDependenciesTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$MetricsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MetricsTableTable,
          Metric,
          $$MetricsTableTableFilterComposer,
          $$MetricsTableTableOrderingComposer,
          $$MetricsTableTableAnnotationComposer,
          $$MetricsTableTableCreateCompanionBuilder,
          $$MetricsTableTableUpdateCompanionBuilder,
          (Metric, $$MetricsTableTableReferences),
          Metric,
          PrefetchHooks Function({
            bool actionMetricsTableRefs,
            bool dependentMetricLinks,
            bool contributingMetricLinks,
          })
        > {
  $$MetricsTableTableTableManager(_$AppDatabase db, $MetricsTableTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MetricsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MetricsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MetricsTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<double> weight = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String?> timeWindow = const Value.absent(),
                Value<double> target = const Value.absent(),
                Value<bool> isMain = const Value.absent(),
                Value<int> importanceLevel = const Value.absent(),
                Value<String?> icon = const Value.absent(),
                Value<double?> posX = const Value.absent(),
                Value<double?> posY = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MetricsTableCompanion(
                id: id,
                name: name,
                weight: weight,
                kind: kind,
                timeWindow: timeWindow,
                target: target,
                isMain: isMain,
                importanceLevel: importanceLevel,
                icon: icon,
                posX: posX,
                posY: posY,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<double> weight = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String?> timeWindow = const Value.absent(),
                Value<double> target = const Value.absent(),
                Value<bool> isMain = const Value.absent(),
                Value<int> importanceLevel = const Value.absent(),
                Value<String?> icon = const Value.absent(),
                Value<double?> posX = const Value.absent(),
                Value<double?> posY = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MetricsTableCompanion.insert(
                id: id,
                name: name,
                weight: weight,
                kind: kind,
                timeWindow: timeWindow,
                target: target,
                isMain: isMain,
                importanceLevel: importanceLevel,
                icon: icon,
                posX: posX,
                posY: posY,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MetricsTableTable, Metric>(table),
                  $$MetricsTableTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                actionMetricsTableRefs = false,
                dependentMetricLinks = false,
                contributingMetricLinks = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (actionMetricsTableRefs) db.actionMetricsTable,
                    if (dependentMetricLinks) db.metricDependenciesTable,
                    if (contributingMetricLinks) db.metricDependenciesTable,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (actionMetricsTableRefs)
                        await $_getPrefetchedData<
                          Metric,
                          $MetricsTableTable,
                          ActionMetric
                        >(
                          currentTable: table,
                          referencedTable: $$MetricsTableTableReferences
                              ._actionMetricsTableRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$MetricsTableTableReferences(
                                db,
                                table,
                                p0,
                              ).actionMetricsTableRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.metricId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (dependentMetricLinks)
                        await $_getPrefetchedData<
                          Metric,
                          $MetricsTableTable,
                          MetricDependency
                        >(
                          currentTable: table,
                          referencedTable: $$MetricsTableTableReferences
                              ._dependentMetricLinksTable(db),
                          managerFromTypedResult: (p0) =>
                              $$MetricsTableTableReferences(
                                db,
                                table,
                                p0,
                              ).dependentMetricLinks,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.metricId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (contributingMetricLinks)
                        await $_getPrefetchedData<
                          Metric,
                          $MetricsTableTable,
                          MetricDependency
                        >(
                          currentTable: table,
                          referencedTable: $$MetricsTableTableReferences
                              ._contributingMetricLinksTable(db),
                          managerFromTypedResult: (p0) =>
                              $$MetricsTableTableReferences(
                                db,
                                table,
                                p0,
                              ).contributingMetricLinks,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.dependsOnId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$MetricsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MetricsTableTable,
      Metric,
      $$MetricsTableTableFilterComposer,
      $$MetricsTableTableOrderingComposer,
      $$MetricsTableTableAnnotationComposer,
      $$MetricsTableTableCreateCompanionBuilder,
      $$MetricsTableTableUpdateCompanionBuilder,
      (Metric, $$MetricsTableTableReferences),
      Metric,
      PrefetchHooks Function({
        bool actionMetricsTableRefs,
        bool dependentMetricLinks,
        bool contributingMetricLinks,
      })
    >;
typedef $$ActionMetricsTableTableCreateCompanionBuilder =
    ActionMetricsTableCompanion Function({
      required String id,
      required String actionId,
      required String metricId,
      Value<int> rowid,
    });
typedef $$ActionMetricsTableTableUpdateCompanionBuilder =
    ActionMetricsTableCompanion Function({
      Value<String> id,
      Value<String> actionId,
      Value<String> metricId,
      Value<int> rowid,
    });

final class $$ActionMetricsTableTableReferences
    extends
        BaseReferences<_$AppDatabase, $ActionMetricsTableTable, ActionMetric> {
  $$ActionMetricsTableTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ActionsTableTable _actionIdTable(_$AppDatabase db) =>
      db.actionsTable.createAlias('action_metrics__action_id__actions__id');

  $$ActionsTableTableProcessedTableManager get actionId {
    final $_column = $_itemColumn<String>('action_id')!;

    final manager = $$ActionsTableTableTableManager(
      $_db,
      $_db.actionsTable,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_actionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $MetricsTableTable _metricIdTable(_$AppDatabase db) =>
      db.metricsTable.createAlias('action_metrics__metric_id__metrics__id');

  $$MetricsTableTableProcessedTableManager get metricId {
    final $_column = $_itemColumn<String>('metric_id')!;

    final manager = $$MetricsTableTableTableManager(
      $_db,
      $_db.metricsTable,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_metricIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ActionMetricsTableTableFilterComposer
    extends Composer<_$AppDatabase, $ActionMetricsTableTable> {
  $$ActionMetricsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  $$ActionsTableTableFilterComposer get actionId {
    final $$ActionsTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.actionId,
      referencedTable: $db.actionsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionsTableTableFilterComposer(
            $db: $db,
            $table: $db.actionsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$MetricsTableTableFilterComposer get metricId {
    final $$MetricsTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.metricId,
      referencedTable: $db.metricsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MetricsTableTableFilterComposer(
            $db: $db,
            $table: $db.metricsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ActionMetricsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $ActionMetricsTableTable> {
  $$ActionMetricsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  $$ActionsTableTableOrderingComposer get actionId {
    final $$ActionsTableTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.actionId,
      referencedTable: $db.actionsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionsTableTableOrderingComposer(
            $db: $db,
            $table: $db.actionsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$MetricsTableTableOrderingComposer get metricId {
    final $$MetricsTableTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.metricId,
      referencedTable: $db.metricsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MetricsTableTableOrderingComposer(
            $db: $db,
            $table: $db.metricsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ActionMetricsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $ActionMetricsTableTable> {
  $$ActionMetricsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  $$ActionsTableTableAnnotationComposer get actionId {
    final $$ActionsTableTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.actionId,
      referencedTable: $db.actionsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionsTableTableAnnotationComposer(
            $db: $db,
            $table: $db.actionsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$MetricsTableTableAnnotationComposer get metricId {
    final $$MetricsTableTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.metricId,
      referencedTable: $db.metricsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MetricsTableTableAnnotationComposer(
            $db: $db,
            $table: $db.metricsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ActionMetricsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ActionMetricsTableTable,
          ActionMetric,
          $$ActionMetricsTableTableFilterComposer,
          $$ActionMetricsTableTableOrderingComposer,
          $$ActionMetricsTableTableAnnotationComposer,
          $$ActionMetricsTableTableCreateCompanionBuilder,
          $$ActionMetricsTableTableUpdateCompanionBuilder,
          (ActionMetric, $$ActionMetricsTableTableReferences),
          ActionMetric,
          PrefetchHooks Function({bool actionId, bool metricId})
        > {
  $$ActionMetricsTableTableTableManager(
    _$AppDatabase db,
    $ActionMetricsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ActionMetricsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ActionMetricsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ActionMetricsTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> actionId = const Value.absent(),
                Value<String> metricId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ActionMetricsTableCompanion(
                id: id,
                actionId: actionId,
                metricId: metricId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String actionId,
                required String metricId,
                Value<int> rowid = const Value.absent(),
              }) => ActionMetricsTableCompanion.insert(
                id: id,
                actionId: actionId,
                metricId: metricId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ActionMetricsTableTable, ActionMetric>(table),
                  $$ActionMetricsTableTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({actionId = false, metricId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (actionId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.actionId,
                        referencedTable: $$ActionMetricsTableTableReferences
                            ._actionIdTable(db),
                        referencedColumn: $$ActionMetricsTableTableReferences
                            ._actionIdTable(db)
                            .id,
                      ) as T;
                    }
                    if (metricId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.metricId,
                        referencedTable: $$ActionMetricsTableTableReferences
                            ._metricIdTable(db),
                        referencedColumn: $$ActionMetricsTableTableReferences
                            ._metricIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ActionMetricsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ActionMetricsTableTable,
      ActionMetric,
      $$ActionMetricsTableTableFilterComposer,
      $$ActionMetricsTableTableOrderingComposer,
      $$ActionMetricsTableTableAnnotationComposer,
      $$ActionMetricsTableTableCreateCompanionBuilder,
      $$ActionMetricsTableTableUpdateCompanionBuilder,
      (ActionMetric, $$ActionMetricsTableTableReferences),
      ActionMetric,
      PrefetchHooks Function({bool actionId, bool metricId})
    >;
typedef $$ActionTemplatesTableTableCreateCompanionBuilder =
    ActionTemplatesTableCompanion Function({
      required String id,
      required String name,
      required String payload,
      Value<int> rowid,
    });
typedef $$ActionTemplatesTableTableUpdateCompanionBuilder =
    ActionTemplatesTableCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> payload,
      Value<int> rowid,
    });

class $$ActionTemplatesTableTableFilterComposer
    extends Composer<_$AppDatabase, $ActionTemplatesTableTable> {
  $$ActionTemplatesTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ActionTemplatesTableTableOrderingComposer
    extends Composer<_$AppDatabase, $ActionTemplatesTableTable> {
  $$ActionTemplatesTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ActionTemplatesTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $ActionTemplatesTableTable> {
  $$ActionTemplatesTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);
}

class $$ActionTemplatesTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ActionTemplatesTableTable,
          ActionTemplate,
          $$ActionTemplatesTableTableFilterComposer,
          $$ActionTemplatesTableTableOrderingComposer,
          $$ActionTemplatesTableTableAnnotationComposer,
          $$ActionTemplatesTableTableCreateCompanionBuilder,
          $$ActionTemplatesTableTableUpdateCompanionBuilder,
          (
            ActionTemplate,
            BaseReferences<
              _$AppDatabase,
              $ActionTemplatesTableTable,
              ActionTemplate
            >,
          ),
          ActionTemplate,
          PrefetchHooks Function()
        > {
  $$ActionTemplatesTableTableTableManager(
    _$AppDatabase db,
    $ActionTemplatesTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ActionTemplatesTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ActionTemplatesTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ActionTemplatesTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ActionTemplatesTableCompanion(
                id: id,
                name: name,
                payload: payload,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String payload,
                Value<int> rowid = const Value.absent(),
              }) => ActionTemplatesTableCompanion.insert(
                id: id,
                name: name,
                payload: payload,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ActionTemplatesTableTable, ActionTemplate>(
                    table,
                  ),
                  BaseReferences<
                    _$AppDatabase,
                    $ActionTemplatesTableTable,
                    ActionTemplate
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ActionTemplatesTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ActionTemplatesTableTable,
      ActionTemplate,
      $$ActionTemplatesTableTableFilterComposer,
      $$ActionTemplatesTableTableOrderingComposer,
      $$ActionTemplatesTableTableAnnotationComposer,
      $$ActionTemplatesTableTableCreateCompanionBuilder,
      $$ActionTemplatesTableTableUpdateCompanionBuilder,
      (
        ActionTemplate,
        BaseReferences<
          _$AppDatabase,
          $ActionTemplatesTableTable,
          ActionTemplate
        >,
      ),
      ActionTemplate,
      PrefetchHooks Function()
    >;
typedef $$MetricDependenciesTableTableCreateCompanionBuilder =
    MetricDependenciesTableCompanion Function({
      required String id,
      required String metricId,
      required String dependsOnId,
      Value<int> rowid,
    });
typedef $$MetricDependenciesTableTableUpdateCompanionBuilder =
    MetricDependenciesTableCompanion Function({
      Value<String> id,
      Value<String> metricId,
      Value<String> dependsOnId,
      Value<int> rowid,
    });

final class $$MetricDependenciesTableTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $MetricDependenciesTableTable,
          MetricDependency
        > {
  $$MetricDependenciesTableTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $MetricsTableTable _metricIdTable(_$AppDatabase db) => db.metricsTable
      .createAlias('metric_dependencies__metric_id__metrics__id');

  $$MetricsTableTableProcessedTableManager get metricId {
    final $_column = $_itemColumn<String>('metric_id')!;

    final manager = $$MetricsTableTableTableManager(
      $_db,
      $_db.metricsTable,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_metricIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $MetricsTableTable _dependsOnIdTable(_$AppDatabase db) => db
      .metricsTable
      .createAlias('metric_dependencies__depends_on_id__metrics__id');

  $$MetricsTableTableProcessedTableManager get dependsOnId {
    final $_column = $_itemColumn<String>('depends_on_id')!;

    final manager = $$MetricsTableTableTableManager(
      $_db,
      $_db.metricsTable,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_dependsOnIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$MetricDependenciesTableTableFilterComposer
    extends Composer<_$AppDatabase, $MetricDependenciesTableTable> {
  $$MetricDependenciesTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  $$MetricsTableTableFilterComposer get metricId {
    final $$MetricsTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.metricId,
      referencedTable: $db.metricsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MetricsTableTableFilterComposer(
            $db: $db,
            $table: $db.metricsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$MetricsTableTableFilterComposer get dependsOnId {
    final $$MetricsTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.dependsOnId,
      referencedTable: $db.metricsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MetricsTableTableFilterComposer(
            $db: $db,
            $table: $db.metricsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MetricDependenciesTableTableOrderingComposer
    extends Composer<_$AppDatabase, $MetricDependenciesTableTable> {
  $$MetricDependenciesTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  $$MetricsTableTableOrderingComposer get metricId {
    final $$MetricsTableTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.metricId,
      referencedTable: $db.metricsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MetricsTableTableOrderingComposer(
            $db: $db,
            $table: $db.metricsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$MetricsTableTableOrderingComposer get dependsOnId {
    final $$MetricsTableTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.dependsOnId,
      referencedTable: $db.metricsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MetricsTableTableOrderingComposer(
            $db: $db,
            $table: $db.metricsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MetricDependenciesTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $MetricDependenciesTableTable> {
  $$MetricDependenciesTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  $$MetricsTableTableAnnotationComposer get metricId {
    final $$MetricsTableTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.metricId,
      referencedTable: $db.metricsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MetricsTableTableAnnotationComposer(
            $db: $db,
            $table: $db.metricsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$MetricsTableTableAnnotationComposer get dependsOnId {
    final $$MetricsTableTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.dependsOnId,
      referencedTable: $db.metricsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MetricsTableTableAnnotationComposer(
            $db: $db,
            $table: $db.metricsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MetricDependenciesTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MetricDependenciesTableTable,
          MetricDependency,
          $$MetricDependenciesTableTableFilterComposer,
          $$MetricDependenciesTableTableOrderingComposer,
          $$MetricDependenciesTableTableAnnotationComposer,
          $$MetricDependenciesTableTableCreateCompanionBuilder,
          $$MetricDependenciesTableTableUpdateCompanionBuilder,
          (MetricDependency, $$MetricDependenciesTableTableReferences),
          MetricDependency,
          PrefetchHooks Function({bool metricId, bool dependsOnId})
        > {
  $$MetricDependenciesTableTableTableManager(
    _$AppDatabase db,
    $MetricDependenciesTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MetricDependenciesTableTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$MetricDependenciesTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$MetricDependenciesTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> metricId = const Value.absent(),
                Value<String> dependsOnId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MetricDependenciesTableCompanion(
                id: id,
                metricId: metricId,
                dependsOnId: dependsOnId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String metricId,
                required String dependsOnId,
                Value<int> rowid = const Value.absent(),
              }) => MetricDependenciesTableCompanion.insert(
                id: id,
                metricId: metricId,
                dependsOnId: dependsOnId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MetricDependenciesTableTable, MetricDependency>(
                    table,
                  ),
                  $$MetricDependenciesTableTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({metricId = false, dependsOnId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (metricId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.metricId,
                        referencedTable:
                            $$MetricDependenciesTableTableReferences
                                ._metricIdTable(db),
                        referencedColumn:
                            $$MetricDependenciesTableTableReferences
                                ._metricIdTable(db)
                                .id,
                      ) as T;
                    }
                    if (dependsOnId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.dependsOnId,
                        referencedTable:
                            $$MetricDependenciesTableTableReferences
                                ._dependsOnIdTable(db),
                        referencedColumn:
                            $$MetricDependenciesTableTableReferences
                                ._dependsOnIdTable(db)
                                .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$MetricDependenciesTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MetricDependenciesTableTable,
      MetricDependency,
      $$MetricDependenciesTableTableFilterComposer,
      $$MetricDependenciesTableTableOrderingComposer,
      $$MetricDependenciesTableTableAnnotationComposer,
      $$MetricDependenciesTableTableCreateCompanionBuilder,
      $$MetricDependenciesTableTableUpdateCompanionBuilder,
      (MetricDependency, $$MetricDependenciesTableTableReferences),
      MetricDependency,
      PrefetchHooks Function({bool metricId, bool dependsOnId})
    >;
typedef $$BudgetAccountsTableTableCreateCompanionBuilder =
    BudgetAccountsTableCompanion Function({
      required String id,
      required String name,
      Value<String?> type,
      required String currency,
      Value<double> rateToBase,
      Value<double> openingBalance,
      Value<String?> icon,
      required String createdAt,
      required String updatedAt,
      Value<int> rowid,
    });
typedef $$BudgetAccountsTableTableUpdateCompanionBuilder =
    BudgetAccountsTableCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String?> type,
      Value<String> currency,
      Value<double> rateToBase,
      Value<double> openingBalance,
      Value<String?> icon,
      Value<String> createdAt,
      Value<String> updatedAt,
      Value<int> rowid,
    });

final class $$BudgetAccountsTableTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $BudgetAccountsTableTable,
          BudgetAccount
        > {
  $$BudgetAccountsTableTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$BudgetCategoriesTableTable, List<BudgetCategory>>
  _countedCategoriesTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.budgetCategoriesTable,
    aliasName: 'budget_accounts__id__budget_categories__account_count_id',
  );

  $$BudgetCategoriesTableTableProcessedTableManager get countedCategories {
    final manager = $$BudgetCategoriesTableTableTableManager(
      $_db,
      $_db.budgetCategoriesTable,
    ).filter((f) => f.accountCountId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_countedCategoriesTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$BudgetCategoriesTableTable, List<BudgetCategory>>
  _usedCategoriesTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.budgetCategoriesTable,
    aliasName: 'budget_accounts__id__budget_categories__account_use_id',
  );

  $$BudgetCategoriesTableTableProcessedTableManager get usedCategories {
    final manager = $$BudgetCategoriesTableTableTableManager(
      $_db,
      $_db.budgetCategoriesTable,
    ).filter((f) => f.accountUseId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_usedCategoriesTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $BudgetTransactionsTableTable,
    List<BudgetTransaction>
  >
  _countedTransactionsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.budgetTransactionsTable,
    aliasName: 'budget_accounts__id__budget_transactions__account_count_id',
  );

  $$BudgetTransactionsTableTableProcessedTableManager get countedTransactions {
    final manager = $$BudgetTransactionsTableTableTableManager(
      $_db,
      $_db.budgetTransactionsTable,
    ).filter((f) => f.accountCountId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _countedTransactionsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $BudgetTransactionsTableTable,
    List<BudgetTransaction>
  >
  _usedTransactionsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.budgetTransactionsTable,
    aliasName: 'budget_accounts__id__budget_transactions__account_use_id',
  );

  $$BudgetTransactionsTableTableProcessedTableManager get usedTransactions {
    final manager = $$BudgetTransactionsTableTableTableManager(
      $_db,
      $_db.budgetTransactionsTable,
    ).filter((f) => f.accountUseId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_usedTransactionsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$BudgetAccountsTableTableFilterComposer
    extends Composer<_$AppDatabase, $BudgetAccountsTableTable> {
  $$BudgetAccountsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get rateToBase => $composableBuilder(
    column: $table.rateToBase,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get openingBalance => $composableBuilder(
    column: $table.openingBalance,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get icon => $composableBuilder(
    column: $table.icon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> countedCategories(
    Expression<bool> Function($$BudgetCategoriesTableTableFilterComposer f) f,
  ) {
    final $$BudgetCategoriesTableTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.budgetCategoriesTable,
          getReferencedColumn: (t) => t.accountCountId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$BudgetCategoriesTableTableFilterComposer(
                $db: $db,
                $table: $db.budgetCategoriesTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<bool> usedCategories(
    Expression<bool> Function($$BudgetCategoriesTableTableFilterComposer f) f,
  ) {
    final $$BudgetCategoriesTableTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.budgetCategoriesTable,
          getReferencedColumn: (t) => t.accountUseId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$BudgetCategoriesTableTableFilterComposer(
                $db: $db,
                $table: $db.budgetCategoriesTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<bool> countedTransactions(
    Expression<bool> Function($$BudgetTransactionsTableTableFilterComposer f) f,
  ) {
    final $$BudgetTransactionsTableTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.budgetTransactionsTable,
          getReferencedColumn: (t) => t.accountCountId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$BudgetTransactionsTableTableFilterComposer(
                $db: $db,
                $table: $db.budgetTransactionsTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<bool> usedTransactions(
    Expression<bool> Function($$BudgetTransactionsTableTableFilterComposer f) f,
  ) {
    final $$BudgetTransactionsTableTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.budgetTransactionsTable,
          getReferencedColumn: (t) => t.accountUseId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$BudgetTransactionsTableTableFilterComposer(
                $db: $db,
                $table: $db.budgetTransactionsTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$BudgetAccountsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $BudgetAccountsTableTable> {
  $$BudgetAccountsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get rateToBase => $composableBuilder(
    column: $table.rateToBase,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get openingBalance => $composableBuilder(
    column: $table.openingBalance,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get icon => $composableBuilder(
    column: $table.icon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BudgetAccountsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $BudgetAccountsTableTable> {
  $$BudgetAccountsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get currency =>
      $composableBuilder(column: $table.currency, builder: (column) => column);

  GeneratedColumn<double> get rateToBase => $composableBuilder(
    column: $table.rateToBase,
    builder: (column) => column,
  );

  GeneratedColumn<double> get openingBalance => $composableBuilder(
    column: $table.openingBalance,
    builder: (column) => column,
  );

  GeneratedColumn<String> get icon =>
      $composableBuilder(column: $table.icon, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> countedCategories<T extends Object>(
    Expression<T> Function($$BudgetCategoriesTableTableAnnotationComposer a) f,
  ) {
    final $$BudgetCategoriesTableTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.budgetCategoriesTable,
          getReferencedColumn: (t) => t.accountCountId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$BudgetCategoriesTableTableAnnotationComposer(
                $db: $db,
                $table: $db.budgetCategoriesTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> usedCategories<T extends Object>(
    Expression<T> Function($$BudgetCategoriesTableTableAnnotationComposer a) f,
  ) {
    final $$BudgetCategoriesTableTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.budgetCategoriesTable,
          getReferencedColumn: (t) => t.accountUseId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$BudgetCategoriesTableTableAnnotationComposer(
                $db: $db,
                $table: $db.budgetCategoriesTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> countedTransactions<T extends Object>(
    Expression<T> Function($$BudgetTransactionsTableTableAnnotationComposer a)
    f,
  ) {
    final $$BudgetTransactionsTableTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.budgetTransactionsTable,
          getReferencedColumn: (t) => t.accountCountId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$BudgetTransactionsTableTableAnnotationComposer(
                $db: $db,
                $table: $db.budgetTransactionsTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> usedTransactions<T extends Object>(
    Expression<T> Function($$BudgetTransactionsTableTableAnnotationComposer a)
    f,
  ) {
    final $$BudgetTransactionsTableTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.budgetTransactionsTable,
          getReferencedColumn: (t) => t.accountUseId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$BudgetTransactionsTableTableAnnotationComposer(
                $db: $db,
                $table: $db.budgetTransactionsTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$BudgetAccountsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BudgetAccountsTableTable,
          BudgetAccount,
          $$BudgetAccountsTableTableFilterComposer,
          $$BudgetAccountsTableTableOrderingComposer,
          $$BudgetAccountsTableTableAnnotationComposer,
          $$BudgetAccountsTableTableCreateCompanionBuilder,
          $$BudgetAccountsTableTableUpdateCompanionBuilder,
          (BudgetAccount, $$BudgetAccountsTableTableReferences),
          BudgetAccount,
          PrefetchHooks Function({
            bool countedCategories,
            bool usedCategories,
            bool countedTransactions,
            bool usedTransactions,
          })
        > {
  $$BudgetAccountsTableTableTableManager(
    _$AppDatabase db,
    $BudgetAccountsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BudgetAccountsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BudgetAccountsTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$BudgetAccountsTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> type = const Value.absent(),
                Value<String> currency = const Value.absent(),
                Value<double> rateToBase = const Value.absent(),
                Value<double> openingBalance = const Value.absent(),
                Value<String?> icon = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BudgetAccountsTableCompanion(
                id: id,
                name: name,
                type: type,
                currency: currency,
                rateToBase: rateToBase,
                openingBalance: openingBalance,
                icon: icon,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<String?> type = const Value.absent(),
                required String currency,
                Value<double> rateToBase = const Value.absent(),
                Value<double> openingBalance = const Value.absent(),
                Value<String?> icon = const Value.absent(),
                required String createdAt,
                required String updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => BudgetAccountsTableCompanion.insert(
                id: id,
                name: name,
                type: type,
                currency: currency,
                rateToBase: rateToBase,
                openingBalance: openingBalance,
                icon: icon,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$BudgetAccountsTableTable, BudgetAccount>(table),
                  $$BudgetAccountsTableTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                countedCategories = false,
                usedCategories = false,
                countedTransactions = false,
                usedTransactions = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (countedCategories) db.budgetCategoriesTable,
                    if (usedCategories) db.budgetCategoriesTable,
                    if (countedTransactions) db.budgetTransactionsTable,
                    if (usedTransactions) db.budgetTransactionsTable,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (countedCategories)
                        await $_getPrefetchedData<
                          BudgetAccount,
                          $BudgetAccountsTableTable,
                          BudgetCategory
                        >(
                          currentTable: table,
                          referencedTable: $$BudgetAccountsTableTableReferences
                              ._countedCategoriesTable(db),
                          managerFromTypedResult: (p0) =>
                              $$BudgetAccountsTableTableReferences(
                                db,
                                table,
                                p0,
                              ).countedCategories,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.accountCountId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (usedCategories)
                        await $_getPrefetchedData<
                          BudgetAccount,
                          $BudgetAccountsTableTable,
                          BudgetCategory
                        >(
                          currentTable: table,
                          referencedTable: $$BudgetAccountsTableTableReferences
                              ._usedCategoriesTable(db),
                          managerFromTypedResult: (p0) =>
                              $$BudgetAccountsTableTableReferences(
                                db,
                                table,
                                p0,
                              ).usedCategories,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.accountUseId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (countedTransactions)
                        await $_getPrefetchedData<
                          BudgetAccount,
                          $BudgetAccountsTableTable,
                          BudgetTransaction
                        >(
                          currentTable: table,
                          referencedTable: $$BudgetAccountsTableTableReferences
                              ._countedTransactionsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$BudgetAccountsTableTableReferences(
                                db,
                                table,
                                p0,
                              ).countedTransactions,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.accountCountId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (usedTransactions)
                        await $_getPrefetchedData<
                          BudgetAccount,
                          $BudgetAccountsTableTable,
                          BudgetTransaction
                        >(
                          currentTable: table,
                          referencedTable: $$BudgetAccountsTableTableReferences
                              ._usedTransactionsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$BudgetAccountsTableTableReferences(
                                db,
                                table,
                                p0,
                              ).usedTransactions,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.accountUseId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$BudgetAccountsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BudgetAccountsTableTable,
      BudgetAccount,
      $$BudgetAccountsTableTableFilterComposer,
      $$BudgetAccountsTableTableOrderingComposer,
      $$BudgetAccountsTableTableAnnotationComposer,
      $$BudgetAccountsTableTableCreateCompanionBuilder,
      $$BudgetAccountsTableTableUpdateCompanionBuilder,
      (BudgetAccount, $$BudgetAccountsTableTableReferences),
      BudgetAccount,
      PrefetchHooks Function({
        bool countedCategories,
        bool usedCategories,
        bool countedTransactions,
        bool usedTransactions,
      })
    >;
typedef $$BudgetCategoriesTableTableCreateCompanionBuilder =
    BudgetCategoriesTableCompanion Function({
      required String id,
      required String name,
      Value<bool> isIncome,
      Value<bool> oneTime,
      Value<String> unit,
      Value<String?> endDate,
      Value<double?> price,
      Value<double?> percent,
      Value<double?> frequencyMonths,
      Value<double?> unitsPerMonth,
      Value<String?> parentId,
      Value<String?> countPercentOfId,
      Value<String?> accountCountId,
      Value<String?> accountUseId,
      required String createdAt,
      required String updatedAt,
      Value<int> rowid,
    });
typedef $$BudgetCategoriesTableTableUpdateCompanionBuilder =
    BudgetCategoriesTableCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<bool> isIncome,
      Value<bool> oneTime,
      Value<String> unit,
      Value<String?> endDate,
      Value<double?> price,
      Value<double?> percent,
      Value<double?> frequencyMonths,
      Value<double?> unitsPerMonth,
      Value<String?> parentId,
      Value<String?> countPercentOfId,
      Value<String?> accountCountId,
      Value<String?> accountUseId,
      Value<String> createdAt,
      Value<String> updatedAt,
      Value<int> rowid,
    });

final class $$BudgetCategoriesTableTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $BudgetCategoriesTableTable,
          BudgetCategory
        > {
  $$BudgetCategoriesTableTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $BudgetCategoriesTableTable _parentIdTable(_$AppDatabase db) => db
      .budgetCategoriesTable
      .createAlias('budget_categories__parent_id__budget_categories__id');

  $$BudgetCategoriesTableTableProcessedTableManager? get parentId {
    final $_column = $_itemColumn<String>('parent_id');
    if ($_column == null) return null;
    final manager = $$BudgetCategoriesTableTableTableManager(
      $_db,
      $_db.budgetCategoriesTable,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_parentIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $BudgetCategoriesTableTable _countPercentOfIdTable(_$AppDatabase db) =>
      db.budgetCategoriesTable.createAlias(
        'budget_categories__count_percent_of_id__budget_categories__id',
      );

  $$BudgetCategoriesTableTableProcessedTableManager? get countPercentOfId {
    final $_column = $_itemColumn<String>('count_percent_of_id');
    if ($_column == null) return null;
    final manager = $$BudgetCategoriesTableTableTableManager(
      $_db,
      $_db.budgetCategoriesTable,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_countPercentOfIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $BudgetAccountsTableTable _accountCountIdTable(_$AppDatabase db) => db
      .budgetAccountsTable
      .createAlias('budget_categories__account_count_id__budget_accounts__id');

  $$BudgetAccountsTableTableProcessedTableManager? get accountCountId {
    final $_column = $_itemColumn<String>('account_count_id');
    if ($_column == null) return null;
    final manager = $$BudgetAccountsTableTableTableManager(
      $_db,
      $_db.budgetAccountsTable,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_accountCountIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $BudgetAccountsTableTable _accountUseIdTable(_$AppDatabase db) => db
      .budgetAccountsTable
      .createAlias('budget_categories__account_use_id__budget_accounts__id');

  $$BudgetAccountsTableTableProcessedTableManager? get accountUseId {
    final $_column = $_itemColumn<String>('account_use_id');
    if ($_column == null) return null;
    final manager = $$BudgetAccountsTableTableTableManager(
      $_db,
      $_db.budgetAccountsTable,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_accountUseIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<
    $BudgetTransactionsTableTable,
    List<BudgetTransaction>
  >
  _budgetTransactionsTableRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.budgetTransactionsTable,
        aliasName: 'budget_categories__id__budget_transactions__category_id',
      );

  $$BudgetTransactionsTableTableProcessedTableManager
  get budgetTransactionsTableRefs {
    final manager = $$BudgetTransactionsTableTableTableManager(
      $_db,
      $_db.budgetTransactionsTable,
    ).filter((f) => f.categoryId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _budgetTransactionsTableRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$BudgetCategoriesTableTableFilterComposer
    extends Composer<_$AppDatabase, $BudgetCategoriesTableTable> {
  $$BudgetCategoriesTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isIncome => $composableBuilder(
    column: $table.isIncome,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get oneTime => $composableBuilder(
    column: $table.oneTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get unit => $composableBuilder(
    column: $table.unit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get endDate => $composableBuilder(
    column: $table.endDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get price => $composableBuilder(
    column: $table.price,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get percent => $composableBuilder(
    column: $table.percent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get frequencyMonths => $composableBuilder(
    column: $table.frequencyMonths,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get unitsPerMonth => $composableBuilder(
    column: $table.unitsPerMonth,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$BudgetCategoriesTableTableFilterComposer get parentId {
    final $$BudgetCategoriesTableTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.parentId,
          referencedTable: $db.budgetCategoriesTable,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$BudgetCategoriesTableTableFilterComposer(
                $db: $db,
                $table: $db.budgetCategoriesTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }

  $$BudgetCategoriesTableTableFilterComposer get countPercentOfId {
    final $$BudgetCategoriesTableTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.countPercentOfId,
          referencedTable: $db.budgetCategoriesTable,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$BudgetCategoriesTableTableFilterComposer(
                $db: $db,
                $table: $db.budgetCategoriesTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }

  $$BudgetAccountsTableTableFilterComposer get accountCountId {
    final $$BudgetAccountsTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountCountId,
      referencedTable: $db.budgetAccountsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BudgetAccountsTableTableFilterComposer(
            $db: $db,
            $table: $db.budgetAccountsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$BudgetAccountsTableTableFilterComposer get accountUseId {
    final $$BudgetAccountsTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountUseId,
      referencedTable: $db.budgetAccountsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BudgetAccountsTableTableFilterComposer(
            $db: $db,
            $table: $db.budgetAccountsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> budgetTransactionsTableRefs(
    Expression<bool> Function($$BudgetTransactionsTableTableFilterComposer f) f,
  ) {
    final $$BudgetTransactionsTableTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.budgetTransactionsTable,
          getReferencedColumn: (t) => t.categoryId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$BudgetTransactionsTableTableFilterComposer(
                $db: $db,
                $table: $db.budgetTransactionsTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$BudgetCategoriesTableTableOrderingComposer
    extends Composer<_$AppDatabase, $BudgetCategoriesTableTable> {
  $$BudgetCategoriesTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isIncome => $composableBuilder(
    column: $table.isIncome,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get oneTime => $composableBuilder(
    column: $table.oneTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get unit => $composableBuilder(
    column: $table.unit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get endDate => $composableBuilder(
    column: $table.endDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get price => $composableBuilder(
    column: $table.price,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get percent => $composableBuilder(
    column: $table.percent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get frequencyMonths => $composableBuilder(
    column: $table.frequencyMonths,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get unitsPerMonth => $composableBuilder(
    column: $table.unitsPerMonth,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$BudgetCategoriesTableTableOrderingComposer get parentId {
    final $$BudgetCategoriesTableTableOrderingComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.parentId,
          referencedTable: $db.budgetCategoriesTable,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$BudgetCategoriesTableTableOrderingComposer(
                $db: $db,
                $table: $db.budgetCategoriesTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }

  $$BudgetCategoriesTableTableOrderingComposer get countPercentOfId {
    final $$BudgetCategoriesTableTableOrderingComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.countPercentOfId,
          referencedTable: $db.budgetCategoriesTable,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$BudgetCategoriesTableTableOrderingComposer(
                $db: $db,
                $table: $db.budgetCategoriesTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }

  $$BudgetAccountsTableTableOrderingComposer get accountCountId {
    final $$BudgetAccountsTableTableOrderingComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.accountCountId,
          referencedTable: $db.budgetAccountsTable,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$BudgetAccountsTableTableOrderingComposer(
                $db: $db,
                $table: $db.budgetAccountsTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }

  $$BudgetAccountsTableTableOrderingComposer get accountUseId {
    final $$BudgetAccountsTableTableOrderingComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.accountUseId,
          referencedTable: $db.budgetAccountsTable,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$BudgetAccountsTableTableOrderingComposer(
                $db: $db,
                $table: $db.budgetAccountsTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$BudgetCategoriesTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $BudgetCategoriesTableTable> {
  $$BudgetCategoriesTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<bool> get isIncome =>
      $composableBuilder(column: $table.isIncome, builder: (column) => column);

  GeneratedColumn<bool> get oneTime =>
      $composableBuilder(column: $table.oneTime, builder: (column) => column);

  GeneratedColumn<String> get unit =>
      $composableBuilder(column: $table.unit, builder: (column) => column);

  GeneratedColumn<String> get endDate =>
      $composableBuilder(column: $table.endDate, builder: (column) => column);

  GeneratedColumn<double> get price =>
      $composableBuilder(column: $table.price, builder: (column) => column);

  GeneratedColumn<double> get percent =>
      $composableBuilder(column: $table.percent, builder: (column) => column);

  GeneratedColumn<double> get frequencyMonths => $composableBuilder(
    column: $table.frequencyMonths,
    builder: (column) => column,
  );

  GeneratedColumn<double> get unitsPerMonth => $composableBuilder(
    column: $table.unitsPerMonth,
    builder: (column) => column,
  );

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$BudgetCategoriesTableTableAnnotationComposer get parentId {
    final $$BudgetCategoriesTableTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.parentId,
          referencedTable: $db.budgetCategoriesTable,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$BudgetCategoriesTableTableAnnotationComposer(
                $db: $db,
                $table: $db.budgetCategoriesTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }

  $$BudgetCategoriesTableTableAnnotationComposer get countPercentOfId {
    final $$BudgetCategoriesTableTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.countPercentOfId,
          referencedTable: $db.budgetCategoriesTable,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$BudgetCategoriesTableTableAnnotationComposer(
                $db: $db,
                $table: $db.budgetCategoriesTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }

  $$BudgetAccountsTableTableAnnotationComposer get accountCountId {
    final $$BudgetAccountsTableTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.accountCountId,
          referencedTable: $db.budgetAccountsTable,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$BudgetAccountsTableTableAnnotationComposer(
                $db: $db,
                $table: $db.budgetAccountsTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }

  $$BudgetAccountsTableTableAnnotationComposer get accountUseId {
    final $$BudgetAccountsTableTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.accountUseId,
          referencedTable: $db.budgetAccountsTable,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$BudgetAccountsTableTableAnnotationComposer(
                $db: $db,
                $table: $db.budgetAccountsTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }

  Expression<T> budgetTransactionsTableRefs<T extends Object>(
    Expression<T> Function($$BudgetTransactionsTableTableAnnotationComposer a)
    f,
  ) {
    final $$BudgetTransactionsTableTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.budgetTransactionsTable,
          getReferencedColumn: (t) => t.categoryId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$BudgetTransactionsTableTableAnnotationComposer(
                $db: $db,
                $table: $db.budgetTransactionsTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$BudgetCategoriesTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BudgetCategoriesTableTable,
          BudgetCategory,
          $$BudgetCategoriesTableTableFilterComposer,
          $$BudgetCategoriesTableTableOrderingComposer,
          $$BudgetCategoriesTableTableAnnotationComposer,
          $$BudgetCategoriesTableTableCreateCompanionBuilder,
          $$BudgetCategoriesTableTableUpdateCompanionBuilder,
          (BudgetCategory, $$BudgetCategoriesTableTableReferences),
          BudgetCategory,
          PrefetchHooks Function({
            bool parentId,
            bool countPercentOfId,
            bool accountCountId,
            bool accountUseId,
            bool budgetTransactionsTableRefs,
          })
        > {
  $$BudgetCategoriesTableTableTableManager(
    _$AppDatabase db,
    $BudgetCategoriesTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BudgetCategoriesTableTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$BudgetCategoriesTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$BudgetCategoriesTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<bool> isIncome = const Value.absent(),
                Value<bool> oneTime = const Value.absent(),
                Value<String> unit = const Value.absent(),
                Value<String?> endDate = const Value.absent(),
                Value<double?> price = const Value.absent(),
                Value<double?> percent = const Value.absent(),
                Value<double?> frequencyMonths = const Value.absent(),
                Value<double?> unitsPerMonth = const Value.absent(),
                Value<String?> parentId = const Value.absent(),
                Value<String?> countPercentOfId = const Value.absent(),
                Value<String?> accountCountId = const Value.absent(),
                Value<String?> accountUseId = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BudgetCategoriesTableCompanion(
                id: id,
                name: name,
                isIncome: isIncome,
                oneTime: oneTime,
                unit: unit,
                endDate: endDate,
                price: price,
                percent: percent,
                frequencyMonths: frequencyMonths,
                unitsPerMonth: unitsPerMonth,
                parentId: parentId,
                countPercentOfId: countPercentOfId,
                accountCountId: accountCountId,
                accountUseId: accountUseId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<bool> isIncome = const Value.absent(),
                Value<bool> oneTime = const Value.absent(),
                Value<String> unit = const Value.absent(),
                Value<String?> endDate = const Value.absent(),
                Value<double?> price = const Value.absent(),
                Value<double?> percent = const Value.absent(),
                Value<double?> frequencyMonths = const Value.absent(),
                Value<double?> unitsPerMonth = const Value.absent(),
                Value<String?> parentId = const Value.absent(),
                Value<String?> countPercentOfId = const Value.absent(),
                Value<String?> accountCountId = const Value.absent(),
                Value<String?> accountUseId = const Value.absent(),
                required String createdAt,
                required String updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => BudgetCategoriesTableCompanion.insert(
                id: id,
                name: name,
                isIncome: isIncome,
                oneTime: oneTime,
                unit: unit,
                endDate: endDate,
                price: price,
                percent: percent,
                frequencyMonths: frequencyMonths,
                unitsPerMonth: unitsPerMonth,
                parentId: parentId,
                countPercentOfId: countPercentOfId,
                accountCountId: accountCountId,
                accountUseId: accountUseId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$BudgetCategoriesTableTable, BudgetCategory>(
                    table,
                  ),
                  $$BudgetCategoriesTableTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                parentId = false,
                countPercentOfId = false,
                accountCountId = false,
                accountUseId = false,
                budgetTransactionsTableRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (budgetTransactionsTableRefs) db.budgetTransactionsTable,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (parentId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.parentId,
                            referencedTable:
                                $$BudgetCategoriesTableTableReferences
                                    ._parentIdTable(db),
                            referencedColumn:
                                $$BudgetCategoriesTableTableReferences
                                    ._parentIdTable(db)
                                    .id,
                          ) as T;
                        }
                        if (countPercentOfId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.countPercentOfId,
                            referencedTable:
                                $$BudgetCategoriesTableTableReferences
                                    ._countPercentOfIdTable(db),
                            referencedColumn:
                                $$BudgetCategoriesTableTableReferences
                                    ._countPercentOfIdTable(db)
                                    .id,
                          ) as T;
                        }
                        if (accountCountId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.accountCountId,
                            referencedTable:
                                $$BudgetCategoriesTableTableReferences
                                    ._accountCountIdTable(db),
                            referencedColumn:
                                $$BudgetCategoriesTableTableReferences
                                    ._accountCountIdTable(db)
                                    .id,
                          ) as T;
                        }
                        if (accountUseId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.accountUseId,
                            referencedTable:
                                $$BudgetCategoriesTableTableReferences
                                    ._accountUseIdTable(db),
                            referencedColumn:
                                $$BudgetCategoriesTableTableReferences
                                    ._accountUseIdTable(db)
                                    .id,
                          ) as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (budgetTransactionsTableRefs)
                        await $_getPrefetchedData<
                          BudgetCategory,
                          $BudgetCategoriesTableTable,
                          BudgetTransaction
                        >(
                          currentTable: table,
                          referencedTable:
                              $$BudgetCategoriesTableTableReferences
                                  ._budgetTransactionsTableRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$BudgetCategoriesTableTableReferences(
                                db,
                                table,
                                p0,
                              ).budgetTransactionsTableRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.categoryId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$BudgetCategoriesTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BudgetCategoriesTableTable,
      BudgetCategory,
      $$BudgetCategoriesTableTableFilterComposer,
      $$BudgetCategoriesTableTableOrderingComposer,
      $$BudgetCategoriesTableTableAnnotationComposer,
      $$BudgetCategoriesTableTableCreateCompanionBuilder,
      $$BudgetCategoriesTableTableUpdateCompanionBuilder,
      (BudgetCategory, $$BudgetCategoriesTableTableReferences),
      BudgetCategory,
      PrefetchHooks Function({
        bool parentId,
        bool countPercentOfId,
        bool accountCountId,
        bool accountUseId,
        bool budgetTransactionsTableRefs,
      })
    >;
typedef $$BudgetTransactionsTableTableCreateCompanionBuilder =
    BudgetTransactionsTableCompanion Function({
      required String id,
      Value<String> name,
      Value<String?> categoryId,
      Value<String?> actionId,
      required String occurredAt,
      Value<double> quantity,
      Value<double> unitPrice,
      Value<bool> isIncome,
      Value<bool> isAmount,
      Value<String?> accountCountId,
      Value<String?> accountUseId,
      Value<double?> rateCount,
      Value<double?> rateInteract,
      required String createdAt,
      required String updatedAt,
      Value<int> rowid,
    });
typedef $$BudgetTransactionsTableTableUpdateCompanionBuilder =
    BudgetTransactionsTableCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String?> categoryId,
      Value<String?> actionId,
      Value<String> occurredAt,
      Value<double> quantity,
      Value<double> unitPrice,
      Value<bool> isIncome,
      Value<bool> isAmount,
      Value<String?> accountCountId,
      Value<String?> accountUseId,
      Value<double?> rateCount,
      Value<double?> rateInteract,
      Value<String> createdAt,
      Value<String> updatedAt,
      Value<int> rowid,
    });

final class $$BudgetTransactionsTableTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $BudgetTransactionsTableTable,
          BudgetTransaction
        > {
  $$BudgetTransactionsTableTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $BudgetCategoriesTableTable _categoryIdTable(_$AppDatabase db) => db
      .budgetCategoriesTable
      .createAlias('budget_transactions__category_id__budget_categories__id');

  $$BudgetCategoriesTableTableProcessedTableManager? get categoryId {
    final $_column = $_itemColumn<String>('category_id');
    if ($_column == null) return null;
    final manager = $$BudgetCategoriesTableTableTableManager(
      $_db,
      $_db.budgetCategoriesTable,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_categoryIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $ActionsTableTable _actionIdTable(_$AppDatabase db) => db.actionsTable
      .createAlias('budget_transactions__action_id__actions__id');

  $$ActionsTableTableProcessedTableManager? get actionId {
    final $_column = $_itemColumn<String>('action_id');
    if ($_column == null) return null;
    final manager = $$ActionsTableTableTableManager(
      $_db,
      $_db.actionsTable,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_actionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $BudgetAccountsTableTable _accountCountIdTable(_$AppDatabase db) =>
      db.budgetAccountsTable.createAlias(
        'budget_transactions__account_count_id__budget_accounts__id',
      );

  $$BudgetAccountsTableTableProcessedTableManager? get accountCountId {
    final $_column = $_itemColumn<String>('account_count_id');
    if ($_column == null) return null;
    final manager = $$BudgetAccountsTableTableTableManager(
      $_db,
      $_db.budgetAccountsTable,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_accountCountIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $BudgetAccountsTableTable _accountUseIdTable(_$AppDatabase db) => db
      .budgetAccountsTable
      .createAlias('budget_transactions__account_use_id__budget_accounts__id');

  $$BudgetAccountsTableTableProcessedTableManager? get accountUseId {
    final $_column = $_itemColumn<String>('account_use_id');
    if ($_column == null) return null;
    final manager = $$BudgetAccountsTableTableTableManager(
      $_db,
      $_db.budgetAccountsTable,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_accountUseIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$BudgetTransactionsTableTableFilterComposer
    extends Composer<_$AppDatabase, $BudgetTransactionsTableTable> {
  $$BudgetTransactionsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get quantity => $composableBuilder(
    column: $table.quantity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get unitPrice => $composableBuilder(
    column: $table.unitPrice,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isIncome => $composableBuilder(
    column: $table.isIncome,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isAmount => $composableBuilder(
    column: $table.isAmount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get rateCount => $composableBuilder(
    column: $table.rateCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get rateInteract => $composableBuilder(
    column: $table.rateInteract,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$BudgetCategoriesTableTableFilterComposer get categoryId {
    final $$BudgetCategoriesTableTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.categoryId,
          referencedTable: $db.budgetCategoriesTable,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$BudgetCategoriesTableTableFilterComposer(
                $db: $db,
                $table: $db.budgetCategoriesTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }

  $$ActionsTableTableFilterComposer get actionId {
    final $$ActionsTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.actionId,
      referencedTable: $db.actionsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionsTableTableFilterComposer(
            $db: $db,
            $table: $db.actionsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$BudgetAccountsTableTableFilterComposer get accountCountId {
    final $$BudgetAccountsTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountCountId,
      referencedTable: $db.budgetAccountsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BudgetAccountsTableTableFilterComposer(
            $db: $db,
            $table: $db.budgetAccountsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$BudgetAccountsTableTableFilterComposer get accountUseId {
    final $$BudgetAccountsTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountUseId,
      referencedTable: $db.budgetAccountsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BudgetAccountsTableTableFilterComposer(
            $db: $db,
            $table: $db.budgetAccountsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BudgetTransactionsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $BudgetTransactionsTableTable> {
  $$BudgetTransactionsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get quantity => $composableBuilder(
    column: $table.quantity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get unitPrice => $composableBuilder(
    column: $table.unitPrice,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isIncome => $composableBuilder(
    column: $table.isIncome,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isAmount => $composableBuilder(
    column: $table.isAmount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get rateCount => $composableBuilder(
    column: $table.rateCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get rateInteract => $composableBuilder(
    column: $table.rateInteract,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$BudgetCategoriesTableTableOrderingComposer get categoryId {
    final $$BudgetCategoriesTableTableOrderingComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.categoryId,
          referencedTable: $db.budgetCategoriesTable,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$BudgetCategoriesTableTableOrderingComposer(
                $db: $db,
                $table: $db.budgetCategoriesTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }

  $$ActionsTableTableOrderingComposer get actionId {
    final $$ActionsTableTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.actionId,
      referencedTable: $db.actionsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionsTableTableOrderingComposer(
            $db: $db,
            $table: $db.actionsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$BudgetAccountsTableTableOrderingComposer get accountCountId {
    final $$BudgetAccountsTableTableOrderingComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.accountCountId,
          referencedTable: $db.budgetAccountsTable,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$BudgetAccountsTableTableOrderingComposer(
                $db: $db,
                $table: $db.budgetAccountsTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }

  $$BudgetAccountsTableTableOrderingComposer get accountUseId {
    final $$BudgetAccountsTableTableOrderingComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.accountUseId,
          referencedTable: $db.budgetAccountsTable,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$BudgetAccountsTableTableOrderingComposer(
                $db: $db,
                $table: $db.budgetAccountsTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$BudgetTransactionsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $BudgetTransactionsTableTable> {
  $$BudgetTransactionsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => column,
  );

  GeneratedColumn<double> get quantity =>
      $composableBuilder(column: $table.quantity, builder: (column) => column);

  GeneratedColumn<double> get unitPrice =>
      $composableBuilder(column: $table.unitPrice, builder: (column) => column);

  GeneratedColumn<bool> get isIncome =>
      $composableBuilder(column: $table.isIncome, builder: (column) => column);

  GeneratedColumn<bool> get isAmount =>
      $composableBuilder(column: $table.isAmount, builder: (column) => column);

  GeneratedColumn<double> get rateCount =>
      $composableBuilder(column: $table.rateCount, builder: (column) => column);

  GeneratedColumn<double> get rateInteract => $composableBuilder(
    column: $table.rateInteract,
    builder: (column) => column,
  );

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$BudgetCategoriesTableTableAnnotationComposer get categoryId {
    final $$BudgetCategoriesTableTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.categoryId,
          referencedTable: $db.budgetCategoriesTable,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$BudgetCategoriesTableTableAnnotationComposer(
                $db: $db,
                $table: $db.budgetCategoriesTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }

  $$ActionsTableTableAnnotationComposer get actionId {
    final $$ActionsTableTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.actionId,
      referencedTable: $db.actionsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActionsTableTableAnnotationComposer(
            $db: $db,
            $table: $db.actionsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$BudgetAccountsTableTableAnnotationComposer get accountCountId {
    final $$BudgetAccountsTableTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.accountCountId,
          referencedTable: $db.budgetAccountsTable,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$BudgetAccountsTableTableAnnotationComposer(
                $db: $db,
                $table: $db.budgetAccountsTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }

  $$BudgetAccountsTableTableAnnotationComposer get accountUseId {
    final $$BudgetAccountsTableTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.accountUseId,
          referencedTable: $db.budgetAccountsTable,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$BudgetAccountsTableTableAnnotationComposer(
                $db: $db,
                $table: $db.budgetAccountsTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$BudgetTransactionsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BudgetTransactionsTableTable,
          BudgetTransaction,
          $$BudgetTransactionsTableTableFilterComposer,
          $$BudgetTransactionsTableTableOrderingComposer,
          $$BudgetTransactionsTableTableAnnotationComposer,
          $$BudgetTransactionsTableTableCreateCompanionBuilder,
          $$BudgetTransactionsTableTableUpdateCompanionBuilder,
          (BudgetTransaction, $$BudgetTransactionsTableTableReferences),
          BudgetTransaction,
          PrefetchHooks Function({
            bool categoryId,
            bool actionId,
            bool accountCountId,
            bool accountUseId,
          })
        > {
  $$BudgetTransactionsTableTableTableManager(
    _$AppDatabase db,
    $BudgetTransactionsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BudgetTransactionsTableTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$BudgetTransactionsTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$BudgetTransactionsTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> categoryId = const Value.absent(),
                Value<String?> actionId = const Value.absent(),
                Value<String> occurredAt = const Value.absent(),
                Value<double> quantity = const Value.absent(),
                Value<double> unitPrice = const Value.absent(),
                Value<bool> isIncome = const Value.absent(),
                Value<bool> isAmount = const Value.absent(),
                Value<String?> accountCountId = const Value.absent(),
                Value<String?> accountUseId = const Value.absent(),
                Value<double?> rateCount = const Value.absent(),
                Value<double?> rateInteract = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BudgetTransactionsTableCompanion(
                id: id,
                name: name,
                categoryId: categoryId,
                actionId: actionId,
                occurredAt: occurredAt,
                quantity: quantity,
                unitPrice: unitPrice,
                isIncome: isIncome,
                isAmount: isAmount,
                accountCountId: accountCountId,
                accountUseId: accountUseId,
                rateCount: rateCount,
                rateInteract: rateInteract,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String> name = const Value.absent(),
                Value<String?> categoryId = const Value.absent(),
                Value<String?> actionId = const Value.absent(),
                required String occurredAt,
                Value<double> quantity = const Value.absent(),
                Value<double> unitPrice = const Value.absent(),
                Value<bool> isIncome = const Value.absent(),
                Value<bool> isAmount = const Value.absent(),
                Value<String?> accountCountId = const Value.absent(),
                Value<String?> accountUseId = const Value.absent(),
                Value<double?> rateCount = const Value.absent(),
                Value<double?> rateInteract = const Value.absent(),
                required String createdAt,
                required String updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => BudgetTransactionsTableCompanion.insert(
                id: id,
                name: name,
                categoryId: categoryId,
                actionId: actionId,
                occurredAt: occurredAt,
                quantity: quantity,
                unitPrice: unitPrice,
                isIncome: isIncome,
                isAmount: isAmount,
                accountCountId: accountCountId,
                accountUseId: accountUseId,
                rateCount: rateCount,
                rateInteract: rateInteract,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$BudgetTransactionsTableTable, BudgetTransaction>(
                    table,
                  ),
                  $$BudgetTransactionsTableTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                categoryId = false,
                actionId = false,
                accountCountId = false,
                accountUseId = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (categoryId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.categoryId,
                            referencedTable:
                                $$BudgetTransactionsTableTableReferences
                                    ._categoryIdTable(db),
                            referencedColumn:
                                $$BudgetTransactionsTableTableReferences
                                    ._categoryIdTable(db)
                                    .id,
                          ) as T;
                        }
                        if (actionId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.actionId,
                            referencedTable:
                                $$BudgetTransactionsTableTableReferences
                                    ._actionIdTable(db),
                            referencedColumn:
                                $$BudgetTransactionsTableTableReferences
                                    ._actionIdTable(db)
                                    .id,
                          ) as T;
                        }
                        if (accountCountId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.accountCountId,
                            referencedTable:
                                $$BudgetTransactionsTableTableReferences
                                    ._accountCountIdTable(db),
                            referencedColumn:
                                $$BudgetTransactionsTableTableReferences
                                    ._accountCountIdTable(db)
                                    .id,
                          ) as T;
                        }
                        if (accountUseId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.accountUseId,
                            referencedTable:
                                $$BudgetTransactionsTableTableReferences
                                    ._accountUseIdTable(db),
                            referencedColumn:
                                $$BudgetTransactionsTableTableReferences
                                    ._accountUseIdTable(db)
                                    .id,
                          ) as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [];
                  },
                );
              },
        ),
      );
}

typedef $$BudgetTransactionsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BudgetTransactionsTableTable,
      BudgetTransaction,
      $$BudgetTransactionsTableTableFilterComposer,
      $$BudgetTransactionsTableTableOrderingComposer,
      $$BudgetTransactionsTableTableAnnotationComposer,
      $$BudgetTransactionsTableTableCreateCompanionBuilder,
      $$BudgetTransactionsTableTableUpdateCompanionBuilder,
      (BudgetTransaction, $$BudgetTransactionsTableTableReferences),
      BudgetTransaction,
      PrefetchHooks Function({
        bool categoryId,
        bool actionId,
        bool accountCountId,
        bool accountUseId,
      })
    >;
typedef $$BudgetSettingsTableTableCreateCompanionBuilder =
    BudgetSettingsTableCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$BudgetSettingsTableTableUpdateCompanionBuilder =
    BudgetSettingsTableCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$BudgetSettingsTableTableFilterComposer
    extends Composer<_$AppDatabase, $BudgetSettingsTableTable> {
  $$BudgetSettingsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BudgetSettingsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $BudgetSettingsTableTable> {
  $$BudgetSettingsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BudgetSettingsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $BudgetSettingsTableTable> {
  $$BudgetSettingsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$BudgetSettingsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BudgetSettingsTableTable,
          BudgetSetting,
          $$BudgetSettingsTableTableFilterComposer,
          $$BudgetSettingsTableTableOrderingComposer,
          $$BudgetSettingsTableTableAnnotationComposer,
          $$BudgetSettingsTableTableCreateCompanionBuilder,
          $$BudgetSettingsTableTableUpdateCompanionBuilder,
          (
            BudgetSetting,
            BaseReferences<
              _$AppDatabase,
              $BudgetSettingsTableTable,
              BudgetSetting
            >,
          ),
          BudgetSetting,
          PrefetchHooks Function()
        > {
  $$BudgetSettingsTableTableTableManager(
    _$AppDatabase db,
    $BudgetSettingsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BudgetSettingsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BudgetSettingsTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$BudgetSettingsTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BudgetSettingsTableCompanion(
                key: key,
                value: value,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => BudgetSettingsTableCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$BudgetSettingsTableTable, BudgetSetting>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $BudgetSettingsTableTable,
                    BudgetSetting
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BudgetSettingsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BudgetSettingsTableTable,
      BudgetSetting,
      $$BudgetSettingsTableTableFilterComposer,
      $$BudgetSettingsTableTableOrderingComposer,
      $$BudgetSettingsTableTableAnnotationComposer,
      $$BudgetSettingsTableTableCreateCompanionBuilder,
      $$BudgetSettingsTableTableUpdateCompanionBuilder,
      (
        BudgetSetting,
        BaseReferences<_$AppDatabase, $BudgetSettingsTableTable, BudgetSetting>,
      ),
      BudgetSetting,
      PrefetchHooks Function()
    >;
typedef $$SavedViewsTableTableCreateCompanionBuilder =
    SavedViewsTableCompanion Function({
      required String id,
      required String screen,
      required String name,
      Value<String> kind,
      Value<String> payload,
      Value<bool> isDefault,
      required String createdAt,
      required String updatedAt,
      Value<int> rowid,
    });
typedef $$SavedViewsTableTableUpdateCompanionBuilder =
    SavedViewsTableCompanion Function({
      Value<String> id,
      Value<String> screen,
      Value<String> name,
      Value<String> kind,
      Value<String> payload,
      Value<bool> isDefault,
      Value<String> createdAt,
      Value<String> updatedAt,
      Value<int> rowid,
    });

class $$SavedViewsTableTableFilterComposer
    extends Composer<_$AppDatabase, $SavedViewsTableTable> {
  $$SavedViewsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get screen => $composableBuilder(
    column: $table.screen,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDefault => $composableBuilder(
    column: $table.isDefault,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SavedViewsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $SavedViewsTableTable> {
  $$SavedViewsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get screen => $composableBuilder(
    column: $table.screen,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDefault => $composableBuilder(
    column: $table.isDefault,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SavedViewsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $SavedViewsTableTable> {
  $$SavedViewsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get screen =>
      $composableBuilder(column: $table.screen, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<bool> get isDefault =>
      $composableBuilder(column: $table.isDefault, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SavedViewsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SavedViewsTableTable,
          SavedView,
          $$SavedViewsTableTableFilterComposer,
          $$SavedViewsTableTableOrderingComposer,
          $$SavedViewsTableTableAnnotationComposer,
          $$SavedViewsTableTableCreateCompanionBuilder,
          $$SavedViewsTableTableUpdateCompanionBuilder,
          (
            SavedView,
            BaseReferences<_$AppDatabase, $SavedViewsTableTable, SavedView>,
          ),
          SavedView,
          PrefetchHooks Function()
        > {
  $$SavedViewsTableTableTableManager(
    _$AppDatabase db,
    $SavedViewsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SavedViewsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SavedViewsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SavedViewsTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> screen = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<bool> isDefault = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SavedViewsTableCompanion(
                id: id,
                screen: screen,
                name: name,
                kind: kind,
                payload: payload,
                isDefault: isDefault,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String screen,
                required String name,
                Value<String> kind = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<bool> isDefault = const Value.absent(),
                required String createdAt,
                required String updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => SavedViewsTableCompanion.insert(
                id: id,
                screen: screen,
                name: name,
                kind: kind,
                payload: payload,
                isDefault: isDefault,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SavedViewsTableTable, SavedView>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $SavedViewsTableTable,
                    SavedView
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SavedViewsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SavedViewsTableTable,
      SavedView,
      $$SavedViewsTableTableFilterComposer,
      $$SavedViewsTableTableOrderingComposer,
      $$SavedViewsTableTableAnnotationComposer,
      $$SavedViewsTableTableCreateCompanionBuilder,
      $$SavedViewsTableTableUpdateCompanionBuilder,
      (
        SavedView,
        BaseReferences<_$AppDatabase, $SavedViewsTableTable, SavedView>,
      ),
      SavedView,
      PrefetchHooks Function()
    >;
typedef $$PlanItemsTableTableCreateCompanionBuilder =
    PlanItemsTableCompanion Function({
      required String id,
      required String name,
      Value<String?> templateId,
      Value<String> kind,
      required String startDate,
      Value<String?> endDate,
      Value<bool> forever,
      Value<bool> paused,
      Value<String> rule,
      Value<String?> collections,
      required String createdAt,
      required String updatedAt,
      Value<int> rowid,
    });
typedef $$PlanItemsTableTableUpdateCompanionBuilder =
    PlanItemsTableCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String?> templateId,
      Value<String> kind,
      Value<String> startDate,
      Value<String?> endDate,
      Value<bool> forever,
      Value<bool> paused,
      Value<String> rule,
      Value<String?> collections,
      Value<String> createdAt,
      Value<String> updatedAt,
      Value<int> rowid,
    });

final class $$PlanItemsTableTableReferences
    extends BaseReferences<_$AppDatabase, $PlanItemsTableTable, PlanItem> {
  $$PlanItemsTableTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$PlanOverridesTableTable, List<PlanOverride>>
  _planOverridesTableRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.planOverridesTable,
        aliasName: 'plan_items__id__plan_overrides__plan_item_id',
      );

  $$PlanOverridesTableTableProcessedTableManager get planOverridesTableRefs {
    final manager = $$PlanOverridesTableTableTableManager(
      $_db,
      $_db.planOverridesTable,
    ).filter((f) => f.planItemId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _planOverridesTableRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$PlanItemsTableTableFilterComposer
    extends Composer<_$AppDatabase, $PlanItemsTableTable> {
  $$PlanItemsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get templateId => $composableBuilder(
    column: $table.templateId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get startDate => $composableBuilder(
    column: $table.startDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get endDate => $composableBuilder(
    column: $table.endDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get forever => $composableBuilder(
    column: $table.forever,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get paused => $composableBuilder(
    column: $table.paused,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rule => $composableBuilder(
    column: $table.rule,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get collections => $composableBuilder(
    column: $table.collections,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> planOverridesTableRefs(
    Expression<bool> Function($$PlanOverridesTableTableFilterComposer f) f,
  ) {
    final $$PlanOverridesTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.planOverridesTable,
      getReferencedColumn: (t) => t.planItemId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PlanOverridesTableTableFilterComposer(
            $db: $db,
            $table: $db.planOverridesTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$PlanItemsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $PlanItemsTableTable> {
  $$PlanItemsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get templateId => $composableBuilder(
    column: $table.templateId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get startDate => $composableBuilder(
    column: $table.startDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get endDate => $composableBuilder(
    column: $table.endDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get forever => $composableBuilder(
    column: $table.forever,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get paused => $composableBuilder(
    column: $table.paused,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rule => $composableBuilder(
    column: $table.rule,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get collections => $composableBuilder(
    column: $table.collections,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PlanItemsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlanItemsTableTable> {
  $$PlanItemsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get templateId => $composableBuilder(
    column: $table.templateId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get startDate =>
      $composableBuilder(column: $table.startDate, builder: (column) => column);

  GeneratedColumn<String> get endDate =>
      $composableBuilder(column: $table.endDate, builder: (column) => column);

  GeneratedColumn<bool> get forever =>
      $composableBuilder(column: $table.forever, builder: (column) => column);

  GeneratedColumn<bool> get paused =>
      $composableBuilder(column: $table.paused, builder: (column) => column);

  GeneratedColumn<String> get rule =>
      $composableBuilder(column: $table.rule, builder: (column) => column);

  GeneratedColumn<String> get collections => $composableBuilder(
    column: $table.collections,
    builder: (column) => column,
  );

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> planOverridesTableRefs<T extends Object>(
    Expression<T> Function($$PlanOverridesTableTableAnnotationComposer a) f,
  ) {
    final $$PlanOverridesTableTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.planOverridesTable,
          getReferencedColumn: (t) => t.planItemId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$PlanOverridesTableTableAnnotationComposer(
                $db: $db,
                $table: $db.planOverridesTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$PlanItemsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PlanItemsTableTable,
          PlanItem,
          $$PlanItemsTableTableFilterComposer,
          $$PlanItemsTableTableOrderingComposer,
          $$PlanItemsTableTableAnnotationComposer,
          $$PlanItemsTableTableCreateCompanionBuilder,
          $$PlanItemsTableTableUpdateCompanionBuilder,
          (PlanItem, $$PlanItemsTableTableReferences),
          PlanItem,
          PrefetchHooks Function({bool planOverridesTableRefs})
        > {
  $$PlanItemsTableTableTableManager(
    _$AppDatabase db,
    $PlanItemsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlanItemsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlanItemsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlanItemsTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> templateId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> startDate = const Value.absent(),
                Value<String?> endDate = const Value.absent(),
                Value<bool> forever = const Value.absent(),
                Value<bool> paused = const Value.absent(),
                Value<String> rule = const Value.absent(),
                Value<String?> collections = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PlanItemsTableCompanion(
                id: id,
                name: name,
                templateId: templateId,
                kind: kind,
                startDate: startDate,
                endDate: endDate,
                forever: forever,
                paused: paused,
                rule: rule,
                collections: collections,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<String?> templateId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                required String startDate,
                Value<String?> endDate = const Value.absent(),
                Value<bool> forever = const Value.absent(),
                Value<bool> paused = const Value.absent(),
                Value<String> rule = const Value.absent(),
                Value<String?> collections = const Value.absent(),
                required String createdAt,
                required String updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => PlanItemsTableCompanion.insert(
                id: id,
                name: name,
                templateId: templateId,
                kind: kind,
                startDate: startDate,
                endDate: endDate,
                forever: forever,
                paused: paused,
                rule: rule,
                collections: collections,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PlanItemsTableTable, PlanItem>(table),
                  $$PlanItemsTableTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({planOverridesTableRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (planOverridesTableRefs) db.planOverridesTable,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (planOverridesTableRefs)
                    await $_getPrefetchedData<
                      PlanItem,
                      $PlanItemsTableTable,
                      PlanOverride
                    >(
                      currentTable: table,
                      referencedTable: $$PlanItemsTableTableReferences
                          ._planOverridesTableRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$PlanItemsTableTableReferences(
                            db,
                            table,
                            p0,
                          ).planOverridesTableRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.planItemId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$PlanItemsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PlanItemsTableTable,
      PlanItem,
      $$PlanItemsTableTableFilterComposer,
      $$PlanItemsTableTableOrderingComposer,
      $$PlanItemsTableTableAnnotationComposer,
      $$PlanItemsTableTableCreateCompanionBuilder,
      $$PlanItemsTableTableUpdateCompanionBuilder,
      (PlanItem, $$PlanItemsTableTableReferences),
      PlanItem,
      PrefetchHooks Function({bool planOverridesTableRefs})
    >;
typedef $$PlanOverridesTableTableCreateCompanionBuilder =
    PlanOverridesTableCompanion Function({
      required String id,
      required String planItemId,
      required String date,
      Value<int> occurrenceIndex,
      Value<int?> startMin,
      Value<int?> durationMin,
      Value<String?> name,
      Value<bool> skipped,
      required String createdAt,
      required String updatedAt,
      Value<int> rowid,
    });
typedef $$PlanOverridesTableTableUpdateCompanionBuilder =
    PlanOverridesTableCompanion Function({
      Value<String> id,
      Value<String> planItemId,
      Value<String> date,
      Value<int> occurrenceIndex,
      Value<int?> startMin,
      Value<int?> durationMin,
      Value<String?> name,
      Value<bool> skipped,
      Value<String> createdAt,
      Value<String> updatedAt,
      Value<int> rowid,
    });

final class $$PlanOverridesTableTableReferences
    extends
        BaseReferences<_$AppDatabase, $PlanOverridesTableTable, PlanOverride> {
  $$PlanOverridesTableTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $PlanItemsTableTable _planItemIdTable(_$AppDatabase db) => db
      .planItemsTable
      .createAlias('plan_overrides__plan_item_id__plan_items__id');

  $$PlanItemsTableTableProcessedTableManager get planItemId {
    final $_column = $_itemColumn<String>('plan_item_id')!;

    final manager = $$PlanItemsTableTableTableManager(
      $_db,
      $_db.planItemsTable,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_planItemIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$PlanOverridesTableTableFilterComposer
    extends Composer<_$AppDatabase, $PlanOverridesTableTable> {
  $$PlanOverridesTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get occurrenceIndex => $composableBuilder(
    column: $table.occurrenceIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startMin => $composableBuilder(
    column: $table.startMin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMin => $composableBuilder(
    column: $table.durationMin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get skipped => $composableBuilder(
    column: $table.skipped,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$PlanItemsTableTableFilterComposer get planItemId {
    final $$PlanItemsTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.planItemId,
      referencedTable: $db.planItemsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PlanItemsTableTableFilterComposer(
            $db: $db,
            $table: $db.planItemsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PlanOverridesTableTableOrderingComposer
    extends Composer<_$AppDatabase, $PlanOverridesTableTable> {
  $$PlanOverridesTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get occurrenceIndex => $composableBuilder(
    column: $table.occurrenceIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startMin => $composableBuilder(
    column: $table.startMin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMin => $composableBuilder(
    column: $table.durationMin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get skipped => $composableBuilder(
    column: $table.skipped,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$PlanItemsTableTableOrderingComposer get planItemId {
    final $$PlanItemsTableTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.planItemId,
      referencedTable: $db.planItemsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PlanItemsTableTableOrderingComposer(
            $db: $db,
            $table: $db.planItemsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PlanOverridesTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlanOverridesTableTable> {
  $$PlanOverridesTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<int> get occurrenceIndex => $composableBuilder(
    column: $table.occurrenceIndex,
    builder: (column) => column,
  );

  GeneratedColumn<int> get startMin =>
      $composableBuilder(column: $table.startMin, builder: (column) => column);

  GeneratedColumn<int> get durationMin => $composableBuilder(
    column: $table.durationMin,
    builder: (column) => column,
  );

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<bool> get skipped =>
      $composableBuilder(column: $table.skipped, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$PlanItemsTableTableAnnotationComposer get planItemId {
    final $$PlanItemsTableTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.planItemId,
      referencedTable: $db.planItemsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PlanItemsTableTableAnnotationComposer(
            $db: $db,
            $table: $db.planItemsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PlanOverridesTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PlanOverridesTableTable,
          PlanOverride,
          $$PlanOverridesTableTableFilterComposer,
          $$PlanOverridesTableTableOrderingComposer,
          $$PlanOverridesTableTableAnnotationComposer,
          $$PlanOverridesTableTableCreateCompanionBuilder,
          $$PlanOverridesTableTableUpdateCompanionBuilder,
          (PlanOverride, $$PlanOverridesTableTableReferences),
          PlanOverride,
          PrefetchHooks Function({bool planItemId})
        > {
  $$PlanOverridesTableTableTableManager(
    _$AppDatabase db,
    $PlanOverridesTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlanOverridesTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlanOverridesTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlanOverridesTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> planItemId = const Value.absent(),
                Value<String> date = const Value.absent(),
                Value<int> occurrenceIndex = const Value.absent(),
                Value<int?> startMin = const Value.absent(),
                Value<int?> durationMin = const Value.absent(),
                Value<String?> name = const Value.absent(),
                Value<bool> skipped = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PlanOverridesTableCompanion(
                id: id,
                planItemId: planItemId,
                date: date,
                occurrenceIndex: occurrenceIndex,
                startMin: startMin,
                durationMin: durationMin,
                name: name,
                skipped: skipped,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String planItemId,
                required String date,
                Value<int> occurrenceIndex = const Value.absent(),
                Value<int?> startMin = const Value.absent(),
                Value<int?> durationMin = const Value.absent(),
                Value<String?> name = const Value.absent(),
                Value<bool> skipped = const Value.absent(),
                required String createdAt,
                required String updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => PlanOverridesTableCompanion.insert(
                id: id,
                planItemId: planItemId,
                date: date,
                occurrenceIndex: occurrenceIndex,
                startMin: startMin,
                durationMin: durationMin,
                name: name,
                skipped: skipped,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PlanOverridesTableTable, PlanOverride>(table),
                  $$PlanOverridesTableTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({planItemId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (planItemId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.planItemId,
                        referencedTable: $$PlanOverridesTableTableReferences
                            ._planItemIdTable(db),
                        referencedColumn: $$PlanOverridesTableTableReferences
                            ._planItemIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$PlanOverridesTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PlanOverridesTableTable,
      PlanOverride,
      $$PlanOverridesTableTableFilterComposer,
      $$PlanOverridesTableTableOrderingComposer,
      $$PlanOverridesTableTableAnnotationComposer,
      $$PlanOverridesTableTableCreateCompanionBuilder,
      $$PlanOverridesTableTableUpdateCompanionBuilder,
      (PlanOverride, $$PlanOverridesTableTableReferences),
      PlanOverride,
      PrefetchHooks Function({bool planItemId})
    >;
typedef $$BudgetTxTemplatesTableTableCreateCompanionBuilder =
    BudgetTxTemplatesTableCompanion Function({
      required String id,
      Value<String> name,
      Value<String?> categoryId,
      Value<double> quantity,
      Value<double?> unitPrice,
      required String createdAt,
      required String updatedAt,
      Value<int> rowid,
    });
typedef $$BudgetTxTemplatesTableTableUpdateCompanionBuilder =
    BudgetTxTemplatesTableCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String?> categoryId,
      Value<double> quantity,
      Value<double?> unitPrice,
      Value<String> createdAt,
      Value<String> updatedAt,
      Value<int> rowid,
    });

class $$BudgetTxTemplatesTableTableFilterComposer
    extends Composer<_$AppDatabase, $BudgetTxTemplatesTableTable> {
  $$BudgetTxTemplatesTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get quantity => $composableBuilder(
    column: $table.quantity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get unitPrice => $composableBuilder(
    column: $table.unitPrice,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BudgetTxTemplatesTableTableOrderingComposer
    extends Composer<_$AppDatabase, $BudgetTxTemplatesTableTable> {
  $$BudgetTxTemplatesTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get quantity => $composableBuilder(
    column: $table.quantity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get unitPrice => $composableBuilder(
    column: $table.unitPrice,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BudgetTxTemplatesTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $BudgetTxTemplatesTableTable> {
  $$BudgetTxTemplatesTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => column,
  );

  GeneratedColumn<double> get quantity =>
      $composableBuilder(column: $table.quantity, builder: (column) => column);

  GeneratedColumn<double> get unitPrice =>
      $composableBuilder(column: $table.unitPrice, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$BudgetTxTemplatesTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BudgetTxTemplatesTableTable,
          BudgetTxTemplate,
          $$BudgetTxTemplatesTableTableFilterComposer,
          $$BudgetTxTemplatesTableTableOrderingComposer,
          $$BudgetTxTemplatesTableTableAnnotationComposer,
          $$BudgetTxTemplatesTableTableCreateCompanionBuilder,
          $$BudgetTxTemplatesTableTableUpdateCompanionBuilder,
          (
            BudgetTxTemplate,
            BaseReferences<
              _$AppDatabase,
              $BudgetTxTemplatesTableTable,
              BudgetTxTemplate
            >,
          ),
          BudgetTxTemplate,
          PrefetchHooks Function()
        > {
  $$BudgetTxTemplatesTableTableTableManager(
    _$AppDatabase db,
    $BudgetTxTemplatesTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BudgetTxTemplatesTableTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$BudgetTxTemplatesTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$BudgetTxTemplatesTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> categoryId = const Value.absent(),
                Value<double> quantity = const Value.absent(),
                Value<double?> unitPrice = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BudgetTxTemplatesTableCompanion(
                id: id,
                name: name,
                categoryId: categoryId,
                quantity: quantity,
                unitPrice: unitPrice,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String> name = const Value.absent(),
                Value<String?> categoryId = const Value.absent(),
                Value<double> quantity = const Value.absent(),
                Value<double?> unitPrice = const Value.absent(),
                required String createdAt,
                required String updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => BudgetTxTemplatesTableCompanion.insert(
                id: id,
                name: name,
                categoryId: categoryId,
                quantity: quantity,
                unitPrice: unitPrice,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$BudgetTxTemplatesTableTable, BudgetTxTemplate>(
                    table,
                  ),
                  BaseReferences<
                    _$AppDatabase,
                    $BudgetTxTemplatesTableTable,
                    BudgetTxTemplate
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BudgetTxTemplatesTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BudgetTxTemplatesTableTable,
      BudgetTxTemplate,
      $$BudgetTxTemplatesTableTableFilterComposer,
      $$BudgetTxTemplatesTableTableOrderingComposer,
      $$BudgetTxTemplatesTableTableAnnotationComposer,
      $$BudgetTxTemplatesTableTableCreateCompanionBuilder,
      $$BudgetTxTemplatesTableTableUpdateCompanionBuilder,
      (
        BudgetTxTemplate,
        BaseReferences<
          _$AppDatabase,
          $BudgetTxTemplatesTableTable,
          BudgetTxTemplate
        >,
      ),
      BudgetTxTemplate,
      PrefetchHooks Function()
    >;
typedef $$PlanCollectionsTableTableCreateCompanionBuilder =
    PlanCollectionsTableCompanion Function({
      required String id,
      required String name,
      Value<bool> visible,
      required String createdAt,
      required String updatedAt,
      Value<int> rowid,
    });
typedef $$PlanCollectionsTableTableUpdateCompanionBuilder =
    PlanCollectionsTableCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<bool> visible,
      Value<String> createdAt,
      Value<String> updatedAt,
      Value<int> rowid,
    });

class $$PlanCollectionsTableTableFilterComposer
    extends Composer<_$AppDatabase, $PlanCollectionsTableTable> {
  $$PlanCollectionsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get visible => $composableBuilder(
    column: $table.visible,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PlanCollectionsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $PlanCollectionsTableTable> {
  $$PlanCollectionsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get visible => $composableBuilder(
    column: $table.visible,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PlanCollectionsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlanCollectionsTableTable> {
  $$PlanCollectionsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<bool> get visible =>
      $composableBuilder(column: $table.visible, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$PlanCollectionsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PlanCollectionsTableTable,
          PlanCollection,
          $$PlanCollectionsTableTableFilterComposer,
          $$PlanCollectionsTableTableOrderingComposer,
          $$PlanCollectionsTableTableAnnotationComposer,
          $$PlanCollectionsTableTableCreateCompanionBuilder,
          $$PlanCollectionsTableTableUpdateCompanionBuilder,
          (
            PlanCollection,
            BaseReferences<
              _$AppDatabase,
              $PlanCollectionsTableTable,
              PlanCollection
            >,
          ),
          PlanCollection,
          PrefetchHooks Function()
        > {
  $$PlanCollectionsTableTableTableManager(
    _$AppDatabase db,
    $PlanCollectionsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlanCollectionsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlanCollectionsTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$PlanCollectionsTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<bool> visible = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PlanCollectionsTableCompanion(
                id: id,
                name: name,
                visible: visible,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<bool> visible = const Value.absent(),
                required String createdAt,
                required String updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => PlanCollectionsTableCompanion.insert(
                id: id,
                name: name,
                visible: visible,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PlanCollectionsTableTable, PlanCollection>(
                    table,
                  ),
                  BaseReferences<
                    _$AppDatabase,
                    $PlanCollectionsTableTable,
                    PlanCollection
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PlanCollectionsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PlanCollectionsTableTable,
      PlanCollection,
      $$PlanCollectionsTableTableFilterComposer,
      $$PlanCollectionsTableTableOrderingComposer,
      $$PlanCollectionsTableTableAnnotationComposer,
      $$PlanCollectionsTableTableCreateCompanionBuilder,
      $$PlanCollectionsTableTableUpdateCompanionBuilder,
      (
        PlanCollection,
        BaseReferences<
          _$AppDatabase,
          $PlanCollectionsTableTable,
          PlanCollection
        >,
      ),
      PlanCollection,
      PrefetchHooks Function()
    >;
typedef $$FormsTableTableCreateCompanionBuilder = FormsTableCompanion Function({
  required String id,
  Value<String> name,
  Value<String> payload,
  required String createdAt,
  required String updatedAt,
  Value<int> rowid,
});
typedef $$FormsTableTableUpdateCompanionBuilder = FormsTableCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<String> payload,
  Value<String> createdAt,
  Value<String> updatedAt,
  Value<int> rowid,
});

class $$FormsTableTableFilterComposer
    extends Composer<_$AppDatabase, $FormsTableTable> {
  $$FormsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FormsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $FormsTableTable> {
  $$FormsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FormsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $FormsTableTable> {
  $$FormsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$FormsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FormsTableTable,
          FormRow,
          $$FormsTableTableFilterComposer,
          $$FormsTableTableOrderingComposer,
          $$FormsTableTableAnnotationComposer,
          $$FormsTableTableCreateCompanionBuilder,
          $$FormsTableTableUpdateCompanionBuilder,
          (FormRow, BaseReferences<_$AppDatabase, $FormsTableTable, FormRow>),
          FormRow,
          PrefetchHooks Function()
        > {
  $$FormsTableTableTableManager(_$AppDatabase db, $FormsTableTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FormsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FormsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FormsTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FormsTableCompanion(
                id: id,
                name: name,
                payload: payload,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String> name = const Value.absent(),
                Value<String> payload = const Value.absent(),
                required String createdAt,
                required String updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => FormsTableCompanion.insert(
                id: id,
                name: name,
                payload: payload,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$FormsTableTable, FormRow>(table),
                  BaseReferences<_$AppDatabase, $FormsTableTable, FormRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FormsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FormsTableTable,
      FormRow,
      $$FormsTableTableFilterComposer,
      $$FormsTableTableOrderingComposer,
      $$FormsTableTableAnnotationComposer,
      $$FormsTableTableCreateCompanionBuilder,
      $$FormsTableTableUpdateCompanionBuilder,
      (FormRow, BaseReferences<_$AppDatabase, $FormsTableTable, FormRow>),
      FormRow,
      PrefetchHooks Function()
    >;
typedef $$CalendarZonesTableTableCreateCompanionBuilder =
    CalendarZonesTableCompanion Function({
      required String id,
      required String tz,
      Value<String> label,
      Value<int> position,
      required String createdAt,
      required String updatedAt,
      Value<int> rowid,
    });
typedef $$CalendarZonesTableTableUpdateCompanionBuilder =
    CalendarZonesTableCompanion Function({
      Value<String> id,
      Value<String> tz,
      Value<String> label,
      Value<int> position,
      Value<String> createdAt,
      Value<String> updatedAt,
      Value<int> rowid,
    });

class $$CalendarZonesTableTableFilterComposer
    extends Composer<_$AppDatabase, $CalendarZonesTableTable> {
  $$CalendarZonesTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tz => $composableBuilder(
    column: $table.tz,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CalendarZonesTableTableOrderingComposer
    extends Composer<_$AppDatabase, $CalendarZonesTableTable> {
  $$CalendarZonesTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tz => $composableBuilder(
    column: $table.tz,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CalendarZonesTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $CalendarZonesTableTable> {
  $$CalendarZonesTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get tz =>
      $composableBuilder(column: $table.tz, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CalendarZonesTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CalendarZonesTableTable,
          CalendarZone,
          $$CalendarZonesTableTableFilterComposer,
          $$CalendarZonesTableTableOrderingComposer,
          $$CalendarZonesTableTableAnnotationComposer,
          $$CalendarZonesTableTableCreateCompanionBuilder,
          $$CalendarZonesTableTableUpdateCompanionBuilder,
          (
            CalendarZone,
            BaseReferences<
              _$AppDatabase,
              $CalendarZonesTableTable,
              CalendarZone
            >,
          ),
          CalendarZone,
          PrefetchHooks Function()
        > {
  $$CalendarZonesTableTableTableManager(
    _$AppDatabase db,
    $CalendarZonesTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CalendarZonesTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CalendarZonesTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CalendarZonesTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> tz = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CalendarZonesTableCompanion(
                id: id,
                tz: tz,
                label: label,
                position: position,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String tz,
                Value<String> label = const Value.absent(),
                Value<int> position = const Value.absent(),
                required String createdAt,
                required String updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => CalendarZonesTableCompanion.insert(
                id: id,
                tz: tz,
                label: label,
                position: position,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CalendarZonesTableTable, CalendarZone>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $CalendarZonesTableTable,
                    CalendarZone
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CalendarZonesTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CalendarZonesTableTable,
      CalendarZone,
      $$CalendarZonesTableTableFilterComposer,
      $$CalendarZonesTableTableOrderingComposer,
      $$CalendarZonesTableTableAnnotationComposer,
      $$CalendarZonesTableTableCreateCompanionBuilder,
      $$CalendarZonesTableTableUpdateCompanionBuilder,
      (
        CalendarZone,
        BaseReferences<_$AppDatabase, $CalendarZonesTableTable, CalendarZone>,
      ),
      CalendarZone,
      PrefetchHooks Function()
    >;
typedef $$AiThreadsTableTableCreateCompanionBuilder =
    AiThreadsTableCompanion Function({
      required String id,
      Value<String> title,
      Value<bool> archived,
      required String createdAt,
      required String updatedAt,
      Value<int> rowid,
    });
typedef $$AiThreadsTableTableUpdateCompanionBuilder =
    AiThreadsTableCompanion Function({
      Value<String> id,
      Value<String> title,
      Value<bool> archived,
      Value<String> createdAt,
      Value<String> updatedAt,
      Value<int> rowid,
    });

class $$AiThreadsTableTableFilterComposer
    extends Composer<_$AppDatabase, $AiThreadsTableTable> {
  $$AiThreadsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get archived => $composableBuilder(
    column: $table.archived,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AiThreadsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $AiThreadsTableTable> {
  $$AiThreadsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get archived => $composableBuilder(
    column: $table.archived,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AiThreadsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $AiThreadsTableTable> {
  $$AiThreadsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<bool> get archived =>
      $composableBuilder(column: $table.archived, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$AiThreadsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AiThreadsTableTable,
          AiThread,
          $$AiThreadsTableTableFilterComposer,
          $$AiThreadsTableTableOrderingComposer,
          $$AiThreadsTableTableAnnotationComposer,
          $$AiThreadsTableTableCreateCompanionBuilder,
          $$AiThreadsTableTableUpdateCompanionBuilder,
          (
            AiThread,
            BaseReferences<_$AppDatabase, $AiThreadsTableTable, AiThread>,
          ),
          AiThread,
          PrefetchHooks Function()
        > {
  $$AiThreadsTableTableTableManager(
    _$AppDatabase db,
    $AiThreadsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AiThreadsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AiThreadsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AiThreadsTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<bool> archived = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AiThreadsTableCompanion(
                id: id,
                title: title,
                archived: archived,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String> title = const Value.absent(),
                Value<bool> archived = const Value.absent(),
                required String createdAt,
                required String updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => AiThreadsTableCompanion.insert(
                id: id,
                title: title,
                archived: archived,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AiThreadsTableTable, AiThread>(table),
                  BaseReferences<_$AppDatabase, $AiThreadsTableTable, AiThread>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AiThreadsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AiThreadsTableTable,
      AiThread,
      $$AiThreadsTableTableFilterComposer,
      $$AiThreadsTableTableOrderingComposer,
      $$AiThreadsTableTableAnnotationComposer,
      $$AiThreadsTableTableCreateCompanionBuilder,
      $$AiThreadsTableTableUpdateCompanionBuilder,
      (AiThread, BaseReferences<_$AppDatabase, $AiThreadsTableTable, AiThread>),
      AiThread,
      PrefetchHooks Function()
    >;
typedef $$AiMessagesTableTableCreateCompanionBuilder =
    AiMessagesTableCompanion Function({
      required String id,
      required String threadId,
      Value<String> role,
      Value<String> kind,
      Value<String> body,
      Value<String> contentJson,
      Value<String?> jobId,
      required String createdAt,
      required String updatedAt,
      Value<int> rowid,
    });
typedef $$AiMessagesTableTableUpdateCompanionBuilder =
    AiMessagesTableCompanion Function({
      Value<String> id,
      Value<String> threadId,
      Value<String> role,
      Value<String> kind,
      Value<String> body,
      Value<String> contentJson,
      Value<String?> jobId,
      Value<String> createdAt,
      Value<String> updatedAt,
      Value<int> rowid,
    });

class $$AiMessagesTableTableFilterComposer
    extends Composer<_$AppDatabase, $AiMessagesTableTable> {
  $$AiMessagesTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get threadId => $composableBuilder(
    column: $table.threadId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentJson => $composableBuilder(
    column: $table.contentJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get jobId => $composableBuilder(
    column: $table.jobId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AiMessagesTableTableOrderingComposer
    extends Composer<_$AppDatabase, $AiMessagesTableTable> {
  $$AiMessagesTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get threadId => $composableBuilder(
    column: $table.threadId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentJson => $composableBuilder(
    column: $table.contentJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get jobId => $composableBuilder(
    column: $table.jobId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AiMessagesTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $AiMessagesTableTable> {
  $$AiMessagesTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get threadId =>
      $composableBuilder(column: $table.threadId, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<String> get contentJson => $composableBuilder(
    column: $table.contentJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get jobId =>
      $composableBuilder(column: $table.jobId, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$AiMessagesTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AiMessagesTableTable,
          AiMessage,
          $$AiMessagesTableTableFilterComposer,
          $$AiMessagesTableTableOrderingComposer,
          $$AiMessagesTableTableAnnotationComposer,
          $$AiMessagesTableTableCreateCompanionBuilder,
          $$AiMessagesTableTableUpdateCompanionBuilder,
          (
            AiMessage,
            BaseReferences<_$AppDatabase, $AiMessagesTableTable, AiMessage>,
          ),
          AiMessage,
          PrefetchHooks Function()
        > {
  $$AiMessagesTableTableTableManager(
    _$AppDatabase db,
    $AiMessagesTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AiMessagesTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AiMessagesTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AiMessagesTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> threadId = const Value.absent(),
                Value<String> role = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<String> contentJson = const Value.absent(),
                Value<String?> jobId = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AiMessagesTableCompanion(
                id: id,
                threadId: threadId,
                role: role,
                kind: kind,
                body: body,
                contentJson: contentJson,
                jobId: jobId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String threadId,
                Value<String> role = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<String> contentJson = const Value.absent(),
                Value<String?> jobId = const Value.absent(),
                required String createdAt,
                required String updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => AiMessagesTableCompanion.insert(
                id: id,
                threadId: threadId,
                role: role,
                kind: kind,
                body: body,
                contentJson: contentJson,
                jobId: jobId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AiMessagesTableTable, AiMessage>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $AiMessagesTableTable,
                    AiMessage
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AiMessagesTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AiMessagesTableTable,
      AiMessage,
      $$AiMessagesTableTableFilterComposer,
      $$AiMessagesTableTableOrderingComposer,
      $$AiMessagesTableTableAnnotationComposer,
      $$AiMessagesTableTableCreateCompanionBuilder,
      $$AiMessagesTableTableUpdateCompanionBuilder,
      (
        AiMessage,
        BaseReferences<_$AppDatabase, $AiMessagesTableTable, AiMessage>,
      ),
      AiMessage,
      PrefetchHooks Function()
    >;
typedef $$AiJobsTableTableCreateCompanionBuilder =
    AiJobsTableCompanion Function({
      required String id,
      required String threadId,
      Value<String> kind,
      Value<String> state,
      Value<String> stage,
      Value<String> payloadJson,
      Value<String?> error,
      Value<int> attempts,
      required String createdAt,
      required String updatedAt,
      Value<int> rowid,
    });
typedef $$AiJobsTableTableUpdateCompanionBuilder =
    AiJobsTableCompanion Function({
      Value<String> id,
      Value<String> threadId,
      Value<String> kind,
      Value<String> state,
      Value<String> stage,
      Value<String> payloadJson,
      Value<String?> error,
      Value<int> attempts,
      Value<String> createdAt,
      Value<String> updatedAt,
      Value<int> rowid,
    });

class $$AiJobsTableTableFilterComposer
    extends Composer<_$AppDatabase, $AiJobsTableTable> {
  $$AiJobsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get threadId => $composableBuilder(
    column: $table.threadId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get stage => $composableBuilder(
    column: $table.stage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AiJobsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $AiJobsTableTable> {
  $$AiJobsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get threadId => $composableBuilder(
    column: $table.threadId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get stage => $composableBuilder(
    column: $table.stage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AiJobsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $AiJobsTableTable> {
  $$AiJobsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get threadId =>
      $composableBuilder(column: $table.threadId, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<String> get stage =>
      $composableBuilder(column: $table.stage, builder: (column) => column);

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get error =>
      $composableBuilder(column: $table.error, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$AiJobsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AiJobsTableTable,
          AiJob,
          $$AiJobsTableTableFilterComposer,
          $$AiJobsTableTableOrderingComposer,
          $$AiJobsTableTableAnnotationComposer,
          $$AiJobsTableTableCreateCompanionBuilder,
          $$AiJobsTableTableUpdateCompanionBuilder,
          (AiJob, BaseReferences<_$AppDatabase, $AiJobsTableTable, AiJob>),
          AiJob,
          PrefetchHooks Function()
        > {
  $$AiJobsTableTableTableManager(_$AppDatabase db, $AiJobsTableTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AiJobsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AiJobsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AiJobsTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> threadId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<String> stage = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<String?> error = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AiJobsTableCompanion(
                id: id,
                threadId: threadId,
                kind: kind,
                state: state,
                stage: stage,
                payloadJson: payloadJson,
                error: error,
                attempts: attempts,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String threadId,
                Value<String> kind = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<String> stage = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<String?> error = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                required String createdAt,
                required String updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => AiJobsTableCompanion.insert(
                id: id,
                threadId: threadId,
                kind: kind,
                state: state,
                stage: stage,
                payloadJson: payloadJson,
                error: error,
                attempts: attempts,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AiJobsTableTable, AiJob>(table),
                  BaseReferences<_$AppDatabase, $AiJobsTableTable, AiJob>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AiJobsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AiJobsTableTable,
      AiJob,
      $$AiJobsTableTableFilterComposer,
      $$AiJobsTableTableOrderingComposer,
      $$AiJobsTableTableAnnotationComposer,
      $$AiJobsTableTableCreateCompanionBuilder,
      $$AiJobsTableTableUpdateCompanionBuilder,
      (AiJob, BaseReferences<_$AppDatabase, $AiJobsTableTable, AiJob>),
      AiJob,
      PrefetchHooks Function()
    >;
typedef $$AiBatchesTableTableCreateCompanionBuilder =
    AiBatchesTableCompanion Function({
      required String id,
      required String jobId,
      required String threadId,
      Value<String?> messageId,
      Value<String> summary,
      Value<String?> undoneAt,
      required String createdAt,
      required String updatedAt,
      Value<int> rowid,
    });
typedef $$AiBatchesTableTableUpdateCompanionBuilder =
    AiBatchesTableCompanion Function({
      Value<String> id,
      Value<String> jobId,
      Value<String> threadId,
      Value<String?> messageId,
      Value<String> summary,
      Value<String?> undoneAt,
      Value<String> createdAt,
      Value<String> updatedAt,
      Value<int> rowid,
    });

class $$AiBatchesTableTableFilterComposer
    extends Composer<_$AppDatabase, $AiBatchesTableTable> {
  $$AiBatchesTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get jobId => $composableBuilder(
    column: $table.jobId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get threadId => $composableBuilder(
    column: $table.threadId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get summary => $composableBuilder(
    column: $table.summary,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get undoneAt => $composableBuilder(
    column: $table.undoneAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AiBatchesTableTableOrderingComposer
    extends Composer<_$AppDatabase, $AiBatchesTableTable> {
  $$AiBatchesTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get jobId => $composableBuilder(
    column: $table.jobId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get threadId => $composableBuilder(
    column: $table.threadId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get summary => $composableBuilder(
    column: $table.summary,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get undoneAt => $composableBuilder(
    column: $table.undoneAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AiBatchesTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $AiBatchesTableTable> {
  $$AiBatchesTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get jobId =>
      $composableBuilder(column: $table.jobId, builder: (column) => column);

  GeneratedColumn<String> get threadId =>
      $composableBuilder(column: $table.threadId, builder: (column) => column);

  GeneratedColumn<String> get messageId =>
      $composableBuilder(column: $table.messageId, builder: (column) => column);

  GeneratedColumn<String> get summary =>
      $composableBuilder(column: $table.summary, builder: (column) => column);

  GeneratedColumn<String> get undoneAt =>
      $composableBuilder(column: $table.undoneAt, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$AiBatchesTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AiBatchesTableTable,
          AiBatch,
          $$AiBatchesTableTableFilterComposer,
          $$AiBatchesTableTableOrderingComposer,
          $$AiBatchesTableTableAnnotationComposer,
          $$AiBatchesTableTableCreateCompanionBuilder,
          $$AiBatchesTableTableUpdateCompanionBuilder,
          (
            AiBatch,
            BaseReferences<_$AppDatabase, $AiBatchesTableTable, AiBatch>,
          ),
          AiBatch,
          PrefetchHooks Function()
        > {
  $$AiBatchesTableTableTableManager(
    _$AppDatabase db,
    $AiBatchesTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AiBatchesTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AiBatchesTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AiBatchesTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> jobId = const Value.absent(),
                Value<String> threadId = const Value.absent(),
                Value<String?> messageId = const Value.absent(),
                Value<String> summary = const Value.absent(),
                Value<String?> undoneAt = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AiBatchesTableCompanion(
                id: id,
                jobId: jobId,
                threadId: threadId,
                messageId: messageId,
                summary: summary,
                undoneAt: undoneAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String jobId,
                required String threadId,
                Value<String?> messageId = const Value.absent(),
                Value<String> summary = const Value.absent(),
                Value<String?> undoneAt = const Value.absent(),
                required String createdAt,
                required String updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => AiBatchesTableCompanion.insert(
                id: id,
                jobId: jobId,
                threadId: threadId,
                messageId: messageId,
                summary: summary,
                undoneAt: undoneAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AiBatchesTableTable, AiBatch>(table),
                  BaseReferences<_$AppDatabase, $AiBatchesTableTable, AiBatch>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AiBatchesTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AiBatchesTableTable,
      AiBatch,
      $$AiBatchesTableTableFilterComposer,
      $$AiBatchesTableTableOrderingComposer,
      $$AiBatchesTableTableAnnotationComposer,
      $$AiBatchesTableTableCreateCompanionBuilder,
      $$AiBatchesTableTableUpdateCompanionBuilder,
      (AiBatch, BaseReferences<_$AppDatabase, $AiBatchesTableTable, AiBatch>),
      AiBatch,
      PrefetchHooks Function()
    >;
typedef $$AiBatchItemsTableTableCreateCompanionBuilder =
    AiBatchItemsTableCompanion Function({
      required String id,
      required String batchId,
      required String entityType,
      required String entityId,
      Value<String> op,
      Value<String?> beforeJson,
      Value<String?> afterJson,
      Value<int> position,
      required String createdAt,
      required String updatedAt,
      Value<int> rowid,
    });
typedef $$AiBatchItemsTableTableUpdateCompanionBuilder =
    AiBatchItemsTableCompanion Function({
      Value<String> id,
      Value<String> batchId,
      Value<String> entityType,
      Value<String> entityId,
      Value<String> op,
      Value<String?> beforeJson,
      Value<String?> afterJson,
      Value<int> position,
      Value<String> createdAt,
      Value<String> updatedAt,
      Value<int> rowid,
    });

class $$AiBatchItemsTableTableFilterComposer
    extends Composer<_$AppDatabase, $AiBatchItemsTableTable> {
  $$AiBatchItemsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get batchId => $composableBuilder(
    column: $table.batchId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get op => $composableBuilder(
    column: $table.op,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get beforeJson => $composableBuilder(
    column: $table.beforeJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get afterJson => $composableBuilder(
    column: $table.afterJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AiBatchItemsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $AiBatchItemsTableTable> {
  $$AiBatchItemsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get batchId => $composableBuilder(
    column: $table.batchId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get op => $composableBuilder(
    column: $table.op,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get beforeJson => $composableBuilder(
    column: $table.beforeJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get afterJson => $composableBuilder(
    column: $table.afterJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AiBatchItemsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $AiBatchItemsTableTable> {
  $$AiBatchItemsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get batchId =>
      $composableBuilder(column: $table.batchId, builder: (column) => column);

  GeneratedColumn<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get op =>
      $composableBuilder(column: $table.op, builder: (column) => column);

  GeneratedColumn<String> get beforeJson => $composableBuilder(
    column: $table.beforeJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get afterJson =>
      $composableBuilder(column: $table.afterJson, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$AiBatchItemsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AiBatchItemsTableTable,
          AiBatchItem,
          $$AiBatchItemsTableTableFilterComposer,
          $$AiBatchItemsTableTableOrderingComposer,
          $$AiBatchItemsTableTableAnnotationComposer,
          $$AiBatchItemsTableTableCreateCompanionBuilder,
          $$AiBatchItemsTableTableUpdateCompanionBuilder,
          (
            AiBatchItem,
            BaseReferences<_$AppDatabase, $AiBatchItemsTableTable, AiBatchItem>,
          ),
          AiBatchItem,
          PrefetchHooks Function()
        > {
  $$AiBatchItemsTableTableTableManager(
    _$AppDatabase db,
    $AiBatchItemsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AiBatchItemsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AiBatchItemsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AiBatchItemsTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> batchId = const Value.absent(),
                Value<String> entityType = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<String> op = const Value.absent(),
                Value<String?> beforeJson = const Value.absent(),
                Value<String?> afterJson = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AiBatchItemsTableCompanion(
                id: id,
                batchId: batchId,
                entityType: entityType,
                entityId: entityId,
                op: op,
                beforeJson: beforeJson,
                afterJson: afterJson,
                position: position,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String batchId,
                required String entityType,
                required String entityId,
                Value<String> op = const Value.absent(),
                Value<String?> beforeJson = const Value.absent(),
                Value<String?> afterJson = const Value.absent(),
                Value<int> position = const Value.absent(),
                required String createdAt,
                required String updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => AiBatchItemsTableCompanion.insert(
                id: id,
                batchId: batchId,
                entityType: entityType,
                entityId: entityId,
                op: op,
                beforeJson: beforeJson,
                afterJson: afterJson,
                position: position,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AiBatchItemsTableTable, AiBatchItem>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $AiBatchItemsTableTable,
                    AiBatchItem
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AiBatchItemsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AiBatchItemsTableTable,
      AiBatchItem,
      $$AiBatchItemsTableTableFilterComposer,
      $$AiBatchItemsTableTableOrderingComposer,
      $$AiBatchItemsTableTableAnnotationComposer,
      $$AiBatchItemsTableTableCreateCompanionBuilder,
      $$AiBatchItemsTableTableUpdateCompanionBuilder,
      (
        AiBatchItem,
        BaseReferences<_$AppDatabase, $AiBatchItemsTableTable, AiBatchItem>,
      ),
      AiBatchItem,
      PrefetchHooks Function()
    >;
typedef $$AiBlobsTableTableCreateCompanionBuilder =
    AiBlobsTableCompanion Function({
      required String id,
      Value<String?> messageId,
      Value<String?> jobId,
      Value<String> kind,
      Value<String> mime,
      Value<String?> data,
      Value<String> sha256,
      Value<int?> width,
      Value<int?> height,
      Value<String?> storedOnHubAt,
      required String createdAt,
      required String updatedAt,
      Value<int> rowid,
    });
typedef $$AiBlobsTableTableUpdateCompanionBuilder =
    AiBlobsTableCompanion Function({
      Value<String> id,
      Value<String?> messageId,
      Value<String?> jobId,
      Value<String> kind,
      Value<String> mime,
      Value<String?> data,
      Value<String> sha256,
      Value<int?> width,
      Value<int?> height,
      Value<String?> storedOnHubAt,
      Value<String> createdAt,
      Value<String> updatedAt,
      Value<int> rowid,
    });

class $$AiBlobsTableTableFilterComposer
    extends Composer<_$AppDatabase, $AiBlobsTableTable> {
  $$AiBlobsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get jobId => $composableBuilder(
    column: $table.jobId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mime => $composableBuilder(
    column: $table.mime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get data => $composableBuilder(
    column: $table.data,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get storedOnHubAt => $composableBuilder(
    column: $table.storedOnHubAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AiBlobsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $AiBlobsTableTable> {
  $$AiBlobsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get jobId => $composableBuilder(
    column: $table.jobId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mime => $composableBuilder(
    column: $table.mime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get data => $composableBuilder(
    column: $table.data,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get storedOnHubAt => $composableBuilder(
    column: $table.storedOnHubAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AiBlobsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $AiBlobsTableTable> {
  $$AiBlobsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get messageId =>
      $composableBuilder(column: $table.messageId, builder: (column) => column);

  GeneratedColumn<String> get jobId =>
      $composableBuilder(column: $table.jobId, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get mime =>
      $composableBuilder(column: $table.mime, builder: (column) => column);

  GeneratedColumn<String> get data =>
      $composableBuilder(column: $table.data, builder: (column) => column);

  GeneratedColumn<String> get sha256 =>
      $composableBuilder(column: $table.sha256, builder: (column) => column);

  GeneratedColumn<int> get width =>
      $composableBuilder(column: $table.width, builder: (column) => column);

  GeneratedColumn<int> get height =>
      $composableBuilder(column: $table.height, builder: (column) => column);

  GeneratedColumn<String> get storedOnHubAt => $composableBuilder(
    column: $table.storedOnHubAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$AiBlobsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AiBlobsTableTable,
          AiBlob,
          $$AiBlobsTableTableFilterComposer,
          $$AiBlobsTableTableOrderingComposer,
          $$AiBlobsTableTableAnnotationComposer,
          $$AiBlobsTableTableCreateCompanionBuilder,
          $$AiBlobsTableTableUpdateCompanionBuilder,
          (AiBlob, BaseReferences<_$AppDatabase, $AiBlobsTableTable, AiBlob>),
          AiBlob,
          PrefetchHooks Function()
        > {
  $$AiBlobsTableTableTableManager(_$AppDatabase db, $AiBlobsTableTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AiBlobsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AiBlobsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AiBlobsTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> messageId = const Value.absent(),
                Value<String?> jobId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> mime = const Value.absent(),
                Value<String?> data = const Value.absent(),
                Value<String> sha256 = const Value.absent(),
                Value<int?> width = const Value.absent(),
                Value<int?> height = const Value.absent(),
                Value<String?> storedOnHubAt = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AiBlobsTableCompanion(
                id: id,
                messageId: messageId,
                jobId: jobId,
                kind: kind,
                mime: mime,
                data: data,
                sha256: sha256,
                width: width,
                height: height,
                storedOnHubAt: storedOnHubAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> messageId = const Value.absent(),
                Value<String?> jobId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> mime = const Value.absent(),
                Value<String?> data = const Value.absent(),
                Value<String> sha256 = const Value.absent(),
                Value<int?> width = const Value.absent(),
                Value<int?> height = const Value.absent(),
                Value<String?> storedOnHubAt = const Value.absent(),
                required String createdAt,
                required String updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => AiBlobsTableCompanion.insert(
                id: id,
                messageId: messageId,
                jobId: jobId,
                kind: kind,
                mime: mime,
                data: data,
                sha256: sha256,
                width: width,
                height: height,
                storedOnHubAt: storedOnHubAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AiBlobsTableTable, AiBlob>(table),
                  BaseReferences<_$AppDatabase, $AiBlobsTableTable, AiBlob>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AiBlobsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AiBlobsTableTable,
      AiBlob,
      $$AiBlobsTableTableFilterComposer,
      $$AiBlobsTableTableOrderingComposer,
      $$AiBlobsTableTableAnnotationComposer,
      $$AiBlobsTableTableCreateCompanionBuilder,
      $$AiBlobsTableTableUpdateCompanionBuilder,
      (AiBlob, BaseReferences<_$AppDatabase, $AiBlobsTableTable, AiBlob>),
      AiBlob,
      PrefetchHooks Function()
    >;
typedef $$ProductAliasesTableTableCreateCompanionBuilder =
    ProductAliasesTableCompanion Function({
      required String id,
      required String pattern,
      Value<String?> categoryId,
      Value<String?> unitOverride,
      Value<double?> weightGramsDefault,
      Value<double?> pieceDefault,
      Value<String> source,
      required String createdAt,
      required String updatedAt,
      Value<int> rowid,
    });
typedef $$ProductAliasesTableTableUpdateCompanionBuilder =
    ProductAliasesTableCompanion Function({
      Value<String> id,
      Value<String> pattern,
      Value<String?> categoryId,
      Value<String?> unitOverride,
      Value<double?> weightGramsDefault,
      Value<double?> pieceDefault,
      Value<String> source,
      Value<String> createdAt,
      Value<String> updatedAt,
      Value<int> rowid,
    });

class $$ProductAliasesTableTableFilterComposer
    extends Composer<_$AppDatabase, $ProductAliasesTableTable> {
  $$ProductAliasesTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pattern => $composableBuilder(
    column: $table.pattern,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get unitOverride => $composableBuilder(
    column: $table.unitOverride,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get weightGramsDefault => $composableBuilder(
    column: $table.weightGramsDefault,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get pieceDefault => $composableBuilder(
    column: $table.pieceDefault,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ProductAliasesTableTableOrderingComposer
    extends Composer<_$AppDatabase, $ProductAliasesTableTable> {
  $$ProductAliasesTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pattern => $composableBuilder(
    column: $table.pattern,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get unitOverride => $composableBuilder(
    column: $table.unitOverride,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get weightGramsDefault => $composableBuilder(
    column: $table.weightGramsDefault,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get pieceDefault => $composableBuilder(
    column: $table.pieceDefault,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProductAliasesTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProductAliasesTableTable> {
  $$ProductAliasesTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get pattern =>
      $composableBuilder(column: $table.pattern, builder: (column) => column);

  GeneratedColumn<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get unitOverride => $composableBuilder(
    column: $table.unitOverride,
    builder: (column) => column,
  );

  GeneratedColumn<double> get weightGramsDefault => $composableBuilder(
    column: $table.weightGramsDefault,
    builder: (column) => column,
  );

  GeneratedColumn<double> get pieceDefault => $composableBuilder(
    column: $table.pieceDefault,
    builder: (column) => column,
  );

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ProductAliasesTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ProductAliasesTableTable,
          ProductAlias,
          $$ProductAliasesTableTableFilterComposer,
          $$ProductAliasesTableTableOrderingComposer,
          $$ProductAliasesTableTableAnnotationComposer,
          $$ProductAliasesTableTableCreateCompanionBuilder,
          $$ProductAliasesTableTableUpdateCompanionBuilder,
          (
            ProductAlias,
            BaseReferences<
              _$AppDatabase,
              $ProductAliasesTableTable,
              ProductAlias
            >,
          ),
          ProductAlias,
          PrefetchHooks Function()
        > {
  $$ProductAliasesTableTableTableManager(
    _$AppDatabase db,
    $ProductAliasesTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProductAliasesTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProductAliasesTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ProductAliasesTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> pattern = const Value.absent(),
                Value<String?> categoryId = const Value.absent(),
                Value<String?> unitOverride = const Value.absent(),
                Value<double?> weightGramsDefault = const Value.absent(),
                Value<double?> pieceDefault = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProductAliasesTableCompanion(
                id: id,
                pattern: pattern,
                categoryId: categoryId,
                unitOverride: unitOverride,
                weightGramsDefault: weightGramsDefault,
                pieceDefault: pieceDefault,
                source: source,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String pattern,
                Value<String?> categoryId = const Value.absent(),
                Value<String?> unitOverride = const Value.absent(),
                Value<double?> weightGramsDefault = const Value.absent(),
                Value<double?> pieceDefault = const Value.absent(),
                Value<String> source = const Value.absent(),
                required String createdAt,
                required String updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ProductAliasesTableCompanion.insert(
                id: id,
                pattern: pattern,
                categoryId: categoryId,
                unitOverride: unitOverride,
                weightGramsDefault: weightGramsDefault,
                pieceDefault: pieceDefault,
                source: source,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ProductAliasesTableTable, ProductAlias>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $ProductAliasesTableTable,
                    ProductAlias
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ProductAliasesTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ProductAliasesTableTable,
      ProductAlias,
      $$ProductAliasesTableTableFilterComposer,
      $$ProductAliasesTableTableOrderingComposer,
      $$ProductAliasesTableTableAnnotationComposer,
      $$ProductAliasesTableTableCreateCompanionBuilder,
      $$ProductAliasesTableTableUpdateCompanionBuilder,
      (
        ProductAlias,
        BaseReferences<_$AppDatabase, $ProductAliasesTableTable, ProductAlias>,
      ),
      ProductAlias,
      PrefetchHooks Function()
    >;
typedef $$AiRulesMemoryTableTableCreateCompanionBuilder =
    AiRulesMemoryTableCompanion Function({
      required String id,
      required String key,
      Value<String> valueJson,
      Value<String?> sourceMessageId,
      required String createdAt,
      required String updatedAt,
      Value<int> rowid,
    });
typedef $$AiRulesMemoryTableTableUpdateCompanionBuilder =
    AiRulesMemoryTableCompanion Function({
      Value<String> id,
      Value<String> key,
      Value<String> valueJson,
      Value<String?> sourceMessageId,
      Value<String> createdAt,
      Value<String> updatedAt,
      Value<int> rowid,
    });

class $$AiRulesMemoryTableTableFilterComposer
    extends Composer<_$AppDatabase, $AiRulesMemoryTableTable> {
  $$AiRulesMemoryTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get valueJson => $composableBuilder(
    column: $table.valueJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceMessageId => $composableBuilder(
    column: $table.sourceMessageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AiRulesMemoryTableTableOrderingComposer
    extends Composer<_$AppDatabase, $AiRulesMemoryTableTable> {
  $$AiRulesMemoryTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get valueJson => $composableBuilder(
    column: $table.valueJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceMessageId => $composableBuilder(
    column: $table.sourceMessageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AiRulesMemoryTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $AiRulesMemoryTableTable> {
  $$AiRulesMemoryTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get valueJson =>
      $composableBuilder(column: $table.valueJson, builder: (column) => column);

  GeneratedColumn<String> get sourceMessageId => $composableBuilder(
    column: $table.sourceMessageId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$AiRulesMemoryTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AiRulesMemoryTableTable,
          AiRule,
          $$AiRulesMemoryTableTableFilterComposer,
          $$AiRulesMemoryTableTableOrderingComposer,
          $$AiRulesMemoryTableTableAnnotationComposer,
          $$AiRulesMemoryTableTableCreateCompanionBuilder,
          $$AiRulesMemoryTableTableUpdateCompanionBuilder,
          (
            AiRule,
            BaseReferences<_$AppDatabase, $AiRulesMemoryTableTable, AiRule>,
          ),
          AiRule,
          PrefetchHooks Function()
        > {
  $$AiRulesMemoryTableTableTableManager(
    _$AppDatabase db,
    $AiRulesMemoryTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AiRulesMemoryTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AiRulesMemoryTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AiRulesMemoryTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> key = const Value.absent(),
                Value<String> valueJson = const Value.absent(),
                Value<String?> sourceMessageId = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AiRulesMemoryTableCompanion(
                id: id,
                key: key,
                valueJson: valueJson,
                sourceMessageId: sourceMessageId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String key,
                Value<String> valueJson = const Value.absent(),
                Value<String?> sourceMessageId = const Value.absent(),
                required String createdAt,
                required String updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => AiRulesMemoryTableCompanion.insert(
                id: id,
                key: key,
                valueJson: valueJson,
                sourceMessageId: sourceMessageId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AiRulesMemoryTableTable, AiRule>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $AiRulesMemoryTableTable,
                    AiRule
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AiRulesMemoryTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AiRulesMemoryTableTable,
      AiRule,
      $$AiRulesMemoryTableTableFilterComposer,
      $$AiRulesMemoryTableTableOrderingComposer,
      $$AiRulesMemoryTableTableAnnotationComposer,
      $$AiRulesMemoryTableTableCreateCompanionBuilder,
      $$AiRulesMemoryTableTableUpdateCompanionBuilder,
      (AiRule, BaseReferences<_$AppDatabase, $AiRulesMemoryTableTable, AiRule>),
      AiRule,
      PrefetchHooks Function()
    >;
typedef $$AiSettingsTableTableCreateCompanionBuilder =
    AiSettingsTableCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$AiSettingsTableTableUpdateCompanionBuilder =
    AiSettingsTableCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$AiSettingsTableTableFilterComposer
    extends Composer<_$AppDatabase, $AiSettingsTableTable> {
  $$AiSettingsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AiSettingsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $AiSettingsTableTable> {
  $$AiSettingsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AiSettingsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $AiSettingsTableTable> {
  $$AiSettingsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$AiSettingsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AiSettingsTableTable,
          AiSetting,
          $$AiSettingsTableTableFilterComposer,
          $$AiSettingsTableTableOrderingComposer,
          $$AiSettingsTableTableAnnotationComposer,
          $$AiSettingsTableTableCreateCompanionBuilder,
          $$AiSettingsTableTableUpdateCompanionBuilder,
          (
            AiSetting,
            BaseReferences<_$AppDatabase, $AiSettingsTableTable, AiSetting>,
          ),
          AiSetting,
          PrefetchHooks Function()
        > {
  $$AiSettingsTableTableTableManager(
    _$AppDatabase db,
    $AiSettingsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AiSettingsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AiSettingsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AiSettingsTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => AiSettingsTableCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => AiSettingsTableCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AiSettingsTableTable, AiSetting>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $AiSettingsTableTable,
                    AiSetting
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AiSettingsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AiSettingsTableTable,
      AiSetting,
      $$AiSettingsTableTableFilterComposer,
      $$AiSettingsTableTableOrderingComposer,
      $$AiSettingsTableTableAnnotationComposer,
      $$AiSettingsTableTableCreateCompanionBuilder,
      $$AiSettingsTableTableUpdateCompanionBuilder,
      (
        AiSetting,
        BaseReferences<_$AppDatabase, $AiSettingsTableTable, AiSetting>,
      ),
      AiSetting,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$CountableActivitiesTableTableTableManager get countableActivitiesTable =>
      $$CountableActivitiesTableTableTableManager(
        _db,
        _db.countableActivitiesTable,
      );
  $$ActionsTableTableTableManager get actionsTable =>
      $$ActionsTableTableTableManager(_db, _db.actionsTable);
  $$ActionDependenciesTableTableTableManager get actionDependenciesTable =>
      $$ActionDependenciesTableTableTableManager(
        _db,
        _db.actionDependenciesTable,
      );
  $$ActionOccurrencesTableTableTableManager get actionOccurrencesTable =>
      $$ActionOccurrencesTableTableTableManager(
        _db,
        _db.actionOccurrencesTable,
      );
  $$MetricsTableTableTableManager get metricsTable =>
      $$MetricsTableTableTableManager(_db, _db.metricsTable);
  $$ActionMetricsTableTableTableManager get actionMetricsTable =>
      $$ActionMetricsTableTableTableManager(_db, _db.actionMetricsTable);
  $$ActionTemplatesTableTableTableManager get actionTemplatesTable =>
      $$ActionTemplatesTableTableTableManager(_db, _db.actionTemplatesTable);
  $$MetricDependenciesTableTableTableManager get metricDependenciesTable =>
      $$MetricDependenciesTableTableTableManager(
        _db,
        _db.metricDependenciesTable,
      );
  $$BudgetAccountsTableTableTableManager get budgetAccountsTable =>
      $$BudgetAccountsTableTableTableManager(_db, _db.budgetAccountsTable);
  $$BudgetCategoriesTableTableTableManager get budgetCategoriesTable =>
      $$BudgetCategoriesTableTableTableManager(_db, _db.budgetCategoriesTable);
  $$BudgetTransactionsTableTableTableManager get budgetTransactionsTable =>
      $$BudgetTransactionsTableTableTableManager(
        _db,
        _db.budgetTransactionsTable,
      );
  $$BudgetSettingsTableTableTableManager get budgetSettingsTable =>
      $$BudgetSettingsTableTableTableManager(_db, _db.budgetSettingsTable);
  $$SavedViewsTableTableTableManager get savedViewsTable =>
      $$SavedViewsTableTableTableManager(_db, _db.savedViewsTable);
  $$PlanItemsTableTableTableManager get planItemsTable =>
      $$PlanItemsTableTableTableManager(_db, _db.planItemsTable);
  $$PlanOverridesTableTableTableManager get planOverridesTable =>
      $$PlanOverridesTableTableTableManager(_db, _db.planOverridesTable);
  $$BudgetTxTemplatesTableTableTableManager get budgetTxTemplatesTable =>
      $$BudgetTxTemplatesTableTableTableManager(
        _db,
        _db.budgetTxTemplatesTable,
      );
  $$PlanCollectionsTableTableTableManager get planCollectionsTable =>
      $$PlanCollectionsTableTableTableManager(_db, _db.planCollectionsTable);
  $$FormsTableTableTableManager get formsTable =>
      $$FormsTableTableTableManager(_db, _db.formsTable);
  $$CalendarZonesTableTableTableManager get calendarZonesTable =>
      $$CalendarZonesTableTableTableManager(_db, _db.calendarZonesTable);
  $$AiThreadsTableTableTableManager get aiThreadsTable =>
      $$AiThreadsTableTableTableManager(_db, _db.aiThreadsTable);
  $$AiMessagesTableTableTableManager get aiMessagesTable =>
      $$AiMessagesTableTableTableManager(_db, _db.aiMessagesTable);
  $$AiJobsTableTableTableManager get aiJobsTable =>
      $$AiJobsTableTableTableManager(_db, _db.aiJobsTable);
  $$AiBatchesTableTableTableManager get aiBatchesTable =>
      $$AiBatchesTableTableTableManager(_db, _db.aiBatchesTable);
  $$AiBatchItemsTableTableTableManager get aiBatchItemsTable =>
      $$AiBatchItemsTableTableTableManager(_db, _db.aiBatchItemsTable);
  $$AiBlobsTableTableTableManager get aiBlobsTable =>
      $$AiBlobsTableTableTableManager(_db, _db.aiBlobsTable);
  $$ProductAliasesTableTableTableManager get productAliasesTable =>
      $$ProductAliasesTableTableTableManager(_db, _db.productAliasesTable);
  $$AiRulesMemoryTableTableTableManager get aiRulesMemoryTable =>
      $$AiRulesMemoryTableTableTableManager(_db, _db.aiRulesMemoryTable);
  $$AiSettingsTableTableTableManager get aiSettingsTable =>
      $$AiSettingsTableTableTableManager(_db, _db.aiSettingsTable);
}
