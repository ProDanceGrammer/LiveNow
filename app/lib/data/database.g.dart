// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
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
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('task'),
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('open'),
  );
  static const VerificationMeta _priorityMeta = const VerificationMeta(
    'priority',
  );
  @override
  late final GeneratedColumn<String> priority = GeneratedColumn<String>(
    'priority',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
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
    kind,
    status,
    priority,
    postponeFlex,
    depthLevel,
    startAt,
    endAt,
    isAllDay,
    estimatedMinutes,
    resultNote,
    completedAt,
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
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('priority')) {
      context.handle(
        _priorityMeta,
        priority.isAcceptableOrUnknown(data['priority']!, _priorityMeta),
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
    if (data.containsKey('completed_at')) {
      context.handle(
        _completedAtMeta,
        completedAt.isAcceptableOrUnknown(
          data['completed_at']!,
          _completedAtMeta,
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
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      priority: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}priority'],
      ),
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
      completedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}completed_at'],
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
  final String kind;
  final String status;
  final String? priority;
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
  final String? completedAt;
  final String createdAt;
  final String updatedAt;
  const ActionRow({
    required this.id,
    required this.name,
    required this.kind,
    required this.status,
    this.priority,
    required this.postponeFlex,
    this.depthLevel,
    this.startAt,
    this.endAt,
    required this.isAllDay,
    this.estimatedMinutes,
    this.resultNote,
    this.completedAt,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['kind'] = Variable<String>(kind);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || priority != null) {
      map['priority'] = Variable<String>(priority);
    }
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
    if (!nullToAbsent || completedAt != null) {
      map['completed_at'] = Variable<String>(completedAt);
    }
    map['created_at'] = Variable<String>(createdAt);
    map['updated_at'] = Variable<String>(updatedAt);
    return map;
  }

  ActionsTableCompanion toCompanion(bool nullToAbsent) {
    return ActionsTableCompanion(
      id: Value(id),
      name: Value(name),
      kind: Value(kind),
      status: Value(status),
      priority: priority == null && nullToAbsent
          ? const Value.absent()
          : Value(priority),
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
      completedAt: completedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAt),
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
      kind: serializer.fromJson<String>(json['kind']),
      status: serializer.fromJson<String>(json['status']),
      priority: serializer.fromJson<String?>(json['priority']),
      postponeFlex: serializer.fromJson<String>(json['postponeFlex']),
      depthLevel: serializer.fromJson<String?>(json['depthLevel']),
      startAt: serializer.fromJson<String?>(json['startAt']),
      endAt: serializer.fromJson<String?>(json['endAt']),
      isAllDay: serializer.fromJson<bool>(json['isAllDay']),
      estimatedMinutes: serializer.fromJson<int?>(json['estimatedMinutes']),
      resultNote: serializer.fromJson<String?>(json['resultNote']),
      completedAt: serializer.fromJson<String?>(json['completedAt']),
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
      'kind': serializer.toJson<String>(kind),
      'status': serializer.toJson<String>(status),
      'priority': serializer.toJson<String?>(priority),
      'postponeFlex': serializer.toJson<String>(postponeFlex),
      'depthLevel': serializer.toJson<String?>(depthLevel),
      'startAt': serializer.toJson<String?>(startAt),
      'endAt': serializer.toJson<String?>(endAt),
      'isAllDay': serializer.toJson<bool>(isAllDay),
      'estimatedMinutes': serializer.toJson<int?>(estimatedMinutes),
      'resultNote': serializer.toJson<String?>(resultNote),
      'completedAt': serializer.toJson<String?>(completedAt),
      'createdAt': serializer.toJson<String>(createdAt),
      'updatedAt': serializer.toJson<String>(updatedAt),
    };
  }

  ActionRow copyWith({
    String? id,
    String? name,
    String? kind,
    String? status,
    Value<String?> priority = const Value.absent(),
    String? postponeFlex,
    Value<String?> depthLevel = const Value.absent(),
    Value<String?> startAt = const Value.absent(),
    Value<String?> endAt = const Value.absent(),
    bool? isAllDay,
    Value<int?> estimatedMinutes = const Value.absent(),
    Value<String?> resultNote = const Value.absent(),
    Value<String?> completedAt = const Value.absent(),
    String? createdAt,
    String? updatedAt,
  }) => ActionRow(
    id: id ?? this.id,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    status: status ?? this.status,
    priority: priority.present ? priority.value : this.priority,
    postponeFlex: postponeFlex ?? this.postponeFlex,
    depthLevel: depthLevel.present ? depthLevel.value : this.depthLevel,
    startAt: startAt.present ? startAt.value : this.startAt,
    endAt: endAt.present ? endAt.value : this.endAt,
    isAllDay: isAllDay ?? this.isAllDay,
    estimatedMinutes: estimatedMinutes.present
        ? estimatedMinutes.value
        : this.estimatedMinutes,
    resultNote: resultNote.present ? resultNote.value : this.resultNote,
    completedAt: completedAt.present ? completedAt.value : this.completedAt,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ActionRow copyWithCompanion(ActionsTableCompanion data) {
    return ActionRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      kind: data.kind.present ? data.kind.value : this.kind,
      status: data.status.present ? data.status.value : this.status,
      priority: data.priority.present ? data.priority.value : this.priority,
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
      completedAt: data.completedAt.present
          ? data.completedAt.value
          : this.completedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ActionRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('kind: $kind, ')
          ..write('status: $status, ')
          ..write('priority: $priority, ')
          ..write('postponeFlex: $postponeFlex, ')
          ..write('depthLevel: $depthLevel, ')
          ..write('startAt: $startAt, ')
          ..write('endAt: $endAt, ')
          ..write('isAllDay: $isAllDay, ')
          ..write('estimatedMinutes: $estimatedMinutes, ')
          ..write('resultNote: $resultNote, ')
          ..write('completedAt: $completedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    kind,
    status,
    priority,
    postponeFlex,
    depthLevel,
    startAt,
    endAt,
    isAllDay,
    estimatedMinutes,
    resultNote,
    completedAt,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ActionRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.kind == this.kind &&
          other.status == this.status &&
          other.priority == this.priority &&
          other.postponeFlex == this.postponeFlex &&
          other.depthLevel == this.depthLevel &&
          other.startAt == this.startAt &&
          other.endAt == this.endAt &&
          other.isAllDay == this.isAllDay &&
          other.estimatedMinutes == this.estimatedMinutes &&
          other.resultNote == this.resultNote &&
          other.completedAt == this.completedAt &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ActionsTableCompanion extends UpdateCompanion<ActionRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> kind;
  final Value<String> status;
  final Value<String?> priority;
  final Value<String> postponeFlex;
  final Value<String?> depthLevel;
  final Value<String?> startAt;
  final Value<String?> endAt;
  final Value<bool> isAllDay;
  final Value<int?> estimatedMinutes;
  final Value<String?> resultNote;
  final Value<String?> completedAt;
  final Value<String> createdAt;
  final Value<String> updatedAt;
  final Value<int> rowid;
  const ActionsTableCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.kind = const Value.absent(),
    this.status = const Value.absent(),
    this.priority = const Value.absent(),
    this.postponeFlex = const Value.absent(),
    this.depthLevel = const Value.absent(),
    this.startAt = const Value.absent(),
    this.endAt = const Value.absent(),
    this.isAllDay = const Value.absent(),
    this.estimatedMinutes = const Value.absent(),
    this.resultNote = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ActionsTableCompanion.insert({
    required String id,
    required String name,
    this.kind = const Value.absent(),
    this.status = const Value.absent(),
    this.priority = const Value.absent(),
    this.postponeFlex = const Value.absent(),
    this.depthLevel = const Value.absent(),
    this.startAt = const Value.absent(),
    this.endAt = const Value.absent(),
    this.isAllDay = const Value.absent(),
    this.estimatedMinutes = const Value.absent(),
    this.resultNote = const Value.absent(),
    this.completedAt = const Value.absent(),
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
    Expression<String>? kind,
    Expression<String>? status,
    Expression<String>? priority,
    Expression<String>? postponeFlex,
    Expression<String>? depthLevel,
    Expression<String>? startAt,
    Expression<String>? endAt,
    Expression<bool>? isAllDay,
    Expression<int>? estimatedMinutes,
    Expression<String>? resultNote,
    Expression<String>? completedAt,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (kind != null) 'kind': kind,
      if (status != null) 'status': status,
      if (priority != null) 'priority': priority,
      if (postponeFlex != null) 'postpone_flex': postponeFlex,
      if (depthLevel != null) 'depth_level': depthLevel,
      if (startAt != null) 'start_at': startAt,
      if (endAt != null) 'end_at': endAt,
      if (isAllDay != null) 'is_all_day': isAllDay,
      if (estimatedMinutes != null) 'estimated_minutes': estimatedMinutes,
      if (resultNote != null) 'result_note': resultNote,
      if (completedAt != null) 'completed_at': completedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ActionsTableCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? kind,
    Value<String>? status,
    Value<String?>? priority,
    Value<String>? postponeFlex,
    Value<String?>? depthLevel,
    Value<String?>? startAt,
    Value<String?>? endAt,
    Value<bool>? isAllDay,
    Value<int?>? estimatedMinutes,
    Value<String?>? resultNote,
    Value<String?>? completedAt,
    Value<String>? createdAt,
    Value<String>? updatedAt,
    Value<int>? rowid,
  }) {
    return ActionsTableCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      postponeFlex: postponeFlex ?? this.postponeFlex,
      depthLevel: depthLevel ?? this.depthLevel,
      startAt: startAt ?? this.startAt,
      endAt: endAt ?? this.endAt,
      isAllDay: isAllDay ?? this.isAllDay,
      estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
      resultNote: resultNote ?? this.resultNote,
      completedAt: completedAt ?? this.completedAt,
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
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (priority.present) {
      map['priority'] = Variable<String>(priority.value);
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
    if (completedAt.present) {
      map['completed_at'] = Variable<String>(completedAt.value);
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
          ..write('kind: $kind, ')
          ..write('status: $status, ')
          ..write('priority: $priority, ')
          ..write('postponeFlex: $postponeFlex, ')
          ..write('depthLevel: $depthLevel, ')
          ..write('startAt: $startAt, ')
          ..write('endAt: $endAt, ')
          ..write('isAllDay: $isAllDay, ')
          ..write('estimatedMinutes: $estimatedMinutes, ')
          ..write('resultNote: $resultNote, ')
          ..write('completedAt: $completedAt, ')
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
  static const VerificationMeta _leadingMeta = const VerificationMeta(
    'leading',
  );
  @override
  late final GeneratedColumn<String> leading = GeneratedColumn<String>(
    'leading',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _targetIntervalDaysMeta =
      const VerificationMeta('targetIntervalDays');
  @override
  late final GeneratedColumn<int> targetIntervalDays = GeneratedColumn<int>(
    'target_interval_days',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    weight,
    leading,
    targetIntervalDays,
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
    if (data.containsKey('leading')) {
      context.handle(
        _leadingMeta,
        leading.isAcceptableOrUnknown(data['leading']!, _leadingMeta),
      );
    }
    if (data.containsKey('target_interval_days')) {
      context.handle(
        _targetIntervalDaysMeta,
        targetIntervalDays.isAcceptableOrUnknown(
          data['target_interval_days']!,
          _targetIntervalDaysMeta,
        ),
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
      leading: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}leading'],
      ),
      targetIntervalDays: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}target_interval_days'],
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
  final String? leading;
  final int? targetIntervalDays;
  const Metric({
    required this.id,
    required this.name,
    required this.weight,
    this.leading,
    this.targetIntervalDays,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['weight'] = Variable<double>(weight);
    if (!nullToAbsent || leading != null) {
      map['leading'] = Variable<String>(leading);
    }
    if (!nullToAbsent || targetIntervalDays != null) {
      map['target_interval_days'] = Variable<int>(targetIntervalDays);
    }
    return map;
  }

  MetricsTableCompanion toCompanion(bool nullToAbsent) {
    return MetricsTableCompanion(
      id: Value(id),
      name: Value(name),
      weight: Value(weight),
      leading: leading == null && nullToAbsent
          ? const Value.absent()
          : Value(leading),
      targetIntervalDays: targetIntervalDays == null && nullToAbsent
          ? const Value.absent()
          : Value(targetIntervalDays),
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
      leading: serializer.fromJson<String?>(json['leading']),
      targetIntervalDays: serializer.fromJson<int?>(json['targetIntervalDays']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'weight': serializer.toJson<double>(weight),
      'leading': serializer.toJson<String?>(leading),
      'targetIntervalDays': serializer.toJson<int?>(targetIntervalDays),
    };
  }

  Metric copyWith({
    String? id,
    String? name,
    double? weight,
    Value<String?> leading = const Value.absent(),
    Value<int?> targetIntervalDays = const Value.absent(),
  }) => Metric(
    id: id ?? this.id,
    name: name ?? this.name,
    weight: weight ?? this.weight,
    leading: leading.present ? leading.value : this.leading,
    targetIntervalDays: targetIntervalDays.present
        ? targetIntervalDays.value
        : this.targetIntervalDays,
  );
  Metric copyWithCompanion(MetricsTableCompanion data) {
    return Metric(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      weight: data.weight.present ? data.weight.value : this.weight,
      leading: data.leading.present ? data.leading.value : this.leading,
      targetIntervalDays: data.targetIntervalDays.present
          ? data.targetIntervalDays.value
          : this.targetIntervalDays,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Metric(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('weight: $weight, ')
          ..write('leading: $leading, ')
          ..write('targetIntervalDays: $targetIntervalDays')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, weight, leading, targetIntervalDays);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Metric &&
          other.id == this.id &&
          other.name == this.name &&
          other.weight == this.weight &&
          other.leading == this.leading &&
          other.targetIntervalDays == this.targetIntervalDays);
}

class MetricsTableCompanion extends UpdateCompanion<Metric> {
  final Value<String> id;
  final Value<String> name;
  final Value<double> weight;
  final Value<String?> leading;
  final Value<int?> targetIntervalDays;
  final Value<int> rowid;
  const MetricsTableCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.weight = const Value.absent(),
    this.leading = const Value.absent(),
    this.targetIntervalDays = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MetricsTableCompanion.insert({
    required String id,
    required String name,
    this.weight = const Value.absent(),
    this.leading = const Value.absent(),
    this.targetIntervalDays = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name);
  static Insertable<Metric> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<double>? weight,
    Expression<String>? leading,
    Expression<int>? targetIntervalDays,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (weight != null) 'weight': weight,
      if (leading != null) 'leading': leading,
      if (targetIntervalDays != null)
        'target_interval_days': targetIntervalDays,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MetricsTableCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<double>? weight,
    Value<String?>? leading,
    Value<int?>? targetIntervalDays,
    Value<int>? rowid,
  }) {
    return MetricsTableCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      weight: weight ?? this.weight,
      leading: leading ?? this.leading,
      targetIntervalDays: targetIntervalDays ?? this.targetIntervalDays,
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
    if (leading.present) {
      map['leading'] = Variable<String>(leading.value);
    }
    if (targetIntervalDays.present) {
      map['target_interval_days'] = Variable<int>(targetIntervalDays.value);
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
          ..write('leading: $leading, ')
          ..write('targetIntervalDays: $targetIntervalDays, ')
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

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
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
  late final Index idxActionsStatusStart = Index(
    'idx_actions_status_start',
    'CREATE INDEX idx_actions_status_start ON actions (status, start_at)',
  );
  late final Index idxActionsKindStatusAllday = Index(
    'idx_actions_kind_status_allday',
    'CREATE INDEX idx_actions_kind_status_allday ON actions (kind, status, is_all_day)',
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
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    actionsTable,
    actionDependenciesTable,
    actionOccurrencesTable,
    metricsTable,
    actionMetricsTable,
    actionTemplatesTable,
    idxActionsStatusStart,
    idxActionsKindStatusAllday,
    idxDepSuccessor,
    idxOccurrenceAction,
    idxActionMetricsMetric,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
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
  ]);
}

typedef $$ActionsTableTableCreateCompanionBuilder =
    ActionsTableCompanion Function({
      required String id,
      required String name,
      Value<String> kind,
      Value<String> status,
      Value<String?> priority,
      Value<String> postponeFlex,
      Value<String?> depthLevel,
      Value<String?> startAt,
      Value<String?> endAt,
      Value<bool> isAllDay,
      Value<int?> estimatedMinutes,
      Value<String?> resultNote,
      Value<String?> completedAt,
      required String createdAt,
      required String updatedAt,
      Value<int> rowid,
    });
typedef $$ActionsTableTableUpdateCompanionBuilder =
    ActionsTableCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> kind,
      Value<String> status,
      Value<String?> priority,
      Value<String> postponeFlex,
      Value<String?> depthLevel,
      Value<String?> startAt,
      Value<String?> endAt,
      Value<bool> isAllDay,
      Value<int?> estimatedMinutes,
      Value<String?> resultNote,
      Value<String?> completedAt,
      Value<String> createdAt,
      Value<String> updatedAt,
      Value<int> rowid,
    });

final class $$ActionsTableTableReferences
    extends BaseReferences<_$AppDatabase, $ActionsTableTable, ActionRow> {
  $$ActionsTableTableReferences(super.$_db, super.$_table, super.$_typedResult);

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

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get priority => $composableBuilder(
    column: $table.priority,
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

  ColumnFilters<String> get completedAt => $composableBuilder(
    column: $table.completedAt,
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

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get priority => $composableBuilder(
    column: $table.priority,
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

  ColumnOrderings<String> get completedAt => $composableBuilder(
    column: $table.completedAt,
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

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get priority =>
      $composableBuilder(column: $table.priority, builder: (column) => column);

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

  GeneratedColumn<String> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

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
            bool predecessorDependencies,
            bool successorDependencies,
            bool actionOccurrencesTableRefs,
            bool actionMetricsTableRefs,
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
                Value<String> kind = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> priority = const Value.absent(),
                Value<String> postponeFlex = const Value.absent(),
                Value<String?> depthLevel = const Value.absent(),
                Value<String?> startAt = const Value.absent(),
                Value<String?> endAt = const Value.absent(),
                Value<bool> isAllDay = const Value.absent(),
                Value<int?> estimatedMinutes = const Value.absent(),
                Value<String?> resultNote = const Value.absent(),
                Value<String?> completedAt = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ActionsTableCompanion(
                id: id,
                name: name,
                kind: kind,
                status: status,
                priority: priority,
                postponeFlex: postponeFlex,
                depthLevel: depthLevel,
                startAt: startAt,
                endAt: endAt,
                isAllDay: isAllDay,
                estimatedMinutes: estimatedMinutes,
                resultNote: resultNote,
                completedAt: completedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<String> kind = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> priority = const Value.absent(),
                Value<String> postponeFlex = const Value.absent(),
                Value<String?> depthLevel = const Value.absent(),
                Value<String?> startAt = const Value.absent(),
                Value<String?> endAt = const Value.absent(),
                Value<bool> isAllDay = const Value.absent(),
                Value<int?> estimatedMinutes = const Value.absent(),
                Value<String?> resultNote = const Value.absent(),
                Value<String?> completedAt = const Value.absent(),
                required String createdAt,
                required String updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ActionsTableCompanion.insert(
                id: id,
                name: name,
                kind: kind,
                status: status,
                priority: priority,
                postponeFlex: postponeFlex,
                depthLevel: depthLevel,
                startAt: startAt,
                endAt: endAt,
                isAllDay: isAllDay,
                estimatedMinutes: estimatedMinutes,
                resultNote: resultNote,
                completedAt: completedAt,
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
                predecessorDependencies = false,
                successorDependencies = false,
                actionOccurrencesTableRefs = false,
                actionMetricsTableRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (predecessorDependencies) db.actionDependenciesTable,
                    if (successorDependencies) db.actionDependenciesTable,
                    if (actionOccurrencesTableRefs) db.actionOccurrencesTable,
                    if (actionMetricsTableRefs) db.actionMetricsTable,
                  ],
                  addJoins: null,
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
        bool predecessorDependencies,
        bool successorDependencies,
        bool actionOccurrencesTableRefs,
        bool actionMetricsTableRefs,
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
      Value<String?> leading,
      Value<int?> targetIntervalDays,
      Value<int> rowid,
    });
typedef $$MetricsTableTableUpdateCompanionBuilder =
    MetricsTableCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<double> weight,
      Value<String?> leading,
      Value<int?> targetIntervalDays,
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

  ColumnFilters<String> get leading => $composableBuilder(
    column: $table.leading,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get targetIntervalDays => $composableBuilder(
    column: $table.targetIntervalDays,
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

  ColumnOrderings<String> get leading => $composableBuilder(
    column: $table.leading,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get targetIntervalDays => $composableBuilder(
    column: $table.targetIntervalDays,
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

  GeneratedColumn<String> get leading =>
      $composableBuilder(column: $table.leading, builder: (column) => column);

  GeneratedColumn<int> get targetIntervalDays => $composableBuilder(
    column: $table.targetIntervalDays,
    builder: (column) => column,
  );

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
          PrefetchHooks Function({bool actionMetricsTableRefs})
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
                Value<String?> leading = const Value.absent(),
                Value<int?> targetIntervalDays = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MetricsTableCompanion(
                id: id,
                name: name,
                weight: weight,
                leading: leading,
                targetIntervalDays: targetIntervalDays,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<double> weight = const Value.absent(),
                Value<String?> leading = const Value.absent(),
                Value<int?> targetIntervalDays = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MetricsTableCompanion.insert(
                id: id,
                name: name,
                weight: weight,
                leading: leading,
                targetIntervalDays: targetIntervalDays,
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
          prefetchHooksCallback: ({actionMetricsTableRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (actionMetricsTableRefs) db.actionMetricsTable,
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
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.metricId == item.id),
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
      PrefetchHooks Function({bool actionMetricsTableRefs})
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

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
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
}
