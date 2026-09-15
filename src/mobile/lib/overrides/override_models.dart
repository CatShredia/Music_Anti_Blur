import '../catalog/catalog_models.dart';

class TrackOverride {
  TrackOverride({
    required this.sourcePreference,
    required this.privateReady,
    required this.availableQualities,
    this.displayName,
    this.durationMs,
    this.sizeBytes,
    this.privateStatus,
    this.privateGenerationId,
  });

  final String sourcePreference;
  final String? displayName;
  final int? durationMs;
  final int? sizeBytes;
  final bool privateReady;
  final String? privateStatus;
  final String? privateGenerationId;
  final List<TrackQuality> availableQualities;

  factory TrackOverride.fromJson(Map<String, dynamic> json) => TrackOverride(
        sourcePreference: json['sourcePreference'] as String? ?? 'auto',
        displayName: json['displayName'] as String?,
        durationMs: (json['durationMs'] as num?)?.toInt(),
        sizeBytes: (json['sizeBytes'] as num?)?.toInt(),
        privateReady: json['privateReady'] as bool? ?? false,
        privateStatus: json['privateStatus'] as String?,
        privateGenerationId: json['privateGenerationId'] as String?,
        availableQualities: (json['availableQualities'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(TrackQuality.fromJson)
            .toList(),
      );
}

class InitiatePrivateUpload {
  InitiatePrivateUpload({
    required this.generationId,
    required this.partSizeBytes,
    required this.partCount,
    required this.expiresAt,
  });

  final String generationId;
  final int partSizeBytes;
  final int partCount;
  final DateTime expiresAt;

  factory InitiatePrivateUpload.fromJson(Map<String, dynamic> json) => InitiatePrivateUpload(
        generationId: json['generationId'] as String,
        partSizeBytes: (json['partSizeBytes'] as num).toInt(),
        partCount: (json['partCount'] as num).toInt(),
        expiresAt: DateTime.parse(json['expiresAt'] as String),
      );
}

class UploadPartUrl {
  UploadPartUrl({required this.partNumber, required this.url, required this.expiresAt});

  final int partNumber;
  final String url;
  final DateTime expiresAt;

  factory UploadPartUrl.fromJson(Map<String, dynamic> json) => UploadPartUrl(
        partNumber: (json['partNumber'] as num).toInt(),
        url: json['url'] as String,
        expiresAt: DateTime.parse(json['expiresAt'] as String),
      );
}

class PrivateUploadStatus {
  PrivateUploadStatus({
    required this.generationId,
    required this.status,
    required this.isActive,
    this.sizeBytes,
    this.durationMs,
    this.errorMessage,
  });

  final String generationId;
  final String status;
  final bool isActive;
  final int? sizeBytes;
  final int? durationMs;
  final String? errorMessage;

  bool get isReady => status == 'ready';
  bool get isFailed => status == 'failed' || status == 'cancelled';
  bool get isBusy => !isReady && !isFailed;

  factory PrivateUploadStatus.fromJson(Map<String, dynamic> json) => PrivateUploadStatus(
        generationId: json['generationId'] as String,
        status: json['status'] as String,
        isActive: json['isActive'] as bool? ?? false,
        sizeBytes: (json['sizeBytes'] as num?)?.toInt(),
        durationMs: (json['durationMs'] as num?)?.toInt(),
        errorMessage: json['errorMessage'] as String?,
      );
}

String sourceLabel(String source) => switch (source) {
      'local' => 'Local',
      'private' => 'Private',
      'catalog' => 'Catalog',
      'auto' => 'Авто',
      _ => source,
    };

String fallbackNotice(String? reason) => switch (reason) {
      'local_unavailable' => 'Локальный файл на другом устройстве',
      'private_not_ready' => 'Private-копия ещё не готова — играю другую копию',
      _ => '',
    };
