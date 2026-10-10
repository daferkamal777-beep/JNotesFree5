import 'stroke.dart';

/// خلفيات الصفحة المتاحة.
enum PageBackground { blank, ruled, grid, dots }

/// بيانات تعريفية خفيفة عن الملاحظة (تظهر في الشاشة الرئيسية).
class NoteMeta {
  final String id;
  String title;
  String folder; // نص فارغ = بدون مجلد
  bool favorite;
  bool trashed;
  DateTime updatedAt;
  int pageCount;

  NoteMeta({
    required this.id,
    required this.title,
    this.folder = '',
    this.favorite = false,
    this.trashed = false,
    DateTime? updatedAt,
    this.pageCount = 1,
  }) : updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'folder': folder,
        'favorite': favorite,
        'trashed': trashed,
        'updatedAt': updatedAt.toIso8601String(),
        'pageCount': pageCount,
      };

  factory NoteMeta.fromJson(Map<String, dynamic> j) => NoteMeta(
        id: j['id'] as String,
        title: j['title'] as String? ?? 'ملاحظة بدون عنوان',
        folder: j['folder'] as String? ?? '',
        favorite: j['favorite'] as bool? ?? false,
        trashed: j['trashed'] as bool? ?? false,
        updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? ''),
        pageCount: (j['pageCount'] as num?)?.toInt() ?? 1,
      );
}

/// محتوى الملاحظة الكامل (الصفحات والخطوط).
class NoteContent {
  final String title;
  final List<List<InkStroke>> pages;
  final List<PageBackground> backgrounds;

  NoteContent({
    required this.title,
    required this.pages,
    required this.backgrounds,
  });
}
