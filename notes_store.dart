import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/note.dart';
import '../models/stroke.dart';

/// طبقة الحفظ المحلي. كل عمليات الكتابة تُنفَّذ بالتتابع حتى لا تتعارض.
///
/// المفاتيح المستخدمة في الجهاز:
///   note_<id>        محتوى الملاحظة (نفس الصيغة القديمة + حقل backgrounds)
///   notes_index_v1   فهرس الملاحظات (العنوان، المجلد، المفضلة، المحذوفة...)
class NotesStore {
  NotesStore._();

  static const String _indexKey = 'notes_index_v1';
  static Future<void> _lock = Future<void>.value();

  static String _contentKey(String id) => 'note_$id';

  static String newId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}';

  static Future<void> _chain(Future<void> Function() action) {
    final next = _lock.then((_) => action()).catchError((Object _) {});
    _lock = next;
    return next;
  }

  static List<NoteMeta> _readIndex(SharedPreferences prefs) {
    final raw = prefs.getString(_indexKey);
    final result = <NoteMeta>[];
    if (raw == null) return result;
    try {
      for (final item in jsonDecode(raw) as List) {
        result.add(NoteMeta.fromJson(Map<String, dynamic>.from(item as Map)));
      }
    } catch (_) {}
    return result;
  }

  static Future<void> _writeIndex(
    SharedPreferences prefs,
    List<NoteMeta> list,
  ) {
    return prefs.setString(
      _indexKey,
      jsonEncode(list.map((n) => n.toJson()).toList()),
    );
  }

  /// يقرأ قائمة الملاحظات. وإن وجد ملاحظات محفوظة بالصيغة القديمة
  /// (note_<id>) غير مفهرسة، يضيفها إلى الفهرس دون تعديل محتواها.
  static Future<List<NoteMeta>> loadIndex() async {
    final result = <NoteMeta>[];
    await _chain(() async {
      final prefs = await SharedPreferences.getInstance();
      final list = _readIndex(prefs);
      final known = list.map((n) => n.id).toSet();
      var changed = false;
      for (final key in prefs.getKeys().toList()) {
        if (!key.startsWith('note_')) continue;
        final id = key.substring(5);
        if (known.contains(id)) continue;
        try {
          final data =
              Map<String, dynamic>.from(jsonDecode(prefs.getString(key) ?? '') as Map);
          list.add(NoteMeta(
            id: id,
            title: data['title'] as String? ?? 'ملاحظة بدون عنوان',
            updatedAt: DateTime.tryParse(data['updatedAt'] as String? ?? ''),
            pageCount: (data['pages'] as List?)?.length ?? 1,
          ));
          changed = true;
        } catch (_) {}
      }
      if (changed) await _writeIndex(prefs, list);
      result.addAll(list);
    });
    result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return result;
  }

  static Future<NoteContent?> loadContent(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_contentKey(id));
    if (raw == null) return null;
    try {
      final data = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final pages = (data['pages'] as List)
          .map<List<InkStroke>>((page) => (page as List)
              .map((s) =>
                  InkStroke.fromJson(Map<String, dynamic>.from(s as Map)))
              .toList())
          .toList();
      final bgRaw = (data['backgrounds'] as List?) ?? const [];
      final backgrounds = List<PageBackground>.generate(pages.length, (i) {
        if (i < bgRaw.length) {
          final v = (bgRaw[i] as num).toInt();
          if (v >= 0 && v < PageBackground.values.length) {
            return PageBackground.values[v];
          }
        }
        return PageBackground.blank;
      });
      return NoteContent(
        title: data['title'] as String? ?? 'ملاحظة بدون عنوان',
        pages: pages,
        backgrounds: backgrounds,
      );
    } catch (_) {
      return null;
    }
  }

  /// يحفظ المحتوى ويحدّث الفهرس. تُبنى النسخة النصية فورًا (قبل الانتظار)
  /// حتى تُحفظ الحالة الصحيحة حتى لو أُغلقت الشاشة مباشرة بعد الاستدعاء.
  static Future<void> saveContent({
    required String id,
    required String title,
    required List<List<InkStroke>> pages,
    required List<PageBackground> backgrounds,
    String folder = '',
  }) {
    final cleanTitle = title.trim().isEmpty ? 'ملاحظة بدون عنوان' : title.trim();
    final now = DateTime.now();
    final encoded = jsonEncode({
      'title': cleanTitle,
      'updatedAt': now.toIso8601String(),
      'pages': pages
          .map((page) => page.map((stroke) => stroke.toJson()).toList())
          .toList(),
      'backgrounds': backgrounds.map((b) => b.index).toList(),
    });
    final pageCount = pages.length;
    return _chain(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_contentKey(id), encoded);
      final index = _readIndex(prefs);
      final i = index.indexWhere((n) => n.id == id);
      if (i >= 0) {
        index[i].title = cleanTitle;
        index[i].updatedAt = now;
        index[i].pageCount = pageCount;
      } else {
        index.add(NoteMeta(
          id: id,
          title: cleanTitle,
          folder: folder,
          updatedAt: now,
          pageCount: pageCount,
        ));
      }
      await _writeIndex(prefs, index);
    });
  }

  static Future<void> rename(String id, String title) {
    final clean = title.trim().isEmpty ? 'ملاحظة بدون عنوان' : title.trim();
    return _chain(() async {
      final prefs = await SharedPreferences.getInstance();
      final index = _readIndex(prefs);
      final i = index.indexWhere((n) => n.id == id);
      if (i >= 0) {
        index[i].title = clean;
        await _writeIndex(prefs, index);
      }
      final raw = prefs.getString(_contentKey(id));
      if (raw != null) {
        try {
          final data = Map<String, dynamic>.from(jsonDecode(raw) as Map);
          data['title'] = clean;
          await prefs.setString(_contentKey(id), jsonEncode(data));
        } catch (_) {}
      }
    });
  }

  static Future<void> updateFlags(
    String id, {
    String? folder,
    bool? favorite,
    bool? trashed,
  }) {
    return _chain(() async {
      final prefs = await SharedPreferences.getInstance();
      final index = _readIndex(prefs);
      final i = index.indexWhere((n) => n.id == id);
      if (i < 0) return;
      if (folder != null) index[i].folder = folder;
      if (favorite != null) index[i].favorite = favorite;
      if (trashed != null) index[i].trashed = trashed;
      await _writeIndex(prefs, index);
    });
  }

  /// حذف نهائي (لا رجعة فيه) — لا يُستدعى إلا بعد تأكيد من المستخدم.
  static Future<void> deleteForever(String id) {
    return _chain(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_contentKey(id));
      final index = _readIndex(prefs);
      index.removeWhere((n) => n.id == id);
      await _writeIndex(prefs, index);
    });
  }
}
