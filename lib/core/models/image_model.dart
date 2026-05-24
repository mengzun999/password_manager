/// 图片数据模型
/// 用于存储与密码条目关联的图片信息
class ImageModel {
  /// 图片唯一标识（UUID）
  final String id;

  /// 关联的密码条目ID
  final String entryId;

  /// 加密后的文件名（存储在本地）
  final String filename;

  /// 缩略图文件名
  final String? thumbnailFilename;

  /// 原始文件大小（字节）
  final int? fileSize;

  /// 图片类型（image/jpeg, image/png等）
  final String? mimeType;

  /// 显示顺序（用于排序）
  final int sortOrder;

  /// 创建时间戳
  final int createdAt;

  const ImageModel({
    required this.id,
    required this.entryId,
    required this.filename,
    this.thumbnailFilename,
    this.fileSize,
    this.mimeType,
    this.sortOrder = 0,
    required this.createdAt,
  });

  /// 转换为Map（用于数据库存储）
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'entry_id': entryId,
      'filename': filename,
      'thumbnail_filename': thumbnailFilename,
      'file_size': fileSize,
      'mime_type': mimeType,
      'sort_order': sortOrder,
      'created_at': createdAt,
    };
  }

  /// 从Map创建ImageModel对象
  factory ImageModel.fromMap(Map<String, dynamic> map) {
    return ImageModel(
      id: map['id'],
      entryId: map['entry_id'],
      filename: map['filename'],
      thumbnailFilename: map['thumbnail_filename'],
      fileSize: map['file_size'],
      mimeType: map['mime_type'],
      sortOrder: map['sort_order'] ?? 0,
      createdAt: map['created_at'],
    );
  }

  /// 复制并修改部分字段
  ImageModel copyWith({
    String? id,
    String? entryId,
    String? filename,
    String? thumbnailFilename,
    int? fileSize,
    String? mimeType,
    int? sortOrder,
    int? createdAt,
  }) {
    return ImageModel(
      id: id ?? this.id,
      entryId: entryId ?? this.entryId,
      filename: filename ?? this.filename,
      thumbnailFilename: thumbnailFilename ?? this.thumbnailFilename,
      fileSize: fileSize ?? this.fileSize,
      mimeType: mimeType ?? this.mimeType,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  //便于调试
  @override
  String toString() {
    return 'ImageModel(id: $id, entryId: $entryId, filename: $filename, sortOrder: $sortOrder)';
  }
}